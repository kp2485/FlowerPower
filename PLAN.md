# FlowerPower — state of the project and what is next

Audited and worked through on 2026-09-05. The engine was built and its full
suite run on Windows; the Xcode side was written but not compiled, because that
needs a Mac.

---

## 1. Where things stand

### Verified here

| Layer | State |
|---|---|
| `FlowerPowerCore` engine | 248 XCTest + 123 Swift Testing, 0 failures |
| Swift 6 language mode | Builds clean, complete concurrency checking |
| Determinism | Byte-identical across processes; three runs diffed |
| Balance, standard preset | 89% first year, 66% second, 2.49 swarms per colony per two years (200 colonies, deterministic release build, 2026-09-06) |
| `beesim` | Sweeps any constant with `--set`, any player policy with `--policy`, reports forage scale with `--scale` |

#### The balance baseline, and why the numbers moved

Twice, for two different reasons, and it is worth keeping them apart.

**The measurement changed first.** The previously recorded baseline — 75% first
year, 37% second — was taken before the determinism fix above and in a debug
build. It was not wrong so much as unrepeatable: the same command gave anything
from 30% to 37% depending on what hash seed the process happened to get. Nothing
about the colony changed; the measurement did. Re-measured on a deterministic
release build it was 79% and 36% over 200 colonies.

**Then the colony changed.** Two modelling errors were found and fixed — comb
being drawn out of the winter larder, and a second swarm cast on the day a new
queen mated. Both are in section 3. Together they took the standard preset from
79%/36% to 92%/66%.

Every balance number in this document is now from `beesim --trials 200 --days
730 --patches 9 --restock 45` on a release build, and every one of them
reproduces byte for byte. Anything quoted at 60 trials says so, and should be
treated as indicative: a 60-colony sample moves five points on nothing.

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

  Acted on more widely afterwards. `Presentation/Symbols.swift` now holds the
  SF Symbol for every drawn engine type — nine switches that were in `Theme`,
  two of them written out a second and third time in `WatchTheme` and
  `WidgetTheme` — along with `HiveLocationType.summary` (the site notes the
  new-colony screen chooses on) and `AttackStyle.explanation`, which had been
  returning the empty string for the two styles with no posture to offer, so a
  card could show a siege and say nothing at all about it. Colours stayed in
  the app: `Color` is SwiftUI, and a palette is house style in a way that "a
  shield means defence" is not.
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

Items 4, 5 and 6 — second-year survival, something to do about swarming, and
winter — were done on 2026-09-06 and are written up under "Done since" below.
The numbering of what is left is unchanged so it still matches what you knew it
as. Everything remaining needs a Mac, a device, real photographs or a trained
model, so none of it could be started here.

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

**4. Second-year survival.** Two more modelling errors, both found by tracing
single seeds through their second spring rather than by reading the aggregate,
and neither visible in the summary. Measured over 200 colonies:

| | first year | second year | swarms per 2 yr | winter cluster | autumn stores |
|---|---|---|---|---|---|
| before | 79% | 36% | 1.25 | 57 | 288 |
| comb drawn from the flow | 88% | 54% | 2.76 | 124 | 384 |
| and no afterswarm on requeening | 92% | 66% | 2.53 | 293 | 608 |

**Comb was being drawn out of the larder.** `ConstructionSystem`'s own header
has always said "no flow, no drawn comb, no matter how much foundation you give
them", and the code gated on a flow being *on* and then spent everything above a
flat 25-unit reserve — which, for a colony that has just overwintered, is its
entire standing store. Traced on seed 32676: 60 bees came through winter with
107 units, met a day or two of willow in early spring, spent 71 of those units
drawing 127 cells they had no bees to fill, and starved on day 416 with their
whole nest of brood, at full vitality a fortnight earlier. Six more of the same
sixty did it inside the same fortnight, which is what the flat cluster of
starvations at days 408 to 424 in the trial list turned out to be. Wax is now
made out of the day's surplus income (`waxIncomeShare`), so a colony whose
income stops stops building that day.

**A requeening did not end the swarm that caused it.** `emergeQueens`
deliberately leaves developing queen cells standing as insurance against the new
virgin's mating flight, which is right and worth keeping. But `attemptSwarm`
needs a laying queen to send, so those leftover cells could not fire while she
was a virgin — and fired on the very tick she stopped being one. Seed 198975
reads `mated x13, SWARM (-245)` on a single line: the colony swarmed on day 410,
spent a month rebuilding and raising a replacement, and cast a second swarm with
57% of everything it had rebuilt on the day it finally had a queen again. It
starved on day 468. Seed 24757 reads `MATING FAILED, SWARM (-136)` — the same
thing through the failure branch, which also sets `queenIsMated` because that is
how a queen resolves to a drone layer.

