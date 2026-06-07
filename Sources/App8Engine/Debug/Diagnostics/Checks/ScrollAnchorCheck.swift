import Foundation

/// Flags `scrollView` components whose content doesn't pin its bottom (vertical)
/// or trailing (horizontal) edge to `superview` — the scroll content view then
/// collapses on the scroll axis, so children draw but fall outside its bounds
/// and silently won't scroll or receive taps. The warning's message string
/// carries the full rationale. Operates on raw screen JSON.
enum ScrollAnchorCheck {

    typealias EC = App8.DiagnosticReport.ErrorCode

    static func findings(
        screenData: Data,
        screenId: String?
    ) -> (errors: [App8.ValidationError], warnings: [App8.ValidationWarning]) {
        guard let root = try? JSONSerialization.jsonObject(with: screenData) as? [String: Any] else {
            return ([], [])
        }
        var warnings: [App8.ValidationWarning] = []
        walk(root, screenId: screenId, path: nodePath(root, parent: ""), into: &warnings)
        return ([], warnings)
    }

    private static func walk(
        _ node: [String: Any],
        screenId: String?,
        path: String,
        into warnings: inout [App8.ValidationWarning]
    ) {
        guard let content = node["content"] as? [String: Any] else { return }
        let children = content["children"] as? [[String: Any]] ?? []

        if (node["type"] as? String) == "scrollView" {
            checkScrollView(node, content: content, children: children, screenId: screenId, path: path, into: &warnings)
        }

        for child in children {
            walk(child, screenId: screenId, path: nodePath(child, parent: path), into: &warnings)
        }
    }

    private static func checkScrollView(
        _ node: [String: Any],
        content: [String: Any],
        children: [[String: Any]],
        screenId: String?,
        path: String,
        into warnings: inout [App8.ValidationWarning]
    ) {
        let properties = content["properties"] as? [String: Any]

        // Marquee / auto-scroll views are sized by the engine — skip them.
        if properties?["autoScroll"] != nil { return }
        guard !children.isEmpty else { return }

        let direction = (properties?["direction"] as? String) ?? "vertical"
        let isHorizontal = direction == "horizontal"
        let axisAnchor = isHorizontal ? "trailing" : "bottom"
        let axisDimension = isHorizontal ? "width" : "height"

        let anchored = children.contains { childPins($0, axis: axisAnchor) }
        guard !anchored else { return }

        let id = (node["id"] as? String) ?? "scrollView"
        warnings.append(App8.ValidationWarning(
            code: EC.scrollContentUnanchored,
            message: "scrollView \"\(id)\" has \(children.count) child(ren) but none pins its \(axisAnchor) to \"superview\", so the scroll content has no defined \(axisDimension). The content renders but the scroll view collapses on the scroll axis — children fall outside its bounds and silently won't scroll or receive taps. Pin the last/bottom-most child's \(axisAnchor) to superview (the robust pattern is a single stackView pinned top, leading, trailing, and \(axisAnchor)).",
            path: screenId.map { "screens/\($0) > \(path)" } ?? path,
            context: ["scrollViewId": id, "direction": direction]
        ))
    }

    /// True when a direct child pins the scroll-axis edge to the scroll content
    /// (its `superview`), which is what gives the content its scroll-axis size.
    private static func childPins(_ child: [String: Any], axis: String) -> Bool {
        guard let content = child["content"] as? [String: Any],
              let layout = content["layout"] as? [String: Any],
              let constraints = layout["constraints"] as? [[String: Any]] else { return false }
        return constraints.contains { c in
            (c["type"] as? String) == axis && (c["target"] as? String) == "superview"
        }
    }

    private static func nodePath(_ node: [String: Any], parent: String) -> String {
        let id = (node["id"] as? String) ?? (node["type"] as? String) ?? "?"
        return parent.isEmpty ? id : "\(parent).\(id)"
    }
}
