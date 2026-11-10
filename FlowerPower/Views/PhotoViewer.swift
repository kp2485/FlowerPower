//
//  PhotoViewer.swift
//  FlowerPower
//
//  The photograph, whole and large.
//
//  Everywhere else the app shows a square crop of a flower's picture, which
//  suits a grid and a card and loses the edges of the photograph a player
//  took. This is the one screen that shows the whole frame, at the most the
//  app ever decodes of it, with a pinch to look closer. It is a viewer and
//  nothing more: the actions on a flower stay on the detail sheet behind it.
//

import SwiftUI

struct PhotoViewer: View {

    let localIdentifier: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: UIImage?
    @State private var hasLoaded = false
    @State private var scale: CGFloat = 1
    @State private var magnifying: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale * magnifying)
                        .gesture(magnify)
                        .onTapGesture(count: 2) { toggleZoom() }
                        .accessibilityLabel("Your photograph of \(title)")
                        .accessibilityAddTraits(.isImage)
                } else if hasLoaded {
                    ContentUnavailableView(
                        "Not on This Phone",
                        systemImage: "photo",
                        description: Text("The photograph is in a library this phone cannot see.")
                    )
                    .foregroundStyle(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { @MainActor in
                image = await PhotoLoader.fullImage(for: localIdentifier)
                hasLoaded = true
            }
        }
        // Scoped to this view. `preferredColorScheme` would be a preference
        // carried up to the presentation, and it stayed dark after this was
        // dismissed: the sheet underneath and the share form it opened came
        // up in the dark on a light phone.
        .environment(\.colorScheme, .dark)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                magnifying = value.magnification
            }
            .onEnded { value in
                scale = min(max(1, scale * value.magnification), 4)
                magnifying = 1
            }
    }

    private func toggleZoom() {
        let target: CGFloat = scale > 1 ? 1 : 2.5
        if reduceMotion {
            scale = target
        } else {
            withAnimation(.snappy) { scale = target }
        }
    }
}
