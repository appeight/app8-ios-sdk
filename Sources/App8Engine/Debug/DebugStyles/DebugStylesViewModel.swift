import Foundation
import Combine

// MARK: - Style Models

struct StylePairWithContent {
    let original: DSL.Model.Style.`Any`
    let resolved: DSL.Model.Style.`Any`
}

// MARK: - View Model Protocol

@MainActor
protocol DebugStylesViewModelProtocol {
    var sections: [[DebugStyleItemViewModelProtocol]] { get }
}

@MainActor
final class DebugStylesViewModel: DebugStylesViewModelProtocol {

    let sections: [[DebugStyleItemViewModelProtocol]]

    // MARK: - Publishers

    let onJsonTapped = PassthroughSubject<(styleId: String, styleType: String, json: String), Never>()

    private(set) weak var dataSource: App8DataSource?
    private let decoder = JSONDecoder()
    private weak var logger: A8Log?

    init(stylesData: [Data], resolveStyles: Bool, dataSource: App8DataSource?, logger: A8Log? = nil) {
        self.logger = logger
        typealias Section = [Result<StylePairWithContent, Error>]
        var decodedSections: [Section] = []

        // Decode each Data into styles, capturing errors
        for (index, data) in stylesData.enumerated() {
            guard let _ = String(data: data, encoding: .utf8) else {
                logger?.warning("stylesheet at index \(index): invalid UTF-8 data")
                decodedSections.append([.failure(NSError(domain: "DebugStyles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 data"]))])
                continue
            }

            do {
                let styles = try decoder.decode([FailableDecodable<DSL.Model.Style.`Any`>].self, from: data)
                var section: Section = []
                for style in styles {
                    if let value = style.base {
                        section.append(.success(StylePairWithContent(original: value, resolved: value)))
                    } else if let error = style.decodingError {
                        section.append(.failure(error))
                    }
                }
                decodedSections.append(section)
            } catch {
                logger?.warning("stylesheet at index \(index): failed to decode - \(error)")
                decodedSections.append([.failure(error)])
            }
        }

        let finalSections: [Section]
        if resolveStyles {
            let allSuccessfulStyles = decodedSections.flatMap { section in
                section.compactMap { result -> DSL.Model.Style.`Any`? in
                    if case .success(let pair) = result {
                        return pair.original
                    }
                    return nil
                }
            }
            let stylesDict = allSuccessfulStyles.reduce(into: [String: DSL.Model.Style.`Any`]()) { acc, style in
                acc[style.id] = style
            }

            finalSections = decodedSections.map { section in
                section.map { result in
                    guard case .success(let pair) = result else {
                        return result
                    }

                    var resolved = pair.original
                    resolved.resolveStylePointers { id in
                        return stylesDict[id]?.asEntity()
                    }

                    return .success(StylePairWithContent(original: pair.original, resolved: resolved))
                }
            }
        } else {
            finalSections = decodedSections
        }

        self.sections = Self.buildSections(
            sections: finalSections,
            stylesData: stylesData,
            withResolution: resolveStyles
        )
    }

    // MARK: - Helpers

    private static func buildSections(
        sections: [[Result<StylePairWithContent, Error>]],
        stylesData: [Data],
        withResolution: Bool
    ) -> [[DebugStyleItemViewModelProtocol]] {
        return sections.enumerated().map { sectionIndex, section in
            section.map { result in
                switch result {
                case .success(let pair):
                    if withResolution, pair.resolved.asEntity().isNotNil {
                        return ResolvedStyleItemViewModel(
                            original: pair.original,
                            resolved: pair.resolved
                        ) as DebugStyleItemViewModelProtocol
                    } else {
                        return SingleStyleItemViewModel(style: pair.resolved) as DebugStyleItemViewModelProtocol
                    }

                case .failure(let error):
                    let jsonString = String(data: stylesData[sectionIndex], encoding: .utf8) ?? "Invalid data"
                    return ErrorStyleItemViewModel(
                        errorMessage: error.localizedDescription,
                        jsonData: jsonString
                    ) as DebugStyleItemViewModelProtocol
                }
            }
        }
    }

    /// Legacy initializer kept for backward compatibility.
    init(styleItems: [[DSL.Model.Style.`Any`]], resolveStyles: Bool = false) {
        self.sections = styleItems.map { sectionStyles in
            sectionStyles.map { style in
                SingleStyleItemViewModel(style: style) as DebugStyleItemViewModelProtocol
            }
        }
    }
}
