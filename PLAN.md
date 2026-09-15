# FlowerPower — state of the project and what is next

Audited and worked through on 2026-09-05, worked on again on 2026-09-06,
built out into a whole app on 2026-09-12, first built on a Mac on 2026-09-14,
built against the iOS 27 SDK it was written for on 2026-09-15, and stripped of
location entirely later the same day — the map, the coordinates and the
permission — as unnecessary and off-putting, after the first run on a phone.
The engine's full suite runs on Windows and on macOS. The Xcode side compiles
with Xcode 27, its tests pass on an iOS 27 simulator, and it has been signed
and installed on an iPhone on iOS 27 — though most of what it does there is
still to be walked. See "The first Mac build", "Xcode 27" and "location
removed" below.

---

## 1. Where things stand

### Verified here

| Layer | State |
|---|---|
| `FlowerPowerCore` engine | 248 XCTest + 246 Swift Testing, 0 failures (2026-09-12); on macOS, 248 XCTest + 282 Swift Testing, 0 failures (Swift 6.3, 2026-09-14; again under Swift 6.4, 2026-09-15 — which reports the two XCTest bundles separately, 172 + 76); 240 XCTest + 282 Swift Testing, 0 failures (2026-09-15, after geography was removed), with `beesim` byte-identical across that change |
| Xcode targets | All four compile, and the test targets (Xcode 26.5, 2026-09-14; Xcode 27 against the iOS 27 SDK, 2026-09-15, one warning left — see "Xcode 27"). 10 unit tests and 4 UI test runs pass on an iOS 27 simulator. Three tabs since 2026-09-15: Colony, Nest, Garden |
| Swift 6 language mode | Builds clean, complete concurrency checking |
| Determinism | Byte-identical across processes; three runs diffed |
| Balance, standard preset | 89% first year, 66% second, 2.49 swarms per colony per two years (200 colonies, deterministic release build, 2026-09-06; reproduced byte for byte on 2026-09-12 after the record-keeping systems were added) |
| Balance, other presets | Gentle 92% / 60%, harsh 64% / 14% (200 colonies, 2026-09-12). Gentle is *worse* at two years: better-fed colonies swarm more |
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

Wiring alarm pheromone up afterwards cost about three points of the first year
and none of the second, which is the 89%/66% in the table above. That is the
whole ledger: 79/36 measured properly, 92/66 after two bugs, 89/66 once the
colony pays for being roused.

Every balance number in this document is now from `beesim --trials 200 --days
730 --patches 9 --restock 45` on a release build, and every one of them
reproduces byte for byte. Anything quoted at 60 trials says so, and should be
treated as indicative: a 60-colony sample moves five points on nothing.

### Not verified, and cannot be here

Everything in `FlowerPower/`, `FlowerPowerWatch/` and `FlowerPowerWidgets/` —
roughly 11,500 lines of SwiftUI, Swift Charts, TipKit, App Intents, PhotosUI,
Vision, FoundationModels, ActivityKit, WidgetKit, WatchConnectivity and
BackgroundTasks. That count was taken on 2026-09-06, and MapKit and
CoreLocation were both in the list until they were removed on 2026-09-15, so it
is somewhat fewer lines now; it has not been re-counted. **Until 2026-09-14
nothing in those three folders had been through a compiler.** The two
desk-checks below were written before that and
are kept as the record of what was expected; "The first Mac build" after them
says what the compiler and the simulator actually found, which was not the
same list.

`project.yml` had also never been run through XcodeGen. XcodeGen 2.46.0
accepted it unchanged on the first attempt; the one fault in it was found by
`build-for-testing`, below.

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
  `CaptureView`'s `LocationProvider` (removed 2026-09-15).
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
  ActivityKit expects. The same question now applies to `AppIntents.swift`,
  which is compiled into both for the widget's buttons.

#### Added on 2026-09-12, and equally unverified

The app grew by about 4,500 lines in one day, written by seven agents in
parallel and merged by hand, so a second desk-check was run over the merged
result (its findings are recorded under section 2). Beyond the list above,
these spellings are from documentation rather than a compiler:

- **TipKit** — `Tip`, `Tips.configure`, `.popoverTip`, `TipView`,
  `@Parameter`, `#Rule`; and whether `Tips.configure` is synchronous.
- **Swift Charts**, the project's first use — `Chart`, `LineMark`,
  `AreaMark`, `BarMark`, `RectangleMark`, `RuleMark`, `chartYScale`.
- **App Intents** — `AppIntent`, `IntentDialog`, `ProvidesDialog`,
  `ShowsSnippetView`, `AppShortcutsProvider`, `Button(intent:)`,
  `ControlWidget`, `ControlWidgetButton`; whether an intent's `perform()`
  runs in the app's process when a widget button is tapped.
- **WatchConnectivity messages** — `session(_:didReceiveMessage:)`,
  `transferUserInfo`, `WKInterfaceDevice.play(.notification)`.
