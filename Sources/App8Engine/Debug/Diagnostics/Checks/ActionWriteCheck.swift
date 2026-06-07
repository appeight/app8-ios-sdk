import Foundation

/// Lints variable-WRITE targets across a screen's tree — silent-failure bugs
/// that decode cleanly but no-op at runtime: ERROR for `$`-prefixed dotted
/// targets (resolve only on the read path) and WARNING for undeclared names.
/// The findings' message strings carry the full rationale. Operates on raw JSON
/// (after template preprocessing), independent of the typed models.
enum ActionWriteCheck {

    typealias EC = App8.DiagnosticReport.ErrorCode

    /// Names the engine injects into scope implicitly (loop / event context).
    /// Never declared in `variables`, so they must not be flagged as undeclared.
    private static let implicitNames: Set<String> = ["item", "index", "section", "event"]

    /// Action `type`s whose `variableName` field is a write target.
    private static let singleTargetWrites: Set<String> =
        ["updateVariable", "incrementVariable", "toggleArrayValue", "appendToArray"]

    // MARK: - Per-app section (runDiagnostics / validateApp)

    static func run(
        screenIds: Set<String>,
        dataSource: App8DataSource,
        templateResolver: TemplateResolver?
    ) async -> App8.DiagnosticReport.Section {
        var errors: [App8.ValidationError] = []
        var warnings: [App8.ValidationWarning] = []

        for screenId in screenIds.sorted() {
            guard let data = try? await dataSource.getScreen(screenId: screenId) else { continue }
            let f = findings(screenData: data, screenId: screenId, templateResolver: templateResolver)
            errors += f.errors
            warnings += f.warnings
        }

        return App8.DiagnosticReport.Section(
            kind: .actions,
            label: "Action writes",
            errors: errors,
            warnings: warnings,
            statusDetail: errors.isEmpty && warnings.isEmpty ? "all variable writes resolve" : nil
        )
    }

    // MARK: - Per-screen findings (validate(screenId:) / validate(screenData:))

    static func findings(
        screenData: Data,
        screenId: String?,
        templateResolver: TemplateResolver?
    ) -> (errors: [App8.ValidationError], warnings: [App8.ValidationWarning]) {
        var processed = screenData
        if let templateResolver {
            processed = TemplatePreprocessor(resolver: templateResolver).preprocess(screenData) ?? screenData
        }
        guard let root = try? JSONSerialization.jsonObject(with: processed) as? [String: Any] else {
            return ([], [])
        }
        var acc = Accumulator(screenId: screenId)
        walk(node: root, inheritedScope: implicitNames, path: nodePath(root, parent: ""), into: &acc)
        return (acc.errors, acc.warnings)
    }

    // MARK: - Walk

    private struct Accumulator {
        let screenId: String?
        var errors: [App8.ValidationError] = []
        var warnings: [App8.ValidationWarning] = []

        func qualified(_ path: String) -> String {
            screenId.map { "screens/\($0) > \(path)" } ?? path
        }
    }

    private static func walk(
        node: [String: Any],
        inheritedScope: Set<String>,
        path: String,
        into acc: inout Accumulator
    ) {
        // A node's own declarations (and template-instance bindings) extend the
        // scope visible to it and its descendants.
        let scope = inheritedScope.union(declaredNames(in: node))

        guard let content = node["content"] as? [String: Any] else { return }

        if let actions = content["actions"] as? [String: Any] {
            for (trigger, value) in actions {
                checkActionValue(value, scope: scope, path: "\(path).\(trigger)", into: &acc)
            }
        }

        if let children = content["children"] as? [[String: Any]] {
            for child in children {
                walk(node: child, inheritedScope: scope, path: nodePath(child, parent: path), into: &acc)
            }
        }
    }

    /// A trigger maps to a single action object or an array of them.
    private static func checkActionValue(
        _ value: Any,
        scope: Set<String>,
        path: String,
        into acc: inout Accumulator
    ) {
        if let action = value as? [String: Any] {
            checkAction(action, scope: scope, path: path, into: &acc)
        } else if let actions = value as? [[String: Any]] {
            for (i, action) in actions.enumerated() {
                checkAction(action, scope: scope, path: "\(path)[\(i)]", into: &acc)
            }
        }
    }

    private static func checkAction(
        _ action: [String: Any],
        scope: Set<String>,
        path: String,
        into acc: inout Accumulator
    ) {
        guard let type = action["type"] as? String else { return }

        if singleTargetWrites.contains(type), let target = action["variableName"] as? String {
            checkTarget(target, scope: scope, path: path, into: &acc)
        }

        if type == "updateMultipleVariables", let updates = action["updates"] as? [String: Any] {
            for key in updates.keys.sorted() {
                checkTarget(key, scope: scope, path: path, into: &acc)
            }
        }
    }

    private static func checkTarget(
        _ target: String,
        scope: Set<String>,
        path: String,
        into acc: inout Accumulator
    ) {
        // `$parent.x` / any `$`-prefixed dotted target: unsupported on the write path.
        if target.hasPrefix("$"), target.contains(".") {
            let bare = String(target.drop(while: { $0 != "." }).dropFirst())
            acc.errors.append(App8.ValidationError(
                code: EC.actionWriteParentScope,
                message: "Action at \(path) writes \"\(target)\". A \"$\"-prefixed path resolves only when READING {{…}} expressions, not on the write path, so the update silently fails (no-op). Use the bare name \"\(bare)\" — the engine walks up the scope chain to find the variable.",
                path: acc.qualified(path),
                context: ["target": target, "suggestedTarget": bare]
            ))
            return
        }

        if !scope.contains(target) {
            acc.warnings.append(App8.ValidationWarning(
                code: EC.actionWriteUndeclared,
                message: "Action at \(path) writes \"\(target)\", which isn't declared in this screen's variables or any enclosing scope. The write will no-op unless the variable is provided at runtime — declare it in content.variables, or check for a typo.",
                path: acc.qualified(path),
                context: ["target": target]
            ))
        }
    }

    // MARK: - Scope helpers

    /// Variable names a node introduces into scope: the declaration shape
    /// (`content.variables`, name → definition) plus the template-instance
    /// binding shape (`variables`, name → value).
    private static func declaredNames(in node: [String: Any]) -> Set<String> {
        var names: Set<String> = []
        if let content = node["content"] as? [String: Any],
           let declared = content["variables"] as? [String: Any] {
            names.formUnion(declared.keys)
        }
        if let bound = node["variables"] as? [String: Any] {
            names.formUnion(bound.keys)
        }
        return names
    }

    private static func nodePath(_ node: [String: Any], parent: String) -> String {
        let id = (node["id"] as? String) ?? (node["type"] as? String) ?? "?"
        return parent.isEmpty ? id : "\(parent).\(id)"
    }
}
