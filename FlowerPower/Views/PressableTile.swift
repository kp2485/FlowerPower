//
//  PressableTile.swift
//  FlowerPower
//
//  Making a tile look like it can be pressed.
//
//  The garden's thumbnails and the milestone badges were `Button`s wearing
//  `.buttonStyle(.plain)`, which is exactly right for the layout and says
//  nothing at all under a finger: the tile does not move, does not dim, and
//  gives a player no reason to believe anything is going to happen. A plain
//  style is the absence of feedback, not a quiet kind of it.
//
//  So: a small scale and a small dip in opacity while the press is down. The
//  scale is dropped entirely when the system is asked to reduce motion, and
//  the dimming is kept, because somebody who has turned motion off still
//  needs to be told their finger landed.
//

import SwiftUI

/// The press feedback every tappable tile in the app shares.
struct PressableTileStyle: ButtonStyle {

    /// How far it shrinks. Deliberately slight: these are photographs and
    /// badges sitting shoulder to shoulder in a grid, and anything more reads
    /// as the grid itself moving.
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration, pressedScale: pressedScale)
    }

    /// The style's work, done in a view rather than in `makeBody` directly.
    ///
    /// A `ButtonStyle` is not a `View`, and an `@Environment` property on one
    /// is never filled in — it reads as the default for ever, which for
    /// `accessibilityReduceMotion` means "no, they did not ask for that". The
    /// only way to read the environment from a style is to put a real view
    /// inside it.
    private struct Tile: View {

        // Spelled out rather than as the protocol's `Configuration`, which
        // is a name that belongs to the conformance and not to this type.
        let configuration: ButtonStyleConfiguration
        let pressedScale: CGFloat

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(scale)
                .opacity(configuration.isPressed ? 0.82 : 1)
                .animation(press, value: configuration.isPressed)
        }

        private var scale: CGFloat {
            configuration.isPressed && !reduceMotion ? pressedScale : 1
        }

        /// `.snappy` rather than a spring, because it is the curve the map
        /// already moves on and one house style is enough. Nil under Reduce
        /// Motion, which leaves the dimming to land at once.
        private var press: Animation? {
            reduceMotion ? nil : .snappy(duration: 0.18)
        }
    }
}

extension ButtonStyle where Self == PressableTileStyle {

    /// `.buttonStyle(.pressableTile)`, read the way `.plain` is.
    static var pressableTile: PressableTileStyle { PressableTileStyle() }
}
