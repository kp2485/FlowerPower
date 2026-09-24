# FlowerPower — state of the project and what is next

Audited and worked through on 2026-09-05, worked on again on 2026-09-06,
built out into a whole app on 2026-09-12, first built on a Mac on 2026-09-14,
built against the iOS 27 SDK it was written for on 2026-09-15, and stripped of
location entirely later the same day — the map, the coordinates and the
permission — as unnecessary and off-putting, after the first run on a phone.
Phase 1 of the world — the ground, `docs/WORLD.md` — was built the same day, so
that the distance location was supposed to supply comes from a generated hex
world instead: the garden is a ring of cells at 200 m around the nest, and a
flower is planted in one of them. Phase 2, the country, followed on 2026-09-16:
wild forage in the chunks around the nest, fog that lifts as bees go there,
scouts as the game's sixth decision, and biomes that decide what hunts the
colony and what infects it. It cost three corrections to the foraging model,
one of which — the dance being far too willing to send bees a long way — had
been wrong since long before there was a world. The engine's full suite runs on
Windows and on macOS. The Xcode side compiles with Xcode 27, its tests pass on an iOS 27
simulator, and it has been signed and installed on an iPhone on iOS 27 — though
most of what it does there is still to be walked. See "The first Mac build",
"Xcode 27", "location removed", "the ground" and "the country" below.

---

## 1. Where things stand

### Verified here

| Layer | State |
|---|---|
| `FlowerPowerCore` engine | 248 XCTest + 246 Swift Testing, 0 failures (2026-09-12); on macOS, 248 XCTest + 282 Swift Testing, 0 failures (Swift 6.3, 2026-09-14; again under Swift 6.4, 2026-09-15 — which reports the two XCTest bundles separately, 172 + 76); 240 XCTest + 282 Swift Testing, 0 failures (2026-09-15, after geography was removed), with `beesim` byte-identical across that change; 572 in total, 0 failures (2026-09-15, after the world's Phase 1 — 522 → 572), with `beesim` byte-identical across that change too when the world is off; 615 in total, 0 failures (2026-09-16, after the world's Phase 2 — 244 XCTest + 371 Swift Testing, with `CountryTests` and `ScoutingTests` new). Phase 2 is *not* byte-identical with the world off: two of its three foraging corrections change the colony, and what they cost is in the ledger below. 245 XCTest + 489 Swift Testing, 0 failures on Windows (2026-09-24, after the honey-bound corrections, with `HoneyBoundTests` new) |
| Xcode targets | All four compile, and the test targets (Xcode 26.5, 2026-09-14; Xcode 27 against the iOS 27 SDK, 2026-09-15, one warning left — see "Xcode 27"). 10 unit tests and 5 UI test runs pass on an iOS 27 simulator. Four tabs since 2026-09-15: Colony, Nest, World, Garden |
| Swift 6 language mode | Builds clean, complete concurrency checking |
| Determinism | Byte-identical across processes; three runs diffed |
| Balance, standard preset, world off | **74%** at two years, 3.11 swarms per colony per two years, 794 autumn stores, 394 winter cluster (200 colonies, deterministic release build, 2026-09-24, run twice and diffed). It was 62% / 2.50 from 2026-09-16, and 89% / 66% / 2.49 before that; the twelve points are the honey-bound corrections, item 7 in section 3 |
| Balance, the world | The garden and the country together, which is what the app now plays: **92% first year, 76% second**, 3.38 swarms, 981 autumn stores, 426 winter cluster (200 colonies, 2026-09-24, after the honey-bound corrections; 90% / 67% the same morning before them). Wild forage with no photographs at all: **46%** first year and `--policy scout` **64%** at two years were measured on 2026-09-16 and have not been re-taken since. See "the country" in section 2 and item 7 in section 3 |
| Balance, other presets | With the world on, 2026-09-24: gentle **98% / 90%**, harsh **69% / 11%**. Before the honey-bound corrections the same morning they were 92% / 25% and 57% / 12% — gentle, the easy preset, was the worst of the three at two years, because its colonies filled their comb with honey and could not rear their way out. See item 7 in section 3 |
| Balance, distance | Every world-off number above was measured at `beesim`'s default 400 m, which was the recorded 89% / 66% baseline until 2026-09-16 and is 89% / 62% now. The app's own flowers sat at the engine's nominal 800 m, which measured 86% / 54%. The garden the world plants them in measured 86% / 64% on 2026-09-15. Phase 2's corrections and its dance-distance exponent moved all of that again, and the garden with the country around it is the row above. See "the ground" and "the country" in section 2 |
| `beesim` | Sweeps any constant with `--set`, any player policy with `--policy`, reports forage scale with `--scale`; `--world` for the world as the app plays it, `--world --patches 0` for wild forage alone, `--biome <name>` to force the home biome |

#### The balance baseline, and why the numbers moved

Twice, for two different reasons, and it is worth keeping them apart — a
third time on 2026-09-15, when it turned out the numbers had never been
measured where the game was actually being played — and a fourth on 2026-09-16,
when the country arrived and the dance turned out to have been wrong about
distance all along.

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

**Then, on 2026-09-15, the measurement's distance turned out never to have been
the app's distance.** `beesim`'s `--distance` defaults to 400 m, so every number
in the ledger above — 79/36, 92/66, 89/66, the presets, the policy tables, the
alarm comparison — was taken with the trial colony's flowers 400 m from the
nest. A flower in the app has always sat at `FlowerPatch.nominalDistance`, which
is 800 m. Measured there, the same build is 86% first year and 54% second: ten
points under what this document has been quoting, and it has been true since the
day a patch got a distance at all. Nothing about the colony changed again — this
is the first kind of move, not the second. The app's flowers were simply further
away than the trials' flowers, and nobody had put the two numbers side by side.
The world's garden puts them at 200 m and a ring or two out, which measures 86%
and 64%; the four-row table is under "the ground" in section 2, and where the
baseline should now sit is in section 3.

**Then, on 2026-09-16, the dance was corrected twice and the model changed
under the world-off baseline too.** Phase 2's forty-odd wild stands broke two
things that nine patches at one distance had never exercised: a forager whom a
stripped patch could not serve simply did not forage, and the dance recruited
onto every patch in range at once. Fixing both took the world-off 400 m colony
from 66% to **62%** at two years, first year unchanged at 89% — so that is the
world-off baseline from today, and everything in this section above it was
measured on an engine that had those two faults. This is the second kind of move
again: the colony changed, because the model was wrong. The third correction,
handing forage space out in quality order rather than insertion order, moved
66% to 66% and 612 stores to 613 — but it is not byte-identical, which is worth
knowing about how often the colony is honey-bound. And a fourth change,
`danceDistanceExponent`, leaves the world-off numbers alone entirely: a colony
whose patches all stand at one distance cancels the factor when the shares are
normalised, and the 400 m run diffs clean at exponent 1 and at exponent 3. Its
effect is on the country, and it is in "the country" in section 2.

**Then, on 2026-09-24, the colony changed again: the second kind of move.**
The gentle preset measured 25% at two years against standard's 67%, and
tracing it found a colony with no brood nest — every free cell was one pool,
and foragers filled it before the queen could lay — and, behind that, two
more gaps the first one had been hiding. The world-off 400 m baseline moved
from 62% to **74%**, the world from 67% to **76%**. Item 7 in section 3 has
the traces and the step-by-step ledger.

Every balance number in this document is now from `beesim --trials 200 --days
730 --patches 9 --restock 45` on a release build, at that command's default
400 m unless a distance is named or `--world` is passed, and every one of them
reproduces byte for byte. Anything quoted at 60 trials says so, and should be treated as
indicative: a 60-colony sample moves five points on nothing.

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

### 2026-09-15 — the ground (world, phase 1)

