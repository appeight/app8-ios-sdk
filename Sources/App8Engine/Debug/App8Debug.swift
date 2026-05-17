import UIKit

extension App8 {

    // MARK: - Validation Types

    public struct ValidationResult: Sendable {
        public let isValid: Bool
        public let errors: [ValidationError]
        public let warnings: [ValidationWarning]
    }

    public struct ValidationError: Sendable {
        public let code: String
        public let message: String
        public let path: String?  // JSON path where error occurred
        public let context: [String: String]?  // Extra data for LLM/developer consumption

        public init(code: String, message: String, path: String? = nil, context: [String: String]? = nil) {
            self.code = code
            self.message = message
            self.path = path
            self.context = context
        }
    }

    public struct ValidationWarning: Sendable {
        public let code: String
        public let message: String
        public let path: String?
        public let context: [String: String]?  // Extra data for LLM/developer consumption

        public init(code: String, message: String, path: String? = nil, context: [String: String]? = nil) {
            self.code = code
            self.message = message
            self.path = path
            self.context = context
        }
    }

    public struct ValidationOptions: Sendable {
        public let resolvePointers: Bool  // Whether to validate pointer resolution

        public static let structureOnly = ValidationOptions(resolvePointers: false)
        public static let full = ValidationOptions(resolvePointers: true)
    }

    // MARK: - Debug Protocol

    public protocol DebugProtocol {
        @MainActor func render(styles: [Data], resolveStyles: Bool) async throws -> UIViewController

        // Render by ID
        @MainActor func render(screenId: String) async throws -> UIViewController
        @MainActor func render(componentId: String) async throws -> UIView

        // Render by Data
        @MainActor func render(screenData: Data, resolveStyles: Bool) async throws -> UIViewController
        @MainActor func render(componentData: Data, resolveStyles: Bool) async throws -> UIView

        // Validate full app (uses DataSource internally)
        @MainActor func validateApp(options: ValidationOptions) async throws -> ValidationResult

        // Run full diagnostic report
        @MainActor func runDiagnostics(options: DiagnosticOptions) async -> DiagnosticReport

        // Validate by ID (uses DataSource internally)
        func validate(screenId: String, options: ValidationOptions) async throws -> ValidationResult
        func validate(componentId: String, options: ValidationOptions) async throws -> ValidationResult
        func validateStyles(options: ValidationOptions) async throws -> ValidationResult

        // Validate by Data
        func validate(appData: Data, options: ValidationOptions) async throws -> ValidationResult
        func validate(screenData: Data, options: ValidationOptions) async throws -> ValidationResult
        func validate(componentData: Data, options: ValidationOptions) async throws -> ValidationResult
        func validate(stylesData: [Data], options: ValidationOptions) async throws -> ValidationResult

        // State inspection
        @MainActor func states(componentId: String) async throws -> [String]
        @MainActor func states(componentData: Data) async throws -> [String]
        @MainActor func defaultStateName(componentId: String) async throws -> String?

        // State manipulation (for rendered components)
        @MainActor func setState(_ stateName: String?, forComponentId id: String, animated: Bool)

        // Render logging
        @MainActor func setRenderLogging(enabled: Bool)

        // Constraint monitoring
        /// Installs the stderr tee and starts accumulating constraint violations.
        /// Call once, typically in AppDelegate or at app launch for debug builds.
        @MainActor func setConstraintMonitoring(enabled: Bool)

        /// Runs static diagnostic checks and prints Phase 1 immediately, then switches to live
        /// mode: each AutoLayout constraint violation is printed to the console as it occurs.
        @MainActor func startLiveDiagnostics(options: DiagnosticOptions) async
    }
    
    final class Debug: DebugProtocol {

        private unowned let appInstance: A8
        private let decoder = JSONDecoder()

        init(_ appInstance: A8) {
            self.appInstance = appInstance
        }

        // MARK: - Render Styles

        func render(styles: [Data], resolveStyles: Bool) async throws -> UIViewController {
            let viewModel = DebugStylesViewModel(
                stylesData: styles,
                resolveStyles: resolveStyles,
                dataSource: appInstance.dataSource
            )
            let viewController = DebugStylesViewController()
            viewController.viewModel = viewModel
            return viewController
        }

        // MARK: - Render by ID

        /// Renders a screen by ID, supplying type defaults for missing params.
        func render(screenId: String) async throws -> UIViewController {
            return try await appInstance.renderScreen(
                screenId: screenId,
                options: ScreenRenderOptions(missingParamStrategy: .typeDefaults)
            )
        }

