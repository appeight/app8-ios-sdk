import Foundation

/// Hard limits bounding work done on untrusted DSL input — backstops against
/// stack overflow, hangs, and memory exhaustion, set far above any real DSL.
enum EngineLimits {

    static let maxExpressionDepth = 64

    static let maxComponentDepth = 64

    /// Higher than the others: a pure stack-overflow backstop on decode
    /// nesting, not a functional limit.
    static let maxJSONDepth = 512

    static let maxDeepMergeDepth = 256

    static let maxDSLPayloadBytes = 8 * 1024 * 1024

    static let maxArrayVariableCount = 10_000

    static let maxRegexPatternLength = 200
    static let maxRegexInputLength = 10_000

    static let maxImageBytes = 20 * 1024 * 1024
}
