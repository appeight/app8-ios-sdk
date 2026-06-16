import UIKit

final class App8Service: A8.DataSourceHolder {

    let dataSource: A8.DataSourceProtocol

    let context: App8Context

    /// Registry for cross-component state propagation.
    @MainActor private(set) lazy var componentRegistry: ComponentRegistry = {
        let r = ComponentRegistry()
        r.logger = context.logger
        return r
    }()

    /// App-level variable store — persists across screens.
    @MainActor private(set) lazy var appVariableStore = VariableStore(context: context)

    @MainActor private(set) lazy var imageLoader: ImageLoader = {
        let l = ImageLoader()
        l.logger = context.logger
        return l
    }()

    var renderLoggingEnabled = true

    private var templateResolver: TemplateResolver?

    var styleResolver: ((String) -> (any DSL.Model.Style.Entity)?)?

    /// Set by A8 to merge new style entities into the shared registry when streaming styles arrive.
    var styleRegistryUpdater: (([DSL.Model.Style.`Any`]) -> Void)?

    init(publicDataSource: App8DataSource, context: App8Context) {
        self.dataSource = A8.DataSource(publicDataSource: publicDataSource)
        self.context = context
    }

    /// Called by StreamingSession when style streaming data arrives.
    /// Parses the JSON style array and invokes styleRegistryUpdater.
    func applyStyleUpdate(_ data: Data) {
        guard data.count <= EngineLimits.maxDSLPayloadBytes else {
            context.logger.error("applyStyleUpdate: payload of \(data.count) bytes exceeds limit — ignored")
            return
        }
        let decoder = JSONDecoder()
        decoder.userInfo[.app8Logger] = context.logger
        guard let styles = try? decoder.decode([DSL.Model.Style.`Any`].self, from: data) else { return }
        styleRegistryUpdater?(styles)
    }

    /// Set the template resolver (called by A8 after loading templates)
    func setTemplateResolver(_ resolver: TemplateResolver, styleResolver: @escaping (String) -> (any DSL.Model.Style.Entity)?) {
        self.templateResolver = resolver
        self.styleResolver = styleResolver
    }

    private func logRender(_ componentPath: String, type: DSL.Model.Component.CType) {
        guard renderLoggingEnabled else { return }
        let depth = componentPath.filter({ $0 == "." }).count
        let indent = String(repeating: "  ", count: depth)
        let typeName: String
        switch type {
        case .key(let key): typeName = key.rawValue
        case .custom(let name): typeName = name
        }
        // print("[App8] \(indent)⎿ \(typeName) \"\(componentPath)\"")
    }
}

extension App8Service: ComponentRenderer, ComponentService {

    typealias DSLComponent = DSL.Model.Component
    typealias RenderResult = ComponentRenderResult