- `ShareLink(item: URL)` and `.task(id:)` on a `Section`; `XCUIApplication`
  queries in the two UI tests, which have never run.
- Whether XcodeGen picks `PrivacyInfo.xcprivacy`, `Localizable.xcstrings` and
  the asset catalogues up as resources from a directory source. Checked
  against XcodeGen's documentation, not by generating.

#### The desk-check of 2026-09-12

Done the same way as the first: every symbol the changed interface files name
was grepped in the package and its signature, access level and isolation
compared, and six Swift-language questions were settled with
`swiftc -swift-version 6 -typecheck` probes — including a two-module probe
showing that the app's own `Tips` enum does not stop `TipKit.Tips.configure`
resolving. **No certain build failure was found.** Seven probable faults were,
and six are fixed: `GameStore.save()` not gated on `needsSetup` (the real
one — a watch tap during the introduction would have persisted the placeholder
colony); the watch app sweeping up the widget's generated `WidgetInfo.plist`;
the complication target with no string catalogue; `Bundle` under `import
SwiftUI` alone; the follow-the-swarm notification without the nonce the
photograph intent carries; and the root `.task` not re-running when
onboarding ends. The seventh is left as a thing to watch: `ContentView`
stacks three `.sheet(item:)` and an alert on one view, and SwiftUI has been
known to let sibling presentations shadow each other. If the backup sheet
ever fails to appear, collapse the three into one `enum Incoming:
Identifiable` and present it once.

Still open from that check, all Apple-framework spellings: whether `#Rule`'s
expansion names `Tips` unqualified (if `Services/Tips.swift` fails to
compile, rename the local enum rather than the rule); `@Parameter` as a
static property wrapper; `IntentDialog(stringLiteral:)` with a runtime
string; interpolated `IntentDescription`s under `SWIFT_EMIT_LOC_STRINGS`;
`.task(id:)` and `.confirmationDialog` on a `Section` inside a `Form`; and
`WidgetCenter.reloadAllTimelines()` from a nonisolated `perform()`.

#### The first Mac build, 2026-09-14

On Xcode 26.5 (Swift 6.3.2, iOS and watchOS 26.5 SDKs), because that is what
the Mac had. The deployment target stays at 27 — Kyle's decision, to be built
properly once Xcode 27 is installed — so running anything meant overriding it
on the command line, never in the repo: `IPHONEOS_DEPLOYMENT_TARGET=26.0
WATCHOS_DEPLOYMENT_TARGET=26.0 MACOSX_DEPLOYMENT_TARGET=26.0` on a
`generic/platform=iOS Simulator` build, which does reach the package targets,
then `xcrun simctl install <udid>`. A named destination is refused, because
Xcode matches it against the project's own target and ignores the override;
the tests go through `build-for-testing` and then `test-without-building` with
the `.xctestrun` it writes, which accepts one. Install by UDID, not `booted`:
with a paired watch simulator booted too, `booted` picked the watch. The
iPhone to hand ran 26.6.1, so nothing went on a device.

**What the compiler found: eight faults in the Xcode targets, one in
`project.yml`.** The build stops at the first target that fails, so they
arrived one gate at a time rather than as a list, and none was among the
desk-checks' "probable faults":

- **App Intents' metadata step rejects an interpolated `IntentDescription`**,
  five times over. It reads titles and descriptions at build time without
  running anything, so `IntentDescription("\(HivePosture.x.detail)")` is a
  build failure. They are literal now, repeating the engine's sentences —
  change both together.
- **TipKit's `@Parameter` macro expands to an unqualified `Tips.Parameter`**,
  which the app's own `enum Tips` shadowed. The second desk-check predicted
  this of `#Rule` and got the macro wrong; its advice held. The enum is
  `AppTips` now.
- **Two `[String: Any]` payloads crossing to the main actor** in
  `WatchColonyModel`. The `Data` inside is taken out on WatchConnectivity's
  queue instead.
- **An actor's synchronous `init` calling one of its own methods**
  (`FeaturePrintStore.loadLearned`). Now a static read folded in before the
  stored property is set.
- **A `public` init taking an internal type** (`FlowerClassifier`), in an app
  target where `public` means nothing.
- **Two `Activity` values sent to `@concurrent` methods.** `Activity` is not
  `Sendable`; its `id` is, and `LiveActivities` finds it again on the far
  side.
- **`GenerateImageFeaturePrintRequest.revision` is a `let`.** The revision is
  passed to the initialiser instead — which is how every Vision request in the
  Swift API takes it.
- **`try?` does not nest optionals** and has not since Swift 5, so
  `let placed = try? …; let placement = placed` would not bind.
- **`Attachment(image)` is not in the iOS 26 SDK**, expected. Behind
  `#if compiler(>=6.4)` — the Swift Xcode 27 ships — so an Xcode 26 build
  fell through to feature prints the way a phone without Apple Intelligence
  does. The guess about 6.4 was right, and the gate was deleted on
  2026-09-15 once Xcode 27 was installed.
