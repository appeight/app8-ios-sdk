import Foundation
import ObjectiveC

/// Where `CVideoView` spills a data source's video bytes so AVPlayer can open
/// them as a file.
///
/// Each data source instance gets its own folder under
/// `tmp/app8-video/`. Asset names are only unique inside one app, so a host
/// that runs several apps (two stores that both ship a "launch-reel") must not
/// share files between them. The folder's name is a UUID tied to the data
/// source object for its lifetime, so a later data source at the same memory
/// address never inherits an old folder. Folders from earlier processes are
/// removed the first time the engine asks for one.
enum VideoTempFiles {

    private static let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("app8-video", isDirectory: true)

    nonisolated(unsafe) private static var namespaceKey: UInt8 = 0
    private static let lock = NSLock()
    nonisolated(unsafe) private static var didPurge = false

    static func directory(for dataSource: Any) -> URL {
        lock.lock()
        defer { lock.unlock() }

        if !didPurge {
            didPurge = true
            try? FileManager.default.removeItem(at: root)
            removeLegacyFiles()
        }

        let namespace: String
        if type(of: dataSource) is AnyClass {
            let object = dataSource as AnyObject
            if let existing = objc_getAssociatedObject(object, &namespaceKey) as? String {
                namespace = existing
            } else {
                namespace = UUID().uuidString
                objc_setAssociatedObject(object, &namespaceKey, namespace, .OBJC_ASSOCIATION_RETAIN)
            }
        } else {
            // A value-type data source has no identity to scope by.
            namespace = "shared"
        }

        let directory = root.appendingPathComponent(namespace, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Engine 0.4.1 and earlier wrote `tmp/app8-video-<name>.<ext>`, shared by every app.
    private static func removeLegacyFiles() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: tmp.path) else { return }
        for name in names where name.hasPrefix("app8-video-") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name))
        }
    }
}