        /// Renders a component by fetching it from DataSource by ID.
        func render(componentId: String) async throws -> UIView {
            guard let dataSource = appInstance.dataSource else {
                throw App8.Error.dataSourceDeallocated
            }

            let componentData = try await dataSource.getComponent(componentId: componentId)
            let styles = try await fetchAndResolveStyles()
            let templateResolver = try await fetchAndResolveTemplates()

            // Merge templates into JSON before decoding
            let preprocessor = TemplatePreprocessor(resolver: templateResolver)
            let processedData = preprocessor.preprocess(componentData) ?? componentData

            var component: DSL.Model.Component.`Any`
            do {
                component = try decoder.decode(DSL.Model.Component.`Any`.self, from: processedData)
            } catch {
                throw App8.Error.componentDecodeFailed(id: componentId, underlying: error)
            }

            component.resolveStylePointers { styles[$0]?.asEntity() }

            guard let service = appInstance.appService else {
                throw App8.Error.serviceNotAvailable
            }

            let container = UIView()
            service.renderComponent(component, superview: container)
            return container
        }

        // MARK: - Render by Data

        func render(screenData: Data, resolveStyles: Bool) async throws -> UIViewController {
            throw App8.Error.notImplemented("render(screenData:resolveStyles:)")
        }

        func render(componentData: Data, resolveStyles: Bool) async throws -> UIView {
            throw App8.Error.notImplemented("render(componentData:resolveStyles:)")
        }

        // MARK: - Validate Full App

        @MainActor
        func validateApp(options: ValidationOptions) async throws -> ValidationResult {
            guard appInstance.dataSource != nil else {
                throw App8.Error.dataSourceDeallocated
            }

            let diagOptions = App8.DiagnosticOptions(
                validateStyles: true,
                validateTemplates: true,
                resolvePointers: options.resolvePointers,
                validateNavigation: true,
                validateVariables: true,
                validateDatasources: false
            )
            let report = await runDiagnostics(options: diagOptions)
            return report.asValidationResult()
        }

        @MainActor
        func runDiagnostics(options: App8.DiagnosticOptions) async -> App8.DiagnosticReport {
            guard let dataSource = appInstance.dataSource else {
                let section = App8.DiagnosticReport.Section(
                    kind: .appModel,
                    label: "App Model",
                    errors: [App8.ValidationError(
                        code: "APP001",
                        message: "Data source is not available (deallocated).",
                        path: nil
                    )]
                )
                return App8.DiagnosticReport(
                    appTitle: nil,
                    bundleId: nil,
                    startFlow: nil,
                    startScreen: nil,
                    timestamp: Date(),
                    sections: [section],
                    summary: App8.DiagnosticReport.Summary(errorCount: 1)
                )
            }

            let engine = DiagnosticEngine(dataSource: dataSource, options: options)
            return await engine.run()
        }

        // MARK: - Validate by ID

        func validate(screenId: String, options: ValidationOptions) async throws -> ValidationResult {
            throw App8.Error.notImplemented("validate(screenId:options:)")
        }

        func validate(componentId: String, options: ValidationOptions) async throws -> ValidationResult {
            throw App8.Error.notImplemented("validate(componentId:options:)")
        }

        func validateStyles(options: ValidationOptions) async throws -> ValidationResult {
            throw App8.Error.notImplemented("validateStyles(options:)")
        }

        // MARK: - Validate by Data

        func validate(appData: Data, options: ValidationOptions) async throws -> ValidationResult {
            throw App8.Error.notImplemented("validate(appData:options:)")
        }

        func validate(screenData: Data, options: ValidationOptions) async throws -> ValidationResult {
            throw App8.Error.notImplemented("validate(screenData:options:)")
        }

        func validate(componentData: Data, options: ValidationOptions) async throws -> ValidationResult {
            throw App8.Error.notImplemented("validate(componentData:options:)")
        }

        func validate(stylesData: [Data], options: ValidationOptions) async throws -> ValidationResult {
            throw App8.Error.notImplemented("validate(stylesData:options:)")
        }

        // MARK: - State Inspection

        @MainActor
        func states(componentId: String) async throws -> [String] {
            guard let dataSource = appInstance.dataSource else {
                throw App8.Error.dataSourceDeallocated
            }

            let componentData = try await dataSource.getComponent(componentId: componentId)
            return try extractStateNames(from: componentData)
        }

        @MainActor
        func states(componentData: Data) async throws -> [String] {
            return try extractStateNames(from: componentData)
        }

