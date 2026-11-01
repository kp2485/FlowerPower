//
//  RootPresentation.swift
//  FlowerPower
//
//  Everything the root of the app can put on screen, and the one slot it goes
//  in.
//
//  Each of these used to be a sheet of its own, plus an alert, on two different
//  views. SwiftUI will show only one at a time and says nothing when it
//  refuses, so a flower opened from Messages over the report, or an error over
//  a backup, was dropped with its state still set. Nothing that looked at that
//  state could ever see the way clear again, and every file opened afterwards
//  disappeared until a relaunch. One `.sheet(item:)` cannot compete with
//  itself, and what cannot go up yet waits in order behind it.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

enum RootSheet: Identifiable {
    case capture
    case settings
    case report
    case flower(FlowerShare)
    case swarm(SwarmShare)
    case backup(OpenedBackup)
    case failure(title: String, message: String)

    var id: String {
        switch self {
        case .capture: return "capture"
        case .settings: return "settings"
        case .report: return "report"
        case .flower(let share): return "flower-\(share.id)"
        case .swarm(let share): return "swarm-\(share.id)"
        case .backup(let opened): return "backup-\(opened.id)"
        case .failure(let title, let message): return "failure-\(title)-\(message)"
        }
    }

    /// Opening a file is a deliberate act, so what the player was doing is
    /// put away for it. Capture and Settings can be; the report cannot, since
    /// it is shown once and is read first.
    var isOpenedFromOutside: Bool {
        switch self {
        case .flower, .swarm, .backup, .failure: return true
        case .capture, .settings, .report: return false
        }
    }

    var canBePutAway: Bool {
        switch self {
        case .capture, .settings: return true
        default: return false
        }
    }
}

// MARK: - Sheets the tabs open for themselves

/// The sheets below the root: a flower's detail, the jobs, a queen's name.
///
/// The root cannot see these, and cannot present over one any more than over
/// its own, so a file opened while one was up was refused just as silently.
/// `.childSheet()` on the content of each lets the root count them, and ask
/// them to close.
@Observable
@MainActor
final class ChildSheets {
    fileprivate(set) var open = 0
    fileprivate(set) var closeRequests = 0

    func closeAll() { closeRequests += 1 }
}

private struct ChildSheet: ViewModifier {

    /// Optional so a preview needs nothing set up.
    @Environment(ChildSheets.self) private var sheets: ChildSheets?
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .onAppear { sheets?.open += 1 }
            .onDisappear { sheets?.open -= 1 }
            .onChange(of: sheets?.closeRequests) { _, _ in dismiss() }
    }
}

extension View {
    /// Marks the content of a sheet opened from inside a tab.
    func childSheet() -> some View {
        modifier(ChildSheet())
    }
}

// MARK: - A file that would not open

struct OpenFailedView: View {

    let title: String
    let message: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.alarm)
                Text(message)
                    .foregroundStyle(.secondary)
                Text("Nothing has changed in your colony.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
