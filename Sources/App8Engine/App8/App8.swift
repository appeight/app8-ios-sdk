import Foundation
import Combine
import UIKit

// MARK: - App8

/// Main façade. Framework API
public struct App8 {
    
    @MainActor
    public static func instance(dataSource: App8DataSource) -> App8.Instance {
        return A8(dataSource: dataSource)
    }
    
    @MainActor
    public static func debugInstance(dataSource: App8DataSource) -> App8.DebugInstance {
        return A8(dataSource: dataSource)
    }
}

/// Conforms to `App8.DebugInstance`, `App8.Instance`
@MainActor
final class A8: App8.DebugInstance {

    typealias Error = App8.Error

    /// Strong reference - A8 instance owns its data source for its lifetime
    private(set) var dataSource: App8DataSource?

    let context: App8Context

    init(dataSource: App8DataSource) {
        let context = App8Context()
        self.context = context
        self.dataSource = dataSource
        self.decoder = JSONDecoder()
        self.decoder.userInfo[.app8Logger] = context.logger
        appService = App8Service(publicDataSource: dataSource, context: context)
    }

    private(set) var app: DSL.Model.App? {
        didSet { appSubject.send(app) }
    }

    /// Publishes the decoded app once available, then subsequent updates.
    public var appPublisher: AnyPublisher<DSL.Model.App, Never> {
        appSubject.compactMap { $0 }.eraseToAnyPublisher()
    }
    private let appSubject = CurrentValueSubject<DSL.Model.App?, Never>(nil)

    var logLevel: A8Log.Level {
        get { context.logger.level }
        set { context.logger.level = newValue }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        get { context.appearance.userInterfaceStyle }
        set { context.appearance.userInterfaceStyle = newValue }
    }

    var layoutModeEnabled: Bool {
        get { context.layoutMode.isEnabled }
        set { context.layoutMode.isEnabled = newValue }
    }

    var layoutModeShowsLabels: Bool {
        get { context.layoutMode.showLabels }
        set { context.layoutMode.showLabels = newValue }
    }

    func setLocale(_ locale: String?) {
        context.translationStore.setActive(locale)
    }

    var currentLocale: String {
        context.translationStore.activeLocale
    }

    /// Publishes the currently visible screen context within the navigation hierarchy
    public var screenContext: AnyPublisher<App8.ScreenContext, Never> {
        guard let coordinator = flowCoordinator else {
            return Empty().eraseToAnyPublisher()
        }
        return coordinator.screenContext
    }

    private(set) var styles: [String: DSL.Model.Style.`Any`] = [:]

    /// [animationId : Animation.Inline]. Built from `DSL.Model.App.animations`; consumed at
    /// screen decode time via `decoder.userInfo[.app8AnimationResolver]` so
    /// `{ "id": "..." }` references in screen JSON resolve to inline form.
    private(set) var animationsById: [String: DSL.Model.Animation.Inline] = [:]

    private(set) var templateResolver: TemplateResolver?

    private(set) var initialScreen: DSL.Model.Component.`Any`?

    /// Deduplicate concurrent prefetch/startApp.
    private var inFlightReadyTask: Task<Void, Swift.Error>?

    private(set) var appService: App8Service?

    private var flowCoordinator: FlowCoordinator?

    private let decoder: JSONDecoder

    private(set) lazy var debug: App8.DebugProtocol = App8.Debug(self)
    
    /// Fetches and caches: app model, all declared stylesheets, and the initial screen.
    /// Safe to call multiple times; concurrent calls coalesce.
    public func prefetch() async throws {
        try await awaitReady()
    }

    /// Waits for readiness and returns the initial root view controller.
    public func startApp() async throws -> UIViewController {
        try await awaitReady()

        guard let app, let appService else {
            throw Error.appInitFailed
        }

        let root = App8RootViewController(app: app, context: context)

        // Create and start the flow coordinator
        let coordinator = FlowCoordinator(app: app, screenLoader: self, appService: appService, context: context)
        self.flowCoordinator = coordinator

        do {
            let flowVC = try await coordinator.start()
            root.embedFlow(flowVC)
        } catch {
            return appService.renderErrorScreen(errorText: "Failed to start app: \(error.localizedDescription)")
        }

        return root
    }

    /// Stop the app and clean up resources
    public func stopApp() {
        flowCoordinator?.stop()
        flowCoordinator = nil
    }

    private var infrastructureReady = false

    /// Deduplicate concurrent infrastructure loading.
    private var inFlightInfraTask: Task<Void, Swift.Error>?

