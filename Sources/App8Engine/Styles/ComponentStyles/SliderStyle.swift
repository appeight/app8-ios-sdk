import UIKit

extension DSL.Model.Style {

    struct Slider: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
        let transform: View.Transform?

        /// Tint color for the filled portion of the track
        let minimumTrackTintColor: String?
        /// Tint color for the unfilled portion of the track
        let maximumTrackTintColor: String?
        /// Tint color for the thumb
        let thumbTintColor: String?

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? true
        }
    }
}
