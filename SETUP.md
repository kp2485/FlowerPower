# Getting FlowerPower building on the Mac

The engine is a Swift package and builds anywhere, including Windows. The app
and the watch app are Xcode targets and need a Mac.

Two things to know before starting.

**The Xcode project is generated.** `FlowerPower.xcodeproj` is not in git.
It is built from `project.yml` by XcodeGen, because the hand-maintained one had
drifted so far from the files on disk that it could not open and build at all.
The previous page of drag-and-tick instructions in this file is gone with it.

**The SwiftUI has never been compiled.** The engine and the game layer are
tested — 248 XCTest plus 19 Swift Testing cases, run on Windows — and every engine call in the views was
checked symbol by symbol against the package's public surface. But anything
that needs the Apple SDKs, which is all of SwiftUI, MapKit, PhotosUI, Vision,
WidgetKit, WatchConnectivity and BackgroundTasks, has never been near a
compiler. Expect a round of errors on the first build. That is the known cost
of the arrangement, not a surprise.

---

## 1. Generate the project

```bash
brew install xcodegen
xcodegen generate
open FlowerPower.xcodeproj
```

That is the whole setup. `project.yml` already declares:

- four targets — the iOS app, its widget extension carrying the Home Screen
  widget and the Live Activities, the watch app, and the watch widget
  extension that carries the complication;
- the local `FlowerPowerCore` package, and which of its two libraries each
  target uses;
- the App Group `group.com.kylepeterson.flowerpower` on all three;
- the camera, photo library and location usage strings;
- background refresh, and the task identifier it registers;
- the `.flower`, `.swarm` and `.flowerhive` document types — the first two are
  how one player's flower or swarm reaches another, the third is a backup of a
  whole colony, and all three are what makes tapping one in a message open the
  app;
- Live Activities, and the notification categories whose action buttons let a
  player answer a siege from the lock screen.

It also picks up three kinds of file that are not source and are not listed
anywhere, because XcodeGen chooses a build phase from the file extension and
everything it has no special case for goes into Copy Bundle Resources. They are
all simply inside a target's directory:

- **`PrivacyInfo.xcprivacy`**, one each in `FlowerPower/`,
  `FlowerPowerWidgets/` and `FlowerPowerWatch/` (the watch's is named
  explicitly for the complication extension as well, since that target lists
  its files individually). App Store submission is rejected without one.
  **It has to be kept in step with the code**, and the failure mode is a
  rejected build rather than a compiler error: it declares the
  required-reason APIs the binary actually calls, which today is UserDefaults
  in the phone app and nothing at all in the two extensions. If anything ever
  reads a file's modification date, the system boot time, or how much disk
  space is left, the manifest needs a matching entry. The comment at the top
  of `FlowerPower/PrivacyInfo.xcprivacy` lists what was grepped for and what
  was deliberately left out.
- **`Localizable.xcstrings`**, one per target, currently empty.
  `SWIFT_EMIT_LOC_STRINGS` is on, so the first Mac build extracts every
  `Text("…")` in the app into them. They exist now only so that extraction has
  somewhere to go; nothing is translated and the game is English-only.
- **`Assets.xcassets`**, which now actually has an app icon in it — see
  `tools/make_app_icon.py` below.

Re-run `xcodegen generate` after adding a file. Nothing needs ticking by hand:
target membership is a directory now, not a list of UUIDs. The generated
project, the generated Info.plists and the generated entitlements are all
gitignored — edit `project.yml` instead, or the change will vanish.

Verify the engine without Xcode at any point:

```bash
swift test --package-path FlowerPowerCore
```

## 2. What lives where

| | |
|---|---|
| `FlowerPowerCore/Sources/FlowerPowerCore` | The simulation. No UI, no Apple-only frameworks, no I/O. |
| `FlowerPowerCore/Sources/FlowerPowerGame` | `GameStore`, `GamePersistence`, `ColonyNews`. Foundation and Observation only, so it compiles and is tested off-Mac. |
| `FlowerPowerCore/Sources/BeeSim` | The headless balance runner. |
| `FlowerPower/` | The iOS app: views and services. |
| `FlowerPowerWatch/` | The watch app and the complication. |
| `FlowerPower/Legacy/` | The superseded 2023 model layer, excluded from every target. Delete it once the new app has run on device. |
| `tools/` | Scripts that generate committed assets. Standard-library Python only, so they run on the development machine. |

The rule that keeps this honest: **if it can live in the package, put it in the
package**, because that is the part that can be compiled and tested without a
Mac. `ColonyNews` — the judgement about whether something deserves a
notification — is there for exactly that reason, even though only the app uses
it.

## 3. Deployment target and language mode

iOS 27 and watchOS 27, matching what the package declares. Keep the two in step
if you move either.

The package builds in the **Swift 6 language mode** with complete concurrency
checking, and does so cleanly - which is less of a surprise than it sounds. The
engine is almost entirely `Sendable` value types, because the determinism the
whole design rests on and the data-race safety the compiler wants turn out to
be the same property. The test targets stay in Swift 5 mode: XCTest fixtures
are shared mutable state by nature, and rewriting two hundred passing tests to
satisfy the checker would be churn.

New tests are written with **Swift Testing**, which runs on Windows alongside
the existing XCTest suites. Parameterised cases are the reason: one test covers
the whole flower catalogue rather than thirty near-copies.

## 4. Signing

The bundle identifier is `com.kylepeterson.flowerpower`, changed from the 2023
`com.LinwoodTechnologies.FlowerPower` so that it, the App Group and both
`Logger` subsystems agree. Nothing was provisioned under the old one. If that
turns out to be wrong, it is one line in `project.yml`.

