//
//  PhotoStore.swift
//  App8Engine
//
//  Photos (docs/photos.md): JPEG files the `capturePhoto` action stored,
//  named by the id in their `photo://<id>` reference.
//  Storage: Application Support/app8/<appId>/photos/<id>.jpg.
//

import Foundation
import UIKit

enum PhotoStore {

    /// `photo://` and a lowercase UUID.
    static let scheme = "photo://"

    /// Photos younger than this survive the launch cleanup even when nothing mentions them.
    static let sweepMinimumAge: TimeInterval = 60 * 60

    /// The id of a `photo://` reference, or nil.
    static func photoId(_ value: Any?) -> String? {
        guard let s = value as? String, s.hasPrefix(scheme) else { return nil }
        let id = String(s.dropFirst(scheme.count))
        guard id.count == 36, id == id.lowercased(), UUID(uuidString: id) != nil else { return nil }
        return id
    }

    static func reference(id: String) -> String { scheme + id }

    /// `Application Support/app8`.
    static var rootDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("app8", isDirectory: true)
    }

    static func directory(appId: String) -> URL? {
        rootDirectory?.appendingPathComponent(sanitized(appId), isDirectory: true)
            .appendingPathComponent("photos", isDirectory: true)
    }

    static func fileURL(appId: String, id: String) -> URL? {
        directory(appId: appId)?.appendingPathComponent("\(id).jpg")
    }

    /// App ids become one path component.
    private static func sanitized(_ appId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let s = String(appId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return s.isEmpty || s == "." || s == ".." ? "default" : s
    }

    /// Writes a JPEG and returns its new id.
    static func save(_ jpeg: Data, appId: String) throws -> String {
        guard let dir = directory(appId: appId) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        try jpeg.write(to: dir.appendingPathComponent("\(id).jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        decoded.removeObject(forKey: "\(appId)/\(id)" as NSString)
        return id
    }

    static func delete(appId: String, id: String) {
        guard let url = fileURL(appId: appId, id: id) else { return }
        try? FileManager.default.removeItem(at: url)
        decoded.removeObject(forKey: "\(appId)/\(id)" as NSString)
        NotificationCenter.default.post(name: .app8PhotoDeleted, object: nil, userInfo: ["appId": appId, "id": id])
    }

    /// The launch cleanup: removes photos older than an hour whose id appears
    /// in none of `persistedJSON` (the app's stored persisted values; the id,
    /// not the whole reference, because JSONSerialization escapes `/`).
    @discardableResult
    static func sweep(appId: String, persistedJSON: [String], now: Date = Date()) -> [String] {
        guard let dir = directory(appId: appId),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])
        else { return [] }
        let text = persistedJSON.joined(separator: "\n")
        var removed: [String] = []
        for file in files where file.pathExtension == "jpg" {
            let id = file.deletingPathExtension().lastPathComponent
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard now.timeIntervalSince(created) >= sweepMinimumAge, !text.contains(id) else { continue }
            try? FileManager.default.removeItem(at: file)
            removed.append(id)
        }
        return removed
    }

    /// Runs `sweep` off the main thread with the app's stored persisted values
    /// (UserDefaults suite `app8.<appId>`, keys `var.*`).
    @MainActor static func sweepInBackground(appId: String) {
        let suite = VariablePersistence.suiteName(appId: appId)
        let prefix = VariablePersistence.keyPrefix
        Task.detached(priority: .utility) {
            let defaults = UserDefaults(suiteName: suite)
            let values = (defaults?.dictionaryRepresentation() ?? [:])
                .filter { $0.key.hasPrefix(prefix) }
                .compactMap { ($0.value as? Data).flatMap { String(data: $0, encoding: .utf8) } }
            sweep(appId: appId, persistedJSON: values)
        }
    }

    /// `App8.clearPersistedData()`: every app's photos.
    static func clearAll() {
        guard let root = rootDirectory,
              let apps = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return }
        for app in apps {
            try? FileManager.default.removeItem(at: app.appendingPathComponent("photos", isDirectory: true))
        }
        decoded.removeAllObjects()
        NotificationCenter.default.post(name: .app8PhotoDeleted, object: nil, userInfo: nil)
    }

    // MARK: - Loading for images

    nonisolated(unsafe) private static let decoded: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

    static func cachedImage(appId: String, id: String) -> UIImage? {
        decoded.object(forKey: "\(appId)/\(id)" as NSString)
    }

    /// Decodes a stored photo off the main thread (nil when it does not exist).
    static func loadImage(appId: String, id: String) async -> UIImage? {
        if let hit = cachedImage(appId: appId, id: id) { return hit }
        guard let url = fileURL(appId: appId, id: id) else { return nil }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
            return img.preparingForDisplay() ?? img
        }.value
        if let image { decoded.setObject(image, forKey: "\(appId)/\(id)" as NSString) }
        return image
    }
}