    /// Loads app model, styles, and templates without requiring initialScreenId.
    /// Safe to call multiple times; concurrent calls coalesce.
    func ensureInfrastructureReady() async throws {
        if infrastructureReady { return }

        if let t = inFlightInfraTask {
            try await t.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { throw Self.Error.dataSourceDeallocated }
            guard let ds = self.dataSource else { throw Self.Error.dataSourceDeallocated }

            if self.app == nil {
                let appData = try await ds.getApp()
                if let appJson = String(data: appData, encoding: .utf8) {
                    context.logger.debug("App8: raw app.json = \(appJson)")
                }
                guard String(data: appData, encoding: .utf8) != nil else {
                    throw Self.Error.invalidUTF8("app.json")
                }
                do {
                    let model = try self.decoder.decode(DSL.Model.App.self, from: appData)
                    self.app = model
                    // Pointer-only entries would self-reference and are skipped (inlineOrNil → nil).
                    let registry: [String: DSL.Model.Animation.Inline] = (model.animations ?? [])
                        .reduce(into: [:]) { acc, entry in
                            if let inline = entry.inlineOrNil, let key = inline.id {
                                acc[key] = inline
                            }
                        }
                    self.animationsById = registry
                    self.decoder.userInfo[.app8AnimationResolver] = { @Sendable (id: String) -> DSL.Model.Animation.Inline? in
                        registry[id]
                    }
                } catch {
                    throw Self.Error.appDecodeFailed(underlying: error)
                }
            }

            if self.styles.isEmpty {
                let stylesData = try await ds.getStyles()
                var flatStyleItems: [DSL.Model.Style.`Any`] = stylesData.enumerated()
                    .compactMap { i, data -> [DSL.Model.Style.`Any`]? in
                        guard String(data: data, encoding: .utf8) != nil else {
                            return []
                        }
                        return (try? self.decoder.decode([FailableDecodable<DSL.Model.Style.`Any`>].self, from: data))?.resolve()
                    }
                    .flatMap { $0 }

                var styleItemsDict: [String: DSL.Model.Style.`Any`] = flatStyleItems.reduce(into: [:]) { acc, style in
                    acc[style.id] = style
                }
                var madeProgress = true
                while madeProgress {
                    madeProgress = false
                    for i in 0 ..< flatStyleItems.count {
                        let wasResolved = flatStyleItems[i].isResolved()
                        var itemCopy = flatStyleItems[i]
                        itemCopy.resolveStylePointers { id in
                            return styleItemsDict[id]?.asEntity()
                        }
                        flatStyleItems[i] = itemCopy
                        styleItemsDict[itemCopy.id] = itemCopy
                        if !wasResolved && itemCopy.isResolved() {
                            madeProgress = true
                        }
                    }
                }
                self.styles = styleItemsDict
            }

            // Load translations once at boot — before any screen renders so
            // i18n keys resolve immediately instead of flashing as raw keys.
            // Errors are non-fatal: a failed fetch leaves the store empty
            // (keys render as debug placeholders) but doesn't block infra.
            do {
                let translationsData = try await ds.getTranslations()
                let bundle = try JSONDecoder().decode(TranslationStore.Bundle.self, from: translationsData)
                self.context.translationStore.load(
                    defaultLocale: bundle.defaultLocale,
                    locales: bundle.locales
                )
                let localeList = bundle.locales.keys.sorted().joined(separator: ",")
                context.logger.debug("App8: loaded translations — defaultLocale=\(bundle.defaultLocale), locales=\(localeList)")
            } catch {
                context.logger.warning("App8: getTranslations failed — \(error). i18n keys will render as debug placeholders.")
            }

            if self.templateResolver == nil {
                let componentsData = try await ds.getComponents()
                let templateItems: [DSL.Model.Component.Template] = componentsData.compactMap { data in
                    do {
                        return try self.decoder.decode(DSL.Model.Component.Template.self, from: data)
                    } catch {
                        context.logger.warning("Failed to decode component template: \(error)")
                        return nil
                    }
                }
                var resolver = TemplateResolver(templates: templateItems)
                resolver.resolveAllTemplates()
                self.templateResolver = resolver

                self.appService?.setTemplateResolver(resolver, styleResolver: self.resolveStylePointer)

                // Lets StreamingSession push style changes at runtime.
                self.appService?.styleRegistryUpdater = { [weak self] newStyles in
                    MainActor.assumeIsolated { self?.mergeStyles(newStyles) }
                }
            }

            self.infrastructureReady = true
        }

        inFlightInfraTask = task
        do {
            try await task.value
        } catch {
            inFlightInfraTask = nil
            throw error
        }
    }

