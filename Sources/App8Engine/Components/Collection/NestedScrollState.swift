import UIKit

// MARK: - NestedScrollStateRestorable

/// A component view that owns a scrollable surface (a horizontal shelf, a nested
/// scroll view) and can be rendered inside a reusable `CCollectionCell`.
///
/// Cells are recycled across items, and the reuse fast path keeps the cell's view
/// tree and just reparents its variable store, so a nested scrollable keeps whatever
/// offset the previous item left behind. The owning collection captures each nested
/// scrollable's offset when a cell ends display and restores it when the cell is
/// configured for an item again (the App Store / Netflix shelf pattern).
@MainActor
protocol NestedScrollStateRestorable: AnyObject {
    /// Stable identity of the scrollable inside its cell template (the component id).
    /// `nil` opts out (e.g. an auto-scrolling marquee owns its own offset).
    var nestedScrollStateId: String? { get }
    /// The offset of the scrollable surface, or `nil` when there is nothing to capture.
    var nestedScrollOffset: CGPoint? { get }
    /// Restore a captured offset without animation, clamped to the valid range.
    /// `nil` resets to the rest position so one item's offset never bleeds into another.
    func restoreNestedScrollOffset(_ offset: CGPoint?)
}

// MARK: - NestedScrollOffsetCache

/// Per-collection memory of nested scrollable offsets, keyed by the outer item's
/// identity plus the nested scrollable's id.
struct NestedScrollOffsetCache {
    private(set) var offsets: [String: CGPoint] = [:]
    /// Bumped on `reset()`. Cells remember the generation they were configured in,
    /// so a cell configured for the previous data set can't write its offset back
    /// under a key that now belongs to a different item.
    private(set) var generation = 0

    static func key(itemKey: String, nestedId: String) -> String {
        itemKey + "|" + nestedId
    }

    func offset(itemKey: String, nestedId: String) -> CGPoint? {
        offsets[Self.key(itemKey: itemKey, nestedId: nestedId)]
    }

    mutating func save(_ offset: CGPoint, itemKey: String, nestedId: String, generation: Int) {
        guard generation == self.generation else { return }
        offsets[Self.key(itemKey: itemKey, nestedId: nestedId)] = offset
    }

    mutating func reset() {
        offsets.removeAll()
        generation += 1
    }

    /// Clamp an offset to the scrollable range of a scroll view with the given geometry.
    static func clamp(
        _ offset: CGPoint,
        contentSize: CGSize,
        boundsSize: CGSize,
        insets: UIEdgeInsets
    ) -> CGPoint {
        let minX = -insets.left
        let minY = -insets.top
        let maxX = max(minX, contentSize.width + insets.right - boundsSize.width)
        let maxY = max(minY, contentSize.height + insets.bottom - boundsSize.height)
        return CGPoint(
            x: min(max(offset.x, minX), maxX),
            y: min(max(offset.y, minY), maxY)
        )
    }

    /// Nested restorables in a cell's view tree. Does not descend into a found
    /// restorable: a nested collection manages its own cells' state.
    @MainActor
    static func restorables(in view: UIView) -> [NestedScrollStateRestorable] {
        var result: [NestedScrollStateRestorable] = []
        for subview in view.subviews {
            if let restorable = subview as? NestedScrollStateRestorable {
                result.append(restorable)
            } else {
                result.append(contentsOf: restorables(in: subview))
            }
        }
        return result
    }
}

// MARK: - UIScrollView helpers

extension UIScrollView {
    /// The offset at which content sits at rest (top-left, honoring insets).
    var app8RestOffset: CGPoint {
        CGPoint(x: -adjustedContentInset.left, y: -adjustedContentInset.top)
    }

    /// Set `contentOffset` without animation, clamped to the current scrollable range.
    func app8SetClampedContentOffset(_ offset: CGPoint) {
        let clamped = NestedScrollOffsetCache.clamp(
            offset,
            contentSize: contentSize,
            boundsSize: bounds.size,
            insets: adjustedContentInset
        )
        if contentOffset != clamped {
            setContentOffset(clamped, animated: false)
        }
    }
}
