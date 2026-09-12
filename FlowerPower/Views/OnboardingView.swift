//
//  OnboardingView.swift
//  FlowerPower
//
//  The first two minutes.
//
//  Before this, `GameStore.load` quietly started a colony at a default site
//  and the player arrived on a dashboard of thirty numbers about bees they had
//  not been told they had. Nothing in the app ever said what it was. That is a
//  strange thing to leave to a screenshot on a store page, and it is a
//  particularly bad fit for this game, because the three things a new player
//  needs to know are all things they would otherwise have to infer from
//  something going wrong:
//
//   1. The bees are wild and the player is not their owner. There is no shop.
//   2. Photographs are the only forage there is, and they fade — so the game
//      is asking for a walk rather than for taps.
//   3. The colony runs while the app is closed, and will ask questions with
//      windows on them. Silence is an answer: the bees fall back on instinct,
//      which is usually decent and occasionally fatal.
//
//  Each of those is a page, in that order, because that is the order in which
//  they stop being surprises. The fourth page is where notifications are asked
//  for, which is the only page here that has to exist at a particular moment:
//  iOS gives an app exactly one chance to ask, and the answer is worth far
//  more once the player knows the colony will be making decisions without them.
//  It used to be asked for in `FlowerPowerApp`'s `.task`, which fired before
//  the first frame — a permission dialogue as the opening screen, with nothing
//  behind it to explain why.
//
//  The site is not chosen here. `NewColonyView` already does that, and does it
//  better than a summary would: it shows the three traits that matter against
//  each other. `FirstRunView` below simply runs the two in sequence.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

// MARK: - The first run, start to finish

/// The introduction, and then the choice of where the swarm settles.
///
/// Shown instead of the tabs while `GameStore.needsSetup` is true. The store
/// writes nothing to disk until `startNewGame` is called at the end of this,
/// so a player who quits half way through comes back to the beginning rather
/// than to a colony in a tree they never saw.
struct FirstRunView: View {

    @Environment(GameStore.self) private var store

    @State private var hasReadTheIntroduction = false

    var body: some View {
        if hasReadTheIntroduction {
            NewColonyView(reason: .firstColony) { site in
                store.startNewGame(at: HiveLocation(type: site))
            }
        } else {
            OnboardingView { hasReadTheIntroduction = true }
        }
    }
}

// MARK: - The introduction

struct OnboardingView: View {

    /// Whether the last page should actually ask for notification permission.
    ///
    /// True on a first run. False when this is re-read from Help, because the
    /// system prompt only ever appears once: asking again does nothing at all,
    /// and a button that does nothing is worse than no button. Re-read, the
    /// page explains what the notifications are for and points at Settings.
    var asksForNotifications: Bool = true

    /// Called when the player is through — including when they decline
    /// notifications, which is not a failure and must not be a dead end.
    let onFinish: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pages: [Page] = [
        Page(
            symbol: "hexagon.fill",
            title: "A wild colony",
            lines: [
                "A swarm of honey bees has settled near you. They are not livestock and you are not their keeper — there is nothing to buy and no sugar syrup to pour. They will feed themselves, raise their own young, replace their own queen, and eventually divide.",
                "Your part is to be the reason there is anything to forage on, and to answer them when they ask."
            ]
        ),
        Page(
            symbol: "camera.fill",
            title: "Flowers are the only forage",
            lines: [
                "Photograph a real flower and your bees can work it. There is no other source of nectar in the game: a colony with nothing to fly to starves, however well it is run.",
                "And flowers do not last. A patch is at its best for about two months and is gone a few months later, so a garden photographed once in spring is empty by autumn. Keep finding new ones — different families, and close to the nest, because every kilometre costs the foragers honey to fly."
            ]
        ),
        Page(
            symbol: "clock.badge.questionmark",
            title: "They carry on without you",
            lines: [
                "An hour passes in the hive every five minutes, so a day takes two hours and a year about a month. None of it waits for you to be looking — close the app and the colony goes on foraging, building, brooding and overwintering.",
                "Sometimes it will ask you something: a predator at the entrance, swarm cells started, the entrance to seal for winter. Each question has a window, and if you do not answer it the bees do what instinct says. Instinct is usually reasonable. It is not always right, and it is never as good as knowing why."
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, content in
                    PageView(page: content)
                        .tag(index)
                }

                NotificationPage(asks: asksForNotifications, onAnswer: onFinish)
                    .tag(Self.pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // The last page carries its own two answers, so the shared
            // button below would be a third way off it.
            if page < Self.pages.count {
                Button {
                    // The page still turns; under Reduce Motion it is simply
                    // on the next page rather than sliding there.
                    if reduceMotion {
                        page += 1
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text("Next")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.honey)
                .controlSize(.large)
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - One page

    fileprivate struct Page {
        let symbol: String
        let title: String
        let lines: [String]
    }

    private struct PageView: View {

        let page: Page

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.honey)
                        .accessibilityHidden(true)

                    Text(page.title)
                        .font(.largeTitle.weight(.semibold))

                    ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                        // One paragraph per line, at the same weight: nothing
                        // on these three pages is more important than the rest
                        // of it.
                        Text(line)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                // Room for the page dots, which are drawn over the content.
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Asking for notifications

    /// The one page with a decision on it.
    ///
    /// Both buttons finish the introduction. Declining is a legitimate answer
    /// and the game is entirely playable without notifications — the engine is
    /// handed a `Date` and works out what should have happened, so nothing is
    /// lost by not being told. What is lost is the decisions: they are the
    /// only thing in the game with a window, and a window nobody hears about
    /// is a decision made for them by silence. So the page says that, rather
    /// than asking for permission on trust.
    private struct NotificationPage: View {

        let asks: Bool
        let onAnswer: () -> Void

        @State private var isAsking = false

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.honey)
                        .accessibilityHidden(true)

                    Text("When they need you")
                        .font(.largeTitle.weight(.semibold))

                    Text("A decision can be answered straight from the notification — hold the entrance, make room, keep the entrance open — without opening the app at all. There is also one morning report a day, at an hour you choose.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Nothing else. An idle game that pings about nothing gets its notifications turned off, and then it cannot say the one thing that matters. You can switch any of the three off in Settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if asks {
                        Button {
                            isAsking = true
                            Task { @MainActor in
                                await BackgroundRefresh.requestNotificationPermission()
                                onAnswer()
                            }
                        } label: {
                            Text("Let Them Tell Me")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .controlSize(.large)
                        .disabled(isAsking)

                        Button("Not Now") { onAnswer() }
                            .frame(maxWidth: .infinity)
                            .disabled(isAsking)
                    } else {
                        Button {
                            onAnswer()
                        } label: {
                            Text("Done")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Preview

#Preview("Introduction") {
    OnboardingView {}
}

#Preview("Re-read from Help") {
    OnboardingView(asksForNotifications: false) {}
}