`docs/WORLD.md`, written earlier the same day, answers the question the removal
of location left open — where a patch's distance should come from, if not from
where the player was standing — with a generated hex world around the hive.
Phase 1 of it, "the ground", is built in the package: the hex lattice and its
chunks, the generator, terrain on `World`, patches with cells, and a garden ring
around the nest that a photograph is planted into. No fog, no scouts, no wild
forage; the map is the garden as a place, and distance finally moves.

**Measured first, on the clean tree before anything was written.** Release
build, 200 colonies, `--patches 9 --restock 45`:

| `--distance` | year 1 | year 2 | swarms / 2 yr | autumn stores | winter cluster |
|---|---|---|---|---|---|
| 200 m | 86% | 66% | 2.99 | 749 | 362 |
| 400 m | 89% | 66% | 2.49 | 612 | 313 |
| 800 m | 86% | 54% | 1.19 | 392 | 172 |
| `--world` (the garden) | 86% | 64% | 2.77 | 672 | 331 |

Two findings, and both are worth stating plainly.

**One: the trials were never measured where the game was played.** `beesim`'s
`--distance` defaults to 400 m, so the 89%/66% this document has quoted since
2026-09-06 is the 400 m row — while a flower in the app sat at the engine's
nominal 800 m, which is the 86%/54% row. Real colonies in the app have been
living ten points under the recorded baseline since the day a patch got a
distance, and nothing in the app was ever at 400 m. The ledger in section 1 now
says so. Nothing about the colony changed; the app's flowers were further away
than the trials' flowers, and the two numbers had never been put side by side.

**Two: closer flowers buy stores and swarms, not survival.** 200 m against
400 m is the same 66% at two years, with half a swarm more per colony per two
years and 137 more units of autumn stores — and three points *worse* in the
first year. That is the abundance-breeds-swarms effect `docs/WORLD.md`
section 10 predicted before any of this was built, at about the size it
predicted, and it is the same shape as the gentle preset being worse at two
years than the standard one. The garden lands between the 200 and 400 rows and
nearer 400 for an arithmetic reason rather than a balance one: nine patches plus
restocks overflow ring 1, which is six cells at 200 m, into ring 2, which is
twelve at 400 m, so the colony's effective distance is a mix of the two.

**With the world off the engine is byte-identical**, which is the check the
geography removal set the pattern for: the three `--distance` runs re-run after
the change diff to nothing. **With the world on it is deterministic**: `--world`
twice, diff nothing. That first comparison looked like a difference and was not
— `swift run` interleaves SwiftPM's build lines into stdout, so two identical
runs differ in their first few lines. Build once with `swift build -c release
--product beesim` and run `FlowerPowerCore/.build/release/beesim` directly, and
the logs diff clean. It is a working rule in section 4 now, and a habit in
SETUP.md.

**What was built, all of it additive, with no save-format version moved:**

- **`Core/Hex.swift`.** `HexCoordinate` — axial `q`, `r`, `cellMetres = 200`,
  distance, neighbours and rings in a fixed clockwise order, and a total order
  by `r` then `q` so every walk of the lattice is the same walk everywhere. And
  `ChunkCoordinate`: a hexagon of radius 3, 37 cells, on lattice basis vectors
  (7, −3) and (3, 4) whose determinant is 37, which is what makes the tiling
  exact. A test walks a 49×49 patch of cells and asserts each one lands in
  exactly one chunk.
- **`Core/Biome.swift`.** The seven biomes of `docs/WORLD.md` section 4, each
  with a `displayName`, a `summary` and its `species` as catalogue ids; a test
  resolves every id, so a renamed species is a test failure rather than a biome
  that quietly grows nothing.
- **`Core/WorldGenerator.swift`.** Three integer-hash value-noise fields —
  wetness, openness, settlement — over chunk coordinates, with biome read off
  them exactly as section 5 describes, and `Chunk { coordinate, biome, name,
  centre }` with per-biome name parts. Pure, deterministic, and with no
  `Hasher`, `Date` or `UUID` anywhere near it, which is the rule the whole
  engine already keeps. Pinned by literal values at seed 2026: the home chunk is
  *Mill Carr*, riverbank, with *the Gardens at Thornbury* beside it, and all
  seven biomes appear across a 41×41 sweep.
- **`Core/Terrain.swift`, and `World.terrain: Terrain?`** decoded with
  `decodeIfPresent`. It holds the seed, the home chunk, `discovered` (the home
  chunk and its six neighbours at founding) and `gardenRings`, which starts at
  1. Nothing regenerable is stored.
- **The garden.** `FlowerPatch.cell: HexCoordinate?`, optional and synthesised
  `Codable`. `registerPhotograph` and `importSharedFlower` take `at cell:
  HexCoordinate? = nil` and otherwise place the patch themselves, in the first
  free cell in ring order; a faded patch releases its cell, a full ring opens
  the next, and the `tenFlowers` and `tenFamilies` milestones the game already
  awards open rings 2 and 3. `Simulation.plant(_:at:)` moves a patch and refuses
  an occupied cell — the first way there has ever been to move a patch after
  creation.
- **Presentation.** `PatchSummary.cell`, and `ColonySnapshot.terrain:
  TerrainSummary?` — the home chunk, its six neighbours, `gardenRings`, the
  `garden` as `[GardenCell]` in ring order, and `emptyCells`. `WatchSummary` is
  unchanged, which is `docs/WORLD.md` section 12's answer: the watch shows
  nothing of the map.
- **`beesim`** gains `--world` and `--world-seed <n>`, and `--list` names the
  home biome when the world is on.

**Migration of an old save, and why it runs where it does.**
`Simulation.adoptTerrainIfMissing()` derives a world seed from the saved RNG
state through `SeededRandom.derivedSeed()` and plants every unfaded patch into
the garden in ring order. It is called from `GamePersistence.load()` and
`decodeTransfer(_:)` rather than from `GameStore`, and that is the whole point:
the widget, the complication, the App Intents, `WatchLink` and
`BackgroundRefresh` all open the save directly, and terrain adopted only in the
store would mean the widget showing a different colony from the phone. It is not
written back on read — the next ordinary save records it, and until then the
same bytes derive the same world on every read, which is the property the
generator was built to have.

**`identifyPatch` fixed**, which `docs/WORLD.md` section 9 listed as a thing to
fix *before* the world starts creating patches in bulk. It rebuilt a patch and
dropped `registeredOnDay`, the origin and `sharedBy`, so a late identification
made a flower fresh again; it now preserves those, and `cell`, and restores
`capacityScale` for a shared patch. A failing test came first. The other two
items on that list — forage space handed out in insertion order rather than
quality order, and winter's zero forage multiplier against the three species
that bloom in winter — are still open.

**Three deviations from `docs/WORLD.md`, each deliberate and each recorded
there.** `newGame` always creates terrain, where section 9 had it arriving only
under `--world`: a colony with no terrain is a colony whose flowers are all at
800 m, and there is no reason to ship two worlds. An explicit `distanceMetres:`
suppresses placement entirely — a caller naming a distance is saying where the
flower is, which is what keeps a `beesim` sweep at one distance and is exactly
what made the world-off runs byte-identical. And the migration skips faded
patches, because the free-cell search ignores them and two faded patches would
otherwise be handed the same cell.

**Tests: 522 → 572, 0 failures.** `HexTests` 16, `WorldGeneratorTests` 13,
`GardenTests` 17, and three migration tests in `GamePersistenceTests`. Two
existing tests were renamed rather than deleted, to assert the new truth: that a
registered patch is planted in the garden, with a new sibling holding the old
nominal-800 behaviour for a colony that has no terrain.

**The app half is being built in parallel**, by another agent, on disjoint
files: a World tab in the Forage tab's old slot — Colony, Nest, World, Garden —
drawing the home chunk and its six neighbours on a `Canvas` with the garden's
cells and plantings and the nest on it, a VoiceOver representation of the same,
and a "planted 200 m from the nest" line on the capture result and on the flower
detail. None of it has been seen here, and nothing about it is verified.

