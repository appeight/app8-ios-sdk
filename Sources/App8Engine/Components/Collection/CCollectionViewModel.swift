import UIKit
import Combine

@MainActor
final class CCollectionViewModel: CBaseViewModel<CollectionContent> {

    // MARK: - Types

    struct Section {
        let key: String
        let items: [ItemWrapper]
    }

    struct ItemWrapper {
        let index: Int
        let data: AnyCodableValue
        let templateKey: String?
        /// Section-level template name override (from SectionDefinition.template)
        let sectionTemplate: String?

        init(index: Int, data: AnyCodableValue, templateKey: String?, sectionTemplate: String? = nil) {
            self.index = index
            self.data = data
            self.templateKey = templateKey
            self.sectionTemplate = sectionTemplate
        }
    }

    // MARK: - Published State

    private let sectionsSubject = CurrentValueSubject<[Section], Never>([])
    var sections: AnyPublisher<[Section], Never> {
        sectionsSubject.eraseToAnyPublisher()
    }

    var currentSections: [Section] {
        sectionsSubject.value
    }

    private let isEmptySubject = CurrentValueSubject<Bool, Never>(true)
    var isEmpty: AnyPublisher<Bool, Never> {
        isEmptySubject.eraseToAnyPublisher()
    }

    private let isLoadingSubject = CurrentValueSubject<Bool, Never>(false)
    var isLoading: AnyPublisher<Bool, Never> {
        isLoadingSubject.eraseToAnyPublisher()
    }

    private let errorSubject = CurrentValueSubject<Error?, Never>(nil)
    var error: AnyPublisher<Error?, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    /// Set loading state (can be called from actions)
    func setLoading(_ loading: Bool) {
        isLoadingSubject.send(loading)
        if loading {
            errorSubject.send(nil) // Clear error when loading starts
        }
    }

    /// Set error state (can be called from actions)
    func setError(_ error: Error?) {
        errorSubject.send(error)
        if error != nil {
            isLoadingSubject.send(false) // Stop loading on error
        }
    }

    // MARK: - Private State

    private var dataSubscription: AnyCancellable?
    private var sectionsSubscription: AnyCancellable?
    private var lastDataExpression: String?

    // MARK: - Setup

    override func setup() {
        super.setup()
        observeDataSource()
    }

    // MARK: - Data Source Observation

    private func observeDataSource() {
        if let sectionDefs = component.properties.sectionDefinitions {
            observeStaticSections(sectionDefs)
            return
        }

        if let dataExpression = component.properties.data {
            lastDataExpression = dataExpression
            refreshData()

            dataSubscription = variableStore.anyVariableChanged
                .sink { [weak self] variableName in
                    guard let self = self else { return }
                    if self.expressionMightDependOn(variableName) {
                        self.refreshData()
                    }
                }
        } else {
            sectionsSubject.send([])
            isEmptySubject.send(true)
        }
    }

    /// Observe multiple independent section data sources
    private func observeStaticSections(_ defs: [DSL.Model.Component.Collection.SectionDefinition]) {
        let buildSections: () -> [Section] = { [weak self] in
            guard let self = self else { return [] }
            return defs.compactMap { def in
                let resolved = self.resolveProperty(def.data)
                let rawItems: [AnyCodableValue]
                if let array = resolved as? [Any] {
                    rawItems = array.map { AnyCodableValue(value: $0) }
                } else if let array = resolved as? [AnyCodableValue] {
                    rawItems = array
                } else if let dict = resolved as? [String: Any] {
                    // Single object — wrap in array so it renders as one cell
                    rawItems = [AnyCodableValue(value: dict)]
                } else {
                    rawItems = []
                }
                let wrapped = rawItems.enumerated().map { index, item in
                    ItemWrapper(
                        index: index,
                        data: item,
                        templateKey: self.resolveTemplatKeyForSectionItem(item, sectionDef: def),
                        sectionTemplate: def.templateName
                    )
                }
                return Section(key: def.key, items: wrapped)
            }
        }

        let relevantVars: Set<String> = Set(defs.compactMap { def in
            extractRootVariableName(from: def.data)
        })

        let initial = buildSections()
        sectionsSubject.send(initial)
        isEmptySubject.send(initial.flatMap { $0.items }.isEmpty)

        sectionsSubscription = variableStore.anyVariableChanged
            .filter { variableName in
                // Empty string = reparent signal, always process.
                guard !variableName.isEmpty else { return true }
                // No extracted vars: pass everything through as a safe fallback.
                guard !relevantVars.isEmpty else { return true }
                return relevantVars.contains(variableName)
            }
            .sink { [weak self] _ in
                guard let self = self else { return }
                let updated = buildSections()
                self.sectionsSubject.send(updated)
                self.isEmptySubject.send(updated.flatMap { $0.items }.isEmpty)
            }
    }

