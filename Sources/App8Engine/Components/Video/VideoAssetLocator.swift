import Foundation

/// Resolves a video `localAsset` name to a bundle URL. Single source of truth shared by
/// `CVideoView` (runtime playback) and the static diagnostic check (`ScreenCheck`), so both
/// agree on which names count as "present".
enum VideoAssetLocator {

    /// Container extensions tried when the DSL name has no extension.
    static let supportedExtensions = ["mp4", "mov", "m4v"]

    /// Look up a bundled video resource. The name may include an extension
    /// (`"intro.mp4"`) or omit it (`"intro"`), in which case each supported
    /// extension is tried in order.
    static func url(forResource name: String, in bundle: Bundle = .main) -> URL? {
        if let dotIndex = name.lastIndex(of: ".") {
            let base = String(name[..<dotIndex])
            let ext = String(name[name.index(after: dotIndex)...])
            if let url = bundle.url(forResource: base, withExtension: ext) {
                return url
            }
        }
        for ext in supportedExtensions {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
