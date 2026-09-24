# Getting FlowerPower building on the Mac

The engine is a Swift package and builds anywhere, including Windows. The app
and the watch app are Xcode targets and need a Mac.

Two things to know before starting.

**The Xcode project is generated.** `FlowerPower.xcodeproj` is not in git.
It is built from `project.yml` by XcodeGen, because the hand-maintained one had
drifted so far from the files on disk that it could not open and build at all.
The previous page of drag-and-tick instructions in this file is gone with it.

**The SwiftUI was first compiled on 2026-09-14**, with Xcode 26.5, and against
the iOS 27 SDK it was written for on 2026-09-15, with Xcode 27. It took nine
fixes to build and two more to stop it crashing, all recorded in PLAN.md under
"The first Mac build"; Xcode 27 added two deprecations and nothing else. The
engine and the game layer were tested long before — on Windows, and now on
macOS too — which is why none of the faults were in them.

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
- the App Group `group.com.linwoodtechnologies.flowerpower` on all three;
- the camera and photo library usage strings — there is no location string,
  because the app asks for no location; see PLAN.md, "location removed";
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
- **`Localizable.xcstrings`**, one per target. `SWIFT_EMIT_LOC_STRINGS` is
  on, and building in **Xcode.app** fills them with every `Text("…")` in the
  app — 379, 28 and 12 strings on the first such build, 2026-09-15.
  `xcodebuild` on the command line does not write them back, so a string
  added in code reaches the catalogue at the next Xcode.app build; commit the
  catalogues when they change. Nothing is translated and the game is
  English-only.
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
| `FlowerPowerCore/Sources/FlowerPowerCore` | The simulation, and since 2026-09-15 the hex world under it — `Core/Hex.swift`, `Core/Biome.swift`, `Core/WorldGenerator.swift`, all pure functions of a seed. No UI, no Apple-only frameworks, no I/O. |
| `FlowerPowerCore/Sources/FlowerPowerGame` | `GameStore`, `GamePersistence`, `ColonyNews`. Foundation and Observation only, so it compiles and is tested off-Mac. |
| `FlowerPowerCore/Sources/BeeSim` | The headless balance runner. |
| `FlowerPower/` | The iOS app: views and services. |
| `FlowerPowerWatch/` | The watch app and the complication. |
| `tools/` | Scripts that generate committed assets. Standard-library Python only, so they run on the development machine. |

The rule that keeps this honest: **if it can live in the package, put it in the
package**, because that is the part that can be compiled and tested without a
Mac. `ColonyNews` — the judgement about whether something deserves a
notification — is there for exactly that reason, even though only the app uses
it.

## 3. Deployment target and language mode

iOS 27 and watchOS 27, matching what the package declares. Keep the two in step
if you move either. That needs Xcode 27. The very first build was done on Xcode
26.5 by overriding the targets on the `xcodebuild` command line; PLAN.md's
"The first Mac build" says how, should an older Xcode ever be all there is.

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

The team is LINWOOD TECHNOLOGIES, LLC (`588PCRUA35`), a paid company team —
not the free Personal Team, which is `48Z7V96VSN` and cannot sign an App
Group. The bundle identifier is `com.linwoodtechnologies.flowerpower`, in the
company's namespace to match, and the App Group, the watch's companion
identifier, the background task, the three document types, both widget kinds
and every `Logger` subsystem are spelled from it. It was
`com.kylepeterson.flowerpower` until 2026-09-15; changing it is not one line,
and was done everywhere at once for that reason — a mismatch fails silently
(a widget that finds no save, a background refresh that never runs) or, for an
extension, fails the build with "Embedded binary's bundle identifier is not
prefixed with the parent app's bundle identifier".

Automatic signing needs an Apple ID signed in under Xcode → Settings →
Accounts. After an Xcode or macOS upgrade it may not be: the build then fails
with "No Accounts" and, having nothing better, tries the team's wildcard
profile, which can never carry an App Group — four errors per target, sixteen
in all. Signing back in is the whole fix; Xcode registers the App Group and
makes the profiles itself.

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

**Both test targets first ran on 2026-09-14**, on an iOS 26.5 simulator with
the deployment target overridden, and pass: the ten
`FlowerPowerTests` cases and all four UI test runs. The launch test failed on
its first run, correctly — it listed the site chooser as where a first run
lands, and the introduction had been put in front of that since it was
written.

