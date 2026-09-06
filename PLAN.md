# FlowerPower — state of the project and what is next

Audited and worked through on 2026-09-05. The engine was built and its full
suite run on Windows; the Xcode side was written but not compiled, because that
needs a Mac.

---

## 1. Where things stand

### Verified here

| Layer | State |
|---|---|
| `FlowerPowerCore` engine | 248 XCTest + 19 Swift Testing, 0 failures |
| Swift 6 language mode | Builds clean, complete concurrency checking |
| Balance, standard preset | 80% first-year survival, 30% second-year, 1.43 swarms per colony per two years |
| `beesim` | Runs, sweeps any constant with `--set`, reports forage scale with `--scale` |

### Not verified, and cannot be here

Everything in `FlowerPower/Views`, `FlowerPower/Services`, `FlowerPowerWatch/`,
and the app entry point. Roughly 4,500 lines of SwiftUI, MapKit, PhotosUI,
Vision, WidgetKit, WatchConnectivity and BackgroundTasks. Engine calls were
checked against the package's public surface; framework calls have never been
compiled.

`project.yml` has also never been run through XcodeGen. Its keys were checked
against XcodeGen's own parser source rather than from memory, but XcodeGen does
not build on Windows, so the generated project is unseen.

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

---

## 3. What is next

### Immediately, and only on a Mac

1. **Generate and build.** `brew install xcodegen && xcodegen generate`, then
   fix what the compiler finds. This is the single biggest unknown in the
   project and everything below is easier once it is done.
2. **Run on a device.** The paths worth walking first are the ones with no test
   coverage at all: photographing a flower with the camera, the map with and
   without location permission, and the watch receiving its first save.
3. **Delete `FlowerPower/Legacy/`** once the new app has run.

### Then

4. **Second-year survival, again.** 30% is short of the ~75% a year that
   established colonies manage. Two over-rearing bugs were found and fixed on
   the way here — brood headroom ignoring adult upkeep, and a laying reserve
   that did not scale with the colony — so another tracing pass is likely to
   find more.
5. **Give the player something to do about swarming.** It is now the main thing
   that ends colonies, the alert exists, but nothing acts on it. Real
   beekeeping answers congestion with space. Adding comb, or splitting
   deliberately, would turn the largest cause of death into a decision.
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

### Not decided

- Whether the two-year cliff, now that it is 25% rather than 15%, is where it
  should sit for an idle game.
- Whether the catch-up ceiling of 180 simulated days — a fortnight of real
  absence — is generous enough. Beyond it, time is skipped rather than lived.

---

## 4. Working rules

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
