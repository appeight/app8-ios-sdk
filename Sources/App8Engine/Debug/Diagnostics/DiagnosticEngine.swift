import Foundation

/// Main orchestrator: runs all diagnostic checks and assembles the final report.
/// Never throws — all errors are captured into the report sections.
struct DiagnosticEngine {

    private typealias EC = App8.DiagnosticReport.ErrorCode

    private let dataSource: App8DataSource
    private let options: App8.DiagnosticOptions

    init(dataSource: App8DataSource, options: App8.DiagnosticOptions) {
        self.dataSource = dataSource
        self.options = options
    }

    @MainActor
    func run() async -> App8.DiagnosticReport {
        let startTime = CFAbsoluteTimeGetCurrent()
        var sections: [App8.DiagnosticReport.Section] = []
        var stylesLoaded = 0
        var unresolvedStyles = 0
        var templatesLoaded = 0
        var screensChecked = 0
        var screensReachable = 0

        // 1. App Model
        let appResult = await AppModelCheck.run(dataSource: dataSource)
        sections.append(appResult.section)

        guard let app = appResult.app else {
            return buildReport(
                appTitle: nil,
                bundleId: nil,
                startFlow: nil,
                startScreen: nil,
                sections: sections,
                startTime: startTime,
                screensChecked: 0,
                screensReachable: 0,
                stylesLoaded: 0,
                unresolvedStyles: 0,
                templatesLoaded: 0
            )
        }

        // 2. Styles
        var resolvedStyles: [String: DSL.Model.Style.`Any`] = [:]
        if options.validateStyles {
            let stylesResult = await StylesCheck.run(
                dataSource: dataSource,
                resolvePointers: options.resolvePointers
            )
            sections.append(stylesResult.section)
            resolvedStyles = stylesResult.resolvedStyles
            stylesLoaded = resolvedStyles.count
            unresolvedStyles = resolvedStyles.values.filter { !$0.isResolved() }.count
        }

        // 3. Templates
        var templateResolver: TemplateResolver?
        if options.validateTemplates {
            let templatesResult = await TemplatesCheck.run(dataSource: dataSource)
            sections.append(templatesResult.section)
            templateResolver = templatesResult.templateResolver
            templatesLoaded = templateResolver?.resolvedTemplates.count ?? 0
        }

        // 4. Screen Discovery (BFS)
        let walker = ScreenReferenceWalker(dataSource: dataSource, templateResolver: templateResolver)
        let (discoveredScreenIds, references) = await walker.discoverAllScreens(app: app)
        screensReachable = discoveredScreenIds.count

        // 5. Screen Checks
        let screenResult = await ScreenCheck.run(
            screenIds: discoveredScreenIds,
            dataSource: dataSource,
            resolvedStyles: resolvedStyles,
            templateResolver: templateResolver,
            resolvePointers: options.resolvePointers
        )

        // Group screen sections into a single summary section + individual per-screen sections
        let allScreenErrors = screenResult.sections.flatMap(\.errors)
        let allScreenWarnings = screenResult.sections.flatMap(\.warnings)
        screensChecked = discoveredScreenIds.count

        let screenSummary = App8.DiagnosticReport.Section(
            kind: .screens,
            label: "Screens (\(screensChecked) checked)",
            errors: allScreenErrors,
            warnings: allScreenWarnings,
            statusDetail: allScreenErrors.isEmpty && allScreenWarnings.isEmpty
                ? "\(screensChecked) screen(s) decoded successfully"
                : "\(screenResult.failedScreenIds.count) failed to decode"
        )
        sections.append(screenSummary)

        // 6. Navigation Integrity
        if options.validateNavigation {
            let allKnownScreenIds = try? await dataSource.getAllScreenIds()
            let navSection = NavigationIntegrityCheck.run(
                references: references,
                loadableScreenIds: discoveredScreenIds.subtracting(screenResult.failedScreenIds),
                allKnownScreenIds: allKnownScreenIds.flatMap { Set($0) },
                app: app
            )
            sections.append(navSection)
        }

        // 7. Variables
        if options.validateVariables {
            let varSection = await VariablesCheck.run(
                screenIds: discoveredScreenIds,
                dataSource: dataSource,
                templateResolver: templateResolver,
                validateDatasources: options.validateDatasources
            )
            sections.append(varSection)

            // 7b. Variable-write actions (updateVariable target resolution).
            let actionSection = await ActionWriteCheck.run(
                screenIds: discoveredScreenIds,
                dataSource: dataSource,
                templateResolver: templateResolver
            )
            sections.append(actionSection)
        }

        // 8. Runtime violations (if constraint monitoring was active)
        if options.includeRuntimeViolations {
            let allViolations = await ConstraintMonitor.shared.violations
            if !allViolations.isEmpty {
                let isoFormatter = ISO8601DateFormatter()
                let warnings = allViolations.map { v in
                    App8.ValidationWarning(
                        code: EC.layoutConstraintConflict,
                        message: "AutoLayout conflict\(v.screenId.map { " in screen \"\($0)\"" } ?? "")"
                            + (v.brokenConstraint.map { ": broke \($0)" } ?? ""),
                        path: v.screenId.map { "screens/\($0)" },
                        context: [
                            "brokenConstraint": v.brokenConstraint ?? "",
                            "screenId": v.screenId ?? "",
                            "capturedAt": isoFormatter.string(from: v.capturedAt),
                            "rawMessage": v.rawMessage
                        ].compactMapValues { $0.isEmpty ? nil : $0 }
                    )
                }
                sections.append(App8.DiagnosticReport.Section(
                    kind: .runtime,
                    label: "Runtime (\(allViolations.count) constraint violation(s))",
                    errors: [],
                    warnings: warnings
                ))
            }
        }

        return buildReport(
            appTitle: app.title,
            bundleId: app.bundleId,
            startFlow: app.navigation?.startFlow,
            startScreen: app.initialScreenId,
            sections: sections,
            startTime: startTime,
            screensChecked: screensChecked,
            screensReachable: screensReachable,
            stylesLoaded: stylesLoaded,
            unresolvedStyles: unresolvedStyles,
            templatesLoaded: templatesLoaded
        )
    }

    private func buildReport(
        appTitle: String?,
        bundleId: String?,
        startFlow: String?,
        startScreen: String?,
        sections: [App8.DiagnosticReport.Section],
        startTime: CFAbsoluteTime,
        screensChecked: Int,
        screensReachable: Int,
        stylesLoaded: Int,
        unresolvedStyles: Int,
        templatesLoaded: Int
    ) -> App8.DiagnosticReport {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let totalErrors = sections.reduce(0) { $0 + $1.errors.count }
        let totalWarnings = sections.reduce(0) { $0 + $1.warnings.count }

        let summary = App8.DiagnosticReport.Summary(
            screensChecked: screensChecked,
            screensReachable: screensReachable,
            stylesLoaded: stylesLoaded,
            unresolvedStyles: unresolvedStyles,
            templatesLoaded: templatesLoaded,
            errorCount: totalErrors,
            warningCount: totalWarnings,
            duration: duration
        )

        return App8.DiagnosticReport(
            appTitle: appTitle,
            bundleId: bundleId,
            startFlow: startFlow,
            startScreen: startScreen,
            timestamp: Date(),
            sections: sections,
            summary: summary
        )
    }
}