Built, the same day. `WorldView` is the third tab, `circle.hexagongrid.fill`,
titled by the home chunk's name with the biome's summary under it and a
garden line ("6 of 6 cells planted — ring 2 opens at ten flowers", the
milestone names read from `Milestone.title` so they cannot drift from the
badges). The map is a `Canvas`: the seven chunks' 259 cells as pointy-top
hexagons in seven new `Theme` colours kept in the family of the season bands,
the garden's open rings outlined in wax, planted cells as a pollen dot whose
opacity follows vigour, the nest as a honey hexagon, fog to the frame's edge,
and a low-opacity season tint over all of it. Hit-testing inverts the
pointy-top formula and rounds in cube space, in one helper checked over all
259 cells; a planted cell opens the same `FlowerDetailView` the Garden uses,
an empty one opens the camera, a neighbouring chunk shows its name and biome
in a card. `Canvas` is invisible to VoiceOver, so the map's
`accessibilityRepresentation` is a list: home, six neighbours by compass
direction ("Hazel Rise to the south-east, woodland"), each planted cell as
"species, ring N, 200 metres from the nest, 45 percent left", and one button
for the empty cells that opens the camera. The capture result now ends
"Planted in your garden, 200 m from the nest." and the flower detail carries
"In the garden · 200 m from the nest, ring 1". No pan or zoom yet: a cell is
about 23 pt across on a phone, under the 44 pt a finger wants, so a zoom or
a snap-to-nearest-cell tolerance is the first Phase 2 follow-up. The UI test
that walks the first run now asserts four tabs and taps into World.

### 2026-09-16 — the country (world, phase 2)

Phase 2 of `docs/WORLD.md` — wild forage, the fog, scouts as a decision, biome
multipliers on threats and disease — built over 2026-09-15 and 2026-09-16. All
of it is additive, no save-format version moved, and every old save still opens.
Phase 1 gave the colony ground; this gives it country to forage in, and it
turned out to need three corrections to the foraging model before any of it
could be measured honestly.

**What was built.**

- **Wild stands.** `PatchOrigin.wild`, `FlowerPatch.isWild`, and a photo
  identifier of `"wild:q,r"` (`FlowerPatch.wildPhotoPrefix`).
  `Simulation.patches` now means the player's flowers alone, with `wildPatches`
  and `allPatches` beside it, and the same split on `ColonySnapshot`
  (`patches` / `wildPatches`). That split is what keeps every count, grid and
  calendar in the app meaning the collection without one of them being touched.
- **`WorldGenerator.wildPatches(in:density:)`.** Per chunk, a deterministic
  sparse set of stands: cells from the chunk, species from `Biome.species`
  weighted by the catalogue's rarity, `capacityScale` around `wildPatchYield`.
  Wild stands never fade (`registeredOnDay: nil`), regrow on the seasonal
  schedule, and are exempt from `pruneDepletedPatches`; planting a photograph on
  one digs it up. They are registered into `world.patches` only when their chunk
  is discovered — the seven founding chunks at founding, and on migration — so
  the save holds their state and nothing that can be regenerated.
- **The fog, in three states.** Discovered (`Terrain.discovered`), rumoured
  (`Terrain.rumoured`, derived: an undiscovered neighbour of known ground), and
  unknown.
- **`ExplorationSystem`**, daily, after foraging. When the colony is in a
  dearth — `World.isInDearth`, the engine's own existing notion of "short",
  chosen over a new constant that would drift away from
  `dearthThresholdPerBee` — a small share of the force (`explorationShare` 0.06)
  explores: one rumoured chunk is sampled from the seeded RNG in fixed order and
  discovered with a probability proportional to its wild richness
  (`explorationChance` 0.03). Nothing beyond the 8 km range is ever discovered.
- **Scouts as a decision**, in the shape of the five existing ones:
  `DecisionAction.scout` (identifier `"colony.scout"`, title "Send Scouts"),
  `GameStore.sendScouts()`, `Simulation.sendScouts()`,
  `WatchDecision.Kind.scout` (`binoculars.fill`, "Ground they have not seen"),
  `ColonyNews` offering it once a year when a flow is on and there is rumoured
  ground and no party already out, `ColonySnapshot.scoutDecisionOpen`,
  `scoutsOut` and `scoutsDaysRemaining`, and `World.ScoutingParty`. A party is a
  tenth of the force (`scoutShare` 0.10) for three days (`scoutDays`), gathers
  nothing, and discovers every rumoured chunk when it returns.
- **Biome multipliers**, at exactly the two hooks section 4 of that document
  names and nowhere else: `ThreatSystem.encounterChance` and
  `SimulationConfig.baseArrivalChance(for:)`, read off the home chunk's biome
  and scaled by `biomeThreatScale` (1.0; 0 switches the effect off, and is
  tested neutral). `Biome.predatorMultiplier(for:)` puts each biome's named
  predator — the "who hunts there" column of section 4 — at 1.5–2.0 in its own
  biome and about 0.6 elsewhere; `pathogenMultiplier(for:)` raises nosema in
  riverbank and in wet burrows and chalkbrood in damp woodland, and leaves
  varroa alone.
- **Presentation.** `TerrainSummary` gains `discovered: [Chunk]`, `rumoured`,
  `scoutsOut`, `scoutsDaysRemaining` and `chunk(containing:)`;
  `BloomPrompt.wildKeystone` says where the wild keystone is — "Heather is out
  on Long Moor, to the north-east." — on `HexCoordinate.compassNames` and
  `direction(to:)`.
- **`beesim`.** `--world` now includes wild forage; `--patches 0 --world` is
  wild forage alone; `--biome <name>` forces the home biome; `--policy scout`;
  and `--list` gains a column for how many chunks are known. `--world` *off*
  now forces `wildPatchDensity = 0`, so every baseline recorded at a
  `--distance` stays comparable with every later one. New `--set` keys:
  `wildPatchYield`, `wildPatchDensity`, `danceFloorPatches`, `biomeThreatScale`,
  `scoutShare`, `scoutDays`, `explorationShare`, `explorationChance`,
  `danceDistanceExponent`.

**Three corrections to the foraging model, each measured alone with the world
off, at 400 m, 200 colonies, two years.** These are modelling corrections rather
than tuning: each is the engine doing what the dance already meant, and each was
forced by the country rather than chosen for a number.

1. **Forage space goes to candidates in quality order** — descending
   `forageQuality`, ties broken by id — rather than in insertion order. That is
   what the dance means, and `docs/WORLD.md` section 9 listed it as a thing to
   fix before the world started creating patches in bulk. It barely moved
   anything: 66% to 66% at two years, 612 to 613 autumn stores. But it is not
   byte-identical, because the colony is honey-bound often enough for the order
   to matter.
2. **A forager whom a stripped patch cannot serve follows the next dance**,
   rather than not foraging at all. With forty small wild stands in range the
   old behaviour cut nectar income sevenfold, with more forage on offer than the
   game had ever had. A colony whose patches all absorb their share — which is
   every colony measured before today — is unaffected.
3. **`danceFloorPatches = 16`:** the dance recruits onto the best sixteen
   patches only. A colony that had scouted the whole circle held 260 stands,
   split its force across all of them, and died. Sixteen is above anything the
   game produced before the world existed.

Corrections 2 and 3 together cost four points with the world off: **66% → 62%**
at two years, with swarms 2.49 → 2.50 and nectar 12683 → 12354, and the first
year unchanged at 89%. **The recorded world-off baseline at 400 m is therefore
now 89% and 62%**, and the ledger in section 1 says so. Also tried and reverted:
weighting the dance by standing crop instead of by relative fill, which cost 28
points. The comment in `forageQuality` records that, so nobody tries it twice.