    /// Ensures app, stylesheets, and initial screen are loaded.
    private func awaitReady() async throws {
        try await ensureInfrastructureReady()

        if let t = inFlightReadyTask {
            try await t.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { throw Self.Error.dataSourceDeallocated }
            guard let ds = self.dataSource else { throw Self.Error.dataSourceDeallocated }

            guard let app = self.app else { throw Self.Error.appDecodeFailed(underlying: NSError(domain: "App8", code: -1)) }
            guard let initialScreenId = app.initialScreenId, !initialScreenId.isEmpty else {
                context.logger.error("appMissingInitialScreenId — app: title=\(app.title ?? "nil"), navigation=\(app.navigation.map { "startFlow=\($0.startFlow), flows=[\($0.flows.map(\.id).joined(separator: ", "))]" } ?? "nil")")
                throw Self.Error.appMissingInitialScreenId
            }

            if self.initialScreen == nil {
                let screenData = try await ds.getScreen(screenId: initialScreenId)
                guard String(data: screenData, encoding: .utf8) != nil else {
                    throw Self.Error.invalidUTF8("\(initialScreenId).json")
                }
                do {
                    let screen = try self.decodeComponent(screenData, as: DSL.Model.Component.`Any`.self)
                    self.initialScreen = screen
                } catch {
                    throw Self.Error.screenDecodeFailed(id: initialScreenId, underlying: error)
                }
            }
        }

        inFlightReadyTask = task
        do {
            try await task.value
        } catch {
            inFlightReadyTask = nil
            throw error
        }
    }
    
    private func decodeComponent<T: Decodable>(_ data: Data, as type: T.Type) throws -> DSL.Model.Component.`Any` {
        // Merge templates before decoding.
        let processedData: Data
        if let resolver = templateResolver {
            let preprocessor = TemplatePreprocessor(resolver: resolver)
            processedData = preprocessor.preprocess(data) ?? data
        } else {
            processedData = data
        }

        var component = try self.decoder.decode(DSL.Model.Component.`Any`.self, from: processedData)
        component.resolveStylePointers(resolver: resolveStylePointer)
        return component
    }

    private func resolveStylePointer(styleId: String) -> (any DSL.Model.Style.Entity)? {
        return styles[styleId]?.asEntity()
    }

    /// Merges new style entities into the live registry, then re-runs multi-pass resolution
    /// so transitive changes (e.g. color → fill → material) propagate automatically.
    private func mergeStyles(_ newStyles: [DSL.Model.Style.`Any`]) {
        // Insert in raw (pointer) form so re-resolution can propagate changes.
        for style in newStyles {
            styles[style.id] = style
        }
        var madeProgress = true
        while madeProgress {
            madeProgress = false
            for key in styles.keys {
                guard var style = styles[key] else { continue }
                let wasResolved = style.isResolved()
                style.resolveStylePointers { [weak self] id in self?.styles[id]?.asEntity() }
                styles[key] = style
                if !wasResolved && style.isResolved() { madeProgress = true }
            }
        }
    }
}

// MARK: - Asset reference discovery

extension A8 {

    public func collectAssetReferences(screenId: String) async throws -> App8.AssetReferenceSet {
        try await ensureInfrastructureReady()
        let component = try await loadScreen(id: screenId)
        let collector = AssetReferenceCollector(fontAssetResolver: makeFontAssetResolver())
        return collector.collect(component: component)
    }

    public func collectAllAssetReferences() async throws -> App8.AssetReferenceSet {
        try await ensureInfrastructureReady()
        guard let app = self.app else {
            throw Error.appInitFailed
        }
        let collector = AssetReferenceCollector(fontAssetResolver: makeFontAssetResolver())
        return await collector.collectForApp(app) { [weak self] screenId in
            guard let self else { throw Error.dataSourceDeallocated }
            return try await self.loadScreen(id: screenId)
        }
    }

    public func discoverAllReachableScreenIds() async throws -> [String] {
        try await ensureInfrastructureReady()
        guard let app = self.app, let dataSource = self.dataSource else {
            throw Error.appInitFailed
        }
        // Reuse the diagnostic-side walker so prefetch coverage matches what
        // diagnostics treat as reachable.
        let walker = ScreenReferenceWalker(
            dataSource: dataSource,
            templateResolver: templateResolver
        )
        let (ids, _) = await walker.discoverAllScreens(app: app)
        return Array(ids)
    }

