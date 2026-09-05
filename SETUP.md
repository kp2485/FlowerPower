# Getting FlowerPower building on the Mac

The engine (`FlowerPowerCore`) is a Swift package and builds anywhere. The app
and watch app are Xcode targets and need a Mac. This is what to do when you open
the project there.

Nothing here is guesswork about the code — the engine is compiled and tested.
But **none of the SwiftUI has been compiled**, because that needs Xcode. Expect
to fix a few things on the first build.

---

## 0. Fixes already applied

A pass was made over the uncompiled layers from a Windows machine, using the
Swift 6.3 compiler to check everything that does not need the Apple SDKs. The
engine test suite passes (128 tests), and `GameStore.swift` and
`GamePersistence.swift` were compiled for real against `FlowerPowerCore`. These
were found and fixed:

| File | Problem |
|---|---|
| `Services/FlowerClassifier.swift` | Used `FlowerSpecies` and `FlowerCatalogue` with no `import FlowerPowerCore`, and `MLModel` with no `import CoreML`. |
| `Views/Theme.swift` | `MeterView.caption` was `let caption: String?` — a `let` optional gets no default in the memberwise initialiser, so `caption` was accidentally mandatory and one call in `GardenView` omitted it. |
| `Views/ContentView.swift`, `CaptureView.swift`, `GardenView.swift` | `.task` takes a `@Sendable` closure, which does **not** inherit the view's main-actor isolation, so calls into the `@MainActor` `GameStore` were cross-actor. Bodies now open `{ @MainActor in … }`. |
| `FlowerPowerWatch/WatchTheme.swift` | Extracted from `WatchRootView.swift` so the widget extension can use it without also compiling the watch's views and model. |
| `FlowerPowerWatch/WatchColonyModel.swift` | `isStale` was assigned `summary == nil` directly after `summary` was set non-nil, so the watch's "out of touch with your phone" note could never appear. |

**What is still unverified:** everything that needs the Apple SDKs — SwiftUI,
MapKit, PhotosUI, Vision, WidgetKit, WatchConnectivity. The engine API calls in
the views were checked symbol by symbol against `FlowerPowerCore`'s public
surface and are consistent, but the framework calls themselves have never been
through a compiler. The first build will still turn up SDK-level errors.

---

## 1. Add the engine as a local package

In Xcode: **File ▸ Add Package Dependencies… ▸ Add Local…** and choose the
`FlowerPowerCore` folder.

Then, for the `FlowerPower` target: **General ▸ Frameworks, Libraries, and
Embedded Content ▸ +** and add `FlowerPowerCore`.

Verify with:

```bash
swift test --package-path FlowerPowerCore
```

That runs the whole simulation test suite on the command line, no Xcode needed.

## 2. Add the new source files to the app target

The project predates Xcode 16's synchronised folders, so files have to be added
explicitly. Drag these into the `FlowerPower` group, with **Copy items if
needed** unchecked and the `FlowerPower` target ticked:

```
FlowerPower/App/          GameStore.swift, GamePersistence.swift
FlowerPower/Services/     FlowerClassifier.swift, PhotoLibrary.swift, WatchLink.swift
FlowerPower/Views/        Theme.swift, ContentView.swift, ColonyDashboardView.swift,
                          NestView.swift, ForageMapView.swift, GardenView.swift,
                          CaptureView.swift, CatchUpReportView.swift,
                          JobAssignmentView.swift
```

`FlowerPower/Legacy/` holds the superseded 2023 model files. Do **not** add them
to the target — see `Legacy/README.md` for what replaced what. Delete the folder
once you are happy.

### Files that belong to more than one target

Two files are used outside the iOS app and need their **Target Membership**
ticked for more than one target (File inspector, right-hand pane):

| File | iOS app | Watch app | Widget extension |
|---|:--:|:--:|:--:|
| `FlowerPower/App/GamePersistence.swift` | yes | yes | yes |
| `FlowerPowerWatch/WatchTheme.swift` | no | yes | yes |