**The scout trap, and what was actually wrong.** At the first tuning
(`wildPatchYield` 1.6, `wildPatchDensity` 0.4) the country made the colony
*worse*. Wild forage alone, first year, per biome: meadow 46, hedgerow 42,
woodland 10, riverbank 54, farmland 40, village 39, heath 38 — mean 38.4%, which
is the design's 40 almost exactly. Garden plus country: 78% first year and 56%
second with 1.69 swarms, **against 86/62 for the garden alone** — which is
Phase 1's 86/64 with the two corrections above already in it. Biomes with the
garden on, at two years: heath 42, meadow 50, riverbank 54, farmland 55,
hedgerow 57, woodland 60, village 64 — a 22-point spread, well past the ten
points section 10 asked for, so the tables were not widened. And `--policy
scout` measured **2%**: six parties reveal about 132 parishes, and the colony
then works distant untouched stands in preference to its own worked garden, and
starves.

A decision that measures at 2% is not a decision that wants tuning.
`forageQuality` ranked a patch by the *fraction* of it left times the yield's
gentle distance term, so a full stand five kilometres out beat a half-worked one
at the door. Seeley's finding is that a distant source has to be much more
profitable before it recruits at all — the dance threshold rises with distance
far faster than the yield falls — and the engine had the two on the same slope.
`SimulationConfig.danceDistanceExponent` raises the distance term in the
*recruitment weight only*; the harvest keeps the plain efficiency, which is
flight physics and was never in question. Swept 2026-09-16 — garden on at two
years, then `--policy scout`, then wild alone in the first year:

| `danceDistanceExponent` | garden + country, 2 yr | `--policy scout` | wild alone, 1 yr |
|---|---|---|---|
| 1.0 | 56% | 2% | 38% |
| 1.5 | 60% | 25% | 48% |
| 2.0 | 64% | 55% | 52% |
| 3.0 | 69% | 66% | 64% |

The default is **3.0**. With the world off the exponent changes nothing, and not
approximately: a world-off colony's patches all stand at one distance, so the
factor cancels when the shares are normalised. That was measured rather than
assumed — the 400 m baseline diffs clean at exponent 1 and at exponent 3.

**The density retune.** At exponent 3 wild forage alone had risen to 64%, which
is too near what a garden gives; the photograph has to carry the game. Yield was
not the lever — `wildPatchYield` 1.6 / 1.0 / 0.6 gave 64 / 59 / 60% — because
income is bounded by foragers and flight time rather than by what is standing,
which is section 1 of `docs/WORLD.md` arriving again from a new direction.
Density was the lever: `wildPatchDensity` 0.4 → 64%, 0.25 → 54%, **0.15 → 46%**,
which ships. That is about one stand to a parish.

**Where it ended, at the shipped defaults, 200 colonies:**

| Run | year 1 | year 2 | swarms / 2 yr | and |
|---|---|---|---|---|
| garden + country, instinct | 90% | 68% | 2.68 | 926 autumn stores, 378 winter cluster, 7.7 chunks known |
| garden + country, `--policy scout` | — | 64% | 2.35 | 133 chunks known |
| wild forage alone | 46% | — | — | `--world --patches 0` |
| world off, 400 m | 89% | 62% | 2.50 | byte-identical before and after the exponent |

Two identical `--world` runs diff to nothing. Scouting is a four-point price
where the design asked for two or three — a price now rather than a trap, and
whether four is the right one is a tuning question rather than a modelling one.
**The per-biome tables above were taken at the earlier settings — exponent 1,
density 0.4 — and have not been re-measured at the shipped defaults**, so the
22-point spread is a fact about a world that no longer exists. Re-taking them is
a small item in section 3.

**One test moved, and the finding under it belongs in the balance record.**
`VarroaTests.testVarroaBuildsTowardDamagingLevels` failed at 0.327 against its
0.3 one-year ceiling once the fixture colony had wild stands and the steeper
dance, and the reason is real rather than incidental: a better-fed colony rears
more brood, and more brood is more mite. The test now holds the colony's
composition fixed with `wildPatchDensity = 0`, because it is about mite dynamics
on a known colony rather than about what that colony eats. **Wild forage brings
varroa on sooner** is the finding, and this is where it is recorded; it has not
been measured at scale, only met in one test.

**Tests: 615, 0 failures** — 244 XCTest (172 engine + 72 game) + 371 Swift Testing (274 + 97), with
`CountryTests` (31) and `ScoutingTests` (12) new. That count is from the run
before the exponent was added, and the full suite was being re-run on the final
tree as this was written, so treat it as the last count seen rather than the
final one. It is also *fewer* than the 572 recorded after Phase 1, and nobody
has accounted for the difference; both numbers are as the runner reported them.
Three existing tests were adjusted to the new truth rather than deleted:
`Fixture.barrenSimulation` strips the country,
`testGoodSitesRepelMoreOfWhatComes` sets `biomeThreatScale = 0` and
`wildPatchDensity = 0`, and the varroa test above.

**The app half**, built alongside, and — as always — verified only as far as a
simulator can verify it:

- **The World tab** draws every discovered chunk rather than the founding seven,
  rumoured chunks as paper with a wax outline (the bounds include them, so they
  can be panned to), and wild stands as small `Theme.wild` leaf-green triangles:
  solid in bloom, hollow out of it, opacity following what is left, and
  deliberately unlike the garden's honey dots. Tapping a stand gives a card with
  the species, the chunk's name, "N bees working it" and the bloom state, and
  "Scouts are out — back in N days." sits under the header.
- **A camera on the map**, earlier the same day: pinch between fit-to-width and
  a cell 80 pt across, a drag clamped so the nest can always be brought back, a
  double-tap, and a "Centre on the Nest" button, none of it animated under
  Reduce Motion. A tap snaps to the nearest garden cell within half a cell while
  cells are narrower than a fingertip — which is the follow-up the Phase 1 entry
  above asked for, and the reason it was asked for. The VoiceOver representation
  lists the discovered chunks by name and biome, the rumoured count, and the
  wild blooms grouped one item per chunk.
- **`ScoutDecisionCard`** on the dashboard after the feed card, in the feed
  card's shape: "Ground they have not seen", the detail — "The dancers are
  pointing at N stretches of country nobody has been to. A tenth of the foragers
  for 3 days would bring back all of it, and that is honey they do not gather."
  — one "Send Scouts" button, and the house do-nothing line, "Or let the
  foragers find it in their own time, which is what happens if you do nothing."
  While a party is away it says so quietly: "The scouts are out. They are back
  in N days."
- **`BloomPromptCard`** carries the wild keystone line with a compass glyph.
  `CollectionView`'s bloom-calendar gap sentence and `GardenView`'s empty state
  now say the bees are living on what they find wild, rather than "no forage",
  when there is wild forage to live on. The Garden's grid and counts stay the
  player's flowers only.
- **Plumbing.** A `colony.scouting` notification category with one action, "Send
  Scouts" (`colony.scout`); `SendScoutsIntent`, acting on the save file and
  checking the decision is open, with a literal description; the widget's
  best-answer button showing it after siege and swarm. No Siri phrase — the
  project keeps two. The watch needed no change at all: its decision page
  renders whatever `WatchDecision` the engine hands it, which is what that shape
  was for.
- The 10 unit tests and 5 UI test runs pass on an iOS 27 simulator on the final
  tree.

**Not built, deliberately.** Phase 3 of the design — features, nest sites,
following a swarm to a site, wild colonies — is untouched, so that what Phase 2
moved could be measured on its own, exactly as Phase 1 was.

**Still Kyle's**, and in section 3 under "Not decided": whether 46% is the
wild-forage floor he wants — he did not choose, so the design's 40 was taken as
the default and density set to the nearest thing to it; winter forage, where
three keystones bloom and the multiplier is still zero; and the predator
roster's nationality, which the biome tables answer for now by giving the
American animals British biomes.

### 2026-09-20 — the first week on a phone

Kyle lived with the game for a week and came back with three things. All three
were right, and two of them were bugs that had been there for some time.