    /// Render a screen component, resolving external datasources first.
    @MainActor
    func renderScreen(_ component: DSL.Model.Component.`Any`, screenId: String, params: [String: Any]? = nil, fixedSafeAreaInsets: UIEdgeInsets? = nil) async -> UIViewController {
        guard
            case .key(.screen) = component.type,
            let entity: DSLComponent.View.Entity = component.asConcreteEntity()
        else {
            return renderErrorScreen(errorText: "Precondition failed for screen \(component.id)")
        }

        var resolvedParams = params ?? [:]
        if let variables = entity.content.variables,
           DatasourceResolver.hasExternalDatasources(variables) {
            do {
                let resolvedVariables = try await DatasourceResolver.resolveDatasources(
                    screenId: screenId,
                    variables: variables,
                    dataSource: dataSource
                )
                // Datasource values become the initialValue when CViewModel defines variables.
                for (name, definition) in resolvedVariables where variables[name]?.source != nil {
                    if let value = definition.rawInitialValue {
                        resolvedParams["__datasource_\(name)"] = value
                    }
                }
            } catch {
                context.logger.error("Failed to resolve datasources for screen '\(screenId)': \(error)")
                return renderErrorScreen(errorText: "Failed to load datasources: \(error.localizedDescription)")
            }
        }

        // Resolve preview hints for variables not provided as navigation params.
        // This runs after DatasourceResolver so source-based variables are already handled.
        if let variables = entity.content.variables {
            for (name, definition) in variables {
                guard let preview = definition.preview else { continue }
                guard resolvedParams[name] == nil else { continue }    // already provided via params or datasource
                guard !definition.hasExternalSource else { continue }  // source-based vars handled above

                if let literalValue = preview.value {
                    resolvedParams[name] = literalValue.value
                    context.logger.debug("Screen '\(screenId)': using literal preview value for '\(name)'")
                } else if let sourceId = preview.source {
                    let index = preview.index ?? 0
                    do {
                        context.logger.debug("Screen '\(screenId)': loading preview datasource '\(sourceId)' for '\(name)' (index \(index))")
                        let data = try await dataSource.getDatasource(screenId: screenId, datasourceId: sourceId)
                        guard data.count <= EngineLimits.maxDSLPayloadBytes else {
                            context.logger.error("Screen '\(screenId)': preview datasource '\(sourceId)' payload of \(data.count) bytes exceeds limit. Variable '\(name)' will have no value.")
                            continue
                        }
                        let decoder = JSONDecoder()
                        decoder.userInfo[.app8Logger] = context.logger
                        let datasource = try decoder.decode(DatasourceDefinition.self, from: data)
                        guard let array = datasource.rawData as? [Any] else {
                            context.logger.error("Screen '\(screenId)': preview datasource '\(sourceId)' for '\(name)' is not an array. Variable '\(name)' will have no value.")
                            continue
                        }
                        guard index < array.count else {
                            context.logger.error("Screen '\(screenId)': preview datasource '\(sourceId)' for '\(name)' has \(array.count) item(s) but index \(index) was requested. Variable '\(name)' will have no value.")
                            continue
                        }
                        resolvedParams[name] = array[index]
                        context.logger.debug("Screen '\(screenId)': resolved preview for '\(name)' from '\(sourceId)'[\(index)]")
                    } catch {
                        context.logger.error("Screen '\(screenId)': failed to load preview datasource '\(sourceId)' for '\(name)': \(error). Variable '\(name)' will have no value.")
                    }
                }
            }
        }

        return renderScreenSync(component, screenId: screenId, params: resolvedParams.isEmpty ? nil : resolvedParams, fixedSafeAreaInsets: fixedSafeAreaInsets)
    }

    @MainActor
    func renderScreen(_ component: DSL.Model.Component.`Any`, params: [String: Any]? = nil) -> UIViewController {
        renderScreenSync(component, params: params)
    }