The App Group must be enabled on all three targets. It is how the phone app,
the watch app and the widget extension read the same save file **on one
device**. It is not how the phone talks to the watch — App Groups do not span
devices, which was a real bug for a while. The phone sends the watch a copy of
the save over WatchConnectivity; see `WatchLink`.

## 5. The flower classifier

Identification is a bonus, never a gate: a flower the app cannot name still
feeds the colony at a reduced yield.

It works today, without a trained model, by matching Vision feature prints
against reference photographs. No references are bundled yet, so the library
starts empty and fills from flowers the player names themselves and flowers
other people share with them — which means it gets better as the game is used.
Curating a starter set of reference photographs is the cheapest real
improvement available.

**Do not start with the Oxford 102 dataset**, despite it being the obvious
choice for flower classification. It is ornamental and glasshouse flowers;
this catalogue is British bee forage, and about six of the thirty species
overlap. See [docs/CLASSIFIER.md](docs/CLASSIFIER.md) for what to use instead,
how model labels are mapped onto catalogue species, and which species will be
hard to separate.

Visual Look Up — the plant identification in Photos — has no public API and
cannot be used. That is why a model is needed at all.

## 6. The app icon

`FlowerPower/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is generated:

```bash
python tools/make_app_icon.py --preview 60
```

A honey comb filling the frame with a pale six-petalled flower on the middle
of it. Pure standard library — no Pillow, no numpy — so it runs on the Windows
machine the engine is developed on: shapes are signed distance functions,
pixels are filled by coverage, and the PNG is written with `zlib` and
`struct`. The palette is `Theme.honey`, `Theme.nectar`, `Theme.pollen` and
`Theme.wax` from `FlowerPower/Views/Theme.swift`, and `AccentColor.colorset`
is set to `Theme.honey` exactly.

`--preview 60` writes a second PNG downsampled to 60 pixels, which is the only
honest way to check the claim that it is legible at icon size. `--out` and
`--also` write elsewhere; the watch's own `FlowerPowerWatch/Assets.xcassets`
gets the same image, which survives watchOS's circular mask because the comb
runs to the edges and the flower is centred.

It is not a designed icon and should be replaced by one. It is there because
the empty `AppIcon.appiconset` that was there before is a build error waiting
to happen, and because a script can be adjusted by changing a number and
reviewed in a diff.

## 7. The UI tests

**`FlowerPowerUITests` has never been run**, by anything, ever. Neither has
`FlowerPowerTests`. They are written and desk-checked and that is all.

What is in there is one launch test that asserts the app reaches one of three
screens — the tab bar's "Colony", or "A New Colony", or "Begin Again" — and is
still in the foreground when it does, plus the launch-performance measurement
and a per-configuration launch screenshot. The Xcode template's `testExample`,
which launched the app and asserted nothing, is gone: it would have reported
green for an app that drew a blank window.

There is no launch argument for starting from a known save, so the tests run
against whatever colony is on the simulator. That is the first thing to add
before any test can drive the interface rather than just watch it start.

---

## Balance tooling

The engine ships with a headless runner. Everything about colony balance is
decided from its output rather than from reading the code; see
[PLAN.md](PLAN.md) and the comments in `SimulationConfig.swift` for what the
numbers are solving for.

```bash
swift run --package-path FlowerPowerCore -c release beesim \
    --trials 200 --days 730 --patches 9 --restock 45
```

Runs 200 seeded colonies for two simulated years with a player who keeps
photographing, and reports survival, peak population, winter cluster, autumn
stores, the share of attacks repelled, total nectar gathered, and what killed
the ones that died.

```bash
... beesim --trials 60 --days 730 --patches 9 --restock 45 --list
```

Adds a line per colony — its seed, how it died, and on what day of which
season. That is how a colony worth tracing gets picked.

```bash
... beesim --trials 200 --days 730 --policy split
```

Measures what a player who *answers* the decisions gets, against one who never
opens the app. `instinct` is the default and the baseline; the others are
`makeRoom`, `addComb`, `split` and `roomThenSplit`.

```bash
swift run --package-path FlowerPowerCore -c release beesim \
    --days 560 --every 4 --seed 32676 --patches 9 --restock 45
```

Traces one colony day by day. This is how nearly every balance bug in the
engine has been found — five of them now, including all three queen bugs behind
the second-year collapse, comb being drawn out of the winter larder, and a
second swarm cast on the day a new queen mated. None was visible in an
aggregate and every one was obvious within a few lines of a trace.

```bash
... beesim --set swarmSeasonStart=0.3 --set pheromoneDilutionScale=70
```

Sweeps any listed constant without a rebuild. An unknown key is a hard error,
deliberately: a silently ignored override produces a sweep whose rows all
secretly used the same value.

Habits worth keeping:

- **Run the same command twice and diff the output before believing either.**
  The engine is deterministic across processes and byte-identical run to run,
  and it was not until 2026-09-06 — Swift seeds its `Hasher` per process, and a
  dictionary iterated in hash order inside `DiseaseSystem` forked the random
  stream. Two identical runs returned 30% and 33%. If a diff ever shows a
  difference again, that is a bug in the engine rather than in the tool.
- **Use 200 trials, not 60.** At 60 a `waxIncomeShare` sweep looked like a
  clean step from 45% to 60%; at 200 the same sweep is flat within three
  points. At 24 the noise is around eight points and non-monotonic.
- **Always `-c release`.** A 200-colony two-year run takes about 45 seconds
  against more than half an hour in debug. Release and debug agree on the
  trajectory but not always on the last bit, so never quote one against the
  other.
- **Isolate one change at a time.** Turning three related constants on together
  moves every trajectory, and the comparison reads as a null result even when
  each one on its own does something.
- **Never run two trial batches at once.** They starve each other of CPU and it
  looks like a hang.