So a mating flight, however it resolves, now brings down the swarm cells left
over from the swarm that produced her, and a colony headed by a drone layer does
not swarm at all — she cannot found anything, so every bee that leaves with her
is simply subtracted.

Note what this does to the *first* year as well as the second: 79% to 92%. Some
of the old first-year losses were the same over-building bug, hitting founding
colonies in their first spring.

**5. Something to do about swarming.** Two decisions, in the same shape as the
existing ones, with instinct still the default: `addComb` opens the nest up and
gives the bees drawn comb at the honey price of the wax, and `split` divides the
colony deliberately — the queen and the house bees move out, the foragers stay
with the nest because they know where it is, and one queen cell is kept so there
is no afterswarm behind the first.

Measured over 200 colonies across two years, each policy played by a notional
player who acts on the notifications (`beesim --policy`, new):

| policy | survival | swarms | comb added | splits | autumn stores | winter cluster |
|---|---|---|---|---|---|---|
| instinct (nobody answers) | 66% | 2.49 | — | — | 612 | 313 |
| make room (the old answer) | 76% | 1.75 | — | — | 756 | 366 |
| add comb | 62% | 2.23 | 1.87 | — | 580 | 279 |
| split | 56% | 0.06 | — | 2.59 | 517 | 203 |
| add comb, then split | 61% | 0.08 | 2.04 | 2.48 | 528 | 253 |

**Read that table against the one this section used to contain, because the
difference is the point.** These mechanics were built and measured *before* the
two modelling errors in item 4 were found, on an engine where colonies burned
their winter stores on wax and cast a second swarm on the day their new queen
mated. On that engine, answering the swarm at all looked enormously valuable —
make room appeared to take two-year survival from 32% to 48%, and adding comb
from 32% to 42%. On a correct engine almost all of that goes away: make room is
worth a point, and adding comb is slightly *negative*.

That is worth stating plainly rather than quietly restating the numbers. The
first measurement was not sloppy — it was 60 deterministic colonies, before and
after, exactly as the working rules ask. It was measuring a broken engine, and
no amount of care with the statistics fixes that. Balance conclusions are only
as good as the model underneath them, and a mechanic that looks strong is a
reason to go and check the model rather than to ship the mechanic.

**What survived the correction, and what did not:**

- **The mechanics do what they say.** A split takes swarms to exactly zero, in
  every colony, every time. Adding comb reliably gives the colony room it can
  use. Both are real levers.
- **Splitting was a trap, and both halves of why were modelling errors.** It
  first measured at 30% against instinct's 66%, and the two causes were:

  1. **It could be taken the moment swarm cells were started.** A swarm departs
     at `swarmDepartureDay`, four days short of the cell emerging; a split taken
     on sight left the colony without a laying queen for the whole twelve days
     of the cell's development, through the best of the build-up. A beekeeper
     performs an artificial swarm on a charged cell, not on a cup with an egg in
     it. `splitEarliestCellDay` now requires one, and the interface says how
     many days are left rather than showing a dead button.
  2. **It kept one queen cell and tore the rest down.** That is what a beekeeper
     does, and the reason is to stop an afterswarm following the artificial
     swarm out — a reason that no longer holds here, since afterswarms are
     prevented properly by item 4 above. All it was still doing was throwing
     away the insurance `emergeQueens` deliberately keeps against a failed
     mating flight, staking the colony on one queen getting home.

  Swept together over 200 colonies, both mattered and both pointed the same way:

  | cells kept | earliest cell day | survival | queens mated |
  |---|---|---|---|
  | 1 | 4 | 38% | 2.10 |
  | 1 | 6 | 46% | 2.42 |
  | 2 | 6 | 57% | 2.83 |
  | all | 6 | 56% | 2.91 |

  Keeping them all is now the default, because it needs no justification beyond
  "a swarm leaves them standing" and measures the same as keeping two. The
  mechanic lands at 56% against instinct's 66%: still a price, but a price
  rather than a trap — near-total certainty about swarming, and a swarm to give
  away, for ten points.
