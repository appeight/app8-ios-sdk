import Foundation

/// Cross-screen navigation validation: nextScreen refs, tab refs, completeFlow destinations, orphan detection.
enum NavigationIntegrityCheck {

    typealias EC = App8.DiagnosticReport.ErrorCode

    static func run(
        references: [ScreenReferenceWalker.ScreenReference],
        loadableScreenIds: Set<String>,
        allKnownScreenIds: Set<String>?,
        app: DSL.Model.App
    ) -> App8.DiagnosticReport.Section {
        var errors: [App8.ValidationError] = []
        var warnings: [App8.ValidationWarning] = []

        let flowIds = Set(app.navigation?.flows.map(\.id) ?? [])

        for ref in references {
            let target = ref.targetScreenId

            // completeFlow destinations may reference flow IDs rather than screens
            if ref.path.contains(".destination") && flowIds.contains(target) {
                continue
            }

            if !loadableScreenIds.contains(target) {
                let suggestions = findSimilar(target, in: loadableScreenIds)
                var message = "Screen reference \"\(target)\" does not exist."
                if !suggestions.isEmpty {
                    message += " Did you mean: \(suggestions.joined(separator: ", "))?"
                }
                message += " Available screens: \(loadableScreenIds.sorted().joined(separator: ", "))."

                let sourceInfo = ref.sourceScreenId.map { "Screen \"\($0)\" → " } ?? ""
                errors.append(App8.ValidationError(
                    code: EC.navScreenRefInvalid,
                    message: "\(sourceInfo)\(message)",
                    path: ref.path,
                    context: [
                        "targetScreen": target,
                        "availableScreens": loadableScreenIds.sorted().joined(separator: ", ")
                    ]
                ))
            }
        }

        // Orphan detection: if the datasource tells us all screen IDs, find unreachable ones
        if let allIds = allKnownScreenIds {
            let reachable = Set(references.map(\.targetScreenId))
            let orphans = allIds.subtracting(reachable)
            for orphan in orphans.sorted() {
                warnings.append(App8.ValidationWarning(
                    code: EC.navOrphanScreen,
                    message: "Screen \"\(orphan)\" exists in the data source but is not reachable from any flow or navigation action. It may be unused.",
                    path: "screens/\(orphan)",
                    context: ["screenId": orphan]
                ))
            }
        }

        let detail = errors.isEmpty ? "all screen references resolve" : "\(errors.count) invalid reference(s)"

        return App8.DiagnosticReport.Section(
            kind: .navigation,
            label: "Navigation",
            errors: errors,
            warnings: warnings,
            statusDetail: detail
        )
    }

    /// Simple edit-distance-based suggestion (Levenshtein distance <= 2).
    private static func findSimilar(_ target: String, in candidates: Set<String>) -> [String] {
        let lowered = target.lowercased()
        return candidates
            .filter { levenshtein(lowered, $0.lowercased()) <= 2 }
            .sorted()
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,      // deletion
                    curr[j - 1] + 1,  // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            prev = curr
        }
        return prev[n]
    }
}