        private func extractStateNames(from data: Data) throws -> [String] {
            struct StatesExtractor: Decodable {
                struct Content: Decodable {
                    let states: [String: EmptyDecodable]?
                }
                let content: Content
            }

            struct EmptyDecodable: Decodable {
                init(from decoder: Decoder) throws {
                    _ = try? decoder.singleValueContainer()
                }
            }

            let extractor = try decoder.decode(StatesExtractor.self, from: data)
            return extractor.content.states?.keys.sorted() ?? []
        }

        @MainActor
        func defaultStateName(componentId: String) async throws -> String? {
            guard let dataSource = appInstance.dataSource else {
                throw App8.Error.dataSourceDeallocated
            }

            let componentData = try await dataSource.getComponent(componentId: componentId)
            return try extractDefaultStateName(from: componentData)
        }

        private func extractDefaultStateName(from data: Data) throws -> String? {
            struct DefaultStateExtractor: Decodable {
                struct Content: Decodable {
                    let defaultStateName: String?
                }
                let content: Content
            }

            let extractor = try decoder.decode(DefaultStateExtractor.self, from: data)
            return extractor.content.defaultStateName
        }

        // MARK: - State Manipulation

        @MainActor
        func setState(_ stateName: String?, forComponentId id: String, animated: Bool) {
            guard let service = appInstance.appService else {
                appInstance.context.logger.warning("setState failed: service not available")
                return
            }
            service.componentRegistry.setState(stateName, forComponentId: id, animated: animated)
        }

        // MARK: - Render Logging

        @MainActor
        func setRenderLogging(enabled: Bool) {
            appInstance.appService?.renderLoggingEnabled = enabled
        }

        @MainActor
        func setConstraintMonitoring(enabled: Bool) {
            if enabled { ConstraintMonitor.shared.install() }
        }

        /// Runs static checks (Phase 1) then enables live reporting of subsequent constraint
        /// violations. Call once at launch instead of setConstraintMonitoring + runDiagnostics.
        @MainActor
        func startLiveDiagnostics(options: App8.DiagnosticOptions) async {
            ConstraintMonitor.shared.install()
            ConstraintMonitor.shared.clear()

            let staticOptions = App8.DiagnosticOptions(
                validateStyles: options.validateStyles,
                validateTemplates: options.validateTemplates,
                resolvePointers: options.resolvePointers,
                validateNavigation: options.validateNavigation,
                validateVariables: options.validateVariables,
                validateDatasources: options.validateDatasources,
                includeRuntimeViolations: false
            )
            let report = await runDiagnostics(options: staticOptions)
            let phase1 = report.printableReport()
                .replacingOccurrences(
                    of: "=== End report ===",
                    with: "=== Static checks done. Runtime violations will print as they occur. ==="
                )
            print(phase1)

            ConstraintMonitor.shared.liveReportingEnabled = true
        }

        // MARK: - Private Helpers

        @MainActor
        private func fetchAndResolveStyles() async throws -> [String: DSL.Model.Style.`Any`] {
            guard let dataSource = appInstance.dataSource else {
                throw App8.Error.dataSourceDeallocated
            }

            let stylesData = try await dataSource.getStyles()

            var flatStyleItems: [DSL.Model.Style.`Any`] = stylesData
                .compactMap { data -> [DSL.Model.Style.`Any`]? in
                    return (try? decoder.decode([FailableDecodable<DSL.Model.Style.`Any`>].self, from: data))?.resolve()
                }
                .flatMap { $0 }

            var styles: [String: DSL.Model.Style.`Any`] = flatStyleItems.reduce(into: [:]) { acc, style in
                acc[style.id] = style
            }

            // Resolve style pointers iteratively until no more progress
            var madeProgress = true
            while madeProgress {
                madeProgress = false
                for i in 0..<flatStyleItems.count {
                    let wasResolved = flatStyleItems[i].isResolved()
                    var styleCopy = flatStyleItems[i]
                    styleCopy.resolveStylePointers { styles[$0]?.asEntity() }
                    flatStyleItems[i] = styleCopy
                    styles[styleCopy.id] = styleCopy
                    if !wasResolved && styleCopy.isResolved() {
                        madeProgress = true
                    }
                }
            }

            return styles
        }

        @MainActor
        private func fetchAndResolveTemplates() async throws -> TemplateResolver {
            guard let dataSource = appInstance.dataSource else {
                throw App8.Error.dataSourceDeallocated
            }

            let templatesData = try await dataSource.getComponents()

            let templateItems: [DSL.Model.Component.Template] = templatesData.compactMap { data in
                try? decoder.decode(DSL.Model.Component.Template.self, from: data)
            }

            var resolver = TemplateResolver(templates: templateItems)
            resolver.resolveAllTemplates()

            return resolver
        }
    }
}
