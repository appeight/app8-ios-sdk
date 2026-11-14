//
//  ExpressionDependencies.swift
//  App8Engine
//

import Foundation

/// Variable names that property strings read, so a view can re-resolve only
/// when one of them changes (not on every scroll-offset write).
enum ExpressionDependencies {

    /// Root variable names read by the `{{…}}` expressions in `strings`, or nil
    /// when one cannot be parsed (the caller then reacts to every change).
    static func names(in strings: [String?]) -> Set<String>? {
        var result = Set<String>()
        let parser = ExpressionParser()
        let extractor = DependencyExtractor()
        for case let string? in strings where string.contains("{{") {
            var rest = Substring(string)
            while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
                let expression = String(rest[open.lowerBound..<close.upperBound])
                guard let node = try? parser.parse(expression) else { return nil }
                result.formUnion(extractor.extractDependencies(from: node))
                rest = rest[close.upperBound...]
            }
        }
        return result
    }
}
