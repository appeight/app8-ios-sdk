import Foundation

// MARK: - Diagnostic Options

extension App8 {

    public struct DiagnosticOptions: Sendable {
        public let validateStyles: Bool
        public let validateTemplates: Bool
        public let resolvePointers: Bool
        public let validateNavigation: Bool
        public let validateVariables: Bool
        public let validateDatasources: Bool
        public let includeRuntimeViolations: Bool

        public init(
            validateStyles: Bool = true,
            validateTemplates: Bool = true,
            resolvePointers: Bool = true,
            validateNavigation: Bool = true,
            validateVariables: Bool = true,
            validateDatasources: Bool = true,
            includeRuntimeViolations: Bool = true
        ) {
            self.validateStyles = validateStyles
            self.validateTemplates = validateTemplates
            self.resolvePointers = resolvePointers
            self.validateNavigation = validateNavigation
            self.validateVariables = validateVariables
            self.validateDatasources = validateDatasources
            self.includeRuntimeViolations = includeRuntimeViolations
        }

        /// Quick check: app model + screen decoding only
        public static let quick = DiagnosticOptions(
            validateStyles: false,
            validateTemplates: false,
            resolvePointers: false,
            validateNavigation: true,
            validateVariables: false,
            validateDatasources: false,
            includeRuntimeViolations: true
        )

        /// Standard check: all checks enabled
        public static let standard = DiagnosticOptions(
            validateStyles: true,
            validateTemplates: true,
            resolvePointers: true,
            validateNavigation: true,
            validateVariables: true,
            validateDatasources: true,
            includeRuntimeViolations: true
        )

        /// Exhaustive: all checks enabled
        public static let exhaustive = DiagnosticOptions(
            validateStyles: true,
            validateTemplates: true,
            resolvePointers: true,
            validateNavigation: true,
            validateVariables: true,
            validateDatasources: true,
            includeRuntimeViolations: true
        )
    }
}

// MARK: - Diagnostic Report

extension App8 {

    public struct DiagnosticReport: Sendable {
        public let appTitle: String?
        public let bundleId: String?
        public let startFlow: String?
        public let startScreen: String?
        public let timestamp: Date
        public let sections: [Section]
        public let summary: Summary

        public var isHealthy: Bool { summary.errorCount == 0 }

        /// Convert to the existing ValidationResult type for backward compatibility
        public func asValidationResult() -> ValidationResult {
            let allErrors = sections.flatMap { $0.errors }
            let allWarnings = sections.flatMap { $0.warnings }
            return ValidationResult(
                isValid: isHealthy,
                errors: allErrors,
                warnings: allWarnings
            )
        }

