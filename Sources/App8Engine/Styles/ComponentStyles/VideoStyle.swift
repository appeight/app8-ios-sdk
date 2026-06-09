import AVFoundation
import UIKit

extension DSL.Model.Style {

    struct Video: Decodable, BaseStyleProtocol, StylePointerResolvable {
        /// How the video fills its frame. Mirrors image `contentMode`; mapped to
        /// `AVLayerVideoGravity` via `videoGravity`. Default fill.
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
        let transform: View.Transform?
        let corner: Corner?

        /// `AVPlayerLayer.videoGravity` derived from `contentMode`.
        /// Defaults to aspect-fill so onboarding loops cover their frame edge-to-edge.
        var videoGravity: AVLayerVideoGravity {
            switch contentMode {
            case .scaleAspectFit: return .resizeAspect
            case .scaleToFill: return .resize
            default: return .resizeAspectFill
            }
        }

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? true
        }

        func unresolvedPointerIds() -> [String] {
            _material.unresolvedPointerIds()
        }
    }
}