**"The only thing I see is flowers going out of season."** On opening the app,
and in the hive's notifications. Two causes, neither of them the wording.
`PatchSystem` emitted `.patchOutOfBloom` for every stand that was out of bloom
on *every simulated day it stayed that way*, not on the day it happened — so a
player back after twelve days with nine flowers resting was handed a hundred
and eight of them, the catch-up report keeps sixty highlights, and the report
had room for nothing that had actually happened. The country's wild stands made
it worse the day they arrived. It is emitted once now, on the day the season
turns, and is no longer a highlight: a flower going over is the calendar, and
the garden shows it on the flower. Separately, the morning report opens with
the colony's headline, and the headline of a healthy colony with a resting
garden *is* "Nothing in bloom nearby". The three forage sentences have names
now (`ColonySnapshot.ForageHeadline`), the digest leads with the colony's state
instead, a resting garden is not by itself a reason to send one, and colony
news reports a decline as a decline. The dashboard still says all of it.
`beesim --world` over 200 colonies is byte-identical before and after (68%).

**"The home screen window stayed active way too long when a skunk attacked."**
The rule was that a Live Activity is up for as long as the thing it is about is
happening — and a skunk works a nest for three simulated days, which is six
real hours, after which the card was ended under `.default` dismissal, which
keeps it on the lock screen for up to four more. And nothing ended it at all
unless the app happened to run. `LiveActivityPlan`, in the package, now
decides: a card is up only while there is something to decide, comes down the
moment it is answered, and never outlasts one simulated day (about two real
hours). Every card carries a stale date and the widget draws a stale card as
finished; cards end with `.immediate`; a task sleeps to the stale date while
the process lives, the background refresh asks to run no later than the
soonest one, and answering from a notification button takes the card down
there and then. iOS offers no way to book an activity's removal without a push
server, so the last of those is a request, and the stale drawing is the
backstop.

**"More tappable, more condensed, tap and hold to see inside a cell."** Three
agents in parallel, one tab each:

- **The comb can be touched.** `CombLayout` in the package arranges the comb
  deterministically — brood in the middle, pollen round it, honey outside —
  and says what is in each cell. Nothing per-cell is invented: a brood bee *is*
  a cell, so each larva carries its own age and each pupa its own days to
  emergence, while stores cells give the hive's total and say that the colony
  keeps a total rather than a ledger. `CombGeometry` is the spiral and its
  inverse, in plain `Double`s so it is tested off-Mac. Tap and hold sweeps a
  callout across cells; a tap opens the same thing as a sheet; tapping a
  legend entry lights every cell of that kind. The old `HexGrid` overflowed
  the canvas sideways and that is fixed, so the comb draws slightly smaller.
- **The Colony tab is tiles.** Open decisions are single rows that open the
  full card in a sheet; below them a grid of tiles — stores, population,
  queen, nest, health, honey, forage, the record — each one number, one
  caption and a colour, each opening a detail page that holds what the old
  full-size section held plus a chart of that quantity from the history.
  `DashboardSummary` in the package makes every judgement the tiles show
  (severity bands, the population trend), so the view only draws.
- **The rest.** History charts scrub, with a readout of the nearest day's
  sample (`ColonyHistory.sample(nearestTo:)`). Garden thumbnails have a
  context menu with a preview and the actions the detail page already had.
  The catch-up report groups its highlights by kind with a count —
  `ReportDigest`, capped per group, so no one kind of event can crowd out the
  others again whatever the engine emits. Lineage, almanac and collection rows
  open.

All of the interface code in this round was written on Windows and has not
been through Xcode. The constructs most likely to need attention on the Mac,
by the agents' own ranking: `.chartXSelection` applied inside a generic
`ChartCard`; the x-only `RuleMark`; the long-press-then-drag gesture on the
comb and whether it fights the scroll view; `Gauge` with
`.accessoryLinearCapacity` (the codebase's first — `MeterView` is the
drop-in); and `ColonyDetailView`'s `switch` over eight fileprivate view types.
There are also two pressed-state button styles now (`TilePressStyle` on the
dashboard, `PressableTileStyle` elsewhere) that want to be one.

*Every item in the two paragraphs above was dealt with on 2026-09-24; see
the next entry.*

### 2026-09-24 — a card worth two hours, and everything that was still open

Kyle's next two sentences: "If it is going to be live for 2 hours, it needs to
be more engaging. Let's resolve all outstanding issues." Five agents, one
afternoon.

**The Live Activity does something now.** ActivityKit cannot redraw a card
while the app is suspended and there is no push server, so what moves on the
card is what the widget moves by itself: a countdown and a filling ring to
real dates the plan works out — when instinct will answer, when the siege is
settled. The answers are on the card as buttons (`LiveActivityIntent`s, which
run in the app's process and reconcile the card at once), one per option in
the measured order. A card has three phases: *deciding*, for at most a
simulated day; *holding*, after the player answers — buttons gone, the posture
shown, a countdown to the outcome, up until the event resolves but never past
ActivityKit's eight hours; and *resolved*, which says how it ended (driven off
or not, what it cost, whether the swarm went) and is dismissed half an hour
later. The scene carries the guards on duty and the alarm level; defenders
lost only appear on the resolved card, because the engine settles a siege in
one stroke and a running total would be the card lying. The widget now also
reloads whenever the save is written. 26 tests on the plan; the buttons, the
timer text and the ring have not been through Xcode, and the first thing to
check on the Mac is whether tapping a card button cold-starts the app far
enough to run the hook that redraws the card.

**Every open question in section 3 is decided**, four by decision and four by
measurement; the reasoning is on each bullet there and the tables are under
"Decided by measurement". In short: the winter requirement is reserved in
every season, so harvesting whenever the card offers it is a price (32% at
two years) rather than a death sentence (0%); "open the nest up" is offered
only on its cue; winter forage exists, at 0.5, and moves the trial colony by
about 40 units because the trial garden has no winter bloomer; the catch-up
ceiling is a year, measured at under half a second in release; the calibration
target is what the app measures and nothing is tuned; the wild-forage floor
stays at 46% first year; the predator roster stays, since the game no longer
knows what country it is in; and the per-biome tables and the presets were
re-taken.

**Re-taking the presets found the next modelling error.** Gentle — the easy
preset — measured 25% at two years, the worst of the three, because its
colonies filled their comb with honey and could not rear their way out. That
is item 7 under "Done since": three errors (no brood nest reserved for the
queen; no nursing once the last nurse-age bee had aged out; swarm cells
raised with no brood to raise a queen from), found by tracing single seeds,
no constant tuned. Gentle is 90% at two years now, standard 76%, and the
world-off baseline moved twelve points, the same size as the last two
corrections. Every table taken earlier that day is from before those fixes;
the ones that decided something were about differences between policies on
one engine, which they still show.

**Old saves open.** Every save carries the whole `SimulationConfig`, which
decoded by synthesis, so every key added since a save was written made it
unreadable — and `GameStore.load` treated an unreadable save as no save and
wrote a fresh colony over it. Phase 2's keys on 2026-09-16 will have done
this to any save from before that day. `SimulationConfig`, `FlowerSpecies`
and `FlowerPatch` decode by hand with defaults now, `SaveCompatibilityTests`
removes every key of a real save one at a time (177 cases) and decodes a
checked-in fixture, and an unreadable save is renamed
`colony.unreadable.json` beside the new one rather than overwritten. Section
4 has the rule.

**The interface loose ends from the 20th** — one pressed-state style, no
`Gauge` in the tiles, chart selection at the call sites, the comb out of the
scroll view so its long-press does not fight it, the type-checker load hoisted
out of the big builders, the two `Severity` overloads — are done, still
uncompiled.

