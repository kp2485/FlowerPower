//
//  CameraPicker.swift
//  FlowerPower
//
//  Taking the photograph without leaving the app.
//
//  Until this existed the app had a camera usage string and no camera. The
//  only way in was the photo library picker, so "go and photograph a flower"
//  meant leaving FlowerPower, opening Camera, coming back, and picking the
//  shot out of a grid — for the one action the whole game is built on.
//
//  `UIImagePickerController` rather than an `AVCaptureSession` of our own.
//  That is a deliberately boring choice: it brings its own shutter, focus,
//  flash and permission handling, and none of that is where this app's
//  interest lies. A hand-rolled capture pipeline would be several hundred
//  lines standing between the player and a picture of a flower.
//
//  A photograph taken this way carries no location of its own — that only
//  comes from the Camera app's own EXIF writing — so `PhotoLibrary.save`
//  attaches one from CoreLocation when the player has granted it. This is why
//  location is requested at all, and why the game stays entirely playable
//  without it.
//

import SwiftUI
import UIKit
import AVFoundation

struct CameraPicker: UIViewControllerRepresentable {

    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    /// Whether this device can actually take a picture. False in the
    /// simulator, which is where most of this will first be run.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static var authorisationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    @discardableResult
    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject,
                             UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {

        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // `.editedImage` first even though editing is off, because the key
            // is populated on some paths regardless and is the one the user
            // saw framed.
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let image {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
