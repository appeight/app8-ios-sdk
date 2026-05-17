//
//  ScreenAnalysis.swift
//  App8Engine
//

import Foundation

// MARK: - Screen Analysis Result

/// Result of static analysis of a screen's variable dependencies
public struct ScreenAnalysis: Sendable {
    public let screenId: String
    public let declaredVariables: [DeclaredVariable]
    public let requiredParams: [RequiredParam]

    public var isSelfSufficient: Bool { requiredParams.isEmpty }

    /// A variable declared within the screen's own JSON
    public struct DeclaredVariable: Sendable {
        public let name: String
        public let type: String
        public let source: VariableSource

        public enum VariableSource: Sendable {
            case initialValue
            case datasource(id: String)
            case computed(expression: String)
        }
    }

    /// A variable referenced in expressions but not declared locally
    public struct RequiredParam: Sendable {
        public let name: String
        public let inferredType: String?
    }
}

// MARK: - Screen Render Options

/// Options for independent screen rendering
public struct ScreenRenderOptions: @unchecked Sendable {
    public let params: [String: Any]?
    public let missingParamStrategy: MissingParamStrategy
    public let size: CGSize?

    public enum MissingParamStrategy: Sendable {
        case strict       // fail if any required params are missing
        case typeDefaults  // empty string, 0, [], {} for missing params
        case deriveSample  // cross-screen analysis to get realistic data
    }

    public init(
        params: [String: Any]? = nil,
        missingParamStrategy: MissingParamStrategy = .typeDefaults,
        size: CGSize? = nil
    ) {
        self.params = params
        self.missingParamStrategy = missingParamStrategy
        self.size = size
    }
}

// MARK: - Screen Manifest Entry

/// A single entry in the full screen manifest
public struct ScreenManifestEntry: Sendable {
    public let screenId: String
    public let analysis: ScreenAnalysis
}
