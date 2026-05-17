//
//  DatasourceResolver.swift
//  App8Engine
//

import Foundation

/// Resolves external datasource references for screen variables
enum DatasourceResolver {

    /// Resolve all datasource references in variable definitions
    ///
    /// - Parameters:
    ///   - screenId: The screen ID for which to resolve datasources
    ///   - variables: Dictionary of variable definitions from the screen
    ///   - dataSource: The data source to load datasources from
    /// - Returns: Dictionary of variable names to their resolved definitions (with data injected)
    static func resolveDatasources(
        screenId: String,
        variables: [String: VariableDefinition],
        dataSource: A8.DataSourceProtocol
    ) async throws -> [String: VariableDefinition] {
        let decoder = JSONDecoder()
        var resolvedVariables = variables

        let variablesWithSource = variables.filter { $0.value.source != nil }
        guard !variablesWithSource.isEmpty else { return variables }

        try await withThrowingTaskGroup(of: (String, VariableDefinition).self) { group in
            for (name, definition) in variablesWithSource {
                guard let source = definition.source else { continue }

                group.addTask {
                    let data = try await dataSource.getDatasource(screenId: screenId, datasourceId: source)
                    let datasource = try decoder.decode(DatasourceDefinition.self, from: data)

                    let actualType = VariableType.inferType(from: datasource.rawData)
                    guard definition.type.validate(datasource.rawData) else {
                        throw DatasourceError.typeMismatch(
                            datasourceId: source,
                            expected: definition.type,
                            actual: actualType.rawValue
                        )
                    }

                    if let schema = datasource.schema {
                        try SchemaValidator.validate(data: datasource.rawData, against: schema)
                    }

                    return (name, definition.withResolvedValue(datasource.rawData))
                }
            }

            for try await (name, resolved) in group {
                resolvedVariables[name] = resolved
            }
        }

        return resolvedVariables
    }

    /// Check if any variables reference external datasources
    static func hasExternalDatasources(_ variables: [String: VariableDefinition]?) -> Bool {
        guard let variables = variables else { return false }
        return variables.values.contains { $0.hasExternalSource }
    }
}