- **Adding comb still had to give drawn comb, not room.** The first
  implementation raised `Comb.capacity` and let `ConstructionSystem` fill it,
  and measured at exactly nothing: it never fired once in 60 colonies over two
  years. `swarmPressure` runs on `combOccupancy` — cells used over cells
  *drawn* — and empty cavity is not in that ratio. Which is why beekeepers
  prize drawn comb over foundation.

Where the room comes from is a property of the site: a nestbox takes another
box, a wall cavity runs on, rotten wood can be chewed away, and a cliff face
gives nothing. So the choice of where the swarm settled, made months earlier,
decides whether space is an option at all.

**Alarm pheromone, wired to something.** It was tracked, raised on every attack,
decayed on a careful schedule, and read by nothing at all. It is now the
colony's own instinctive version of holding the entrance: it defends better
(×1.35 at full alarm), forages less (×0.90) and loses more bees stinging
(×1.25). Every one of those is deliberately weaker than the `HivePosture`
multiplier that does the same job, because a posture the player chooses has to
be worth choosing — and `AlarmTests` asserts that relationship so it cannot
quietly stop holding.

Measured over 200 colonies, two years, against the same build with all three
effects set to zero:

| | alarm inert | alarm wired |
|---|---|---|
| attacks repelled | 44.9% | 46.2% |
| total nectar in | 12940 | 12681 |
| defenders lost per colony | 37 | 42 |
| first-year survival | 92% | 89% |
| two-year survival | 66% | 66% |

Which is the brief: it changed what it should and left the rest alone.

The forage cost was 0.20 first — exactly what narrowing the entrance costs —
and that was wrong twice over. It broke the rule above by making instinct as
good as a decision, and it cost more than the defence gave back: 5% of a
colony's whole two-year intake and four points of survival, because a
multi-day siege raises alarm again every morning and holds it up. The three
effects were then measured one at a time, which is the only way to see that,
since turning all three on at once changes every trajectory and confounds the
comparison.

**6. Winter.** Not a faster clock — the clock is already double speed — but
something to read and something still to look for.

The season had one sentence for ninety simulated days: "Clustered for winter."
That is a quarter of the year during which the one line the game offers a player
who opens it never changed. It now moves through the four things that are
actually going on — the cluster forming, the deep of it with the days to spring
counting down, the turn of the year, and brood again weeks before the first
flower — and a colony that is short of stores is told that instead, with the
number of days it has to last.

`Almanac.review(year:lineage:)` reads a year back: what the stores peaked at,
what the player took, whether the colony swarmed or was divided, how many queens
were raised and how many of them came back from their mating flights, how many
raids came and how many were driven off. The counts are tallied from the events
as the lines are written rather than parsed back out of the prose, because the
prose cannot be counted — "swarm cells are started", "a swarm leaves" and "the
swarm is called off" are all `.swarm` entries and mean quite different things.
A quiet year gets a short review rather than a padded one.

And the bloom prompt is no longer hidden in winter, which is where the dashboard
used to switch it off. Two plants in the catalogue flower in winter — winter
heather and mahonia — and both are keystones, because that is what being a
winter flower means. Hiding the prompt removed the one season where knowing
about them matters most.

### Not decided

- **Adding comb measures slightly worse than doing nothing** — 62% against
  instinct's 66%, with lower autumn stores (580 against 612). That is arguably
  honest: drawn comb costs seven honey to one of wax, and a colony that was not
  actually comb-limited has bought room it did not need with stores it did. But
  it means the mechanic is a mild trap unless the player is reading the nest
  card and only spending when the comb has genuinely filled the cavity, which is
  a subtler judgement than the notification implies. Worth deciding whether the
  cue should be narrower, or the price lower, or whether being able to make a
  wrong call is the point.

- **The colony is now healthier than the realism target, and that is a
  calibration call rather than a bug.** Fixing the two modelling errors above
  took the standard preset to 92% first-year and 66% second-year. The target in
  this document has been "the ~75% a year that established colonies manage",
  which implies roughly 56% at two years — so the game now overshoots at both
  ends. Nothing was tuned to get there and nothing should be tuned back without
  deciding what the game is aiming at first: a wild swarm's real first year is
  far *worse* than 75%, and an established colony's is about 80%, and this game
  models the first thing while quoting the second. `predatorStrength`,
  `pathogenArrivalMultiplier` and forage density are the levers.
- Whether the two-year cliff, now that it is 66% rather than 15%, is where it
  should sit for an idle game.
- Whether the catch-up ceiling of 180 simulated days — a fortnight of real
  absence — is generous enough. Beyond it, time is skipped rather than lived.

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