extension Notification.Name {
    /// A stored photo was deleted (`userInfo` appId + id), or all of them (`userInfo` nil).
    static let app8PhotoDeleted = Notification.Name("app8.photo.deleted")
}

/// Downscale, center-crop and JPEG-encode a captured photo (docs/photos.md).
enum PhotoProcessing {

    struct Options: Equatable {
        var maxDimension: Int = 1600
        var quality: Double = 0.8
        var aspectRatio: Double?

        /// `maxDimension` clamped to 256…4096, `quality` to 0.1…1; strings from expressions accepted.
        init(maxDimension: Any? = nil, quality: Any? = nil, aspectRatio: Any? = nil) {
            if let n = Self.number(maxDimension) { self.maxDimension = min(4096, max(256, Int(n.rounded()))) }
            if let q = Self.number(quality) { self.quality = min(1, max(0.1, q)) }
            if let r = Self.number(aspectRatio), r > 0 { self.aspectRatio = r }
        }

        static func number(_ v: Any?) -> Double? {
            switch v {
            case let d as Double: return d.isFinite ? d : nil
            case let i as Int: return Double(i)
            case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
            default: return nil
            }
        }
    }

    struct Geometry: Equatable {
        var crop: CGRect
        var size: CGSize
    }

    /// The crop (in upright pixels) and the output size for a w×h image.
    static func geometry(width w: CGFloat, height h: CGFloat, options o: Options) -> Geometry {
        var sw = w, sh = h
        if let r = o.aspectRatio {
            if w / h > r { sw = (h * r).rounded() } else { sh = (w / r).rounded() }
        }
        let crop = CGRect(x: ((w - sw) / 2).rounded(), y: ((h - sh) / 2).rounded(), width: sw, height: sh)
        let scale = min(1, CGFloat(o.maxDimension) / max(sw, sh))
        return Geometry(crop: crop, size: CGSize(width: max(1, (sw * scale).rounded()), height: max(1, (sh * scale).rounded())))
    }

    /// An upright, cropped, downscaled JPEG without metadata.
    static func encode(_ image: UIImage, options: Options) -> (data: Data, width: Int, height: Int)? {
        // Upright size in pixels (UIImage.size is in points and already oriented).
        let w = image.size.width * image.scale, h = image.size.height * image.scale
        guard w > 0, h > 0 else { return nil }
        let g = geometry(width: w, height: h, options: options)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let factor = g.size.width / g.crop.width
        let rendered = UIGraphicsImageRenderer(size: g.size, format: format).image { _ in
            // Drawing applies the orientation; the offset and scale do the crop.
            image.draw(in: CGRect(x: -g.crop.minX * factor, y: -g.crop.minY * factor, width: w * factor, height: h * factor))
        }
        guard let data = rendered.jpegData(compressionQuality: options.quality) else { return nil }
        return (data, Int(g.size.width), Int(g.size.height))
    }
}
