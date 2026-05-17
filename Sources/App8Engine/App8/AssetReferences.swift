// Public value types describing the remote assets and fonts a screen (or app)
// requires. Returned by `App8.Instance.collectAssetReferences(...)`.

import Foundation

public extension App8 {

    /// Reference to a remote asset declared by the DSL. Mirrors the
    /// `{ id, name, url }` shape that the engine's internal
    /// `DSL.Model.Asset` decodes from, without leaking that internal
    /// type onto the public API surface.
    struct AssetReference: Sendable, Hashable {
        public let id: String?
        public let name: String?
        public let url: String?

        public init(id: String?, name: String?, url: String?) {
            self.id = id
            self.name = name
            self.url = url
        }
    }

    /// Reference to a font face the engine will look up via
    /// `UIFont(name: postScriptName, size:)` at render time.
    ///
    /// `asset` is populated when the engine can resolve a concrete
    /// font-face asset from the app's decoded style sheet's
    /// `font.family.faces[].asset`. It is `nil` when the DSL only uses
    /// the `text.fontFamily` shortcut and no matching `Font.Family.Face`
    /// declares that PostScript name — in which case partners must
    /// look up the font asset themselves (e.g. by filename).
    struct FontReference: Sendable, Hashable {
        public let postScriptName: String
        public let asset: AssetReference?

        public init(postScriptName: String, asset: AssetReference?) {
            self.postScriptName = postScriptName
            self.asset = asset
        }
    }

    /// Deduplicated set of remote-image and font references required
    /// to render one or more screens.
    struct AssetReferenceSet: Sendable {
        public let images: Set<AssetReference>
        public let fonts: Set<FontReference>

        public init(images: Set<AssetReference> = [], fonts: Set<FontReference> = []) {
            self.images = images
            self.fonts = fonts
        }

        /// Union two reference sets — used when aggregating across
        /// multiple screens.
        public func union(_ other: AssetReferenceSet) -> AssetReferenceSet {
            AssetReferenceSet(
                images: images.union(other.images),
                fonts: fonts.union(other.fonts)
            )
        }

        public static let empty = AssetReferenceSet()
    }
}
