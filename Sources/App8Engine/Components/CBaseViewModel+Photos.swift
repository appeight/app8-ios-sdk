//
//  CBaseViewModel+Photos.swift
//  App8Engine
//
//  `capturePhoto` and `deletePhoto` (docs/photos.md). Like `request`, the
//  capture runs after the rest of the action list; `onSuccess` sees `photo`,
//  `onError` sees `error`, and the callbacks are dropped when the component
//  is gone (an app `resultVariable` is still written).
//

import UIKit

/// What the background encode hands back to the main actor.
private struct StoredPhoto: Sendable {
    let ref: String
    let width: Int
    let height: Int
    let createdAt: String
}

extension CBaseViewModel {

    func runCapturePhoto(_ action: DSL.Model.Action, context: VariableContext, store: VariableStoreProtocol?) {
        var request = PhotoCaptureRequest()
        request.source = action.source.flatMap(PhotoCaptureRequest.Source.init(rawValue:)) ?? .cameraOrLibrary
        request.front = action.camera == "front"
        let label = { (key: String, fallback: String) -> String in
            guard let raw = action.labels?[key] else { return fallback }
            let text = "\(self.resolveActionValue(raw, context: context))"
            return text.isEmpty ? fallback : text
        }
        request.cameraLabel = label("camera", request.cameraLabel)
        request.libraryLabel = label("library", request.libraryLabel)
        request.cancelLabel = label("cancel", request.cancelLabel)
        let options = PhotoProcessing.Options(
            maxDimension: action.maxDimension.map { resolveActionValue($0.value, context: context) },
            quality: action.quality.map { resolveActionValue($0.value, context: context) },
            aspectRatio: action.aspectRatio.map { resolveActionValue($0.value, context: context) }
        )
        let resultVariable = action.resultVariable.flatMap { $0.isEmpty ? nil : $0 }
        let onSuccess = action.onSuccess?.actions ?? []
        let onCancel = action.onCancel?.actions ?? []
        let onError = action.onError?.actions ?? []
        let appId = service.context.persistenceId
        let appStore = service.appVariableStore
        let logger = service.context.logger

        PhotoCapture.start(request, logger: logger) { [weak self] pick in
            switch pick {
            case .cancel:
                self?.runPhotoCallbacks(onCancel, context: context, store: store)
            case .error(let code, let message):
                self?.runPhotoCallbacks(onError, context: context.overlaying("error", value: ["code": code, "message": message]), store: store)
            case .image(let image, let source):
                Task { @MainActor [weak self] in
                    let stored = await Task.detached(priority: .userInitiated) { () -> StoredPhoto? in
                        guard let jpeg = PhotoProcessing.encode(image, options: options),
                              let id = try? PhotoStore.save(jpeg.data, appId: appId) else { return nil }
                        return StoredPhoto(ref: PhotoStore.reference(id: id), width: jpeg.width, height: jpeg.height,
                                           createdAt: ISO8601DateFormatter().string(from: Date()))
                    }.value
                    guard let stored else {
                        self?.runPhotoCallbacks(onError, context: context.overlaying("error", value: ["code": "failed", "message": "the photo could not be stored"]), store: store)
                        return
                    }
                    let ref = stored.ref
                    let photo: [String: Any] = ["ref": ref, "width": stored.width, "height": stored.height, "createdAt": stored.createdAt, "source": source]
                    guard let self else {
                        if let resultVariable, appStore.hasVariable(name: resultVariable) { try? appStore.setValue(name: resultVariable, value: ref) }
                        return
                    }
                    if let resultVariable {
                        do { try (store ?? self.variableStore).setValue(name: resultVariable, value: ref) }
                        catch { logger.error("capturePhoto: could not write resultVariable '\(resultVariable)': \(error)") }
                    }
                    self.runPhotoCallbacks(onSuccess, context: context.overlaying("photo", value: photo), store: store)
                }
            }
        }
    }

    private func runPhotoCallbacks(_ actions: [DSL.Model.Action], context: VariableContext, store: VariableStoreProtocol?) {
        for child in actions { executeAction(child, context: context, store: store) }
    }

    func runDeletePhoto(_ action: DSL.Model.Action, context: VariableContext) {
        guard let raw = action.ref,
              let id = PhotoStore.photoId(resolveActionValue(raw, context: context)) else { return }
        PhotoStore.delete(appId: service.context.persistenceId, id: id)
    }
}