    @MainActor
    private func renderScreenSync(_ component: DSL.Model.Component.`Any`, screenId: String? = nil, params: [String: Any]? = nil, fixedSafeAreaInsets: UIEdgeInsets? = nil) -> UIViewController {
        guard
            case .key(.screen) = component.type,
            let entity: DSLComponent.View.Entity = component.asConcreteEntity()
        else {
            return renderErrorScreen(errorText: "Precondition failed for screen \(component.id)")
        }

        ConstraintMonitor.shared.currentScreenId = screenId

        logRender(component.id, type: component.type)

        let screenVariableStore = ScopedVariableStore(parent: appVariableStore)

        if let params = params {
            context.logger.debug("Screen '\(component.id)' received \(params.count) params")
            for (name, value) in params {
                do {
                    let varType = VariableType.inferType(from: value)
                    let definition = VariableDefinition(type: varType, initialValue: value)
                    try screenVariableStore.defineVariable(name: name, definition: definition)
                    context.logger.debug("Screen param '\(name)': type=\(varType)")
                } catch {
                    context.logger.error("Failed to set screen param '\(name)': \(error)")
                }
            }
        }

        // Warn about variables that declare a schema but have no preview, no source, and
        // were not provided as navigation params. These will silently have no value.
        if let variables = entity.content.variables {
            let providedParamKeys = Set((params ?? [:]).keys)
            for (name, definition) in variables {
                guard definition.schema != nil else { continue }
                guard definition.preview == nil else { continue }
                guard definition.source == nil else { continue }
                guard !providedParamKeys.contains(name) else { continue }
                context.logger.warning("Screen '\(component.id)': variable '\(name)' declares schema '\(definition.schema!)' but was not provided as a navigation param and has no preview or source. It will have no value — either pass it via the push action's 'params' or add a 'preview' to the variable definition.")
            }
        }

        // Use the caller-supplied `screenId` (the alias the host passed to
        // `App8.Instance.renderScreen(screenId:)` or `App8Cloud.Instance.screen(id:)`)
        // as the path root, NOT the DSL document's internal `"id"`. The host
        // only knows the alias they requested — that's the value they pass to
        // `subscribe(onScreen:)` and expect on `event.screenId`. Falls back to
        // the DSL internal id only for callers that don't supply one (e.g.
        // `renderScreen(_:params:)` from preview tooling).
        let screenRootId = screenId ?? component.id
        if let screenId, screenId != component.id {
            context.logger.debug("App8Service: screen alias '\(screenId)' differs from DSL document id '\(component.id)' — events will be stamped with the alias.")
        }
        guard let viewModel = CViewModel(component: entity, service: self, componentPath: screenRootId, parentVariableStore: screenVariableStore)
        else {
            return renderErrorScreen(errorText: "Precondition failed for screen \(component.id)")
        }
        componentRegistry.register(id: screenRootId, viewModel: viewModel)
        viewModel.setComponentTypeKey(DSL.Model.Component.CType.Key.screen.rawValue)

        let navigationBar = entity.content.navigationBar
        let hidesTabBar = entity.content.hidesTabBar ?? false
        let dismissKeyboardOnTap = entity.content.dismissKeyboardOnTap ?? true
        let dslInsets: UIEdgeInsets? = entity.content.additionalSafeAreaInsets.map {
            UIEdgeInsets(top: $0.top ?? 0, left: $0.left ?? 0, bottom: $0.bottom ?? 0, right: $0.right ?? 0)
        }
        let additionalSafeAreaInsets: UIEdgeInsets?
        if let fixed = fixedSafeAreaInsets {
            // NaN/inf would crash Auto Layout.
            func sanitize(_ v: CGFloat) -> CGFloat { v.isFinite ? max(0, v) : 0 }
            let extra = dslInsets ?? .zero
            additionalSafeAreaInsets = UIEdgeInsets(
                top: sanitize(fixed.top) + extra.top,
                left: sanitize(fixed.left) + extra.left,
                bottom: sanitize(fixed.bottom) + extra.bottom,
                right: sanitize(fixed.right) + extra.right
            )
        } else {
            additionalSafeAreaInsets = dslInsets
        }
        let root = ScreenViewController(
            screenId: screenId,
            navigationBar: navigationBar,
            hidesTabBar: hidesTabBar,
            dismissKeyboardOnTap: dismissKeyboardOnTap,
            additionalSafeAreaInsets: additionalSafeAreaInsets,
            titleViewService: self,
            titleViewVariableStore: viewModel.variableStore,
            context: context
        )

        // Trigger viewDidLoad, which sets up rootContainerView.
        _ = root.view

        if context.layoutMode.isEnabled {
            // Clear UIKit's default systemBackground so it doesn't bleed through the
            // semi-transparent layout fill on component views.
            root.view.backgroundColor = UIColor(white: 0.92, alpha: 1)
        } else if let bgString = entity.content.properties.backgroundColor?.value,
                  let color = UIColor(withHexString: viewModel.resolvePropertyToString(bgString)) {
            // Set container background to match screen, avoiding a black gap during streaming swaps.
            root.rootContainerView.backgroundColor = color
        }

        let view = CView()
        view.traitOverrides = root.traitOverrides
        view.configure(viewModel: viewModel, superview: root.rootContainerView, animated: false)

        UIView.performWithoutAnimation { [weak root] in
            root?.view.layoutIfNeeded()
        }

        // Pass viewModel.variableStore (not screenVariableStore) — screen variables
        // are defined in CViewModel's own ScopedVariableStore. setExternalValue propagates
        // UP through parents, so the wrong store means updates silently go nowhere.
        if let screenId = screenId, entity.content.streaming == true {
            context.logger.debug("App8Service: starting streaming for screen '\(screenId)'")
            root.startStreaming(
                screenId: screenId,
                store: viewModel.variableStore,
                component: component,
                currentView: view,
                dataSource: dataSource,
                service: self
            )
        }

        // Snapshot this screen's shared-element participants (registered as its
        // children rendered above) so the transition animator can read them
        // independently of the global registry.
        root.transitionParticipants = componentRegistry.participants(forScreenRoot: screenRootId)

        return root
    }
    