- **`project.yml`: the test bundles had no Info.plist.** The project-wide
  `GENERATE_INFOPLIST_FILE: NO` reached them too, and they have no `info:`
  block. They generate their own now.

Two warnings were also cleared: `XCUIApplication` calls from nonisolated test
methods (now `@MainActor`, as Xcode's own template has them), and the Info.plist
not saying whether documents open in place (they do —
`LSSupportsOpeningDocumentsInPlace`, reasoning in `project.yml`).

**What running it found: two crashes the compiler cannot see.** Both are the
same fault, and it is worth understanding because nothing at build time will
ever flag it. A closure written inside a `@MainActor` method is inferred to be
main-actor-isolated. Handed to an Apple API that calls it back on another
thread, and whose SDK signature does not say `@Sendable`, it compiles cleanly —
and the Swift 6 runtime then checks the isolation on entry and traps
(`_swift_task_checkIsolatedSwift` → `_dispatch_assert_queue_fail`).

- **The watch app crashed within a second of every reply from the phone** —
  `closure #1 in WatchColonyModel.refresh()`, on WatchConnectivity's
  operation queue. So it could never show anything the phone sent. Found from
  two crash reports; the same shape was in the decision-sending error handler.
- **The phone app crashed the moment the hive hum started** — `closure #1 in
  HiveHum.start()`, on `AURemoteIO::IOThread`, under a comment saying the
  render block was not main-actor isolated. The setting persists and the hum
  starts at launch, so turning it on made **every later launch** crash.
  Reproduced by writing the default, fixed, and launched again with it still
  on.

All four closures are `@Sendable` now, and everything else that hands a
closure to an Apple callback was audited for it: the rest are `async` APIs,
live in nonisolated types (`WatchLink`, `NotificationDelegate`,
`BackgroundRefresh`, `PhotoLibrary`), or are SwiftUI's own. See the working
rule in section 4.

**And two interface faults, fixed.** The Settings gear floated over the whole
`TabView` at the top trailing corner — where every tab keeps its own main
action — and sat on top of the camera button, so the one thing the game asks
the player to do was hidden on its first screen. Each tab now puts a
`SettingsButton` in its own navigation bar. And the watch's "no colony" screen
cut its only instruction to "Open FlowerPower on you…", on an Ultra; it
scrolls now.

**What has been walked, in the simulator:** a fresh install through all four
introduction pages, the notification prompt (on the fourth page, as intended),
the site chooser, and a new colony on the dashboard, which then advances on its
own; Settings; the capture sheet, the location prompt (removed 2026-09-15) and
the system photo picker. The watch app on a paired Apple Watch Ultra 3
simulator, asking the phone for a summary over WatchConnectivity and showing
the colony. The UI tests' launch screenshots in light and dark.

**Still not seen:** a photograph going all the way through identification into
the garden (the picker opens; choosing an image in it needs simulator control
that was not granted); the widget, Live Activities, App Intents and Siri; the
complication; a decision answered from a notification or the watch; a backup
exported and reopened; the save file reaching the watch by file transfer
(`isWatchAppInstalled` has not been checked in the simulator); TipKit's
popovers, none of which appeared on the first screen. The string catalogues were
still empty — command-line builds did not fill them; see the next section.

#### Xcode 27, 2026-09-15

Xcode 27.0 (Swift 6.4, iOS and watchOS 27.0 SDKs), with the phone updated to
iOS 27. **Against the SDK the deployment target names, the project compiled
with no errors** — the nine faults above were the whole of it — and two new
deprecations, both fixed: `BGTaskScheduler.submit(_:)` for
`submitTaskRequest(_:completionHandler:)`, whose handler runs "on an arbitrary
queue" and so is `@Sendable` by the working rule in section 4; and
`AVAudioEngine.connect` for the throwing `connectNode`. The FoundationModels
image path compiled for the first time, and its gate is gone. The unit and UI
tests pass on an iOS 27 simulator with nothing overridden.

**The first device build failed with sixteen errors, none of them in the
code**: four per target — "No Accounts", and three ways of saying the team's
wildcard profile does not carry the App Group. Xcode 27 had come up with no
Apple ID signed in. Signed back in, it registered the App Group and made
profiles for all five identifiers itself.

**The bundle identifier then moved into the company's namespace**:
`com.linwoodtechnologies.flowerpower`, Kyle's decision, after changing it for
the app alone in Xcode's Signing tab failed the build with "Embedded binary's
bundle identifier is not prefixed with the parent app's bundle identifier".
The same string is spelled in the App Group, the watch's companion identifier,
the background task, the three document types, both widget kinds and every
`Logger` subsystem, so all of them moved together. Anything saved under the
old App Group — only simulator colonies so far — is no longer found. Xcode
registered the new group on the next signed build, which **succeeded and
installed on the phone** (an iPhone 17 on iOS 27.0), and filled the three
string catalogues on the way — 379, 28 and 12 strings. The command-line builds
never had.

One warning is left, and it is a decision rather than a fix. iOS 27 says "All
interface orientations must be supported unless the app requires full
screen": the app is portrait-only and builds for iPad as well. Either make it
iPhone-only (`TARGETED_DEVICE_FAMILY: 1` in `project.yml`) or give the iPad
the other orientations and look at the layouts in landscape.

**The first run on the phone found one fault, in adding a flower from the
library.** A photo that had been saved from the web as WebP failed with
`PHPhotosErrorDomain 3302` and was never added, behind three ImageIO errors in
the console ("unsupported output file format 'org.webmproject.webp'").
`PhotoLibrary.save` handed Photos a `UIImage`, and Photos writes an image back
in the format it was decoded from — which for WebP is a format iOS can read
and not write. It encodes HEIC (or JPEG) itself now. A probe in the simulator
reproduced the failure exactly, passed with the fix, and ruled out the other
suspect, the on-device model. That probe was also the first time the model's
image path ever ran: on iOS 27 it was available, answered in about twelve
seconds, and declined to call a playing card a flower.

The same console showed `WatchLink` queuing a transfer to the watch on every
catch-up on a phone with no watch paired ("WCSession is not paired"). It
asks for a paired watch with the app installed first, as its save-file path
already did. The rest of that console — LaunchServices "process may not map
database", "cannot add handler to 0 from 0", MapKit's `default.csv` and
`SpringfieldUsage`, ICC profile warnings — is the system's, not ours.

Still to see on the device: everything in "Still not seen" above.

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
prevent anything and a gift that arrives diminished is a poor gift. Location
was opt-in and rounded to about a kilometre by default, because a flower
photograph's coordinate is where a person was standing; as of 2026-09-15 a
share carries no location at all, for that same reason. Everything received is
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
CoreLocation move to their modern async APIs (CoreLocation removed 2026-09-15).
New tests are Swift Testing.

**The player experience, all twenty-one proposals.** See `docs/PROPOSALS.md`
for each. The shape of it: decisions with real windows — a siege, a swarm
gathering, the autumn entrance, the colony's surplus — that arrive as
notifications with action buttons and default to instinct if nobody answers; a
record the colony keeps of itself in a line of queens and an almanac; the
garden as a collection with a bloom calendar; Live Activities and a Home Screen
widget; swarms and forage requests between players; a faster winter; the hum.
Every mechanic is in the engine and measured; the interface is written and
uncompiled.

### 2026-09-12 — the app around the game

Everything above was a simulation with screens on it. This is the rest of what
an app on somebody's phone needs, built as seven features in parallel, each in
its own worktree, each with its logic in the package and tested there, each
merged by hand and the balance baseline diffed byte for byte afterwards.

**The first run.** `GameStore.load` used to start a colony at a default site
and say nothing. Now the store knows when there was no save (`needsSetup`) and
refuses to persist until the player has chosen a site, so quitting half way
through the introduction does not leave a colony living somewhere nobody
picked. Three pages of introduction, then the site, then the notification
prompt — asked after the page that explains the colony will ask questions,
not before the first frame. Five TipKit tips wait until the player is in front
of the thing they describe. Notifications are three switches (decisions, the
morning report, colony news), and the line between them is whether
`NotificationActions` has action buttons for the news. An About page, with the
measured survival figures on it, and the Settings footer corrected to the same
numbers (it had been quoting the pre-fix 83/77/43).

**The colony's record of its own numbers.** `ColonyHistory` on `World`, one
`DailySample` per simulated day, capped at 720, taken by `HistorySystem` at the
end of the pipeline. It reads only, and a test proves a tick through it leaves
the RNG, the id counter and the hive untouched. `HistoryView` draws population,
stores against the winter requirement, nest against outside temperature, and
daily intake, with the seasons banded behind — the project's first Swift
Charts. The snapshot's status judgement moved to `ColonyStatus.evaluate` so the
record and the snapshot cannot disagree.

**Milestones.** Twenty-four firsts the colony can reach, recognised by
`MilestoneSystem` from the world and the tick's events, awarded once, narrated
in the catch-up report and the almanac, and mentioned in the morning digest.
Three candidates were dropped as unobservable rather than faked, and "a
thousand adults" was replaced by 100/200/500 after measuring what peak
populations actually are at this scale (180–300 in the first year, 613 the best
second year seen). Milestones belong to the colony, not the player: a new
colony earns its own.

**Decisions on the wrist.** `DecisionAction` in the game layer is now the one
vocabulary for answering the colony — identifiers byte-identical to what the
notification buttons already used — and `GameStore.apply(_:)` the one switch,
which checks the decision is still open and does nothing rather than something
wrong if it is not. `NotificationActions` lost its own switch and calls it.
`WatchSummary` carries a `WatchDecision` built from the same state as the
phone's cards; the watch shows it as its first page, answers it locally for
immediate feedback, and sends the identifier to the phone, which applies it to
the *live* store rather than to the file behind its back. The complication
badges an open decision in all four families.

**A field guide and a glossary.** `FieldGuide` builds an entry per catalogue
species — traits, bloom months per hemisphere derived from `RealSeason` rather
than a second month table, a `NectarReach` verdict, whether it has been
photographed — grouped by family and searchable by common, scientific and
family name (and "linden" finds lime). `Glossary` holds 95 terms, keyed to
eight engine enums by exhaustive switch so a new case cannot go undefined,
plus the free-standing beekeeping words. The thirty identification sentences
are the only new prose content and are tested for presence, not accuracy.

**Siri, Shortcuts, widget buttons and Control Centre.** `ColonySnapshot.
spokenStatus` says how the colony is in one to three sentences with sayable
numbers. Eight App Intents: check the colony, photograph a flower (opens the
app to the capture sheet down the same channel a notification uses), and the
decisions that need no interface. The Home Screen widget shows a button for
the best answer to an open siege or swarm, ordered by measurement as the
notification buttons are; a Control Centre button opens the camera.

**Getting a colony off the phone, and the five things a build cannot ship
without.** `SaveArchive` is a `.flowerhive` file: the whole colony and its
garden, versioned, refused if it comes from a newer format, and restored only
after a confirmation screen because a restore replaces the colony. Privacy
manifests for all three binaries, listing only the required-reason APIs each
actually calls; empty string catalogues so the first Mac build extracts the
strings; a generated placeholder icon so the appiconset is not empty (it should
be replaced by a designed one); the two UI tests rewritten to assert something
true.

**And one bug the work surfaced, and fixed.** Notification buttons, App
Intents and widget buttons all act on the save *file* with no interface
running. When the app was in the foreground, `GameStore` held the colony in
memory and wrote it over the file at the next catch-up, and the decision was
lost. It had been true since the notification actions were built, and two of
the seven agents found it independently. `GamePersisting` now offers a
`changeToken()` — the save's modification date and size — the store records
the token after every save, and `catchUp()` reloads the file first if the
token has moved. Twelve tests, four of which fail with the reload commented
out. The reload happens in `catchUp()` only: by the time `save()` runs the
player's own change is already in memory, and two of the player's own actions
seconds apart in two processes is a race the later one should win, not a bug.
Reading a file's timestamp is a required-reason API, so C617.1 is in all
three privacy manifests — the call is compiled into every binary that links
the game layer, and Apple's check is a static scan.

**Feeding the colony, measured.** Honey the player takes is the score, and it
was a dead end. `Simulation.feed` gives it back — into the same pool the bees
eat from, capped by what is banked and by the comb it can be stored in, using
the same arithmetic as intake — as a decision on the winter-shortage cue,
`DecisionAction.feed` on the phone, the watch and the widget. Measured over
200 colonies, two years:

| policy | survival | autumn stores | winter cluster | taken | fed |
|---|---|---|---|---|---|
| instinct | 66% | 612 | 313 | – | – |
| harvest each autumn, never feed | 64% | 586 | 317 | 26 | 0 |
| harvest each autumn, feed when short | 66% | 592 | 313 | 27 | 20 |
| harvest whenever offered | 0% | 3 | 1 | 204 | 0 |
| harvest whenever offered, feed when short | 36% | 200 | 7 | 830 | 511 |

Autumn harvesting costs two points and feeding buys them back, which is the
mechanic working as intended. The last two rows are the finding. Outside
autumn `takeHoney`'s cap reserves a laying threshold rather than the winter
requirement, the honey card is shown from midsummer, and a player who takes
what it offers whenever it offers it kills 200 colonies out of 200 with a
median collapse on day 130. Feeding it all back recovers a third of them,
because the honey was gone in the season it was needed. **The spring and
summer branch of the cap is the exposure**, it was not retuned in the same
change, and `beesim --policy harvestEagerly` exists so a fix can be measured.
That is in section 3 as a decision to make.

### 2026-09-15 — location removed

After the first run on the phone, Kyle took location out of the app: "it is
unnecessary and will turn people away." Not only the prompt — the Forage map,
the coordinates on flowers and on the hive, and the opt-in location on a shared
flower, all of it. The Forage tab was removed rather than replaced, so the app
is three tabs now: Colony, Nest, Garden.

**It was a clean cut because the mechanic it paid for had never been wired up.**
A grep before any of the work, for who *sets* a hive coordinate, found nobody:
every site is built with `HiveLocation(type:)`, and `relocateHive` only ever
carried a nil across. `world.hive.location.coordinate` has been nil in every
colony that has ever run. So the coordinate-based distance branches in
`Simulation.registerPhotograph`, `importSharedFlower` and `relocateHive` never
once fired, every patch has always sat at `FlowerPatch.nominalDistance` (800 m),
the map's "Centre on Hive" was permanently disabled, and its foraging-range
circle never drew. The location permission bought pins on a map with no hive on
it. Removing location therefore could not change any colony's trajectory, and
that was measured rather than assumed; see the `beesim` diff below.

**Geography out of the package, forage economics kept.** Removed: `GeoPoint`
entire, including `distance(to:)`; `FlowerPatch.coordinate`;
`HiveLocation.coordinate`, which is `public init(type:)` only now;
`Simulation.setPatchLocation` and the distance-recompute loop in
`relocate(to:)`; `PatchSummary.coordinate` and `NestSummary.coordinate`;
`GameStore.setPatchLocation`; the `coordinate:` parameter on
`registerPhotograph`, `importSharedFlower` and `recordPhotograph`;
`FlowerShare.latitude`, `.longitude` and `.coordinate`, the whole
`LocationSharing` enum with its 0.01° grid rounding, and the lat/long clamping
in `validated()`. `Hemisphere.containing(latitude:)` went with them as dead
code — no caller anywhere; `Hemisphere` itself stays, since the settings picker
is how a hemisphere is chosen. `SwarmShare` never carried a coordinate at all.

What stayed is everything foraging cost depends on: `distanceMetres`,
`nominalDistance`, `maximumForagingRange`, `isWithinRange`, and every
calculation that reads them. The balance in this document was measured with
them and they are still doing that work; it is only that the distance is the
same for every patch, as in practice it always has been.
`Simulation.newGame(inheriting:)` used to recompute an inherited patch's
distance from its coordinate and now keeps the stored one, which is a change on
paper only. The glossary and the field guide needed nothing: no term and no
sentence in either is about maps, and the distance material — "Foraging Bee",
"they fly a few miles at most", "Waggle Dance" — is bee biology and stays true.

**Old saves and old `.flower` files still open, and neither version number
moved.**
`FlowerPatch`, `HiveLocation` and `FlowerShare` all use synthesised `Codable`,
which ignores keys it does not know, so a file still carrying `"coordinate"`,
`"latitude"` or `"longitude"` decodes cleanly; and because those fields were
optional in the older build, a file written today opens there too. Neither
`SaveArchive.currentFormatVersion` nor `FlowerShare.currentVersion` was bumped.
A bump would make `decoded(from:)` refuse a perfectly readable file over a
field nobody reads any more; the reasoning is in a comment on
`FlowerShare.currentVersion`. Two tests hold that line:
`GamePersistenceTests.testASaveWrittenWhenFlowersCarriedCoordinatesStillOpens`,
which re-encodes a live colony with coordinate keys salted onto the hive
location and every patch, decodes it and compares for equality, and
`FlowerShareTests.testAShareCarryingTheOldLocationKeysStillOpens`. The save one
is the one that matters, because `GameStore` treats an unreadable save as no
save.

**The engine is byte-identical across the change.** `beesim --trials 200 --days
730 --patches 9 --restock 45` on a release build, run on clean HEAD before any
edit and again afterwards: `diff` printed nothing. The baseline it printed both
times, for the record: 66% survival (133 of 200), median peak population 724.
`swift build` is clean and so is the release `beesim` build. The full
suite is 0 failures: XCTest 248 → 240 and Swift Testing 282 → 282, which is two
geography tests out of `ForagingTests` and one replacement in, seven coordinate
rounding and clamping tests out of `FlowerShareTests` and one persistence
regression in, two out of `SharedFlowerTests`, and one into
`GamePersistenceTests`. A final grep of `Sources/` for
`GeoPoint|coordinate|setPatchLocation` returns nothing.

**The app.** Three agents, on disjoint files.

`CaptureView` lost `import CoreLocation`, the `LocationProvider` that wrapped
`CLLocationUpdate.liveUpdates`, the location request in its `.task`,
`CaptureResult.hasLocation` and the "No location on this photo…" label.
`PhotoLibrary.save(_:)` no longer takes a location and `PhotoMetadata` no
longer has a coordinate, so that file now imports neither CoreLocation nor
`FlowerPowerCore`; the HEIC/JPEG encoding fix from earlier the same day is kept
verbatim, as is using a library photograph as it already is — its own date, no
second copy, with the fallback copy only for limited photo access.
`project.yml` lost `NSLocationWhenInUseUsageDescription`, and the generated
Info.plist now carries the camera string and the two photo-library strings and
nothing else.

`ForageMapView.swift` is deleted, and `ContentView`'s `Tab` lost `.map`, which
no deep link ever selected. Four tips instead of five: `ForageTip` —
"Distance is the cost" — described something the player cannot influence, and
`PhotographTip` no longer ends "the closer to the nest, the less the flight
costs them" but "and the more families you find them across, the longer the
colony eats."

**What the map sheet was really for, and where it went.** Three things in its
`PatchDetailView` were about the flower rather than the place, and they are now
a `PatchStateCard` in the Garden's `FlowerDetailView`, between the name block
and `FlowerFactsCard`: how much forage is left, as a labelled meter with the
percentage, where the Garden had only an unlabelled thin `ProgressView` on the
thumbnail; how many bees are working it (`foragersWorkingIt`, the only place in
the app where a photograph is joined to actual foragers); and "Not in bloom
this season" in words. Rarity took the `Distance` row's slot in
`FlowerFactsCard`. Everything else went with the map, each because it only ever
meant anything with coordinates: the distance row ("800 m" on every flower is
noise), "Beyond foraging range" (nothing can be out of range now), the hive
marker, the range circle, "Centre on Hive", `MapUnavailableView`,
`UnlocatedBanner`, and the greying-out of out-of-range pins.

`NewColonyView`'s relocation blurb no longer ends "Distances to your flowers
are worked out from the new position." Onboarding page 2's second paragraph is
now about the thing the player can actually act on:

> And flowers do not last. A patch is at its best for about two months and is
> gone a few months later, so a garden photographed once in spring is empty by
> autumn. Keep finding new ones, and keep them across different families, so
> that whatever the season there is something still in bloom.

and AboutView's "Your photographs" paragraph:

> The app never asks for or reads your location. Your photographs stay on your
> device and in your own photo library. Flowers and swarms travel between
> players as files through the share sheet — there is no server and no account,
> and nothing leaves the device except the file you hand to somebody.

`FlowerPower/PrivacyInfo.xcprivacy`'s prose now says: "Location least of all:
the app does not use CoreLocation, asks for no location permission, and a
flower it sends carries a picture and a name and nothing whatever about where
anybody stood." `NSPrivacyCollectedDataTypes` was already empty.

`ShareFlowerView` lost the "Where You Found It" picker and its "no location"
fallback, so the form is the flower summary, From, and send; its header now
says that nothing here asks about place, that there is no setting to remember
to switch off, and no way for a flower sent to a group chat to tell everyone
where somebody was standing. `ReceiveFlowerView` lost "No location, so your
bees will fly a guessed distance", and an unnamed received flower now shows
nothing rather than an empty card.

**The one privacy guard left is the re-encode.**
`SharedImageStore.prepareForSharing` decodes and re-encodes the photograph
rather than forwarding the file, which leaves the EXIF behind — the camera, the
timestamp, and the coordinates a phone writes into a picture without being
asked. It is now the only thing standing between a shared photograph and a
location leaving the device inside it, and its comment says so: "a privacy step
first and a size one second: keep it that way round if this is ever made
faster." `FlowerShare.swift`'s header privacy section was rewritten around the
same point — a share says what the flower is, not where it is.

**The app's permission footprint is now the camera, the photo library and
notifications, and nothing else.**

All three agents' builds were clean and the merged result builds with no
warnings. The first run is a UI test now rather than a walk:
`testTheTabsAreColonyNestGardenAndCaptureAsksForNoLocation` goes through the
introduction to a chosen site (or straight on, if a colony is already there),
asserts the tab bar is Colony, Nest and Garden with no Forage, opens the
capture sheet and asserts SpringBoard is showing no alert in front of it —
which is exactly where the location prompt used to be. It passed on a fresh
install on an iOS 27 simulator, along with the 10 unit tests and the other four
UI test runs. It is also the first test that drives the interface at all, done
without the launch argument for a known save that the test file's header said
would be needed first: it accepts either landing instead.

**Two loose ends.** `FlowerPower/Localizable.xcstrings` still holds the dead
strings — "Beyond foraging range", the `ForageTip` message, the old privacy
paragraph — because command-line builds do not write the catalogues back;
Xcode.app's next build will mark them stale. And `FlowerPower/Legacy/` still
had an unrelated `coordinates: (x, y)` tuple of its own, until it was deleted
later the same day — item 3 in section 3. The watch app,
the widgets and the complication never touched location at all — grep returns
nothing.

---

## 3. What is next

### Immediately, and only on a Mac

1. **Generate and build.** Done — on Xcode 26.5 on 2026-09-14, and on Xcode 27
   against the iOS 27 SDK on 2026-09-15; see "Xcode 27" in section 1.
2. **Run on a device.** Xcode 27 and a phone on iOS 27 are both in hand, and
   the app was signed and installed on the phone on 2026-09-15. The team in `project.yml`, `588PCRUA35`, is
   **LINWOOD TECHNOLOGIES, LLC, a paid company team** — an earlier version of
   this item called it the Personal Team, from a sorted list that had
   scrambled the IDs and names; the Personal Team is `48Z7V96VSN`. The first
   run through the
   introduction to a chosen site has now been walked in the simulator, and
   the watch has shown a summary the phone sent it. Still unwalked anywhere:
   photographing a flower all the way into the garden; the watch receiving its
   first save by file transfer and answering its first siege; a widget button;
   "how are my bees" to Siri; exporting a backup and opening it.
3. **Delete `FlowerPower/Legacy/`** once the new app has run. Done on
   2026-09-15, after it was read one last time for the world design in
   `docs/WORLD.md`: the 2023 layer's `BiomeModel` was a schema that was never
   instantiated, its coordinates were a tuple nothing read, and the two lines
   of its design document about a terrain grid and fog of war are quoted
   there. Everything else it had is in git at `1ed62b2` and before.

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
11. **App icon.** A generated placeholder is in the appiconset now
   (`tools/make_app_icon.py`) so the build does not fail on an empty set. It
   is not a design; replace it.

### Done since

**4. Second-year survival.** Two more modelling errors, both found by tracing
single seeds through their second spring rather than by reading the aggregate,
and neither visible in the summary. Measured over 200 colonies:

| | first year | second year | swarms per 2 yr | winter cluster | autumn stores |
|---|---|---|---|---|---|
| before | 79% | 36% | 1.25 | 57 | 288 |
| comb drawn from the flow | 88% | 54% | 2.76 | 124 | 384 |
| and no afterswarm on requeening | 92% | 66% | 2.53 | 293 | 608 |
| and alarm pheromone wired up | 89% | 66% | 2.49 | 313 | 612 |

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
| add comb, on the cue | 68% | 2.46 | 0.17 | — | 615 | 313 |
| add comb, on crowding alone | 63% | 2.29 | 1.88 | — | 594 | 281 |
| split | 56% | 0.06 | — | 2.59 | 517 | 203 |
| add comb, then split | 55% | 0.06 | 0.24 | 2.58 | 495 | 169 |

**The two "add comb" rows are the same mechanic and two different players**, and
the difference between them was very nearly written up as a fault in the
mechanic. The first waits for the thing the interface actually tells them about
— the comb has filled the cavity, which is what the "nest is full" notification
fires on. That happens about once every six colony-years, and is worth two
points. The second opens the nest up whenever the colony is merely crowded,
which is four points *worse* than doing nothing.

The first measurement of this used the eager trigger, concluded that adding comb
was a mild trap, and said so in this document. It was measuring a player who
ignores the only cue the game gives them. The lesson is narrower than the usual
one about noise: **when a mechanic measures badly, check that the policy being
measured is the one the interface actually asks for.**

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

**The interface is ordered by that table now, not by the order things were
built.** The swarm notification offers "Make Room" first, because it measures
best; the decision card styles none of the three as the recommendation, because
the best of them is the oldest one and an interface that pushed a new mechanic
forward would be pushing the wrong one.

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

- **What `takeHoney` may offer outside autumn.** A player who takes the
  surplus whenever the card offers it loses every colony (0% of 200), and the
  card offers it from midsummer. The autumn cap, which reserves the winter
  requirement, is fine. The cheapest fix is to reserve the winter requirement
  in every season, or to show the card only in autumn; either should be
  measured with `beesim --policy harvestEagerly` and `harvestEagerlyAndFeed`,
  which are there for exactly this. Whether being able to ruin a colony on
  purpose is part of the game is Kyle's call, as it is for "add comb" above.

- **Whether "add comb" should be reachable at all except on its cue.** Taken
  when the notification fires it is worth two points; taken whenever the colony
  looks crowded it costs four. The button on the nest card is only shown once
  the comb has filled the cavity, which is right, but the swarm decision card
  offers it for the whole swarm window regardless. Narrowing that is a one-line
  change and a real design decision: being able to make a wrong call may well be
  the point.

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
- **Whether a patch's distance should ever vary again.** `distanceMetres` still
  prices every foraging trip and `maximumForagingRange` still bounds it, but
  with coordinates gone every patch sits at the nominal 800 m — which, as the
  2026-09-15 entry says, it always did anyway. Nothing is broken and the
  balance was measured there. It is a live lever that cannot move, though, and
  if distance is ever to mean something to a player it has to come from
  somewhere other than where they were standing: the site, the species, or a
  draw when the photograph is taken. Whether it is worth having at all is the
  first question. `docs/WORLD.md`, written the same day, proposes the answer:
  a generated hex world around the hive, in which the garden is at 200 m and
  the moor at five kilometres, and the lever finally moves.

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
- **Check a mechanic is wired up before paying a price for it.** The app asked
  every player for their location for months to feed a distance calculation
  that had never once received a hive coordinate; every patch sat at the
  nominal 800 m and always had. Grepping for who *reads* a value shows it is
  used. Only grepping for who *sets* it shows it is wired.
- **A closure handed to an Apple callback API from main-actor code is
  `@Sendable`.** Otherwise Swift 6 infers it main-actor-isolated, the SDK's
  unannotated block type lets it compile, and the runtime traps the first time
  the framework calls it from its own thread. Both crashes on the first Mac run
  were this — the watch on every reply from the phone, the phone whenever the
  hum played — and no build, desk-check or warning could have found either.
  If the closure needs the actor, it hops there with `Task { @MainActor in }`.