Suite on Windows at the end of the day: 245 XCTest + 504 Swift Testing, 0
failures, 0 warnings; the world baseline (92% / 76%, 3.38 swarms, 981 autumn
stores, 426 winter cluster) run twice on the final tree and byte-identical.

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
winter — were done on 2026-09-06 and are written up under "Done since" below,
and item 12, the world's Phase 2, was done on 2026-09-16 and is written up in
section 2. The numbering of what is left is unchanged so it still matches what
you knew it as. **Item 13 is the next thing to do**, for the reason item 12 was:
it is package work and needs none of a Mac, a device, real photographs or a
trained model. Everything from 7 to 11 needs one of those, so none of it can be
started here.

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
12. **~~Phase 2 of the world — the country.~~ Done on 2026-09-16**, and
    written up in section 2 under "the country": wild stands placed per chunk
    from the biome's species list at `origin: .wild`, the fog and the three
    states of a chunk, exploration in a dearth, scouts as the sixth decision,
    and biome multipliers into the two hooks `docs/WORLD.md` section 4 names
    and nowhere else. All four of that document's measurements were taken. The
    first three landed where it hoped — wild alone at 46% against a target of
    40, the garden and the country together at 90%/68%, the biomes separating
    by 22 points against a floor of ten — and the fourth, scouting, only after
    the dance was corrected: it measured 2% before that and 64% after, against
    a design that asked for a two- or three-point price and got four.

13. **Phase 3 of the world — colonising**, and the next thing to do.
    `docs/WORLD.md` section 8. Today `World` holds one `Hive` and following a
    swarm *replaces* the simulation; in the world the map persists and colonies
    come and go on it. Following a swarm becomes choosing a **site** — a cavity
    in a known chunk, at a distance the swarm can fly — which is the
    new-colony screen the game already has, with its three bars for room,
    warmth and safety, but with the ground deciding what the year will be like:
    the church wall in the village winters on mahonia and is robbed by wasps,
    the outcrop on the moor has nothing until August and then more than it can
    store. **The colony that stayed becomes a wild colony on the map**, not
    simulated hour by hour but given a fate each season from survival tables
    that `beesim` itself produces, so the coarse model is calibrated against
    the fine one; it shows as thriving, quiet or gone, and the player can go
    back to it — and if it has died, its cavity is a site again with the comb
    still in it, which is how wild colonies actually get re-founded. Two things
    persist across every colony the player ever has: the map, and the garden —
    so following a swarm two kilometres leaves the flowers behind at two
    kilometres, which is the real cost of moving and the reason a beekeeper
    does not. Several live colonies at once is affordable (a colony-year is
    about 0.11 seconds in release) but is the step after, and the widget and
    the watch would show one colony while the phone carried the rest.

14. **~~Re-take the per-biome tables at the shipped defaults.~~ Done on
    2026-09-24**, under "Decided by measurement" — but taken the morning
    before the honey-bound corrections landed that afternoon, which moved the
    standard world nine points at two years. The spread is what the tables
    were for and a correction to nursing and the brood nest lifts every biome
    alike, so they still say what they said; re-take them when something
    else needs the exact rows.

15. **Re-take the presets and the biome tables on the corrected engine**, and
    the two one-year figures that were never taken with the world on (wild
    alone, and `--policy scout`). Half an hour of runs. Every number in
    section 1 that says 2026-09-24 is from the final tree; the tables in
    section 3 are from the morning's.

16. **The trial's "starvation" label is sticky.** `Trials.swift` sets
    `starvedRecently` on any `.starving` event and never clears it, so a
    colony that went hungry once as a larva and dwindled a year later is
    counted as starved. Item 7 under "Done since" has the case. Making it
    mean *recent* changes every cause-of-death table ever quoted, so it is a
    change to make on its own and re-quote after.


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

**7. The honey-bound colony.** Three more modelling errors, found on
2026-09-24 by tracing single seeds of the one preset that measured backwards:
gentle — richer forage, milder weather, fewer raiders — was 92% at one year
and **25%** at two, against standard's 67%. 95 of its 200 colonies were
labelled starvation, 82 of them between days 460 and 545, and every one
traced died with more than 2,300 units of honey in the comb. That is a sharp
edge, and each
of the three was found by the trace of the colony the previous one left dying.

**The brood nest was storage.** Every free cell was one pool; foragers filled
it through the day and the queen, who lays once a day, got what they left.
Seed 8919, with `beesim --preset gentle --world --seed 8919 --days 560 --every
4 --patches 9 --restock 45` (the trace now shows free cells and the day's
eggs):

```
day  season    pop adult brood  honey pollen cells free eggs ...
360  spring    575   560    15   1702     16   700  251   15
364  spring    635   560    75   1996     49   700  106   15
368  spring    670   560   110   2274     45   700    2    1
388  spring    701   627    74   2418     45   700    2    2
410  spring    273   214    59   2453     49   700    3    1  SWARM (-302)
420  spring    263   223    40   2558     54   700    0    2  mated x7
435  spring    102    75    27   2602     53   700    4    0  SWARM (-89)
450  summer     93    84     9   2581     53   691    0    7  mated x8
518  summer      1     1     0   2598     54   149    0    0  COLLAPSED
```

The 251 cells the winter cluster had eaten clear were full of nectar in eight
days while the queen laid fifteen a day into them. For forty days a colony of
560 to 700 adults then laid none to eight eggs a day into two free cells. It
swarmed; the brood it left emerged while its new queen was a virgin and every
vacated cell was backfilled; she mated into a nest with no room, and the
colony dwindled with 2,598 honey. Consumption *did* free cells — honey is
counted into cells, so eating it empties them — but the foragers took each
one back the same day.

`QueenSystem.broodNestRoom` now holds empty comb for the queen that incoming
nectar may not be stored in: the rest of a brood cycle at her own rate, less
the brood already there, for a laying queen or a virgin (the colony keeps the
nest for the queen it expects), never for a queenless colony (which backfills,
as real ones do), and never at the cost of the larder — the colony first
keeps room to bank its winter requirement. Syrup from the player goes where
nectar goes. Pollen is not held out, because it is packed in a band around
the brood; holding it out starved the brood the nest was kept for (8919 lost
417 bees to starvation that way before that was changed). No new constant
and no new random draw.

**A summer bee past her nursing days never nursed again.** With the nest
kept, seed 1000 swarmed on day 409, its virgin mated on day 437, and by then
the last of the old brood had emerged: 21 nurses the day she mated, none three
days later. She laid nine eggs, got no royal jelly, and the colony died on day
453 with 1,500 honey and 300 cells held for her. Real workers revert to
nursing when there are no young bees — foragers included — so when not one bee
is of nursing age, `Hive.workforce(for: .nurseBee)` now counts the share of
the older bees that would have been nursing in an ordinary colony, which is
the job table's nine nursing days out of forty-two. It is counted, not
assigned, so no forager leaves the flowers. Two other versions were measured
and rejected (the table below): house bees only, which left seed 143542 dead
when its house bees aged into foragers eight days after its queen mated; and
every older bee, which let seed 666196 rear 173 brood on 128 old bees and
starve.

**A broodless colony could cast a swarm.** Swarm cells had no brood
requirement, and `crowded` reads comb occupancy, which honey alone can fill.
Seed 365274 mated a queen into 433 bees and no brood, and eight days later
189 of them left. A swarm cell is an egg laid in a queen cup, so the swarm
branch now asks `canStillRearAQueen`, as the emergency branch always has.

Measured over 200 colonies, two years, release build, each row adding to the
one above:

| | gentle, world | standard, world | standard, world off |
|---|---|---|---|
| before | 25% | 67% | 62% |
| brood nest held for the queen | 68% | 68% | 68% |
| and swarm cells need brood | 72% | 70% | 68% |
| and house bees nurse when nobody can *(rejected)* | 86% | 74% | 72% |
| or every older bee does *(rejected)* | 90% | 66% | 69% |
| or a fifth of the older bees do | 91% | 76% | 82% |
| and pollen may go in the nest *(shipped)* | **90%** | **76%** | **74%** |

And the whole change, before and after, with the world on:

| | first year | second year | swarms | autumn stores | winter cluster |
|---|---|---|---|---|---|
| gentle | 92% → 98% | 25% → **90%** | 2.79 → 3.08 | 1082 → 1813 | 1 → 547 |
| standard | 90% → 92% | 67% → **76%** | 2.66 → 3.38 | 917 → 981 | 372 → 426 |
| harsh | 57% → 69% | 12% → 11% | 0.24 → 0.48 | 135 → 108 | 62 → 53 |
| standard, world off | — | 62% → **74%** | 2.50 → 3.11 | 678 → 794 | 283 → 394 |

Gentle's causes of death went from 95 starvation, 21 queen unmated, 14 laying
workers, 12 predation, 7 queenless and 1 disease to 6 laying workers, 6
starvation, 3 each of predation, queen unmated and queenless: the second-year
cliff is gone from the table, and gentle is no longer worse than standard.
Harsh gained twelve points in the first year and nothing at two: its colonies
die queenless (91 of 200 before), which none of this touches.

The standard baseline moved twelve points, like the last two corrections
(thirteen and twelve), and for the same reason: the model was wrong. Most of
it is the reversion — founding swarms and swarmed colonies both used to sit
through a gap with no nurses at all — and more swarms is what more colonies
living long enough to swarm again looks like.

`--policy harvestEagerlyAndFeed` against instinct, standard with the world
on, went from 74% against 67% (seven points) to 80% against 76% (four).
The honey the player takes was working as comb space the colony could not
otherwise get back, which is the same fault from the other side; most of that
advantage went with it, and what is left is the player feeding back in a
dearth.

**The trial's "starvation" is sticky, and that is still so.** `Trials.swift`
sets `starvedRecently` on any `.starving` event and never clears it, so a
colony that starved a larva on day 12 is labelled starvation if it dies of
anything else on day 518 with a full larder — which is what 8919 was. The
game's own epitaph said "dwindled". With the honey-bound deaths gone there is
nothing for a `honeyBound` cause to name, so none was added; the label should
be made to mean recent, and that will move every cause-of-death table, so it
is left for its own change.

### Not decided

**On 2026-09-24 Kyle asked for every outstanding question to be resolved**, so
each bullet below now carries a decision. Four were decisions and are settled
here; the ones that needed a number were measured the same day and their
results are under "Decided by measurement" at the end of this section.

- **What `takeHoney` may offer outside autumn.** A player who takes the
  surplus whenever the card offers it loses every colony (0% of 200), and the
  card offers it from midsummer. The autumn cap, which reserves the winter
  requirement, is fine. The cheapest fix is to reserve the winter requirement
  in every season, or to show the card only in autumn; either should be
  measured with `beesim --policy harvestEagerly` and `harvestEagerlyAndFeed`,
  which are there for exactly this. Whether being able to ruin a colony on
  purpose is part of the game is Kyle's call, as it is for "add comb" above.

  **Decided 2026-09-24: the winter requirement is reserved in every season.**
  Autumn's rule is now the rule all year; the card's gating is unchanged.
  Measured under "Decided by measurement" below: eager harvesting went from
  0% to 32% at two years, a price rather than a death sentence, and the
  autumn crop is untouched.

- **Whether "add comb" should be reachable at all except on its cue.** Taken
  when the notification fires it is worth two points; taken whenever the colony
  looks crowded it costs four. The button on the nest card is only shown once
  the comb has filled the cavity, which is right, but the swarm decision card
  offers it for the whole swarm window regardless. Narrowing that is a one-line
  change and a real design decision: being able to make a wrong call may well be
  the point.

  **Decided 2026-09-24: on its cue only.** `ColonySnapshot.addCombIsOnCue` is
  the nest-full judgement written once, and the swarm card, the swarm
  notification (a second category, `swarm.preparing.full`), the watch's swarm
  decision and the spoken status all offer comb only on it. The nest card is
  unchanged. `GameStore.apply(.addComb)` stays permissive, so a player who
  reaches it another way can still make the call. The wrong call that costs
  four points is no longer the one the interface suggests.

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

  **Decided 2026-09-24: the game is aiming at what it measures, and nothing is
  tuned.** The target this document quoted was never a decision, it was a
  sentence from the research notes, and it conflated two populations. The
  colony the app plays — a garden and the country around it — measures 90%
  first year and 68% second, which is between a wild swarm's real odds and an
  established colony's and is a perfectly good place for an idle game to sit:
  most colonies see their first spring, a third do not see their second, and
  every one of those deaths has a cause in the almanac. The three levers stay
  where they are. What the document quotes from now on is what the app plays.
- Whether the two-year cliff, now that it is 66% rather than 15%, is where it
  should sit for an idle game. **Decided 2026-09-24: yes.** At 68% with the
  world on, a third of colonies end in their second year, mostly by starving
  in spring or losing a queen — which is the arc of the thing and the reason
  the lineage, the almanac and the milestones exist. A cliff a player can see
  coming and sometimes prevent is the game; a cliff nobody can prevent was
  the bug, and that was fixed on 2026-09-06.
- Whether the catch-up ceiling of 180 simulated days — a fortnight of real
  absence — is generous enough. Beyond it, time is skipped rather than lived.
  **Decided 2026-09-24: a year.** Measured first: a founding colony's year
  catches up in 0.28 s in release and a 250–700-bee world colony's in under
  half a second, process start included (debug 3.4 s). Saves carry their
  ceiling, so `GamePersistence` lifts an older build's default of 30 or 180
  to 365 on load and leaves any other value alone.
- **~~Whether a patch's distance should ever vary again.~~ Decided the same
  day: it varies now.** A photographed flower is planted in a cell of the
  garden, and the cell's hex distance from the nest times 200 m is its
  `distanceMetres` — 200 m in the first ring of six cells, 400 m in the second
  ring of twelve, 600 m in the third, with the rings opened by the `tenFlowers`
  and `tenFamilies` milestones. `Simulation.plant(_:at:)` moves a patch between
  cells. The lever moves; where it should be set is the next bullet.

- **Where the baseline should now sit.** The garden's 86% first year and 64%
  second is what the game actually plays at as of 2026-09-15, and it is not the
  89%/66% this document has quoted for nine days — which was a 400 m
  measurement the app never matched. Three ways to go, and it is a calibration
  call rather than a bug, in the same family as "the colony is now healthier
  than the realism target" above. Accept 86/64 and requote everything to it,
  which is honest and cheap. Or tune the garden — fewer rings, or the first ring
  further out — until it meets the old quote, which is tuning the world to
  protect a number rather than to model anything. Or leave the world where it is
  and take the difference out of `predatorStrength`, `pathogenArrivalMultiplier`
  or forage density, which are the levers that bullet already names. Nothing
  should be tuned until it is decided what the game is aiming at, and Phase 2's
  wild forage will move all of it again.

  **It did, on 2026-09-16.** The garden and the country together measure
  90%/68%, and the world-off 400 m comparison is 89%/62% rather than the
  89%/66% it was. So the game now plays a little *above* the number this
  document quoted for nine days rather than ten points below it, and the gap
  between the app and the trial colony has changed sign. The three ways to go
  are unchanged and so is the question; only the arithmetic moved.

- **Whether 46% is the floor wild forage should hold a colony at.** This is the
  identity question `docs/WORLD.md` section 14 puts first: whether a player who
  photographs nothing should have a colony at all, and how good it should be.
  Kyle has not answered it, so the design's own 40% was taken as the default and
  `wildPatchDensity` was set to 0.15 — the nearest thing to it the sweep offered,
  against 0.25 for 54% and 0.4 for 64%. 64% is close enough to what a garden
  gives that the photograph stops carrying the game, which is the reason not to
  go higher rather than a measurement of where it should be. The lever is one
  `--set` key and re-measuring is one run, so this is cheap to change and should
  be changed on a decision rather than drifted into.

  **Decided 2026-09-24: 0.15 stays, and it is a decision now rather than a
  default.** A player who photographs nothing has a colony that mostly dies in
  its first year and always dies in its second, which is what the design asked
  for: the country keeps the bees alive long enough for the first photograph
  to matter, and no longer. The number is re-taken per biome under "Decided by
  measurement" below, since Phase 2's corrections moved everything.

