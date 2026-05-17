import Foundation

/// Extracts JSON code blocks from markdown files
struct MarkdownJSONExtractor {

    enum ExtractionError: Error {
        case fileNotFound(String)
        case readError(String)
    }

    /// Extract all JSON examples from a markdown file
    /// - Parameter filePath: Path to the markdown file
    /// - Returns: Array of extracted examples with their locations
    static func extract(from filePath: String) throws -> [ExtractedExample] {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ExtractionError.fileNotFound(filePath)
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            throw ExtractionError.readError(filePath)
        }

        let fileName = (filePath as NSString).lastPathComponent
        let lines = content.components(separatedBy: .newlines)

        var examples: [ExtractedExample] = []
        var pendingAnnotation: ExtractedExample.Annotation?
        var inJsonBlock = false
        var jsonStartLine = 0
        var jsonContent: [String] = []

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1  // 1-based line numbers

            if let annotation = parseAnnotation(line) {
                pendingAnnotation = annotation
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```json") {
                inJsonBlock = true
                jsonStartLine = lineNumber
                jsonContent = []
                continue
            }

            if inJsonBlock && line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inJsonBlock = false

                let json = jsonContent.joined(separator: "\n")
                let example = ExtractedExample(
                    json: json,
                    location: ExampleLocation(file: fileName, line: jsonStartLine),
                    annotation: pendingAnnotation
                )
                examples.append(example)

                pendingAnnotation = nil
                jsonContent = []
                continue
            }

            if inJsonBlock {
                jsonContent.append(line)
            } else {
                // Clear pending annotation if we hit non-JSON content
                // (annotation should immediately precede the code block)
                if !line.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !line.trimmingCharacters(in: .whitespaces).hasPrefix("<!--") {
                    pendingAnnotation = nil
                }
            }
        }

        return examples
    }

    /// Parse an annotation from an HTML comment line
    private static func parseAnnotation(_ line: String) -> ExtractedExample.Annotation? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("<!--") && trimmed.hasSuffix("-->") else {
            return nil
        }

        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 4)
        let endIndex = trimmed.index(trimmed.endIndex, offsetBy: -3)
        let content = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)

        if content.hasPrefix("@dsl-type:") {
            let typeName = content
                .dropFirst("@dsl-type:".count)
                .trimmingCharacters(in: .whitespaces)
            return .type(typeName)
        }

        if content.hasPrefix("@dsl-skip:") {
            let reason = content
                .dropFirst("@dsl-skip:".count)
                .trimmingCharacters(in: .whitespaces)
            return .skip(reason)
        }

        if content == "@dsl-skip" {
            return .skip("marked to skip")
        }

        return nil
    }
}