What is in there is one launch test that asserts the app reaches one of three
screens — the tab bar's "Colony", or the introduction's first page, "A wild
colony", or "Begin Again" — and is still in the foreground when it does, plus
the launch-performance measurement and a launch screenshot in light and dark.
The Xcode template's `testExample`, which launched the app and asserted
nothing, is gone: it would have reported green for an app that drew a blank
window.

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
opens the app. `instinct` is the default and the baseline. The answers to
congestion are `makeRoom`, `addComb`, `addCombEagerly`, `split` and
`roomThenSplit`; the answers about the larder are `harvest` (one crop late
each autumn), `harvestAndFeed` (and giving it back whenever the colony is
short), `harvestEagerly` (taking the surplus whenever it is offered, which is
what the honey card actually allows) and `harvestEagerlyAndFeed`.

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
secretly used the same value. The world adds nine keys of its own:
`wildPatchYield` and `wildPatchDensity` (how rich a wild stand is, and how many
there are — density is the lever, yield mostly is not), `danceFloorPatches`
(how many patches the dance will recruit onto at once), `danceDistanceExponent`
(how much harder a distant patch has to work to be danced for),
`biomeThreatScale` (1.0 as shipped; 0 switches the biome multipliers on
predators and pathogens off entirely, which is what a test measuring sites
rather than geography wants), `scoutShare` and `scoutDays`, and
`explorationShare` and `explorationChance`. And `winterForageMultiplier`, what a
stand that blooms in winter gives on a day warm enough to fly (0 until
2026-09-24, 0.5 as shipped).

```bash
... beesim --trials 200 --days 730 --patches 9 --restock 45 --world
... beesim --world --world-seed 2026 --list
... beesim --world --patches 0 --biome heath --trials 200 --days 365
... beesim --world --patches 9 --restock 45 --policy scout
```

`--world` gives the trial colony the generated world of
[docs/WORLD.md](docs/WORLD.md) — a home chunk, a garden of hex cells around the
nest that photographed patches are planted into at 200 m in the first ring and
400 m in the second, and, since Phase 2, the wild forage standing in every chunk
the colony has discovered — instead of putting every patch at one distance.
`--world-seed` picks which world; without it every run is the same one. With the
world on, `--list` also names the home biome and says how many chunks the colony
ended up knowing.

`--patches 0 --world` is wild forage alone: a colony that has never been
photographed, living on what it finds. That is the run behind the 46% first-year
figure in PLAN.md, and it is the number the whole identity of the game rests on.

`--biome <name>` forces the home biome instead of taking whatever the seed
generated, which is the only way to get a survival-by-biome table out of one
world. The seven names are the ones in `Biome`: meadow, hedgerow, woodland,
riverbank, farmland, village, heath.

`--policy scout` measures a player who answers the one decision the world adds,
alongside the congestion and larder policies above: it sends scouts whenever the
game offers to. Each party costs a tenth of the foragers for three days and reveals every
rumoured chunk, so a colony that always scouts ends two years knowing about 133
chunks against instinct's 7.7 — and four points worse off for it.

**Leaving `--world` off forces `wildPatchDensity = 0`.** That is deliberate: a
`--distance` measurement is meant to isolate one lever, and a world-off run that
quietly grew wild flowers would not be comparable with any baseline recorded
before 2026-09-16.

`--world` is the only way to measure the game as the app actually plays it,
because the garden's patches are not all at one distance: they fill ring 1 at
200 m and spill into ring 2 at 400 m. **`--distance` defaults to 400 m, which is
not a distance the app has ever used** — every balance number recorded before
2026-09-15 was taken there, and the app's own flowers were at 800 m. If a
measurement is meant to be about the game rather than about one lever, use
`--world`; if it is meant to isolate distance, name `--distance` and it will
suppress garden placement. See PLAN.md, "the ground" and "the country".

Habits worth keeping:

- **Diff the built binary's output, not `swift run`'s.** `swift run` interleaves
  SwiftPM's build lines into stdout, so two identical runs differ in their first
  few lines and a byte-identity check reports a change that is not there. When
  the output is going to be diffed, build once and run the binary:

  ```bash
  swift build --package-path FlowerPowerCore -c release --product beesim
  FlowerPowerCore/.build/release/beesim --trials 200 --days 730 \
      --patches 9 --restock 45
  ```

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
