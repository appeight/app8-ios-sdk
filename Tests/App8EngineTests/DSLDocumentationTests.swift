//
//  DSLDocumentationTests.swift
//  App8Engine
//
//  Validates that JSON examples in documentation can be decoded by the DSL parser.
//

import Foundation
import Testing
@testable import App8Engine

@Suite("DSL Documentation Tests")
struct DSLDocumentationTests {

    // MARK: - Configuration

    private static let expectedFiles = [
        "actions.md",
        "collections.md",
        "components.md",
        "index.md",
        "layout.md",
        "navigation.md",
        "states.md",
        "styles.md",
        "templates.md",
        "variables.md"
    ]

    // MARK: - Tests

    @Test("All expected documentation files exist")
    func allDocumentationFilesExist() throws {
        guard let docsDirectory = Self.resolveDocsDirectory() else {
            Issue.record("Could not locate docs/dsl directory")
            return
        }

        let actualFiles = try FileManager.default.contentsOfDirectory(atPath: docsDirectory)
            .filter { $0.hasSuffix(".md") }
            .sorted()

        for expected in Self.expectedFiles {
            #expect(actualFiles.contains(expected), "Missing expected documentation file: \(expected)")
        }
    }

    @Test("Documentation JSON examples are valid")
    func documentationExamplesAreValid() throws {
        guard let docsDirectory = Self.resolveDocsDirectory() else {
            Issue.record("Could not locate docs/dsl directory from test file")
            return
        }

        let markdownFiles = try Self.discoverMarkdownFiles(in: docsDirectory)
        guard !markdownFiles.isEmpty else {
            Issue.record("No markdown files found in \(docsDirectory)")
            return
        }

        var passed: [(ExampleLocation, String)] = []
        var skipped: [(ExampleLocation, String)] = []
        var failures: [(ExampleLocation, Error)] = []

        for filePath in markdownFiles {
            let examples: [ExtractedExample]
            do {
                examples = try MarkdownJSONExtractor.extract(from: filePath)
            } catch {
                Issue.record("Failed to extract examples from \(filePath): \(error)")
                continue
            }

            for example in examples {
                switch DSLExampleValidator.validate(example) {
                case .success(let decodedAs):
                    passed.append((example.location, decodedAs))
                case .skipped(let reason):
                    skipped.append((example.location, reason))
                case .failed(let error):
                    failures.append((example.location, error))
                }
            }
        }

        Self.printSummary(
            filesScanned: markdownFiles.count,
            passed: passed,
            skipped: skipped,
            failures: failures
        )

        for (location, error) in failures {
            Issue.record("Documentation example failed at \(location): \(error)")
        }
    }

    // MARK: - Helpers

    private static func resolveDocsDirectory() -> String? {
        let testFilePath = #filePath
        let testFileURL = URL(fileURLWithPath: testFilePath)

        // Navigate: Tests/App8EngineTests/DSLDocumentationTests.swift -> docs/dsl/
        let packageRoot = testFileURL
            .deletingLastPathComponent()  // Remove filename
            .deletingLastPathComponent()  // Remove App8EngineTests
            .deletingLastPathComponent()  // Remove Tests

        let docsDirectory = packageRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("dsl")

        let path = docsDirectory.path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func discoverMarkdownFiles(in directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { "\(directory)/\($0)" }
    }

    private static func printSummary(
        filesScanned: Int,
        passed: [(ExampleLocation, String)],
        skipped: [(ExampleLocation, String)],
        failures: [(ExampleLocation, Error)]
    ) {
        var report = """
        === Documentation Examples Test ===
        Files scanned: \(filesScanned)
        Passed: \(passed.count)
        Skipped: \(skipped.count)
        Failed: \(failures.count)
        """

        if !passed.isEmpty {
            report += "\n\n--- Passed Examples ---"
            let groupedByType = Dictionary(grouping: passed) { $0.1 }
            for (typeName, items) in groupedByType.sorted(by: { $0.key < $1.key }) {
                report += "\n  \(typeName): \(items.count) example(s)"
            }
        }

        if !skipped.isEmpty {
            report += "\n\n--- Skipped Examples ---"
            let groupedByReason = Dictionary(grouping: skipped) { $0.1 }
            for (reason, items) in groupedByReason.sorted(by: { $0.key < $1.key }) {
                report += "\n  \(reason): \(items.count) example(s)"
                for (location, _) in items.prefix(10) {
                    report += "\n    - \(location)"
                }
                if items.count > 10 {
                    report += "\n    ... and \(items.count - 10) more"
                }
            }
        }

        if !failures.isEmpty {
            report += "\n\n--- Failed Examples ---"
            for (location, error) in failures {
                report += "\n  \(location): \(error)"
            }
        }

        print(report)

        // Only record as an issue on failure, to keep passing runs quiet.
        if !failures.isEmpty {
            Issue.record(Comment(rawValue: report))
        }
    }
}
