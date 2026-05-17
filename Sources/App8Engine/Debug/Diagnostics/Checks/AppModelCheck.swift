import Foundation

/// Validates the app.json model: loading, decoding, startFlow + flow startScreens.
enum AppModelCheck {

    typealias EC = App8.DiagnosticReport.ErrorCode

    struct Result {
        let section: App8.DiagnosticReport.Section
        let app: DSL.Model.App?
    }

    static func run(dataSource: App8DataSource) async -> Result {
        var errors: [App8.ValidationError] = []
        var warnings: [App8.ValidationWarning] = []

        let appData: Data
        do {
            appData = try await dataSource.getApp()
        } catch {
            errors.append(App8.ValidationError(
                code: EC.appLoadFailed,
                message: "Failed to load app.json: \(error.localizedDescription). Ensure the data source provides a valid app configuration.",
                path: "app.json",
                context: ["error": "\(error)"]
            ))
            return Result(
                section: .init(kind: .appModel, label: "App Model", errors: errors, warnings: warnings),
                app: nil
            )
        }

        let app: DSL.Model.App
        do {
            app = try JSONDecoder().decode(DSL.Model.App.self, from: appData)
        } catch {
            errors.append(App8.ValidationError(
                code: EC.appDecodeFailed,
                message: "Failed to decode app.json: \(error.localizedDescription). Check that the JSON structure matches the expected App schema (title, navigation.startFlow, navigation.flows).",
                path: "app.json",
                context: ["error": "\(error)"]
            ))
            return Result(
                section: .init(kind: .appModel, label: "App Model", errors: errors, warnings: warnings),
                app: nil
            )
        }

        if let navigation = app.navigation {
            let flowIds = navigation.flows.map(\.id)
            if !flowIds.contains(navigation.startFlow) {
                errors.append(App8.ValidationError(
                    code: EC.appMissingStartFlow,
                    message: "navigation.startFlow references \"\(navigation.startFlow)\" but only these flows exist: \(flowIds). Change startFlow to one of the existing flow IDs.",
                    path: "app.json > navigation.startFlow",
                    context: ["actual": navigation.startFlow, "availableFlows": flowIds.joined(separator: ", ")]
                ))
            }

            for flow in navigation.flows {
                if flow.startScreen.isEmpty {
                    errors.append(App8.ValidationError(
                        code: EC.appFlowMissingStartScreen,
                        message: "Flow \"\(flow.id)\" has an empty startScreen. Provide a valid screen ID.",
                        path: "app.json > navigation.flows[\(flow.id)].startScreen",
                        context: ["flowId": flow.id]
                    ))
                }
            }
        }

        let section = App8.DiagnosticReport.Section(
            kind: .appModel,
            label: "App Model",
            errors: errors,
            warnings: warnings,
            statusDetail: "title: \"\(app.title ?? "unknown")\", \(app.navigation?.flows.count ?? 0) flow(s)"
        )
        return Result(section: section, app: app)
    }
}
