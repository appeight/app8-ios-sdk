import Foundation

/// Discovers all screen IDs reachable from an app definition via BFS traversal.
/// Walks flow start screens, component trees (actions, tabs, onEvent, navigationBar actions).
struct ScreenReferenceWalker {

    /// A reference from one screen to another, with context about where it was found.
    struct ScreenReference: Sendable {
        let sourceScreenId: String?
        let targetScreenId: String
        let path: String  // where in the source the reference was found
    }

    private let dataSource: App8DataSource
    private let decoder = JSONDecoder()
    private let templateResolver: TemplateResolver?

    init(dataSource: App8DataSource, templateResolver: TemplateResolver? = nil) {
        self.dataSource = dataSource
        self.templateResolver = templateResolver
    }

    /// Discovers all reachable screen IDs starting from the app's flow definitions.
    /// Returns the set of discovered screen IDs and all references found.
    ///
    /// `@MainActor` because `DSL.Model.App` isn't `Sendable` and the
    /// engine-side callers (`A8.discoverAllReachableScreenIds`, the
    /// MainActor `DiagnosticEngine.run` path) are already main-actor
    /// isolated. Keeps `app` on a single actor so its decoded subtree
    /// can't race with concurrent style/template merges.
    @MainActor
    func discoverAllScreens(app: DSL.Model.App) async -> (screenIds: Set<String>, references: [ScreenReference]) {
        var visited = Set<String>()
        var queue: [String] = []
        var allReferences: [ScreenReference] = []

        // Seed from flow startScreens
        for flow in app.navigation?.flows ?? [] {
            let screenId = flow.startScreen
            if !visited.contains(screenId) {
                visited.insert(screenId)
                queue.append(screenId)
            }
            allReferences.append(ScreenReference(
                sourceScreenId: nil,
                targetScreenId: screenId,
                path: "app.navigation.flows[\(flow.id)].startScreen"
            ))
        }

        while !queue.isEmpty {
            let screenId = queue.removeFirst()

            let refs = await loadAndWalkScreen(screenId: screenId)
            allReferences.append(contentsOf: refs)

            for ref in refs {
                if !visited.contains(ref.targetScreenId) {
                    visited.insert(ref.targetScreenId)
                    queue.append(ref.targetScreenId)
                }
            }
        }

        return (visited, allReferences)
    }

    /// Loads a screen by ID and extracts all screen references from it.
    private func loadAndWalkScreen(screenId: String) async -> [ScreenReference] {
        do {
            var data = try await dataSource.getScreen(screenId: screenId)

            if let resolver = templateResolver {
                let preprocessor = TemplatePreprocessor(resolver: resolver)
                data = preprocessor.preprocess(data) ?? data
            }

            let component = try decoder.decode(DSL.Model.Component.`Any`.self, from: data)
            return walkComponent(component, screenId: screenId, path: "")
        } catch {
            // Can't walk a screen we can't load — errors handled elsewhere
            return []
        }
    }

