import Foundation

extension DSL.Model {

    /// Universal interaction overrides, declared per component under
    /// `content.interaction`. These apply to **every** component type (they live
    /// on `Component.Content`, not the per-component `properties`).
    ///
    /// Every field is a string so it can carry either a literal (`"true"`, `"2"`)
    /// or an expression (`"{{isTappable}}"`). Resolution goes through the same
    /// `resolvePropertyToBool` / `resolvePropertyToFloat` path that `isHidden` /
    /// `alpha` already use, so the values re-evaluate reactively when variables
    /// change.
    struct Interaction: Decodable, Sendable {
        /// Explicit `isUserInteractionEnabled` override. When omitted the engine
        /// keeps its derived default (containers are non-interactive until they
        /// declare `actions` / `triggers` / `gestures.pan`). When present it wins,
        /// so an author can force-enable a passive container or force-disable an
        /// otherwise-interactive subtree.
        let enabled: String?

        /// `clipsToBounds` override (bool expression).
        let clipsToBounds: String?

        /// `layer.zPosition` override (number expression). Raises/lowers a view
        /// among its siblings without reordering the view hierarchy.
        let zIndex: String?

        /// True when at least one override is declared.
        var hasBindings: Bool {
            enabled != nil || clipsToBounds != nil || zIndex != nil
        }
    }
}