`GamePersistence` is how all three read the same save file in the App Group:
`WatchColonyModel.loadFromSharedContainer()` and the complication's
`HiveProvider` both call `GamePersistence().load()` directly. `WatchTheme` is
used by both the watch views and `HiveComplication`. Miss either and you get
"cannot find 'GamePersistence' in scope" / "cannot find 'WatchTheme' in scope"
in a target that otherwise looks fine.

## 3. Raise the deployment target

The project is set to iOS 17.0. That works, but the newer Vision API and several
SwiftUI conveniences want iOS 18. iOS 17 is what the engine package declares, so
either is fine — just keep the two in step.

## 4. Add the watch target

**File ▸ New ▸ Target ▸ watchOS ▸ App**, named `FlowerPower Watch`, embedded in
the `FlowerPower` app. Then:

- Add `FlowerPowerCore` to its Frameworks list.
- Add these to the **watch app**: `FlowerPowerWatchApp.swift`,
  `WatchRootView.swift`, `WatchColonyModel.swift`, `WatchTheme.swift`.
- `HiveComplication.swift` belongs in a **Widget Extension** target rather than
  the watch app itself (**File ▸ New ▸ Target ▸ watchOS ▸ Widget Extension**).
  It carries its own `@main`, so it will collide if you put it in the app target.
- The **widget extension** additionally needs `WatchTheme.swift` and
  `GamePersistence.swift` ticked — see the table in section 2.

## 5. Capabilities and permissions

**App Groups** on the iOS app, the watch app *and* the widget extension:

```
group.com.kylepeterson.flowerpower
```

This must match `GamePersistence.appGroupIdentifier`. It is how the watch and the
complication read the same save file the phone writes. If you use a different
identifier, change it in one place — that constant.

**Usage descriptions — already done.** This project has no `Info.plist` file:
the app target builds with `GENERATE_INFOPLIST_FILE = YES`, so the usage strings
live in Build Settings as `INFOPLIST_KEY_*`. All four have been added to both
the Debug and Release configurations of the `FlowerPower` target:

| Key | Why |
|---|---|
| `INFOPLIST_KEY_NSCameraUsageDescription` | Photographing flowers |
| `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` | Reading and saving flower photos |
| `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` | Saving captures |
| `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` | Placing flowers on the map |

They show up in Xcode under the target's **Info** tab. Location genuinely is
optional — patches fall back to a nominal distance and the map shows a note.
Don't let the prompt read as though it's required.

**A note on identifiers.** The bundle identifier is
`com.LinwoodTechnologies.FlowerPower` — left over from 2023 — while the App
Group and both `Logger` subsystems use `com.kylepeterson.flowerpower`. Nothing
requires an App Group to sit under the bundle id, so this builds and runs as is.
But if you are going to renamespace the bundle id, do it before the App Group
is provisioned rather than after.

## 6. The flower classifier (optional)

`FlowerClassifier` runs in two stages: Vision's built-in classifier asks "is this
a plant at all?", and a Core ML model asks "which one?". **The second is
optional.** With no model bundled, every flower is unidentified, yields 60% of
normal, and the game plays fine.

To add species identification:

1. Train a classifier in **Create ML ▸ Image Classification**. The Oxford 102
   Flowers dataset is the usual starting point.
2. Name the output labels to match `FlowerCatalogue` ids (`white_clover`,
   `heather`, …), or rely on `FlowerCatalogue.match(label:)`, which also matches
   common and scientific names.
3. Drop `FlowerClassifier.mlmodel` into the app target. `FlowerClassifier.bundled()`
   picks it up automatically.

**Visual Look Up — the plant identification in Photos — is not available to
third-party apps.** There is no public API for it. This is why a model is needed
at all.

---

## Balance tooling

The engine ships with a headless runner:

```bash
swift run beesim --package-path FlowerPowerCore --trials 24 --days 400
```

That runs 24 seeded colonies for a bit over a simulated year and reports survival
rate, peak population, winter cluster size, and what killed the ones that died.

```bash
swift run beesim --package-path FlowerPowerCore --days 400 --every 5 --seed 8919
```

traces a single colony day by day, which is how nearly every balance bug in the
engine was found. Tune against the trial statistics, never a single run — see the
comments in `SimulationConfig.swift` for what the numbers are solving for.
