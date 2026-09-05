# FlowerPower — state of the project and plan

Audited 2026-09-05 from the Windows machine. The engine was built and its full
test suite run here; the Xcode side was read, not compiled.

---

## 1. Where things stand

### What is verified

| Layer | State | Evidence |
|---|---|---|
| `FlowerPowerCore` engine | Builds and passes | 131 tests, 0 failures, 102 s (`swift test`) |
| Balance, standard preset | Matches the recorded baseline | 60 trials × 400 days: 73% survival, 1.08 swarms/yr, peak pop 321, winter cluster 143 |
| `beesim` tooling | Works, including `--set knob=value` sweeps | Run today |
| `GameStore`, `GamePersistence` | Compile against the engine | Compiled on Windows (SETUP.md §0) |

Deaths are spread across starvation, laying workers, absconding and an unmated
queen, and collapse across three seasons. Disease is still a negligible killer
in year one (mean 1 death per colony), which is intended: varroa is designed to
bite in year two.

### What is written but has never been compiled

Everything under `FlowerPower/Views`, `FlowerPower/Services`,
`FlowerPowerWatch/`, and the app entry point. Roughly 3,700 lines of SwiftUI,
MapKit, PhotosUI, Vision, WidgetKit and WatchConnectivity. Symbol use against
the engine was checked by hand; framework use was not. Expect a round of
SDK-level fixes on the first Mac build.

### Uncommitted work

Nineteen files. It is one coherent change and should be committed as such:

- Varroa and swarming made real: per-pathogen `hygieneSusceptibility` and
  `geneticSuppression`, real larval durations, swarm season limited to the
  spring flow, `pheromoneDilutionScale` 130 → 45, provisioning margin 1.3 → 1.0
  (harsh pinned at 1.3), plus `VarroaTests` and `beesim --set`.
- Windows compile-check fixes to the views and watch, `WatchTheme` extraction,
  the four usage-description strings in the project file, and SETUP.md.

Tests and the trial baseline both pass on this tree.

---

## 2. Findings

Ordered by how much they block a working app.

### F1. The Xcode project does not describe the app

`project.pbxproj` still lists the six 2023 files (`HiveModel`, `BeeModel`,
`WorkerModel`, `BiomeModel`, `HiveView`, `ContentView`) at
`FlowerPower/<name>.swift`. Those files now live in `FlowerPower/Legacy/`, so
every one of them is a missing reference *and* still in the Sources build phase.
None of the fifteen new files is in the project, there is no package dependency
on `FlowerPowerCore`, and there is no watch or widget target.

Opening the project today fails to build before any SwiftUI error is reached.
SETUP.md documents the manual repair, but it is a long list of drag-and-tick
steps. `Legacy/README.md` also states the legacy files are "not in any build
target", which is not true of the project file as it stands.

### F2. The watch cannot read the phone's save file

`WatchColonyModel.loadFromSharedContainer()` and the complication's
`HiveProvider` both call `GamePersistence().load()` expecting the phone's
`colony.json` through the App Group. App Groups do not span devices: the watch
app's container is on the watch, and the phone never writes there. So:

- the watch's "catch the colony up locally" fallback always finds nothing;
- the complication can never show data, because the watch app never persists
  the summaries it receives over WatchConnectivity.

The engine-on-the-watch idea is sound; the transport is wrong. The phone has to
ship the save to the watch (`WCSession.transferFile`, or the summary via
`updateApplicationContext`), and the watch app has to write what it receives
into *its own* App Group so the widget extension can read it.

### F3. A dead colony is a dead end

`ColonyStatus` has no collapsed state, `startNewGame` has no caller, and
neither does `relocateHive` or `setDifficulty`. When the colony dies the player
sees "Critical" with zero bees indefinitely. At the current time scale this
happens to a quarter of players in their first month (see F5).

### F4. Photographs stop mattering after five

Measured earlier and still true: intake is clamped to free comb, patches regrow
to full while in bloom, and results from five photos upward are byte-identical.
The premise of the game is that photographing flowers feeds the colony; past
the first afternoon it does not. Raising yield per flower will not help. The
levers are comb space (nest sites, building) and patch persistence (flowers
that fade and need replacing).

### F5. Time scale and difficulty are a pacing decision nobody has made

`SimClock` runs 5 real minutes per simulated hour: one simulated day is two
real hours, one simulated year is 30 real days. Combined with 73% first-year
and ~12% second-year survival, most players lose their colony inside two real
months. `maxCatchUpDays` is 30 simulated days, so a player away for more than
two and a half real days has time skipped rather than simulated. Any of these
may be right for an idle game; they have not been chosen deliberately, and F3
and F4 depend on the answer.

### F6. Capture is a photo picker, not a camera

`CaptureView` offers `PhotosPicker` only. There is no live camera path despite
the camera usage string. Picking an existing photo is a fine first version and
keeps EXIF location, but "go photograph a flower" currently means "leave the
app, take a photo, come back, pick it".

### F7. No notifications, no background progress

Nothing schedules a `BGAppRefreshTask` or posts a local notification. The
simulation advances only while the phone app is open, so the watch and
complication go stale whenever the phone app is not launched. The "foragers
idle" notification from the original brief does not exist.

### F8. No species model

Every flower is unidentified and yields 60%. The catalogue has 30 species and a
`match(label:)` for Create ML output, but no model has been trained. Oxford 102
does not cover the whole catalogue, so a label-to-species mapping is needed
alongside training.

### F9. Smaller items

- No app-layer tests. `FlowerPowerTests.swift` and the UI tests are the Xcode
  templates. `GameStore` is designed for testing (injected clock and
  persistence) and nothing exercises it.