    /// Build a PostScript-name → `DSL.Model.Asset` lookup over the
    /// engine's currently-decoded style entities. Used by the collector
    /// to populate `FontReference.asset` when a screen references a font
    /// by `text.fontFamily` (or `font.family.displayName`) and there's a
    /// matching `Font.Family.Face` in the style sheet.
    ///
    /// Snapshotted at call time — subsequent style merges don't affect
    /// the returned closure's results.
    private func makeFontAssetResolver() -> @Sendable (String) -> DSL.Model.Asset? {
        var mutableIndex: [String: DSL.Model.Asset] = [:]
        for styleAny in self.styles.values {
            guard let entity: DSL.Model.Style.ConcreteEntity<DSL.Model.Style.Font> = styleAny.asConcreteEntity()
            else { continue }
            let family = entity.content.family
            for face in family.faces ?? [] {
                if mutableIndex[face.postScriptName] == nil {
                    mutableIndex[face.postScriptName] = face.asset
                }
            }
            // A Font without faces but with a top-level `family.asset` is still a
            // downloadable font file, keyed by displayName.
            let facesEmpty = (family.faces?.isEmpty ?? true)
            if facesEmpty,
               let asset = family.asset,
               mutableIndex[family.displayName] == nil {
                mutableIndex[family.displayName] = asset
            }
        }
        let index = mutableIndex
        return { postScriptName in index[postScriptName] }
    }
}

extension A8: ScreenLoaderProtocol {

    /// Load and decode a screen by its ID
    func loadScreen(id: String) async throws -> DSL.Model.Component.`Any` {
        guard let ds = dataSource else {
            throw Error.dataSourceDeallocated
        }

        let screenData = try await ds.getScreen(screenId: id)

        guard String(data: screenData, encoding: .utf8) != nil else {
            throw Error.invalidUTF8("\(id).json")
        }

        do {
            let screen = try decodeComponent(screenData, as: DSL.Model.Component.`Any`.self)
            return screen
        } catch {
            throw Error.screenDecodeFailed(id: id, underlying: error)
        }
    }
}

// MARK: - Independent Screen Rendering

extension A8 {

    /// Render a screen independently, outside the normal app flow.
    func renderScreen(screenId: String, options: ScreenRenderOptions) async throws -> UIViewController {
        try await renderScreenInternal(screenId: screenId, options: options, fixedSafeAreaInsets: nil)
    }

    func renderScreen(screenId: String, options: ScreenRenderOptions,
                      fixedSafeAreaInsets: UIEdgeInsets) async throws -> UIViewController {
        try await renderScreenInternal(screenId: screenId, options: options,
                                       fixedSafeAreaInsets: fixedSafeAreaInsets)
    }

