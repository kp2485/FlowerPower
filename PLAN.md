# FlowerPower — state of the project and what is next

Audited and worked through on 2026-09-05. The engine was built and its full
suite run on Windows; the Xcode side was written but not compiled, because that
needs a Mac.

---

## 1. Where things stand

### Verified here

| Layer | State |
|---|---|
| `FlowerPowerCore` engine | 248 XCTest + 96 Swift Testing, 0 failures |
| Swift 6 language mode | Builds clean, complete concurrency checking |
| Determinism | Byte-identical across processes; three runs diffed |
| Balance, standard preset | See the table below. Re-baselined 2026-09-06 on a deterministic release build |
| `beesim` | Sweeps any constant with `--set`, any player policy with `--policy`, reports forage scale with `--scale` |

#### The balance baseline, and why the numbers moved

The previously recorded baseline — 75% first year, 37% second — was measured
before the determinism fix above and in a debug build. It was not wrong so much
as unrepeatable: the same command gave anything from 30% to 37% depending on
what hash seed the process happened to get. Nothing about the colony changed on
2026-09-06; the measurement did.

Every number below is from `beesim --trials 60 --days 730 --patches 9
--restock 45` on a release build, and every one of them reproduces exactly.

### Not verified, and cannot be here

Everything in `FlowerPower/`, `FlowerPowerWatch/` and `FlowerPowerWidgets/` —
roughly 7,000 lines of SwiftUI, MapKit, PhotosUI, Vision, FoundationModels,
ActivityKit, WidgetKit, WatchConnectivity and BackgroundTasks. **Nothing in
those three folders has ever been through a compiler**, and nothing said about
them below should be read as though it had.

`project.yml` has also never been run through XcodeGen. Its keys were checked
against XcodeGen's own parser source rather than from memory, but XcodeGen does
not build on Windows, so the generated project is unseen.

#### The desk-check of 2026-09-06

Every file in those three folders was read against the package's actual public
surface: each type, initialiser, property and enum case the interface names was
grepped for in the package and its signature compared. Where a Swift 6
concurrency question could be reduced to plain Swift with no Apple frameworks
in it, it was written as a small file and run through `swiftc -swift-version 6
-typecheck` on this machine rather than guessed at. That is how the fixes
below were chosen: each one was checked to be *necessary* by reproducing the
error on a minimal case, and *sufficient* by compiling the replacement.

What that found and fixed:

- **A build failure that had been there for a while.** `SimEvent.narration`,
  the sentence shown for each event in the catch-up report, was a switch in
  `CatchUpReportView` — in a target nothing on this machine compiles. The
  engine gained seven cases with the decision events (`threatBegan`,
  `threatEnded`, `swarmPreparing`, `swarmAbandoned`, `postureAdopted`,
  `entranceSealed`, `honeyTaken`) and the switch was never extended, so it had
  been non-exhaustive since. It now lives in the package as
  `Presentation/EventNarration.swift`, with `EventNarrationTests` — which is
  the general lesson: **anything that switches over an engine type belongs in
  the package**, because that is where the compiler can see it.
- **Three cards drawn in the navigation bar.** `ColonyDashboardView` had
  `HoneyDecisionCard`, `RecordLinks` and `BloomPromptCard` inside a single
  `ToolbarItem`. It compiles — a `ToolbarItem` takes a `ViewBuilder` and will
  accept four views — and would have tried to lay three cards out in the
  navigation bar. They are back in the scroll view; the toolbar keeps the
  photograph button.