- `core.autocrlf=true` with no `.gitattributes`: every git operation warns
  about line endings on fifteen files.
- `Features.md` is the 2023 tower-defence spec and is referenced by the project.
- `AppIcon` is empty.
- Bundle id is `com.LinwoodTechnologies.FlowerPower`; App Group and loggers use
  `com.kylepeterson.flowerpower`. Harmless, but renamespace before provisioning.

---

## 3. Plan

Grouped by where the work can be done. Windows work is verifiable in-session;
Mac work is not, so it is kept small and front-loaded with the first build.

### Phase 0 — Close out the current change (Windows, now)

1. Commit the balance and compile-fix work as one commit. Tests and baseline
   pass on it.
2. Add `.gitattributes` (`* text=auto eol=lf`) and renormalise, so the CRLF
   warnings stop.
3. Retire `Features.md` (move the research notes into a `docs/` file, drop the
   tower-defence scope) and point the project at this plan instead.
4. Fix `Legacy/README.md` to say what the project file actually does, or
   better, do Phase 1 step 1.

### Phase 1 — Make the project buildable (Windows prep, Mac verify)

1. **Replace the hand-maintained project file.** Two options:
   - Write an XcodeGen `project.yml` here describing three targets (iOS app,
     watch app, widget extension), the local package dependency, App Group
     entitlements and the usage strings. On the Mac: `xcodegen generate`.
     Reviewable, diffable, and reproducible.
   - Or on the Mac, delete the stale references and convert the `FlowerPower`
     and `FlowerPowerWatch` groups to Xcode 16 synchronised folders, excluding
     `Legacy/`.
   XcodeGen is recommended: the manual list in SETUP.md becomes one command,
   and future files are picked up automatically.
2. **Move `GameStore` and `GamePersistence` into the package** as a second
   library target (`FlowerPowerApp` or similar, Foundation + Observation only)
   with an `InMemoryPersistence`-backed test suite. Both already compile without
   Apple SDKs. This makes the whole non-UI stack testable on Windows and leaves
   only views and services in the Xcode targets.
3. **First Mac build.** Fix SDK-level errors, run on a device, take the
   PhotosPicker flow end to end, delete `Legacy/`. Record what broke in
   SETUP.md so the next uncompiled layer is written more carefully.

### Phase 2 — Finish the core loop (engine on Windows, UI on Mac)

Decide F5 first; everything below tunes against it.

1. **Pacing decision.** Pick a real-time scale and a survival target, then
   re-measure. Candidates: keep 2 h/day and accept a ~6-week colony life with a
   strong restart loop; or slow to 4–6 h/day so a colony lasts a season of real
   time. Decide the catch-up ceiling at the same time.
2. **Colony lifecycle.** Add a collapsed state to `ColonyStatus` and the
   snapshot, a "start a new colony" flow (site choice, difficulty), and
   relocation. Wire `startNewGame`, `relocateHive`, `setDifficulty` to a
   settings screen.
3. **Give photographs ongoing value.** Engine work, measurable with `beesim`:
   - patch senescence: a photographed patch fades over some weeks and is
     replaced only by a new photograph;
   - comb as the progression axis: nest-site upgrades or building that raise
     the intake ceiling, so more forage can actually be stored;
   - seasonal palette pressure: reward covering the bloom calendar, since the
     jump at four photos was palette coverage, not quantity.
   Re-measure against the five-photo table before and after.
4. **Camera capture.** `AVCaptureSession` or `UIImagePickerController` path
   alongside the picker, attaching CoreLocation to the saved asset (the
   plumbing for that already exists in `PhotoLibrary.save`).
5. **Background refresh and notifications.** `BGAppRefreshTask` to advance the
   sim and push a watch summary a few times a day; local notifications for
   critical alerts and for "your foragers have nothing to work".

### Phase 3 — Make the watch truthful (Mac)

1. Phone sends the full `Simulation` JSON with `transferFile` on meaningful
   change (it is small), and the summary via `updateApplicationContext` for
   cheap wakes.
2. Watch app persists what it receives into the *watch's* App Group container.
   `WatchColonyModel` and `HiveProvider` read from there; the deterministic
   local catch-up then works as intended.
3. Test complication refresh on a real watch, with the phone app closed.

### Phase 4 — Species identification (Mac, independent of the above)

1. Build a label mapping from Oxford 102 (and any additional dataset) to the 30
   `FlowerCatalogue` ids; note which catalogue species have no training data.
2. Train in Create ML, bundle as `FlowerClassifier.mlmodel`, and measure top-1
   accuracy on held-out photos of the kind players actually take.
3. Decide the confidence threshold below which the app offers the
   "did you mean?" alternatives instead of committing.

### Phase 5 — Second-year balance (Windows, after Phase 2.1)

1. Decide whether ~12% two-year survival is the game or a cliff. Varroa
   crossing the DWV threshold in year two is realistic; whether an idle player
   should be able to do anything about it is a design call (hygienic genetics,
   requeening, relocation).
2. Sweep with `beesim --set` at ≥ 60 trials, add regression tests to
   `ViabilityTests` for any fix, and update the baseline table in memory.

---

## 4. Working rules that still apply

- Engine changes are measured, never eyeballed: `beesim --trials 60 --days 400`
  before and after, and look at cause and season of collapse first.
- Nothing in the Xcode targets is verified until it has been through Xcode.
  Say so in commit messages and in SETUP.md.
- Keep logic out of the views. If it can live in the package, it can be tested
  here.
