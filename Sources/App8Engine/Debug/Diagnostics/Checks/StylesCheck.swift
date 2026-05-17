import Foundation

/// Validates stylesheets: decoding, multi-pass pointer resolution, duplicate IDs.
enum StylesCheck {

    typealias EC = App8.DiagnosticReport.ErrorCode

    struct Result {
        let section: App8.DiagnosticReport.Section
        let resolvedStyles: [String: DSL.Model.Style.`Any`]
    }

    static func run(dataSource: App8DataSource, resolvePointers: Bool) async -> Result {
        var errors: [App8.ValidationError] = []
        var warnings: [App8.ValidationWarning] = []

        let stylesData: [Data]
        do {
            stylesData = try await dataSource.getStyles()
        } catch {
            errors.append(App8.ValidationError(
                code: EC.styleDecodeFailed,
                message: "Failed to load styles from data source: \(error.localizedDescription).",
                path: "styles",
                context: ["error": "\(error)"]
            ))
            return Result(
                section: .init(kind: .styles, label: "Styles", errors: errors, warnings: warnings),
                resolvedStyles: [:]
            )
        }

        let decoder = JSONDecoder()
        var flatStyleItems: [DSL.Model.Style.`Any`] = []
        var decodeFailures = 0

        for (i, data) in stylesData.enumerated() {
            // Pre-parse raw JSON so style names can be surfaced in decode error messages
            let rawItems = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []

            do {
                let items = try decoder.decode([FailableDecodable<DSL.Model.Style.`Any`>].self, from: data)
                let (resolved, itemErrors) = items.resolveWithErrors()
                for (itemIndex, itemError) in itemErrors {
                    decodeFailures += 1
                    let detail = [FailableDecodable<DSL.Model.Style.`Any`>].formatDecodingError(itemError)
                    let styleName = (itemIndex < rawItems.count ? rawItems[itemIndex]["id"] as? String : nil)
                        .map { " '\($0)'" } ?? ""
                    warnings.append(App8.ValidationWarning(
                        code: EC.styleDecodeFailed,
                        message: "Style item \(itemIndex)\(styleName) in stylesheet \(i) failed to decode: \(detail)",
                        path: "styles[\(i)][\(itemIndex)]",
                        context: ["error": "\(itemError)", "stylesheetIndex": "\(i)", "itemIndex": "\(itemIndex)"]
                    ))
                }
                flatStyleItems.append(contentsOf: resolved)
            } catch {
                decodeFailures += 1
                errors.append(App8.ValidationError(
                    code: EC.styleDecodeFailed,
                    message: "Failed to decode stylesheet \(i): \(error.localizedDescription). Check the JSON structure.",
                    path: "styles[\(i)]",
                    context: ["error": "\(error)"]
                ))
            }
        }

        var seenIds = Set<String>()
        for style in flatStyleItems {
            if seenIds.contains(style.id) {
                warnings.append(App8.ValidationWarning(
                    code: EC.styleDuplicateId,
                    message: "Duplicate style ID \"\(style.id)\". The last definition will be used. Remove or rename the duplicate.",
                    path: "styles > \(style.id)",
                    context: ["styleId": style.id]
                ))
            }
            seenIds.insert(style.id)
        }

        var styles: [String: DSL.Model.Style.`Any`] = flatStyleItems.reduce(into: [:]) { acc, style in
            acc[style.id] = style
        }

        // Multi-pass: pointers may reference styles that themselves resolve in a later pass
        var unresolvedCount = 0
        if resolvePointers {
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

            for style in flatStyleItems {
                let unresolvedIds = style.unresolvedPointerIds()
                guard !unresolvedIds.isEmpty else { continue }
                unresolvedCount += 1
                let unresolvedDetail = unresolvedIds.map { "\"\($0)\"" }.joined(separator: ", ")
                warnings.append(App8.ValidationWarning(
                    code: EC.styleUnresolvedPointer,
                    message: "Style \"\(style.id)\" has unresolved pointer(s): \(unresolvedDetail). These referenced styles may be missing or have a type mismatch.",
                    path: "styles > \(style.id)",
                    context: [
                        "styleId": style.id,
                        "unresolvedPointers": unresolvedIds.joined(separator: ", ")
                    ]
                ))
            }
        }

        let detail = "\(flatStyleItems.count) styles loaded" +
            (resolvePointers ? ", \(unresolvedCount) unresolved pointer(s)" : "") +
            (decodeFailures > 0 ? ", \(decodeFailures) decode failure(s)" : "")

        let section = App8.DiagnosticReport.Section(
            kind: .styles,
            label: "Styles",
            errors: errors,
            warnings: warnings,
            statusDetail: detail
        )
        return Result(section: section, resolvedStyles: styles)
    }
}