    /// Recursively walks a component tree, extracting screen references.
    private func walkComponent(_ component: DSL.Model.Component.`Any`, screenId: String, path: String) -> [ScreenReference] {
        var refs: [ScreenReference] = []
        let componentPath = path.isEmpty ? component.id : "\(path) > \(component.id)"

        // TabBarScreen: tab references replace normal child traversal
        if let tabEntity = component.base as? DSL.Model.Component.ConcreteEntity<DSL.Model.Component.TabBarScreen.C> {
            for (i, tab) in tabEntity.content.tabs.enumerated() {
                refs.append(ScreenReference(
                    sourceScreenId: screenId,
                    targetScreenId: tab.screen,
                    path: "\(componentPath).tabs[\(i)].screen"
                ))
            }
            return refs
        }

        guard let entity = component.asEntity() else { return refs }
        let content = entity.content

        if let actions = content.actions {
            for (trigger, list) in actions {
                for (i, action) in list.enumerated() {
                    let actionPath = list.count > 1
                        ? "\(componentPath).actions.\(trigger.rawValue)[\(i)]"
                        : "\(componentPath).actions.\(trigger.rawValue)"
                    refs.append(contentsOf: extractScreenRefs(from: action, screenId: screenId, path: actionPath))
                }
            }
        }

        if let eventTriggers = (content as? DSL.Model.EventTriggersHolder)?.onEvent {
            for (i, trigger) in eventTriggers.enumerated() {
                let eventPath = "\(componentPath).onEvent[\(i)].action"
                refs.append(contentsOf: extractScreenRefs(from: trigger.action, screenId: screenId, path: eventPath))
            }
        }

        if let navBar = extractNavigationBar(from: content) {
            if let leftAction = navBar.leftAction {
                refs.append(contentsOf: extractScreenRefs(
                    from: leftAction.action,
                    screenId: screenId,
                    path: "\(componentPath).navigationBar.leftAction"
                ))
            }
            if let rightAction = navBar.rightAction {
                refs.append(contentsOf: extractScreenRefs(
                    from: rightAction.action,
                    screenId: screenId,
                    path: "\(componentPath).navigationBar.rightAction"
                ))
            }
            for (i, barAction) in (navBar.rightActions ?? []).enumerated() {
                refs.append(contentsOf: extractScreenRefs(
                    from: barAction.action,
                    screenId: screenId,
                    path: "\(componentPath).navigationBar.rightActions[\(i)]"
                ))
            }
            if let titleView = navBar.titleView {
                refs.append(contentsOf: walkComponent(
                    titleView,
                    screenId: screenId,
                    path: "\(componentPath).navigationBar.titleView"
                ))
            }
        }

        // Walk Collection template definitions and state views — these hold full
        // component subtrees that are not part of `content.children`.
        if let collectionEntity = component.base as? DSL.Model.Component.ConcreteEntity<CollectionContent> {
            let cc = collectionEntity.content
            if let template = cc.template {
                refs.append(contentsOf: walkComponent(template, screenId: screenId, path: "\(componentPath).template"))
            }
            for (key, ref) in cc.templates ?? [:] {
                if case .inline(let tpl) = ref {
                    refs.append(contentsOf: walkComponent(tpl, screenId: screenId, path: "\(componentPath).templates[\(key)]"))
                }
            }
            if let empty = cc.emptyState {
                refs.append(contentsOf: walkComponent(empty, screenId: screenId, path: "\(componentPath).emptyState"))
            }
            if let loading = cc.loadingState {
                refs.append(contentsOf: walkComponent(loading, screenId: screenId, path: "\(componentPath).loadingState"))
            }
            if let errorView = cc.errorState {
                refs.append(contentsOf: walkComponent(errorView, screenId: screenId, path: "\(componentPath).errorState"))
            }
            if let header = cc.defaultSectionHeader {
                refs.append(contentsOf: walkComponent(header, screenId: screenId, path: "\(componentPath).defaultSectionHeader"))
            }
            for (key, header) in cc.sectionHeaders ?? [:] {
                refs.append(contentsOf: walkComponent(header, screenId: screenId, path: "\(componentPath).sectionHeaders[\(key)]"))
            }
        }

        for child in content.children {
            refs.append(contentsOf: walkComponent(child, screenId: screenId, path: componentPath))
        }

        return refs
    }

    /// Extracts screen references from an action.
    private func extractScreenRefs(from action: DSL.Model.Action, screenId: String, path: String) -> [ScreenReference] {
        var refs: [ScreenReference] = []

        if let nextScreen = action.nextScreen {
            refs.append(ScreenReference(
                sourceScreenId: screenId,
                targetScreenId: nextScreen,
                path: "\(path).nextScreen"
            ))
        }

        if action.type == .completeFlow, let destination = action.destination {
            refs.append(ScreenReference(
                sourceScreenId: screenId,
                targetScreenId: destination,
                path: "\(path).destination"
            ))
        }

        return refs
    }

    /// Attempts to extract navigationBar from content via known concrete types.
    /// `navigationBar` isn't on the EntityContent protocol, so we cast through the
    /// concrete content types that declare it.
    private func extractNavigationBar(from content: any DSL.Model.Component.EntityContent) -> DSL.Model.NavigationBar? {
        if let viewContent = content as? DSL.Model.Component.Content<DSL.Model.Component.View.Properties, DSL.Model.Style.View> {
            return viewContent.navigationBar
        }
        if let collectionContent = content as? CollectionContent {
            return collectionContent.navigationBar
        }
        if let mapContent = content as? MapContent {
            return mapContent.navigationBar
        }
        return nil
    }
}