        /// Produces a human- and LLM-readable markdown report
        public func printableReport() -> String {
            var lines: [String] = []

            lines.append("\n\n\n# App8 Diagnostic Report")
            lines.append("**App:** \"\(appTitle ?? "Unknown")\"")
            if let bundleId = bundleId {
                lines.append("**Bundle ID:** \(bundleId)")
            }
            if let startFlow = startFlow {
                lines.append("**Start Flow:** \(startFlow)")
            }
            if let startScreen = startScreen {
                lines.append("**Start Screen:** \(startScreen)")
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            lines.append("**Date:** \(formatter.string(from: timestamp))")
            lines.append("**Duration:** \(String(format: "%.2fs", summary.duration))")

            if isHealthy {
                lines.append("**Status:** HEALTHY (0 errors, \(summary.warningCount) warning\(summary.warningCount == 1 ? "" : "s"))")
            } else {
                lines.append("**Status:** NOT HEALTHY (\(summary.errorCount) error\(summary.errorCount == 1 ? "" : "s"), \(summary.warningCount) warning\(summary.warningCount == 1 ? "" : "s"))")
            }
            lines.append("")

            for section in sections {
                lines.append("## \(section.label)")

                if section.errors.isEmpty && section.warnings.isEmpty {
                    var statusLine = "Status: OK"
                    if let detail = section.statusDetail {
                        statusLine += " — \(detail)"
                    }
                    lines.append(statusLine)
                } else {
                    if let detail = section.statusDetail {
                        lines.append("Info: \(detail)")
                    }
                    for error in section.errors {
                        let pathStr = error.path.map { "`\($0)` " } ?? ""
                        lines.append("- ERROR [\(error.code)]: \(pathStr)\(error.message)")
                    }
                    for warning in section.warnings {
                        let pathStr = warning.path.map { "`\($0)` " } ?? ""
                        lines.append("- WARNING [\(warning.code)]: \(pathStr)\(warning.message)")
                    }
                }
                lines.append("")
            }

            // Summary table
            lines.append("## Summary")
            lines.append("| Metric | Value |")
            lines.append("|--------|-------|")
            lines.append("| Screens checked | \(summary.screensChecked) |")
            lines.append("| Screens reachable | \(summary.screensReachable) |")
            lines.append("| Styles loaded | \(summary.stylesLoaded) |")
            lines.append("| Unresolved styles | \(summary.unresolvedStyles) |")
            lines.append("| Templates loaded | \(summary.templatesLoaded) |")
            lines.append("| Errors | \(summary.errorCount) |")
            lines.append("| Warnings | \(summary.warningCount) |")
            lines.append("=== End report ===\n\n\n\n")

            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - Section

extension App8.DiagnosticReport {

    public struct Section: Sendable {
        public let kind: Kind
        public let label: String
        public let errors: [App8.ValidationError]
        public let warnings: [App8.ValidationWarning]
        /// Additional detail for the status line (e.g., "12 styles loaded")
        public let statusDetail: String?

        public enum Kind: String, Sendable {
            case appModel
            case styles
            case templates
            case screens
            case navigation
            case variables
            case actions   // variable-write actions (updateVariable et al.)
            case runtime   // runtime-captured issues (e.g. constraint conflicts)
        }

        public init(
            kind: Kind,
            label: String,
            errors: [App8.ValidationError] = [],
            warnings: [App8.ValidationWarning] = [],
            statusDetail: String? = nil
        ) {
            self.kind = kind
            self.label = label
            self.errors = errors
            self.warnings = warnings
            self.statusDetail = statusDetail
        }
    }
}

// MARK: - Summary

extension App8.DiagnosticReport {

    public struct Summary: Sendable {
        public let screensChecked: Int
        public let screensReachable: Int
        public let stylesLoaded: Int
        public let unresolvedStyles: Int
        public let templatesLoaded: Int
        public let errorCount: Int
        public let warningCount: Int
        public let duration: TimeInterval

        public init(
            screensChecked: Int = 0,
            screensReachable: Int = 0,
            stylesLoaded: Int = 0,
            unresolvedStyles: Int = 0,
            templatesLoaded: Int = 0,
            errorCount: Int = 0,
            warningCount: Int = 0,
            duration: TimeInterval = 0
        ) {
            self.screensChecked = screensChecked
            self.screensReachable = screensReachable
            self.stylesLoaded = stylesLoaded
            self.unresolvedStyles = unresolvedStyles
            self.templatesLoaded = templatesLoaded
            self.errorCount = errorCount
            self.warningCount = warningCount
            self.duration = duration
        }
    }
}

// MARK: - Error Codes

extension App8.DiagnosticReport {

    /// Error code constants
    enum ErrorCode {
        // App Model
        static let appLoadFailed = "APP001"
        static let appDecodeFailed = "APP002"
        static let appMissingStartFlow = "APP003"
        static let appFlowMissingStartScreen = "APP004"

        // Styles
        static let styleDecodeFailed = "STY001"
        static let styleUnresolvedPointer = "STY002"
        static let styleDuplicateId = "STY003"

        // Templates
        static let templateDecodeFailed = "TPL001"
        static let templateUnresolvedInheritance = "TPL002"

        // Screens
        static let screenLoadFailed = "SCR001"
        static let screenDecodeFailed = "SCR002"
        static let screenInvalidType = "SCR003"
        static let screenStyleUnresolved = "SCR004"
        static let screenChildDecodeFailed = "SCR005"

        // Navigation
        static let navScreenRefInvalid = "NAV001"
        static let navTabRefInvalid = "NAV002"
        static let navCompleteFlowInvalid = "NAV003"
        static let navOrphanScreen = "NAV004"

        // Variables
        static let varTypeMismatch = "VAR001"
        static let varExpressionInvalid = "VAR002"
        static let varDatasourceUnreachable = "VAR003"
        static let varSchemaMissingPreview = "VAR004"
        static let varPreviewAmbiguous = "VAR005"

        // Collections
        static let collectionMissingTemplates = "COL001"
        static let collectionMissingTemplateKey = "COL002"

        // Actions / variable writes
        static let actionWriteParentScope = "ACT001"
        static let actionWriteUndeclared = "ACT002"

        // Scroll layout
        static let scrollContentUnanchored = "SCL001"

        // Layout (runtime)
        static let layoutConstraintConflict = "LAY001"
    }
}
