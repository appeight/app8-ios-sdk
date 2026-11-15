import Combine

class CVideoViewModel: CBaseViewModel<DSL.Model.Component.Video.C> {

    override func setup() {
        super.setup()
    }

    /// Dispatch a video playback trigger through the analytics pipeline, then
    /// run each author-declared action. Routing through `dispatchTrigger` is
    /// mandatory (see CLAUDE.md): it fires author `analytics` bindings and the
    /// auto-tap event, so `.emit` host events and variable actions both work.
    ///
    /// `overlays` inject ephemeral values visible to variable-action
    /// expressions (e.g. `$markId` for `.onTimeMark`, `$error` for
    /// `.onVideoError`). Non-variable actions (`.emit`, navigation, etc.) go
    /// through `executeAction(_:)` so they behave exactly as on any other
    /// trigger.
    func dispatchVideoTrigger(_ trigger: DSL.Model.ActionTrigger, overlays: [String: Any] = [:]) {
        var context = VariableContext(store: variableStore)
        for (name, value) in overlays {
            context = context.overlaying(name, value: value)
        }
        dispatchTrigger(trigger) { [weak self] action in
            self?.executeAction(action, context: context)
        }
    }
}