- **Whether winter forage should exist.** Three keystones bloom in winter —
  crocus, winter heather and mahonia — and the village biome's whole character
  is that it is the only place with something out all year; and winter's forage
  multiplier is zero, so none of them does anything. Every balance number in
  this document, Phase 2's included, was measured with winter empty. Turning it
  on would make the village materially better than the other six in exactly the
  season that kills colonies, which is either the point or a problem.
  `docs/WORLD.md` carries it open in section 4 and again in section 9.

  **Decided 2026-09-24: it exists.** Three keystones bloom in winter and a
  keystone that does nothing is a lie in the field guide; and the village's
  whole character is that something is out all year. The multiplier was swept
  and set by measurement — see "Decided by measurement" — at the largest value
  that keeps the village within ten points of the next-best biome, which is
  the same rule Phase 2 used for the spread.

- **The predator roster's nationality.** The catalogue is British bee forage
  and the predators include a skunk, a raccoon, an opossum and a bear, which
  the biome tables answer for now by giving the American animals British
  biomes. **Decided 2026-09-24: the roster stays.** Location was removed from
  the app on 2026-09-15, so the game no longer knows what country the player
  is in, and a roster that spans the North Atlantic lets the biomes do the
  choosing — a moor has badgers and a suburb has raccoons, and neither is
  wrong somewhere. Renaming cases would also break every save, since a
  predator is stored by its raw value. If the game is ever given a country
  again, this is the first thing to revisit.

### Decided by measurement, 2026-09-24

Every number: 200 colonies, release build, `--world`, from
`beesim --trials 200 --days 730 --patches 9 --restock 45 --world`, with
`--days 365` for first-year figures. The baseline was run twice and diffed
byte for byte before anything was trusted and again at the end.

**Honey reserved in every season.** First year / two years, then honey taken
per colony over two years:

| policy | before | after |
|---|---|---|
| instinct | 90 / 68 | 90 / 68 |
| harvest each autumn | 90 / 68, 61 taken | 90 / 68, 61 taken |
| harvest each autumn, feed when short | 90 / 68, 65 taken, 47 fed | same |
| harvest whenever offered | 3 / 0, 221 taken | 60 / 32, 651 taken |
| harvest whenever offered, feed when short | 85 / 52, 1372 taken, 723 fed | 92 / 74, 1593 taken, 1081 fed |

The instinct baseline and the two autumn-only policies are byte-identical,
because they never harvested outside autumn. Eager harvesting costs 36 points
at two years for 651 units, which is a price. The autumn crop is small but
real — 11 units a colony in the first year, 61 over two, against autumn
stores of about 926 — because the reserve is sized to the cluster. The last
row is the odd one: taking eagerly *and feeding back* beats instinct by six
points with fewer swarms, which says honey out of the hive is working as comb
space the colony did not have to draw. That is the honey-bound mechanism
seen from the other side, and it is under investigation below.

**Winter forage.** One value, `winterForageMultiplier`, stands in for
winter's zero in both the forage and the regrowth multipliers, for a stand in
bloom in winter on a flying day. Two-year survival by biome:

| winter multiplier | 0 | 0.15 | 0.3 | 0.5 |
|---|---|---|---|---|
| standard world | 68 | 67 | 68 | 67 |
| meadow, hedgerow, riverbank | 68 | 68 | 68 | 68 |
| woodland | 64 | 64 | 64 | 64 |
| farmland | 62 | 62 | 62 | 62 |
| village | 68 | 68 | 69 | 68 |
| heath | 56 | 56 | 56 | 56 |

The rule was the largest value at which the village is not more than ten
points above the next-best biome, and none came near it, so it ships at 0.5.
Winter forage hardly moves a trial colony: it needs a warm day after the
cluster has loosened, and the trial garden has no winter bloomer, so only the
sparse wild stands feed it — the village took in about 40 more units over two
years. The player who photographs a mahonia is who it is for. The catalogue's
winter bloomers are rosemary, winter heather and mahonia; crocus turns out to
be spring only, which corrects an earlier bullet.

**The per-biome tables at the shipped defaults** (first year / two years),
which item 14 asked for:

| biome | garden on | wild alone |
|---|---|---|
| meadow | 88 / 68 | 58 / 29 |
| hedgerow | 88 / 68 | 48 / 16 |
| woodland | 86 / 64 | 11 / 3 |
| riverbank | 92 / 68 | 63 / 28 |
| farmland | 86 / 62 | 50 / 20 |
| village | 90 / 68 | 36 / 12 |
| heath | 82 / 56 | 46 / 8 |
| generated world | 90 / 67 | 46 / 18 |

The spread with the garden on is 10 points in the first year and 12 at two;
on wild forage alone it is 52 and 26. Woodland is almost uninhabitable
without photographs, which is right for a wood. The village — the biome whose
identity is year-round bloom — is below average on wild forage alone, and why
has not been traced. The generated world's 46% first year on wild forage
alone is the floor the design asked for, which settles that bullet.

**The presets with the world on**, as first re-taken that morning: standard
90 / 67, harsh 57 / 12, and **gentle 92 / 25**. Gentle was the finding: it had
been 92 / 60 with the world off before Phase 2, and now 95 of its 200 colonies
died in their second summer, recorded as starvation. Seed 8919 swarmed twice
down to a hundred bees with 2,600 units of honey in a 700-cell nest; the new
queen mated and had nowhere to lay, and the colony dwindled to nothing still
holding 2,598 honey. A colony with that much honey does not starve. That is a
sharp edge, so it was a modelling error, and it was traced rather than tuned
the same afternoon: three of them, written up under "Done since" as item 7
(the brood nest kept for the queen; older bees nursing when no nurse is left;
swarm cells needing brood). After them gentle is 98 / 90, standard 92 / 76,
harsh 69 / 11, and the world-off baseline moved twelve points, from 62% to
74% at two years — the same size as the two corrections before it. Every
figure above this paragraph in this section was taken before those fixes;
the tables were not re-taken afterwards, and the ones that matter to a
decision (the honey policies, the winter sweep) were about *differences*
between policies on one engine, which is what they still show.

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
  diff. **Diff the built binary's output, not `swift run`'s.** `swift run`
  interleaves SwiftPM's build lines into stdout, so two identical runs differ in
  their first few lines and a byte-identity check reports a change that is not
  there. Build once with `swift build -c release --product beesim`, then run
  `FlowerPowerCore/.build/release/beesim`. That is how the world's Phase 1 was
  shown to leave the engine untouched with the world off.

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
- **When a mechanic measures as a trap, check the model before the mechanic.**
  The scout decision measured at 2% against instinct's 56% on 2026-09-16, and no
  tuning of the decision could have fixed it: the dance ranked a full patch five
  kilometres out above a half-worked one at the door, so revealing country was
  handing the colony a better way to starve. The mechanic was the only thing
  that had ever asked the dance that question. This is the same lesson as
  "a mechanic that looks strong is a reason to check the model" under item 5 in
  section 3, and as the narrower one beside it about measuring the policy the
  interface actually asks for — three times now, in both directions, which is
  why it is a rule and not an anecdote.
- **If it can live in the package, put it there.** That is the part that can be
  compiled and tested without a Mac.
- **Every save ever written must open.** A property added to any type in the
  save is decoded with `decodeIfPresent` and a default — a synthesised decoder
  throws on a missing key even when the property has a default. On 2026-09-24
  `SimulationConfig`, saved whole in every file, was still synthesised, so every
  balance number added since the world arrived made older saves unreadable.
  `SaveCompatibilityTests` now removes every key in a real save one at a time
  and fails on any the save cannot do without that is not on its allow-list;
  `Fixtures/` holds old saves that must keep decoding (add one when the format
  changes on purpose; never replace one). And a save that still will not open
  is set aside as `colony.unreadable.json`, never written over.
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
