//
//  PhotoCapture.swift
//  App8Engine
//
//  The system UI of `capturePhoto` (docs/photos.md): the chooser (action
//  sheet), the camera (UIImagePickerController, after the camera permission)
//  and the library (PHPickerViewController, no permission). Answers once with
//  an image, a cancel or an error.
//

import AVFoundation
import PhotosUI
import UIKit

enum PhotoPick {
    case image(UIImage, source: String)
    case cancel
    case error(code: String, message: String)
}

struct PhotoCaptureRequest {
    enum Source: String { case camera, library, cameraOrLibrary }
    var source: Source = .cameraOrLibrary
    var front = false
    var cameraLabel = "Take Photo"
    var libraryLabel = "Choose from Library"
    var cancelLabel = "Cancel"
}

@MainActor
final class PhotoCapture: NSObject {

    /// The capture in progress (one at a time).
    private(set) static var current: PhotoCapture?
    static var isBusy: Bool { current != nil }

    private let request: PhotoCaptureRequest
    private var completion: ((PhotoPick) -> Void)?
    private weak var logger: A8Log?

    private init(_ request: PhotoCaptureRequest, logger: A8Log?, completion: @escaping (PhotoPick) -> Void) {
        self.request = request
        self.logger = logger
        self.completion = completion
    }

    /// Opens the UI for `request`; `completion` runs once on the main actor.
    static func start(_ request: PhotoCaptureRequest, logger: A8Log?, completion: @escaping (PhotoPick) -> Void) {
        guard current == nil else {
            logger?.warning("photo.capture.busy: a capturePhoto is already open — ignored")
            return
        }
        let capture = PhotoCapture(request, logger: logger, completion: completion)
        current = capture
        capture.begin()
    }

    private func finish(_ pick: PhotoPick) {
        guard let completion else { return }
        self.completion = nil
        Self.current = nil
        completion(pick)
    }

    // MARK: - Flow

    private func begin() {
        switch request.source {
        case .camera: openCamera()
        case .library: openLibrary()
        case .cameraOrLibrary:
            if cameraHardware || simulatorImage != nil { showChooser() } else { openLibrary() }
        }
    }

    private var cameraHardware: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// Simulator only: `APP8_SIMULATOR_CAMERA_IMAGE=<file>` stands in for the
    /// camera, whose simulated preview takes no pictures (tests and demos),
    /// after the permission check. Ignored on devices.
    private var simulatorImage: UIImage? {
        #if targetEnvironment(simulator)
        if let path = ProcessInfo.processInfo.environment["APP8_SIMULATOR_CAMERA_IMAGE"], !path.isEmpty {
            return UIImage(contentsOfFile: path)
        }
        #endif
        return nil
    }

    private func showChooser() {
        guard let top = Self.topViewController() else { return finish(.error(code: "unavailable", message: "no view controller to present from")) }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: request.cameraLabel, style: .default) { [weak self] _ in self?.openCamera() })
        sheet.addAction(UIAlertAction(title: request.libraryLabel, style: .default) { [weak self] _ in self?.openLibrary() })
        sheet.addAction(UIAlertAction(title: request.cancelLabel, style: .cancel) { [weak self] _ in self?.finish(.cancel) })
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.app8PresentInScreenStyle(sheet)
    }

    private func openCamera() {
        // Without the usage string iOS would terminate the app on access.
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            logger?.warning("photo.camera.usageDescriptionMissing: add NSCameraUsageDescription to the host Info.plist")
            return finish(.error(code: "unavailable", message: "NSCameraUsageDescription missing"))
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    if granted { self?.presentCamera() } else { self?.finish(.error(code: "permissionDenied", message: "camera access was denied")) }
                }
            }
        case .denied, .restricted:
            finish(.error(code: "permissionDenied", message: "camera access was denied"))
        @unknown default:
            finish(.error(code: "permissionDenied", message: "camera access is not allowed"))
        }
    }

    private func presentCamera() {
        // Simulator: its camera shows no frames, so a configured image stands in.
        if let image = simulatorImage {
            return finish(.image(image, source: "camera"))
        }
        guard cameraHardware, let top = Self.topViewController() else {
            return finish(.error(code: "unavailable", message: "this device has no camera"))
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        let device: UIImagePickerController.CameraDevice = request.front ? .front : .rear
        if UIImagePickerController.isCameraDeviceAvailable(device) { picker.cameraDevice = device }
        picker.delegate = self
        picker.presentationController?.delegate = self
        top.app8PresentInScreenStyle(picker)
    }

    private func openLibrary() {
        guard let top = Self.topViewController() else { return finish(.error(code: "unavailable", message: "no view controller to present from")) }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        picker.presentationController?.delegate = self
        top.app8PresentInScreenStyle(picker)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}

extension PhotoCapture: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    nonisolated func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        MainActor.assumeIsolated {
            picker.dismiss(animated: true)
            if let image { finish(.image(image, source: "camera")) } else { finish(.error(code: "failed", message: "the camera returned no image")) }
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        MainActor.assumeIsolated {
            picker.dismiss(animated: true)
            finish(.cancel)
        }
    }
}

extension PhotoCapture: PHPickerViewControllerDelegate {
    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        MainActor.assumeIsolated { picker.dismiss(animated: true) }
        guard let provider = results.first?.itemProvider else {
            MainActor.assumeIsolated { finish(.cancel) }
            return
        }
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            MainActor.assumeIsolated { finish(.error(code: "failed", message: "the photo could not be read")) }
            return
        }
        provider.loadObject(ofClass: UIImage.self) { object, error in
            let image = object as? UIImage
            let message = error?.localizedDescription ?? "the photo could not be read"
            Task { @MainActor [weak self] in
                if let image { self?.finish(.image(image, source: "library")) } else { self?.finish(.error(code: "failed", message: message)) }
            }
        }
    }
}

extension PhotoCapture: UIAdaptivePresentationControllerDelegate {
    /// Swiped down: the same as Cancel.
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        MainActor.assumeIsolated { finish(.cancel) }
    }
}
