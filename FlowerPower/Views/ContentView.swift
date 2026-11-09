//
//  ContentView.swift
//  FlowerPower
//
//  Four places, matching the four things a player does: check on the colony,
//  look inside the nest, look at the ground around it, and go photograph more
//  flowers for it.
//
//  Plus one that is not a tab. When the colony is gone there is nothing to
//  look at in any of the four, so the whole interface gives way to choosing
//  where the next swarm settles. A dead colony used to leave the player on a
//  dashboard whose numbers had stopped moving, with no explanation and no way
//  to start again.
//

import SwiftUI
import TipKit
import UserNotifications
import FlowerPowerCore
import FlowerPowerGame

struct ContentView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = .colony

    /// What the root has on screen, what is waiting behind it, and the sheets
    /// below it that it has to wait for. See `RootSheet`.
    @State private var sheet: RootSheet?
    @State private var waiting: [RootSheet] = []
    @State private var appearedSheet: RootSheet.ID?
    @State private var sheetLastClosed = Date.distantPast
    @State private var children = ChildSheets()

    /// The cell the map should show blooming, once a capture opened from it
    /// is over. Where to plant travels in `RootSheet.capture` itself.
    @State private var bloomingCell: HexCoordinate?

    /// The colony as the player last left it, for the dashboard's "since you
    /// last looked" figures. See `LastLook`.
    @State private var lastLook: LastLook?

    /// Bumped to bring the dashboard back to its top, wherever it had been
    /// pushed to: a tapped notification is about something up there.
    @State private var dashboardResets = 0

    /// The last save problem the player closed, so the banner does not come
    /// straight back for the same one.
    @State private var dismissedError: String?

    @Environment(\.requestedAction) private var requestedAction
    @AppStorage("hiveHum") private var humEnabled = false

    enum Tab: Hashable {
        case colony, nest, world, garden
    }

    var body: some View {
        Group {
            if store.needsSetup {
                // A first launch. Nothing is saved until a site is chosen at
                // the end of this, so quitting half way through comes back
                // here rather than to a colony nobody picked.
                FirstRunView()
            } else if store.isCollapsed {
                NewColonyView(
                    reason: .afterCollapse,
                    epitaph: store.snapshot.epitaph
                ) { site in
                    store.startNewGame(at: HiveLocation(type: site))
                    selection = .colony
                }
            } else {
                tabs
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = store.lastError, error != dismissedError {
                ErrorBanner(message: error) { dismissedError = error }
            }
        }
        .overlay {
            if store.isCatchingUp {
                ProgressView("Catching up with the colony…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 14))
            }
        }
        // `.task` takes a @Sendable closure, which does not inherit the view's
        // main-actor isolation — so the hop has to be explicit to reach the
        // @MainActor store.
        .task(id: store.needsSetup) { @MainActor in
            await resume()
        }
        .onOpenURL { url in
            open(url)
        }
        .sheet(item: $sheet, onDismiss: sheetClosed) { sheet in
            content(for: sheet)
                .environment(store)
                .environment(children)
                .onAppear { appearedSheet = sheet.id }
        }
        .onChange(of: children.open) { _, _ in presentNext() }
        // Up here rather than on the tabs, because a colony that died while
        // the player was away has no tabs to show its report on, and that
        // report is the one they most need.
        .onChange(of: store.pendingReport != nil, initial: true) { _, pending in
            if pending {
                request(.report)
            } else {
                waiting.removeAll { $0.id == RootSheet.report.id }
                if sheet?.id == RootSheet.report.id { sheet = nil }
            }
        }
        .onChange(of: store.isCollapsed) { _, collapsed in
            guard collapsed else { return }
            // A colony that dies under the camera. Waiting to bring it back
            // would open it over the choice of a new site.
            waiting.removeAll { $0.id == RootSheet.capture().id }
            if sheet?.id == RootSheet.capture().id { sheet = nil }
        }
        .onChange(of: store.colonyChanges) { _, _ in
            lastLook = nil
            LastLook.forget()
        }
        .onChange(of: requestedAction) { _, action in
            guard let action else { return }
            // A tapped notification is about the colony, and following a swarm
            // needs a site chosen; both end at the cards on the dashboard.
            if action.hasPrefix(NotificationActions.Action.followSwarm)
                || action.hasPrefix(UNNotificationDefaultActionIdentifier) {
                selection = .colony
                dashboardResets += 1
                clearTheWay()
            }
            // "Photograph a flower" from Siri, a Shortcut or Control Centre.
            // Matched on a prefix because the identifier carries a nonce —
            // see `PhotographFlowerIntent` for why asking twice has to look
            // like two different requests.
            // Not without a colony to photograph for: the camera used to wait
            // through the introduction or the choice of a new site and then
            // open out of nowhere.
            if action.hasPrefix(PhotographFlowerIntent.actionPrefix),
               !store.needsSetup, !store.isCollapsed {
                request(.capture())
            }
        }
        .onChange(of: humEnabled, initial: true) { _, enabled in
            if enabled, scenePhase == .active {
                HiveHum.shared.start()
            } else {
                HiveHum.shared.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await resume() }
                if humEnabled { HiveHum.shared.start() }
            case .inactive, .background:
                if phase == .background, !store.needsSetup {
                    LastLook.record(store.snapshot)
                }
                store.stopLiveUpdates()
                HiveHum.shared.stop()
                // Ask to be woken while the app is closed, so the colony the
                // watch and the complication show is not the one the player
                // last happened to look at.
                BackgroundRefresh.schedule()
            @unknown default:
                break
            }
        }
    }

    /// Brings the colony up to date and starts the live view. Called on every
    /// appearance and every return to the foreground.
    ///
    /// Not during setup: the colony that exists then is the placeholder
    /// `GameStore.load` invented, at a site nobody has chosen, and running it
    /// forward underneath the introduction would hand the player a catch-up
    /// report about a nest they have not seen. The store refuses to save or to
    /// tick while it needs setting up; this keeps it from being asked.
    private func resume() async {
        store.retryUnreadableSave()
        guard !store.needsSetup else { return }
        let look = LastLook.stored()
        // Off the main actor: after weeks away this is months of ticks, and
        // run here it froze the first screen long enough to risk the launch
        // watchdog.
        await store.catchUpInBackground()
        store.startLiveUpdates()

        // A short, quiet absence is told by the dashboard's figures rather
        // than a sheet over everything.
        withAnimation(.snappy) {
            lastLook = look.flatMap {
                Date().timeIntervalSince($0.takenAt) >= LastLook.worthShowingAfter ? $0 : nil
            }
        }
        if let report = store.pendingReport, !report.deservesASheet, lastLook != nil {
            store.dismissReport()
        }
        // See `SettingsTip`: it holds off until there is a flower in the
        // garden, so that it cannot out-run the camera tip on the first
        // screen a player ever sees.
        SettingsTip.hasPhotographed = !store.snapshot.patches.isEmpty
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            ColonyDashboardView(onPhotograph: { request(.capture()) })
                .id(dashboardResets)
                .tabItem { Label("Colony", systemImage: "chart.bar.doc.horizontal") }
                .tag(Tab.colony)

            NestView()
                .tabItem { Label("Nest", systemImage: "hexagon.fill") }
                .tag(Tab.nest)

            // Between the nest and the garden, because that is where it sits
            // in the game: the nest is the inside, the world is the outside,
            // and the garden is the record of what has been carried between
            // them. The symbol is a cluster of cells rather than the Nest's
            // single filled hexagon — the same shape seen from above, and a
            // great deal more of it.
            WorldView(
                onPhotograph: { cell in
                    request(.capture(plantingAt: cell))
                },
                bloomingCell: $bloomingCell
            )
                .tabItem { Label("World", systemImage: "circle.hexagongrid.fill") }
                .tag(Tab.world)

            GardenView(onPhotograph: { request(.capture()) })
                .tabItem { Label("Garden", systemImage: "photo.on.rectangle.angled") }
                .tag(Tab.garden)
        }
        .tint(Theme.honey)
        // Each tab puts a `SettingsButton` in its own navigation bar. This
        // used to be one gear floated over the whole TabView at the top
        // trailing corner — which is exactly where every tab keeps its own
        // main action, so on the first Mac run the gear sat on top of the
        // camera button and hid the one thing the game asks the player to do.
        .environment(\.showSettings, { request(.settings) })
        // The overview's place lines — the comb, the country, the garden —
        // open the tab that draws each, so the first screen can stand in for
        // the tab bar.
        .environment(\.openTab, { selection = $0 })
        .environment(\.lastLook, lastLook)
        .environment(children)
        .disabled(store.isCatchingUp)
    }

    @ViewBuilder
    private func content(for sheet: RootSheet) -> some View {
        switch sheet {
        case .capture(let cell):
            CaptureView(plantingAt: cell)
                // The map checks the cell really was planted before it plays
                // anything, so a capture abandoned half way, or put down to
                // be put up again, shows nothing.
                .onDisappear { if let cell { bloomingCell = cell } }
        case .settings:
            SettingsView()
        case .report:
            if let report = store.pendingReport {
                // On disappearing as well as on Done, so dragging the sheet
                // away also clears the report instead of leaving it to return.
                CatchUpReportView(report: report) { store.dismissReport() }
                    .onDisappear { store.dismissReport() }
            }
        case .flower(let share):
            if share.isRequest {
                ReceiveRequestView(request: share)
            } else {
                ReceiveFlowerView(share: share)
            }
        case .swarm(let share):
            ReceiveSwarmView(share: share)
        case .backup(let opened):
            RestoreBackupView(opened: opened)
        case .failure(let title, let message):
            OpenFailedView(title: title, message: message)
        }
    }

    // MARK: - The one sheet

    /// Puts something up now, or as soon as the way is clear.
    private func request(_ next: RootSheet) {
        guard sheet?.id != next.id, !waiting.contains(where: { $0.id == next.id }) else { return }
        // Done and the buttons underneath it sit in the same corner, so one
        // tap too many on Done opened the camera or Settings.
        if !next.isOpenedFromOutside, next.id != RootSheet.report.id,
           Date().timeIntervalSince(sheetLastClosed) < 0.6 { return }
        if sheet == nil, children.open == 0 {
            show(next)
        } else {
            // The report goes first: it is read before anything new is opened.
            waiting.insert(next, at: next.id == RootSheet.report.id ? 0 : waiting.endIndex)
            if next.isOpenedFromOutside { clearTheWay() }
        }
    }

    /// Asks whatever can be put away to go. What is waiting follows from
    /// `sheetClosed`, or from the count of child sheets reaching zero.
    private func clearTheWay() {
        if sheet?.canBePutAway == true { sheet = nil }
        if children.open > 0 { children.closeAll() }
    }

    private func presentNext() {
        guard sheet == nil, children.open == 0, !waiting.isEmpty else { return }
        show(waiting.removeFirst())
    }

    /// A presentation refused because another is still leaving the screen
    /// gives no error and leaves `sheet` set, so whether it arrived is checked
    /// rather than assumed.
    private func show(_ next: RootSheet) {
        sheet = next
        Task { @MainActor in
            for _ in 0..<3 {
                try? await Task.sleep(for: .seconds(1.5))
                guard sheet?.id == next.id, appearedSheet != next.id else { return }
                sheet = nil
                try? await Task.sleep(for: .milliseconds(100))
                guard sheet == nil else { return }
                sheet = next
            }
        }
    }

    private func sheetClosed() {
        appearedSheet = nil
        sheetLastClosed = Date()
        presentNext()
    }

    /// Handles a `.flower`, `.swarm` or `.flowerhive` file the player opened
    /// from a message, from Files, or from anywhere else.
    ///
    /// The file arrives in a location the app is only lent access to, so it is
    /// read straight away rather than held as a URL. Nothing is imported or
    /// restored here — the receiving screen shows it first, which for a backup
    /// is not a nicety: opening one replaces the colony.
    private func open(_ url: URL) {
        let needsPermission = url.startAccessingSecurityScopedResource()
        defer { if needsPermission { url.stopAccessingSecurityScopedResource() } }

        let kind = url.pathExtension.lowercased()

        // Measured before it is read: every decoder has a limit of its own,
        // but they are handed the file after it is already in memory, on this
        // thread, however many gigabytes it was.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        // A backup's own failure goes to its own screen, so the reassurance
        // that nothing was replaced comes with it.
        if kind == SaveArchive.fileExtension {
            do {
                guard size <= SaveArchive.maximumBytes else { throw SaveArchive.Failure.tooLarge(size) }
                // Read while the file is still lent to us, decoded off the
                // main actor: a backup carrying its photographs is tens of
                // megabytes of JSON, and parsing that where the sheet is
                // drawn froze the screen for the length of it.
                let data = try Data(contentsOf: url)
                Task { @MainActor in
                    request(.backup(await Self.openedBackup(from: data)))
                }
            } catch {
                request(.backup(.failure(error.localizedDescription)))
            }
            return
        }

        let isSwarm = kind == SwarmShare.fileExtension
        do {
            let limit = isSwarm ? SwarmShare.maximumBytes : FlowerShare.maximumImageBytes * 2
            guard size <= limit else { throw TooLarge() }
            let data = try Data(contentsOf: url)
            if isSwarm {
                request(.swarm(try SwarmShare.decoded(from: data)))
            } else {
                request(.flower(try FlowerShare.decoded(from: data)))
            }
        } catch {
            request(.failure(
                title: isSwarm ? "That swarm could not be opened" : "That flower could not be opened",
                message: error.localizedDescription
            ))
        }
    }

    @concurrent
    nonisolated private static func openedBackup(from data: Data) async -> OpenedBackup {
        do {
            return .archive(try SaveArchive.decoded(from: data))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private struct TooLarge: LocalizedError {
        var errorDescription: String? { "That file is too large to be what it says it is." }
    }
}

// MARK: - A save problem

/// A save that could not be written or read. Rare, and worth saying: the
/// store keeps playing through it, and without this the player had no way
/// to know their progress was not being kept.
private struct ErrorBanner: View {

    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        // It arrives over whatever had focus, and it matters.
        .onAppear { AccessibilityNotification.Announcement(message).post() }
    }
}

// MARK: - Settings, from every tab

/// The way into Settings, placed by each tab in its own navigation bar next
/// to that tab's own action, so the two cannot land on top of each other.
///
/// All four carry the Settings tip. TipKit shows a tip at one anchor at a
/// time, and the rule on `SettingsTip` still holds it back until there is a
/// flower in the garden.
struct SettingsButton: View {

    @Environment(\.showSettings) private var showSettings

    var body: some View {
        Button("Settings", systemImage: "gearshape.fill", action: showSettings)
            .popoverTip(AppTips.settings)
    }
}

private struct ShowSettingsKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    /// Opens Settings. Set by `ContentView`, which owns the sheet.
    var showSettings: @MainActor () -> Void {
        get { self[ShowSettingsKey.self] }
        set { self[ShowSettingsKey.self] = newValue }
    }
}

private struct OpenTabKey: EnvironmentKey {
    static let defaultValue: @MainActor (ContentView.Tab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Switches to a tab. Set by `ContentView`, which owns the selection.
    var openTab: @MainActor (ContentView.Tab) -> Void {
        get { self[OpenTabKey.self] }
        set { self[OpenTabKey.self] = newValue }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(GameStore.preview())
}