- **Five Swift 6 strict-concurrency errors**, each reproduced on a minimal
  case first:
  - `HiveHum` is `@MainActor`, and its `AVAudioSourceNode` render callback read
    seven main-actor properties from the audio thread. The oscillator state
    moved into a nonisolated `Tone` box the callback captures instead.
  - `WatchLink` was captured in `@Sendable` closures without being `Sendable`,
    and its three throttle counters were plain `var`s touched from the main
    actor, the background task and WatchConnectivity's own queue — a real data
    race, not only a compiler complaint. They are behind an `NSLock` now.
  - `BackgroundRefresh.handle` sent a non-`Sendable` `BGAppRefreshTask` into a
    `Task` and an expiration handler.
  - `NotificationDelegate` captured itself in `MainActor.run`'s `@Sendable`
    closure.
  - `FlowerClassifier` is a `Sendable`-conforming struct with a
    `VNCoreMLModel?` stored property.
  - `PhotoLibrary` mutated captured `var`s from inside two Photos callbacks
    (the resume-once flag and the new asset's identifier). Both are locked
    boxes now, which compiles whether or not those SDK blocks turn out to be
    `@Sendable`.
- Two defensive tidies: `Section("title") { } footer: { }` in
  `JobAssignmentView` rewritten to the `header:`/`footer:` form that certainly
  exists, and a duplicated `@Environment(\.scenePhase)` in `ContentView`
  removed.

#### Still not verified, and why

The desk-check can only compare against things this machine can see. These
were read and reasoned about but not proved:

- **Foundation Models.** `@Generable`, `@Guide`, `LanguageModelSession`,
  `Attachment(image)` and `SystemLanguageModel.availability` in
  `TaxonomicClassifier`. Written for iOS 27's image-attachment support; the
  spelling of every one of them is from documentation, not from a compiler.
- **The new Vision Swift API.** `GenerateImageFeaturePrintRequest`,
  `ClassifyImageRequest`, `FeaturePrintObservation.elementType` and
  `.revision2` in `FeaturePrints`.
- **The old Vision API in the same app.** `FlowerClassifier.classifySpecies`
  still uses `VNCoreMLModel`, `VNCoreMLRequest` and `VNImageRequestHandler`,
  which were deprecated in favour of the Swift API. Deprecated is not removed,
  and the path is dead code until a model is bundled, but if iOS 27 has
  obsoleted them this is where it will show.
- `CLLocationUpdate.liveUpdates(.default)` and `update.authorizationDenied` in
  `CaptureView`'s `LocationProvider`.
- `WCSession.transferCurrentComplicationUserInfo`, which is the budgeted
  channel for keeping a complication current and may or may not have survived
  ClockKit's deprecation.
- Whether the SDK blocks in `PhotoLibrary`, `BGTaskScheduler.register` and
  `PHPhotoLibrary.performChanges` are `@Sendable`. The fixes above are correct
  either way, so this only decides whether they were needed.
- `BGTaskScheduler.register`'s return value: if it is not
  `@discardableResult`, the call in `BackgroundRefresh.register` warns.
- Every SF Symbol name, of which there are well over a hundred. A wrong one is
  a blank square, not a build failure.
- Whether `HiveActivityAttributes`, compiled into both the app and the widget
  extension as two copies of an internal type, matches at runtime the way
  ActivityKit expects.

---

## 2. What was done

**Phase 0 — housekeeping.** Committed the outstanding varroa and swarming work.
Line endings normalised. The 2023 tower-defence design document retired; its
research notes kept as `docs/RESEARCH.md`.

**Phase 1 — the project builds.** The checked-in `project.pbxproj` compiled five
2023 files at paths that no longer existed and knew nothing about the fifteen
that replaced them, the package, or the watch. Replaced by `project.yml` and
XcodeGen. `GameStore` and `GamePersistence` moved into the package as
`FlowerPowerGame`, which made them testable and removed the manual
target-membership steps.

**Phase 2 — the core loop.** Photographed patches now fade, so photography is
load-bearing: with no new photographs survival is 0%, and with them it is 73–77%
across a wide range of cadences. `ColonyStatus.collapsed` exists and a dead
colony leads to a new-colony screen instead of a dashboard whose numbers stopped.
The garden carries across. Camera capture, background refresh, notifications,
and a settings screen that finally calls `setDifficulty`, `relocateHive` and
`startNewGame`.

**Phase 3 — the watch.** The watch and the complication were reading an App
Group expecting the phone's save. App Groups do not span devices, so they found
nothing, every time. The phone now sends the save by file transfer and the watch
stores it in its own container.

**Phase 4 — identification.** Oxford 102 is the wrong dataset for this
catalogue; `docs/CLASSIFIER.md` says what to use instead. A synonym table maps
model labels onto species, and fixes a matcher that resolved "poison ivy" to the
keystone autumn nectar source. Until a model exists, the player can name a
flower themselves.

**Phase 5 — the second year.** Two-year survival was 15%. It was three queen
bugs, not realism: no start to the swarm season, swarming permitted without a
queen to send, and every virgin queen superseded before she could fly. Now 25%.

**Sharing flowers.** A flower travels between players as a `.flower` file
through the share sheet — no server, no accounts. It arrives at full strength:
a yield penalty was tried and removed, because measurement showed it did not
prevent anything and a gift that arrives diminished is a poor gift. Location is
opt-in and rounds to about a kilometre by default, because a flower
photograph's coordinate is where a person was standing. Everything received is
clamped rather than trusted.

**Identification without a model.** Vision feature prints matched against
reference photographs, so the app can place flowers today rather than after a
dataset exists. The library grows from flowers the player names and flowers
people share.

**Botanical classification.** Flowers are placed to a family, genus or species
— whichever can honestly be reached — and forage is derived from measured
floral traits rather than two abstract numbers. Corolla depth against a honey
bee's reach, sugar concentration apart from volume, pollen protein and amino
acid completeness apart from abundance. The engine reports exactly four plants
a honey bee cannot work for nectar, which is the right four.

**iOS 27 and the Swift 6 language mode.** Foundation Models with image input
and guided generation places flowers at whatever rank it is sure of. Vision and
CoreLocation move to their modern async APIs. New tests are Swift Testing.

**The player experience, all twenty-one proposals.** See `docs/PROPOSALS.md`
for each. The shape of it: decisions with real windows — a siege, a swarm
gathering, the autumn entrance, the colony's surplus — that arrive as
notifications with action buttons and default to instinct if nobody answers; a
record the colony keeps of itself in a line of queens and an almanac; the
garden as a collection with a bloom calendar; Live Activities and a Home Screen
widget; swarms and forage requests between players; a faster winter; the hum.
Every mechanic is in the engine and measured; the interface is written and
uncompiled.

---

## 3. What is next

### Immediately, and only on a Mac

1. **Generate and build.** `brew install xcodegen && xcodegen generate`, then
   fix what the compiler finds. This is the single biggest unknown in the
   project and everything below is easier once it is done. There are now four
   targets — the widget extension is new — and roughly 7,000 lines of
   uncompiled interface, services, ActivityKit and WidgetKit.
2. **Run on a device.** The paths worth walking first are the ones with no test
   coverage at all: photographing a flower with the camera, the map with and
   without location permission, and the watch receiving its first save.
3. **Delete `FlowerPower/Legacy/`** once the new app has run.

### Then

4. **Second-year survival, again.** Short of the ~75% a year that established
   colonies manage. Two over-rearing bugs were found and fixed on the way here
   — brood headroom ignoring adult upkeep, and a laying reserve that did not
   scale with the colony — so another tracing pass is likely to find more.

   One strong lead, from the policy table below: simply *answering* the swarm
   at all — by any means — is worth 5 to 16 points of two-year survival. The
   second-year cliff is substantially a swarming problem.
6. **Winter.** A quarter of the year with nothing to photograph and little to
   watch. The pacing note in `SimClock` argues the answer is something to do in
   winter rather than a faster clock.
7. **Curate reference photographs.** Still the cheapest real win for devices
   without Apple Intelligence: the feature-print classifier works but ships
   with an empty library, so it places nothing until the player does. Thirty
   species, a handful of photographs each. `docs/CLASSIFIER.md` has the
   sources.
8. **Check the on-device model against real photographs.** The taxonomic
   classifier is written and its answer-handling is tested, but nobody has
   seen what the model actually says about a British hedgerow. The open
   question is whether it places to family honestly or reaches for a species,
   which is what the prompt is written to discourage.
9. **Tune `FeaturePrintLibrary.maximumDistance` on device.** It is the number
   that decides between naming things wrongly and naming nothing, and it was
   set by reasoning rather than by measurement — feature-print distances are
   not normalised, so it needs real photographs.
10. **Train the classifier**, if neither of the above is good enough.
   `docs/CLASSIFIER.md` is the brief.
11. **App icon.** There is an empty `AppIcon.appiconset`.

### Done since

**5. Something to do about swarming.** Two decisions, in the same shape as the
existing ones, with instinct still the default: `addComb` opens the nest up,
and `split` divides the colony deliberately. Measured across 60 colonies over
two years, each policy played by a notional player who acts on the
notifications:

| policy | survival | peak pop | swarms | comb added | splits | autumn stores | winter cluster |
|---|---|---|---|---|---|---|---|
| instinct (nobody answers) | 32% | 464 | 1.20 | — | — | 249 | 41 |
| make room (the old answer) | 48% | 518 | 0.93 | — | — | 389 | 164 |
| add comb | 42% | 500 | 1.52 | 1.50 | — | 285 | 80 |
| split | 30% | 496 | 0.00 | — | 0.93 | 251 | 47 |
| add comb, then split | 37% | 518 | 0.00 | 1.58 | 0.97 | 298 | 80 |

First-year survival on the same deterministic build is **75%**, with 0.17
swarms per colony — unchanged from what was recorded before, and the reason to
believe the tooling rather than suspect it. The first year was never the
problem; only the second-year figure was being read off a noisy measurement.

Three things in that table are worth saying plainly.

**Adding comb had to give drawn comb, not room.** The obvious implementation —
raise `Comb.capacity` and let `ConstructionSystem` fill it — was built first and
measured at exactly nothing: it never fired once in 60 colonies over two years,
and when the trigger was loosened until it did, swarming was unmoved. The reason
is that `swarmPressure` is driven by `combOccupancy`, which is cells *used* over
cells *drawn*. Empty cavity is not in that ratio, and a congested colony cannot
afford to draw into it, because comb costs seven honey to one of wax and it has
none to spare. This is exactly why beekeepers prize drawn comb over foundation,
and giving the bees drawn comb at the honey price of the wax is what the method
now does.

**Adding comb does not stop them swarming — it makes them survive it.** Swarms
went *up*, 1.20 to 1.52, while survival went up 10 points. A colony with room
puts away more (autumn stores 249 to 285) and goes into winter twice the size
(cluster 41 to 80), and a bigger colony swarms more. That is the real relationship, not a
bug.

**A deliberate split does not improve survival.** It does exactly what it says —
swarms fall to zero, reliably, every time — but the colony pays about what a
swarm would have cost it, and two-year survival lands at 30% against instinct's
32%, which is inside the noise. It is a decision, not an upgrade: it buys
certainty and timing, and it makes the half that leaves something the player can
give to a friend, follow, or let go. It is not a way to win.

### Not decided

- Whether the two-year cliff, now that it is 25% rather than 15%, is where it
  should sit for an idle game.
- Whether the catch-up ceiling of 180 simulated days — a fortnight of real
  absence — is generous enough. Beyond it, time is skipped rather than lived.
- Whether a deliberate split should keep more than one queen cell. It keeps the
  best-developed one and tears the rest down, which is what a beekeeper does and
  is why there is no afterswarm — but it also means one failed mating ends the
  colony, where a swarm leaves several cells as insurance. Keeping two is the
  obvious lever if the split ought to beat parity rather than match it.
- Whether the split should require a nearly ripe queen cell. It can currently be
  taken the moment cells are started, which leaves the colony queenless about a
  week longer than a swarm would have, and mated queens per colony fall from
  2.35 to 1.50 because of it.

---

## 4. Working rules

- **Run the same thing twice and diff it, before believing either.** The
  engine is deterministic across processes as of 2026-09-06, and was not
  before. Swift seeds its `Hasher` randomly once per process, so every
  `Dictionary` iterated in a different order in every run — and
  `DiseaseSystem.applyMortality` draws from the RNG once per pathogen, so two
  runs of the same seeds consumed the random stream differently and forked.
  Two identical `beesim --trials 60 --days 730` runs returned 30% and 33%.
  Every A/B comparison made before that date carried three points of invisible
  noise on top of seed variance. The fix is `PathogenLoad.ordered` and
  `ResourcePool.ordered`, which iterate `allCases` rather than hash order;
  `OrderingTests` holds the line, and the end-to-end check is two runs and a
  diff.

- **Measure in a release build.** `swift build -c release --product beesim`.
  A 60-colony two-year run takes 14 seconds against more than ten minutes in
  debug, which is the difference between measuring five variants and measuring
  one. Release and debug agree on the trajectory but not always on the last
  bit, so never quote a debug number against a release one.

- **Measure, do not eyeball.** `beesim --trials 60` before and after any
  constant change, and read cause and season of collapse first. At 24 trials
  the noise is eight points.
- **Trace when the aggregate looks wrong.** All three queen bugs were invisible
  in the summary and obvious in `beesim --every 8 --seed N`.
- **A sharp edge in a survival curve is a bug.** Attrition is gradual; 75% to
  25% in sixty days was three modelling errors.
- **If it can live in the package, put it there.** That is the part that can be
  compiled and tested without a Mac.
- **Relative values come from the science; the absolute scale is calibrated.**
  Floral traits are measurements. The unit they are expressed in is normalised
  to the catalogue mean, because every consumption constant in the engine
  assumes the mean flower is 1. Never fix a balance problem by shaving a
  measured trait.
- **Nothing in the Xcode targets is verified until Xcode has seen it.** Say so.