    /// When `reuseViewModel` is provided, it is used instead of creating a new ViewModel.
    @MainActor
    @discardableResult
    func renderComponent(_ component: DSL.Model.Component.`Any`, superview: UIView, parentPath: String? = nil, parentVariableStore: VariableStoreProtocol? = nil, reuseViewModel: ComponentViewModelAbstract? = nil) -> RenderResult {
        let result = renderComponentImpl(component, superview: superview, parentPath: parentPath, parentVariableStore: parentVariableStore, reuseViewModel: reuseViewModel)
        // Register a shared-element transition participant when the component
        // declares an element context on `content.transition`. Done once here
        // (not per render-site) using the same `view` every site already builds.
        if let element = component.elementTransition {
            let path = parentPath.map { "\($0).\(component.id)" } ?? component.id
            let screenRoot = String(path.split(separator: ".").first ?? Substring(path))
            componentRegistry.registerParticipant(screenRoot: screenRoot, key: element.key, view: result.view, config: element)
        }
        return result
    }

    @MainActor
    @discardableResult
    private func renderComponentImpl(_ component: DSL.Model.Component.`Any`, superview: UIView, parentPath: String? = nil, parentVariableStore: VariableStoreProtocol? = nil, reuseViewModel: ComponentViewModelAbstract? = nil) -> RenderResult {
        guard case .key(let type) = component.type else {
            // Custom component types are not renderable yet.
            return RenderResult(view: renderErrorView(), type: .key(.view))
        }

        let componentPath = parentPath.map { "\($0).\(component.id)" } ?? component.id

        logRender(componentPath, type: component.type)

        func errorResult() -> RenderResult {
            RenderResult(view: renderErrorView(), type: component.type)
        }

        // Stop recursing past the depth backstop — deep DSL would stack-overflow.
        let renderDepth = componentPath.filter { $0 == "." }.count
        guard renderDepth <= EngineLimits.maxComponentDepth else {
            context.logger.error("Component nesting exceeds \(EngineLimits.maxComponentDepth) at '\(componentPath)' — rendering error view")
            return errorResult()
        }

        switch type {
        case .view:
            let viewModel: CViewModel
            if let reuse = reuseViewModel as? CViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.View.Entity = component.asConcreteEntity(),
                    let newVM = CViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .image:
            let viewModel: CImageViewModel
            if let reuse = reuseViewModel as? CImageViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Image.Entity = component.asConcreteEntity(),
                    let newVM = CImageViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CImageView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .video:
            let viewModel: CVideoViewModel
            if let reuse = reuseViewModel as? CVideoViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Video.Entity = component.asConcreteEntity(),
                    let newVM = CVideoViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CVideoView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .icon:
            let viewModel: CIconViewModel
            if let reuse = reuseViewModel as? CIconViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Icon.Entity = component.asConcreteEntity(),
                    let newVM = CIconViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CIconView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .shape:
            let viewModel: CShapeViewModel
            if let reuse = reuseViewModel as? CShapeViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Shape.Entity = component.asConcreteEntity(),
                    let newVM = CShapeViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CShapeView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .label:
            let viewModel: CLabelViewModel
            if let reuse = reuseViewModel as? CLabelViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Label.Entity = component.asConcreteEntity(),
                    let newVM = CLabelViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CLabelView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .button:
            let viewModel: CButtonViewModel
            if let reuse = reuseViewModel as? CButtonViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Button.Entity = component.asConcreteEntity(),
                    let newVM = CButtonViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CButtonView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .scrollView:
            let viewModel: CScrollViewViewModel
            if let reuse = reuseViewModel as? CScrollViewViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.ScrollView.Entity = component.asConcreteEntity(),
                    let newVM = CScrollViewViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CScrollViewView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .collection:
            let viewModel: CCollectionViewModel
            if let reuse = reuseViewModel as? CCollectionViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Collection.Entity = component.asConcreteEntity(),
                    let newVM = CCollectionViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CCollectionView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .map:
            let viewModel: CMapViewModel
            if let reuse = reuseViewModel as? CMapViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Map.Entity = component.asConcreteEntity(),
                    let newVM = CMapViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CMapView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .textField:
            let viewModel: CTextFieldViewModel
            if let reuse = reuseViewModel as? CTextFieldViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.TextField.Entity = component.asConcreteEntity(),
                    let newVM = CTextFieldViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CTextFieldView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .textView:
            let viewModel: CTextViewViewModel
            if let reuse = reuseViewModel as? CTextViewViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.TextView.Entity = component.asConcreteEntity(),
                    let newVM = CTextViewViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CTextViewView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .stackView:
            let viewModel: CStackViewViewModel
            if let reuse = reuseViewModel as? CStackViewViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.StackView.Entity = component.asConcreteEntity(),
                    let newVM = CStackViewViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CStackViewView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .tableView:
            let viewModel: CTableViewViewModel
            if let reuse = reuseViewModel as? CTableViewViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.TableView.Entity = component.asConcreteEntity(),
                    let newVM = CTableViewViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CTableViewView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .activityIndicator:
            let viewModel: CActivityIndicatorViewModel
            if let reuse = reuseViewModel as? CActivityIndicatorViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.ActivityIndicator.Entity = component.asConcreteEntity(),
                    let newVM = CActivityIndicatorViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CActivityIndicatorView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .toggle:
            let viewModel: CToggleViewModel
            if let reuse = reuseViewModel as? CToggleViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Toggle.Entity = component.asConcreteEntity(),
                    let newVM = CToggleViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CToggleView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .slider:
            let viewModel: CSliderViewModel
            if let reuse = reuseViewModel as? CSliderViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Slider.Entity = component.asConcreteEntity(),
                    let newVM = CSliderViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CSliderView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .pageControl:
            let viewModel: CPageControlViewModel
            if let reuse = reuseViewModel as? CPageControlViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.PageControl.Entity = component.asConcreteEntity(),
                    let newVM = CPageControlViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CPageControlView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .picker:
            let viewModel: CPickerViewModel
            if let reuse = reuseViewModel as? CPickerViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Picker.Entity = component.asConcreteEntity(),
                    let newVM = CPickerViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CPickerView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .datePicker:
            let viewModel: CDatePickerViewModel
            if let reuse = reuseViewModel as? CDatePickerViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.DatePicker.Entity = component.asConcreteEntity(),
                    let newVM = CDatePickerViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CDatePickerView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        case .shimmer:
            let viewModel: CShimmerViewModel
            if let reuse = reuseViewModel as? CShimmerViewModel {
                viewModel = reuse
            } else {
                guard
                    let entity: DSLComponent.Shimmer.Entity = component.asConcreteEntity(),
                    let newVM = CShimmerViewModel(component: entity, service: self, componentPath: componentPath, parentVariableStore: parentVariableStore)
                else {
                    return errorResult()
                }
                viewModel = newVM
                componentRegistry.register(id: componentPath, viewModel: viewModel)
                viewModel.setComponentTypeKey(type.rawValue)
            }
            let view = CShimmerView()
            view.accessibilityIdentifier = component.id
            componentRegistry.viewRegistry.register(id: componentPath, view: view)
            superview.addSubview(view)
            view.configure(viewModel: viewModel, superview: superview, animated: false)
            return .init(view: view, type: component.type, viewModel: viewModel)

        default:
            return errorResult()
        }
    }

    @MainActor
    func renderErrorScreen(errorText: String) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = errorText
        vc.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)
        ])
        return vc
    }
    
    @MainActor
    func renderErrorView() -> UIView {
        let view = UIView()
        view.backgroundColor = .red
        return view
    }

    /// Resolve a template by name from the app's template registry.
    @MainActor
    func resolveTemplate(named name: String) -> DSL.Model.Component.`Any`? {
        guard let resolver = templateResolver,
              let contentValue = resolver.resolvedTemplates[name],
              let componentType = resolver.getTemplateType(name) else {
            context.logger.error("Template '\(name)' not found")
            return nil
        }

        // resolvedTemplates stores only the content portion; reconstruct the full component.
        let fullComponent: JSONValue = .object([
            "type": componentType.jsonValue,
            "id": .string(name),
            "content": contentValue
        ])

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(fullComponent)
            let decoder = JSONDecoder()
            decoder.userInfo[.app8Logger] = context.logger
            var component = try decoder.decode(DSL.Model.Component.`Any`.self, from: data)

            if let styleResolver = styleResolver {
                component.resolveStylePointers(resolver: styleResolver)
            }

            return component
        } catch {
            context.logger.error("Failed to decode template '\(name)': \(error)")
            return nil
        }
    }
}
