# Getting FlowerPower building on the Mac

The engine (`FlowerPowerCore`) is a Swift package and builds anywhere. The app
and watch app are Xcode targets and need a Mac. This is what to do when you open
the project there.

Nothing here is guesswork about the code — the engine is compiled and tested.
But **none of the SwiftUI has been compiled**, because that needs Xcode. Expect
to fix a few things on the first build.

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

## 3. Raise the deployment target

The project is set to iOS 17.0. That works, but the newer Vision API and several
SwiftUI conveniences want iOS 18. iOS 17 is what the engine package declares, so
either is fine — just keep the two in step.

## 4. Add the watch target

**File ▸ New ▸ Target ▸ watchOS ▸ App**, named `FlowerPower Watch`, embedded in
the `FlowerPower` app. Then:

- Add `FlowerPowerCore` to its Frameworks list.
- Add the files from `FlowerPowerWatch/` to it.
- `HiveComplication.swift` belongs in a **Widget Extension** target rather than
  the watch app itself (**File ▸ New ▸ Target ▸ watchOS ▸ Widget Extension**).
  It carries its own `@main`, so it will collide if you put it in the app target.

## 5. Capabilities and permissions

**App Groups** on the iOS app, the watch app *and* the widget extension:

```
group.com.kylepeterson.flowerpower
```

This must match `GamePersistence.appGroupIdentifier`. It is how the watch and the
complication read the same save file the phone writes. If you use a different
identifier, change it in one place — that constant.

**Info.plist**, on the iOS target:

| Key | Why | Suggested text |
|---|---|---|
| `NSCameraUsageDescription` | Photographing flowers | "FlowerPower uses the camera to photograph flowers for your bees." |
| `NSPhotoLibraryUsageDescription` | Reading and saving flower photos | "Your flower photographs are kept in your library and shown in your garden." |
| `NSPhotoLibraryAddUsageDescription` | Saving captures | "Flowers you photograph are saved to your library." |
| `NSLocationWhenInUseUsageDescription` | Placing flowers on the map | "Locations let your flowers appear on the map, and set how far your bees must fly. FlowerPower works without it." |

Location genuinely is optional — patches fall back to a nominal distance and the
map shows a note. Don't let the prompt read as though it's required.

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