    private func renderScreenInternal(screenId: String, options: ScreenRenderOptions,
                                      fixedSafeAreaInsets: UIEdgeInsets?) async throws -> UIViewController {
        try await ensureInfrastructureReady()

        guard let appService else {
            throw Error.serviceNotAvailable
        }

        let component = try await loadScreen(id: screenId)
        let analysis = try await performAnalysis(screenId: screenId)

        var finalParams = options.params ?? [:]

        // Resolve preview hints before the missing-param strategy runs, so preview-supplied
        // values are treated as provided and don't get overwritten by type defaults.
        if let entity: DSL.Model.Component.View.Entity = component.asConcreteEntity(),
           let variables = entity.content.variables {
            var resolvedPreviewNames: [String] = []
            for (name, definition) in variables {
                guard let preview = definition.preview, finalParams[name] == nil else { continue }

                if let literalValue = preview.value {
                    finalParams[name] = literalValue.value
                    resolvedPreviewNames.append(name)
                } else if let sourceId = preview.source {
                    guard let ds = dataSource else {
                        context.logger.error("Screen '\(screenId)': preview for '\(name)' requires datasource '\(sourceId)' but no dataSource is registered on App8. Variable '\(name)' will have no value.")
                        continue
                    }
                    let index = preview.index ?? 0
                    do {
                        context.logger.debug("Screen '\(screenId)': loading preview datasource '\(sourceId)' for '\(name)' (index \(index))")
                        let data = try await ds.getDatasource(screenId: screenId, datasourceId: sourceId)
                        let datasource = try self.decoder.decode(DatasourceDefinition.self, from: data)
                        guard let array = datasource.rawData as? [Any] else {
                            context.logger.error("Screen '\(screenId)': preview datasource '\(sourceId)' for '\(name)' is not an array — check datasource format. Variable '\(name)' will have no value.")
                            continue
                        }
                        guard index < array.count else {
                            context.logger.error("Screen '\(screenId)': preview datasource '\(sourceId)' for '\(name)' has \(array.count) item(s) but index \(index) was requested. Variable '\(name)' will have no value.")
                            continue
                        }
                        finalParams[name] = array[index]
                        resolvedPreviewNames.append(name)
                    } catch {
                        context.logger.error("Screen '\(screenId)': failed to load preview datasource '\(sourceId)' for '\(name)': \(error). Variable '\(name)' will have no value.")
                    }
                }
            }
            if !resolvedPreviewNames.isEmpty {
                context.logger.debug("Screen '\(screenId)': resolved \(resolvedPreviewNames.count) preview param(s): \(resolvedPreviewNames.sorted().joined(separator: ", "))")
            }
        }

        let missingParams = analysis.requiredParams.filter { !finalParams.keys.contains($0.name) }

        if !missingParams.isEmpty {
            switch options.missingParamStrategy {
            case .strict:
                throw Error.missingRequiredParams(missingParams.map(\.name))

            case .typeDefaults:
                for param in missingParams {
                    let type = VariableType(rawValue: param.inferredType ?? "string") ?? .string
                    finalParams[param.name] = type.defaultValue()
                }

            case .deriveSample:
                guard let ds = dataSource else {
                    throw Error.dataSourceDeallocated
                }
                let deriver = SampleDataDeriver(dataSource: ds, templateResolver: templateResolver)
                let sampleData = await deriver.deriveSampleData(
                    forScreen: screenId,
                    requiredParams: missingParams
                )
                for (name, value) in sampleData {
                    if finalParams[name] == nil {
                        finalParams[name] = value
                    }
                }
                // Fall back to type defaults for anything still missing
                let stillMissing = missingParams.filter { finalParams[$0.name] == nil }
                for param in stillMissing {
                    let type = VariableType(rawValue: param.inferredType ?? "string") ?? .string
                    finalParams[param.name] = type.defaultValue()
                }
            }
        }

        return await appService.renderScreen(
            component,
            screenId: screenId,
            params: finalParams.isEmpty ? nil : finalParams,
            fixedSafeAreaInsets: fixedSafeAreaInsets
        )
    }

    /// Render a screen and capture it as a UIImage.
    func screenshotScreen(screenId: String, options: ScreenRenderOptions) async throws -> UIImage {
        let viewController = try await renderScreen(screenId: screenId, options: options)

        let size = options.size ?? CGSize(width: 390, height: 844)

        // Offscreen window needed for blur/vibrancy to render.
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = viewController
        window.isHidden = false
        window.makeKeyAndVisible()

        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        window.isHidden = true
        window.rootViewController = nil

        return image
    }

    /// Analyze a screen's variable dependencies.
    func analyzeScreen(screenId: String) async throws -> ScreenAnalysis {
        try await ensureInfrastructureReady()
        return try await performAnalysis(screenId: screenId)
    }

    /// Get analysis for all screens in the app.
    func getAllScreenManifest() async throws -> [ScreenManifestEntry] {
        try await ensureInfrastructureReady()

        guard let ds = dataSource else {
            throw Error.dataSourceDeallocated
        }

        guard let screenIds = try await ds.getAllScreenIds() else {
            return []
        }

        var entries: [ScreenManifestEntry] = []
        for screenId in screenIds {
            do {
                let analysis = try await performAnalysis(screenId: screenId)
                entries.append(ScreenManifestEntry(screenId: screenId, analysis: analysis))
            } catch {
                context.logger.warning("Failed to analyze screen '\(screenId)': \(error)")
            }
        }

        return entries
    }

    // MARK: - Private Analysis

    /// Perform static analysis on a screen by loading its raw JSON and running the analyzer.
    private func performAnalysis(screenId: String) async throws -> ScreenAnalysis {
        guard let ds = dataSource else {
            throw Error.dataSourceDeallocated
        }

        let screenData: Data
        do {
            screenData = try await ds.getScreen(screenId: screenId)
        } catch {
            throw Error.screenNotFound(screenId)
        }

        // Preprocess templates so expressions inside expanded templates are found.
        let processedData: Data
        if let resolver = templateResolver {
            let preprocessor = TemplatePreprocessor(resolver: resolver)
            processedData = preprocessor.preprocess(screenData) ?? screenData
        } else {
            processedData = screenData
        }

        let analyzer = ScreenAnalyzer()
        return analyzer.analyze(screenData: processedData, screenId: screenId)
    }
}
