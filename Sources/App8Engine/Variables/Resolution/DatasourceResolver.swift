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
        var resolvedVariables = variables

        let variablesWithSource = variables.filter { $0.value.source != nil }
        guard !variablesWithSource.isEmpty else { return variables }

        try await withThrowingTaskGroup(of: (String, VariableDefinition).self) { group in
            for (name, definition) in variablesWithSource {
                guard let source = definition.source else { continue }

                group.addTask {
                    let value = try await load(source: source, type: definition.type, screenId: screenId, dataSource: dataSource)
                    return (name, definition.withResolvedValue(value))
                }
            }

            for try await (name, resolved) in group {
                resolvedVariables[name] = resolved
            }
        }

        return resolvedVariables
    }

    /// Fetches one datasource through the host data source, decodes it and
    /// checks it against the variable's declared type (and the file's schema).
    /// `screenId` is the screen that owns the variable (`""` for app scope).
    static func load(
        source: String,
        type: VariableType,
        screenId: String,
        dataSource: A8.DataSourceProtocol
    ) async throws -> Any {
        let value = try await fetch(source: source, screenId: screenId, dataSource: dataSource)
        try check(value, source: source, type: type)
        return value
    }

    /// Fetches and decodes one datasource (validated against its own schema).
    static func fetch(source: String, screenId: String, dataSource: A8.DataSourceProtocol) async throws -> Any {
        let data = try await dataSource.getDatasource(screenId: screenId, datasourceId: source)
        let datasource = try JSONDecoder().decode(DatasourceDefinition.self, from: data)
        if let schema = datasource.schema {
            try SchemaValidator.validate(data: datasource.rawData, against: schema)
        }
        return datasource.rawData
    }

    /// Throws when `value` does not match the variable's declared type.
    static func check(_ value: Any, source: String, type: VariableType) throws {
        guard type.validate(value) else {
            throw DatasourceError.typeMismatch(
                datasourceId: source,
                expected: type,
                actual: VariableType.inferType(from: value).rawValue
            )
        }
    }

    /// Check if any variables reference external datasources
    static func hasExternalDatasources(_ variables: [String: VariableDefinition]?) -> Bool {
        guard let variables = variables else { return false }
        return variables.values.contains { $0.hasExternalSource }
    }
}