    /// Extract root variable name from an expression string.
    /// "{{listings}}" → "listings", "{{item.posts}}" → "item", "listings" → "listings"
    private func extractRootVariableName(from expression: String) -> String? {
        var expr = expression.trimmingCharacters(in: .whitespaces)
        if expr.hasPrefix("{{") && expr.hasSuffix("}}") {
            expr = String(expr.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        guard !expr.isEmpty else { return nil }
        let root = expr.prefix(while: { $0 != "." && $0 != "[" })
        return root.isEmpty ? nil : String(root)
    }

    /// Resolve template key for a section item using the section's templateKey override
    private func resolveTemplatKeyForSectionItem(
        _ item: AnyCodableValue,
        sectionDef: DSL.Model.Component.Collection.SectionDefinition
    ) -> String? {
        // If section defines a templateKey, use it; otherwise fall back to global templateKey
        let keyPath = sectionDef.templateKey ?? component.properties.templateKey
        guard let keyPath = keyPath else { return nil }
        let path = keyPath.replacingOccurrences(of: "item.", with: "")
        guard let value = valueAtKeyPath(item.value, keyPath: path) else { return nil }
        if let str = value as? String { return str }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let num = value as? NSNumber { return num.stringValue }
        return "\(value)"
    }

    /// Check if a variable change might affect the current data expression
    private func expressionMightDependOn(_ variableName: String) -> Bool {
        guard let expression = lastDataExpression else { return false }
        return expression.contains(variableName)
    }

    /// Refresh data from the data source expression
    private func refreshData() {
        guard let dataExpression = component.properties.data else { return }

        let resolved = resolveProperty(dataExpression)

        if let array = resolved as? [Any] {
            let items = array.map { AnyCodableValue(value: $0) }
            updateItems(items)
        } else if let array = resolved as? [AnyCodableValue] {
            updateItems(array)
        } else {
            sectionsSubject.send([])
            isEmptySubject.send(true)
        }
    }

    private func updateItems(_ items: [AnyCodableValue]) {
        let wrapped = items.enumerated().map { index, item in
            ItemWrapper(
                index: index,
                data: item,
                templateKey: resolveTemplateKey(for: item)
            )
        }

        let sections: [Section]
        if let groupBy = component.properties.groupBy {
            sections = groupItems(wrapped, by: groupBy)
        } else {
            sections = [Section(key: "", items: wrapped)]
        }

        sectionsSubject.send(sections)
        isEmptySubject.send(sections.flatMap { $0.items }.isEmpty)
    }

    /// Resolve template key from item data for heterogeneous collections
    private func resolveTemplateKey(for item: AnyCodableValue) -> String? {
        guard let keyPath = component.properties.templateKey else { return nil }

        // templateKey is like "item.type"; extract the path after "item.".
        let path = keyPath.replacingOccurrences(of: "item.", with: "")
        guard let value = valueAtKeyPath(item.value, keyPath: path) else { return nil }
        if let str = value as? String { return str }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let num = value as? NSNumber { return num.stringValue }
        return "\(value)"
    }

    /// Group items by a key expression
    private func groupItems(_ items: [ItemWrapper], by expression: String) -> [Section] {
        var groups: [String: [ItemWrapper]] = [:]
        var groupOrder: [String] = []

        for item in items {
            let key = evaluateGroupKey(expression, item: item)
            if groups[key] == nil {
                groupOrder.append(key)
            }
            groups[key, default: []].append(item)
        }

        return groupOrder.compactMap { key in
            guard let items = groups[key] else { return nil }
            return Section(key: key, items: items)
        }
    }

    /// Evaluate groupBy expression with item context
    private func evaluateGroupKey(_ expression: String, item: ItemWrapper) -> String {
        let cellStore = ScopedVariableStore(parent: variableStore)
        injectItemVariables(into: cellStore, item: item)

        do {
            let context = VariableContext(store: cellStore)
            let propertyResolver = PropertyResolver()
            let result = try propertyResolver.resolveToString(expression, context: context)
            return result
        } catch {
            service.context.logger.error("Failed to evaluate groupBy '\(expression)': \(error)")
            return "unknown"
        }
    }

    // MARK: - Template Resolution

    /// Get the template component for an item
    func resolveTemplate(for item: ItemWrapper) -> DSL.Model.Component.`Any`? {
        // 0. Section-level template override (from SectionDefinition.template)
        // Check local templates dict first, then fall back to global registry
        if let sectionTemplate = item.sectionTemplate {
            if let templates = component.templates, let ref = templates[sectionTemplate] {
                switch ref {
                case .reference(let name): return resolveTemplateByName(name)
                case .inline(let component): return component
                }
            }
            return resolveTemplateByName(sectionTemplate)
        }

        // 1. Single inline template (in content)
        if let inlineTemplate = component.template {
            return inlineTemplate
        }

        // 2. Single template reference (in properties)
        if let templateRef = component.properties.templateName {
            return resolveTemplateByName(templateRef)
        }

        // 3. Heterogeneous templates
        guard let templateKey = item.templateKey,
              let templates = component.templates else {
            return nil
        }

        switch templates[templateKey] {
        case .reference(let ref):
            return resolveTemplateByName(ref)
        case .inline(let component):
            return component
        case .none:
            // Try default template if available
            if let defaultTemplate = templates["default"] {
                switch defaultTemplate {
                case .reference(let ref):
                    return resolveTemplateByName(ref)
                case .inline(let component):
                    return component
                }
            }
            return nil
        }
    }

    /// Resolve a template by name from the app's template registry
    private func resolveTemplateByName(_ name: String) -> DSL.Model.Component.`Any`? {
        return service.resolveTemplate(named: name)
    }

    // MARK: - Cell Variable Store

    /// Create a scoped variable store for a cell with item and index injected
    func createCellVariableStore(for item: ItemWrapper) -> ScopedVariableStore {
        let cellStore = ScopedVariableStore(parent: variableStore)

        // Block scroll offset variable from propagating into cell subtrees.
        // Cells never reference scrollY — it's only used by sibling/ancestor transforms.
        // Without this filter, every scroll frame floods the entire cell tree.
        if let scrollVar = component.properties.scrollOffsetVariable {
            cellStore.setParentPropagationFilter { varName in
                varName != scrollVar
            }
        }

        injectItemVariables(into: cellStore, item: item)
        return cellStore
    }

    /// Inject item and index variables into a cell store
    private func injectItemVariables(into store: ScopedVariableStore, item: ItemWrapper) {
        do {
            // Inject $index into the item dictionary so {{item.$index}} works.
            var itemValue: Any = item.data.value
            if var dict = itemValue as? [String: Any] {
                dict["$index"] = item.index
                itemValue = dict
            }

            let itemType = VariableType.inferType(from: itemValue)
            let itemDefinition = VariableDefinition(type: itemType, initialValue: itemValue)
            try store.defineVariable(name: "item", definition: itemDefinition)
        } catch {
            service.context.logger.error("Failed to inject cell variables: \(error)")
        }
    }

    // MARK: - Swipe Actions

    /// Execute a swipe action for the item at the given index path.
    /// Runs the underlying DSL action in the item's cell variable context
    /// (so the action can read `{{item}}`, `{{item.id}}`, `{{item.$index}}`).
    func handleSwipeAction(at indexPath: IndexPath, action: DSL.Model.Action) {
        guard indexPath.section < currentSections.count else { return }
        let section = currentSections[indexPath.section]
        guard indexPath.item < section.items.count else { return }
        let item = section.items[indexPath.item]

        let cellStore = createCellVariableStore(for: item)
        do {
            let handler = VariableActionHandler()
            try handler.execute(action: action, store: cellStore, context: VariableContext(store: cellStore))
        } catch {
            service.context.logger.error("Failed to execute swipe action: \(error)")
        }
    }

    // MARK: - Selection

    func handleSelection(at indexPath: IndexPath) {
        guard let selection = component.properties.selection,
              selection.mode ?? .none != .none else {
            return
        }

        let section = currentSections[indexPath.section]
        let item = section.items[indexPath.item]

        let itemId = valueAtKeyPath(item.data.value, keyPath: "id")

        // Route through dispatchTrigger so author-declared analytics fire
        // before the actions run. Each action handler still uses the cell-
        // scoped store so `{{item.foo}}` resolves against the tapped row.
        let cellStore = createCellVariableStore(for: item)
        let handler = VariableActionHandler()
        dispatchTrigger(.onItemTap) { action in
            do {
                try handler.execute(action: action, store: cellStore, context: VariableContext(store: cellStore))
            } catch {
                service.context.logger.error("Failed to execute onItemTap action: \(error)")
            }
        }

        if let binding = selection.binding {
            handleSelectionChange(itemId: itemId, binding: binding, mode: selection.mode ?? .single)
        }
    }

    private func handleSelectionChange(itemId: Any?, binding: String, mode: DSL.Model.Component.Collection.Selection.SelectionMode) {
        guard let itemId = itemId else { return }

        // binding is like "{{selectedIds}}"; extract the variable name.
        let varName = binding
            .replacingOccurrences(of: "{{", with: "")
            .replacingOccurrences(of: "}}", with: "")
            .trimmingCharacters(in: .whitespaces)

        switch mode {
        case .single:
            do {
                try variableStore.setValue(name: varName, value: itemId)
            } catch {
                service.context.logger.error("Failed to update selection binding: \(error)")
            }

        case .multiple:
            if var currentSelection = variableStore.getValue(name: varName) as? [Any] {
                if let stringId = itemId as? String {
                    if let index = currentSelection.firstIndex(where: { ($0 as? String) == stringId }) {
                        currentSelection.remove(at: index)
                    } else {
                        currentSelection.append(stringId)
                    }
                } else if let intId = itemId as? Int {
                    if let index = currentSelection.firstIndex(where: { ($0 as? Int) == intId }) {
                        currentSelection.remove(at: index)
                    } else {
                        currentSelection.append(intId)
                    }
                }

                do {
                    try variableStore.setValue(name: varName, value: currentSelection)
                } catch {
                    service.context.logger.error("Failed to update multiple selection: \(error)")
                }
            }

        case .none:
            break
        }
    }

    // MARK: - Actions

    func handleRefresh() {
        dispatchTrigger(.onRefresh) { [self] in executeVariableAction($0) }
    }

    func handleLoadMore() {
        guard let pagination = component.properties.pagination,
              pagination.enabled == true else { return }
        dispatchTrigger(.onLoadMore) { [self] in executeVariableAction($0) }
    }

    // MARK: - Helpers

    /// Access a value at a key path from an Any value (object/dictionary)
    private func valueAtKeyPath(_ value: Any, keyPath: String) -> Any? {
        let keys = keyPath.split(separator: ".").map(String.init)
        var current: Any? = value

        for key in keys {
            if let dict = current as? [String: Any] {
                current = dict[key]
            } else {
                return nil
            }
        }

        return current
    }

    // MARK: - ViewModel Cache

    private var itemViewModels: [String: ComponentViewModelAbstract] = [:]

    /// Create cache key from section and item indices
    private func cacheKey(section: Int, item: Int) -> String {
        "\(section)-\(item)"
    }

    /// Get cached ViewModel for item at indexPath (if exists)
    func getCachedViewModel(section: Int, item: Int) -> ComponentViewModelAbstract? {
        return itemViewModels[cacheKey(section: section, item: item)]
    }

    /// Cache a newly created ViewModel
    func cacheViewModel(_ viewModel: ComponentViewModelAbstract, section: Int, item: Int) {
        itemViewModels[cacheKey(section: section, item: item)] = viewModel
    }

    /// Update item variable in an existing ViewModel's store
    func updateItemVariable(in viewModel: ComponentViewModelAbstract, with item: ItemWrapper) {
        var itemValue: Any = item.data.value
        if var dict = itemValue as? [String: Any] {
            dict["$index"] = item.index
            itemValue = dict
        }
        try? viewModel.variableStore.setValue(name: "item", value: itemValue)
    }

    /// Clear cache when data changes significantly
    func clearViewModelCache() {
        itemViewModels.removeAll()
    }
}
