# Getting FlowerPower building on the Mac

The engine is a Swift package and builds anywhere, including Windows. The app
and the watch app are Xcode targets and need a Mac.

Two things to know before starting.

**The Xcode project is generated.** `FlowerPower.xcodeproj` is not in git.
It is built from `project.yml` by XcodeGen, because the hand-maintained one had
drifted so far from the files on disk that it could not open and build at all.
The previous page of drag-and-tick instructions in this file is gone with it.

**The SwiftUI has never been compiled.** The engine and the game layer are
tested — 201 tests, run on Windows — and every engine call in the views was
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

- three targets — the iOS app, the watch app, and the watch widget extension
  that carries the complication;
- the local `FlowerPowerCore` package, and which of its two libraries each
  target uses;
- the App Group `group.com.kylepeterson.flowerpower` on all three;
- the camera, photo library and location usage strings;
- background refresh, and the task identifier it registers.

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

The rule that keeps this honest: **if it can live in the package, put it in the
package**, because that is the part that can be compiled and tested without a
Mac. `ColonyNews` — the judgement about whether something deserves a
notification — is there for exactly that reason, even though only the app uses
it.

## 3. Deployment target

iOS 17 and watchOS 10, matching what the package declares. Keep the two in
step if you raise either.

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

---

## Balance tooling

The engine ships with a headless runner. Everything about colony balance is
decided from its output rather than from reading the code; see
[PLAN.md](PLAN.md) and the comments in `SimulationConfig.swift` for what the
numbers are solving for.

```bash
swift run --package-path FlowerPowerCore -c release beesim \
    --trials 60 --days 400 --patches 9 --restock 45
```

Runs 60 seeded colonies for a simulated year with a player who keeps
photographing, and reports survival, peak population, winter cluster, autumn
stores, and what killed the ones that died.

```bash
swift run --package-path FlowerPowerCore -c release beesim \
    --days 470 --every 8 --seed 8919 --patches 9 --restock 45
```

Traces one colony day by day. This is how nearly every balance bug in the
engine has been found, including all three of the queen bugs behind the
second-year collapse — none of them was visible in the aggregate, and all three
were obvious in a trace.

```bash
... beesim --set swarmSeasonStart=0.3 --set pheromoneDilutionScale=70
```

Sweeps any listed constant without a rebuild. An unknown key is a hard error,
deliberately: a silently ignored override produces a sweep whose rows all
secretly used the same value.

Two habits worth keeping:

- **Use at least 60 trials.** At 24 the noise is around eight points and
  non-monotonic, which has produced wrong conclusions more than once.
- **Never run two trial batches at once.** They starve each other of CPU and it
  looks like a hang.
