//
//  DeepMerge.swift
//  App8Engine
//

import Foundation

/// Deep merge two JSONValue dictionaries.
///
/// Merge rules:
/// 1. Objects are recursively merged (keys from override take precedence)
/// 2. Arrays named "children" are merged by matching element "id" fields
/// 3. Other arrays are REPLACED, not merged
/// 4. Primitives (string, number, bool, null) are REPLACED
func deepMerge(base: [String: JSONValue], override: JSONValue, depth: Int = 0) -> [String: JSONValue] {
    guard case .object(let overrideObj) = override else {
        return base
    }
    guard depth < EngineLimits.maxDeepMergeDepth else { return base }

    var result = base

    for (key, overrideValue) in overrideObj {
        if let baseValue = result[key] {
            switch (baseValue, overrideValue) {
            case (.object(let baseObj), .object(_)):
                result[key] = .object(deepMerge(base: baseObj, override: overrideValue, depth: depth + 1))
            case (.array(let baseArr), .array(let overrideArr)) where key == "children":
                result[key] = .array(mergeChildrenArrays(base: baseArr, override: overrideArr, depth: depth + 1))
            default:
                // Replace: arrays, primitives, or type mismatch.
                result[key] = overrideValue
            }
        } else {
            result[key] = overrideValue
        }
    }

    return result
}

/// Merge two children arrays by matching elements by their "id" field.
/// Override elements with matching ids are deep merged with base elements.
/// Override elements without matching ids are appended.
private func mergeChildrenArrays(base: [JSONValue], override: [JSONValue], depth: Int = 0) -> [JSONValue] {
    var result = base

    for overrideElement in override {
        guard case .object(let overrideObj) = overrideElement,
              case .string(let overrideId) = overrideObj["id"] else {
            result.append(overrideElement)
            continue
        }

        if let matchIndex = result.firstIndex(where: { element in
            guard case .object(let baseObj) = element,
                  case .string(let baseId) = baseObj["id"] else {
                return false
            }
            return baseId == overrideId
        }) {
            result[matchIndex] = deepMerge(base: result[matchIndex], override: overrideElement, depth: depth + 1)
        } else {
            result.append(overrideElement)
        }
    }

    return result
}

/// Convenience overload that accepts two JSONValue objects
func deepMerge(base: JSONValue, override: JSONValue, depth: Int = 0) -> JSONValue {
    guard case .object(let baseObj) = base else {
        // Non-object base: override wins.
        return override
    }
    return .object(deepMerge(base: baseObj, override: override, depth: depth))
}
