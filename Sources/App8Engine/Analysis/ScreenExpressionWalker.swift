//
//  ScreenExpressionWalker.swift
//  App8Engine
//

import Foundation

/// Walks raw JSON data to find all `{{expression}}` references and extract root variable names.
/// Operates on raw JSON (via JSONSerialization) to avoid needing full DSL model decoding.
struct ScreenExpressionWalker {

    private let parser = ExpressionParser()
    private let extractor = DependencyExtractor()

    /// Extract all root variable names referenced via `{{...}}` in any string value within the JSON.
    func extractReferencedVariables(from data: Data) -> Set<String> {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var variables = Set<String>()
        walkValue(json, into: &variables)
        return variables
    }

    // MARK: - Private

    private func walkValue(_ value: Any, into variables: inout Set<String>) {
        switch value {
        case let string as String:
            extractFromString(string, into: &variables)

        case let array as [Any]:
            for element in array {
                walkValue(element, into: &variables)
            }

        case let dict as [String: Any]:
            for (_, v) in dict {
                walkValue(v, into: &variables)
            }

        default:
            break
        }
    }

    /// Scans a string for `{{...}}` patterns and extracts root variable names from each.
    private func extractFromString(_ string: String, into variables: inout Set<String>) {
        var searchStart = string.startIndex

        while searchStart < string.endIndex {
            guard let openRange = string.range(of: "{{", range: searchStart..<string.endIndex) else {
                break
            }
            guard let closeRange = string.range(of: "}}", range: openRange.upperBound..<string.endIndex) else {
                break
            }

            let expressionBody = String(string[openRange.lowerBound..<closeRange.upperBound])

            if let node = try? parser.parse(expressionBody) {
                let deps = extractor.extractDependencies(from: node)
                variables.formUnion(deps)
            }

            searchStart = closeRange.upperBound
        }
    }
}
