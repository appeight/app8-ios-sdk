import Foundation

// MARK: - Data Source (Public protocol)

public protocol App8DataSource: AnyObject, Sendable {
    func getApp() async throws -> Data
    func getStyles() async throws -> [Data]
    func getComponents() async throws -> [Data]
    func getScreen(screenId: String) async throws -> Data
    func getComponent(componentId: String) async throws -> Data
    func getAsset(assetId: String?, assetName: String?) async throws -> Data?
    /// Load a datasource file for a screen
    /// - Parameters:
    ///   - screenId: The screen that references this datasource
    ///   - datasourceId: The datasource path (e.g., "datasources/listings")
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data

    /// Returns all available screen IDs if the datasource supports enumeration.
    /// Used for orphan screen detection in diagnostics.
    func getAllScreenIds() async throws -> [String]?

    /// Stream new screen definitions over time (structural updates).
    /// Return nil to opt out of screen streaming for the given screen.
    func streamScreen(screenId: String) -> AsyncStream<Data>?

    /// Stream variable-only updates for a specific datasource (fast path, no re-render).
    /// - Parameters:
    ///   - screenId: The screen that owns the variable
    ///   - datasourceId: The datasource path referenced by the variable's `source` field
    ///   - componentPath: Optional component path for component-scoped variables
    func streamDatasource(screenId: String, datasourceId: String, componentPath: String?) -> AsyncStream<Data>?

    /// Optionally returns a stream of style primitive updates (JSON array of style entities).
    /// Return nil if this data source does not support style streaming.
    func streamStyles() -> AsyncStream<Data>?

    /// Localised string table for the app. Returns a JSON-encoded
    /// `TranslationStore.Bundle` ({ defaultLocale, locales: { [locale]: {key:value} } }).
    /// Loaded once at app boot in `ensureInfrastructureReady`. The default
    /// implementation returns an empty bundle so existing data sources that
    /// pre-date localisation keep working without changes.
    func getTranslations() async throws -> Data
}

// MARK: - Default implementations for optional methods

extension App8DataSource {
    /// Default implementation throws notImplemented error
    public func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
        throw DatasourceError.notImplemented
    }

    /// Default implementation returns nil (enumeration not supported)
    public func getAllScreenIds() async throws -> [String]? {
        return nil
    }

    /// Default implementation returns nil (screen streaming not supported)
    public func streamScreen(screenId: String) -> AsyncStream<Data>? {
        return nil
    }

    /// Default implementation returns nil (datasource streaming not supported)
    public func streamDatasource(screenId: String, datasourceId: String, componentPath: String?) -> AsyncStream<Data>? {
        return nil
    }

    /// Default implementation returns nil (style streaming not supported)
    public func streamStyles() -> AsyncStream<Data>? {
        return nil
    }

    /// Default implementation: no translations. Engine renders i18n keys as
    /// their key string (debug placeholder) and literal text unchanged.
    public func getTranslations() async throws -> Data {
        return Data(#"{"defaultLocale":"en","locales":{}}"#.utf8)
    }
}

// MARK: - Data Sources (Internal protocols)

extension A8 {

    protocol DataSourceHolder {
        var dataSource: DataSourceProtocol { get }
    }

    protocol DataSourceProtocol: Sendable {
        func getApp() async throws -> Data
        func getStyles() async throws -> [Data]
        func getComponents() async throws -> [Data]
        func getScreen(screenId: String) async throws -> Data
        func getComponent(componentId: String) async throws -> Data
        func getAsset(assetId: String?, assetName: String?) async throws -> Data?
        func getDatasource(screenId: String, datasourceId: String) async throws -> Data
        func getAllScreenIds() async throws -> [String]?
        func streamScreen(screenId: String) -> AsyncStream<Data>?
        func streamDatasource(screenId: String, datasourceId: String, componentPath: String?) -> AsyncStream<Data>?
        func streamStyles() -> AsyncStream<Data>?
        func getTranslations() async throws -> Data
    }

    class DataSource: @unchecked Sendable, DataSourceProtocol {

        /// Strong reference for async operation safety.
        private let ds: App8DataSource

        init(publicDataSource: App8DataSource) {
            ds = publicDataSource
        }
        
        func getApp() async throws -> Data {
            try await ds.getApp()
        }

        func getStyles() async throws -> [Data] {
            try await ds.getStyles()
        }

        func getComponents() async throws -> [Data] {
            try await ds.getComponents()
        }

        func getScreen(screenId: String) async throws -> Data {
            try await ds.getScreen(screenId: screenId)
        }

        func getComponent(componentId: String) async throws -> Data {
            try await ds.getComponent(componentId: componentId)
        }

        func getAsset(assetId: String?, assetName: String?) async throws -> Data? {
            try await ds.getAsset(assetId: assetId, assetName: assetName)
        }

        func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
            try await ds.getDatasource(screenId: screenId, datasourceId: datasourceId)
        }

        func getAllScreenIds() async throws -> [String]? {
            try await ds.getAllScreenIds()
        }

        func streamScreen(screenId: String) -> AsyncStream<Data>? {
            ds.streamScreen(screenId: screenId)
        }

        func streamDatasource(screenId: String, datasourceId: String, componentPath: String?) -> AsyncStream<Data>? {
            ds.streamDatasource(screenId: screenId, datasourceId: datasourceId, componentPath: componentPath)
        }

        func streamStyles() -> AsyncStream<Data>? {
            ds.streamStyles()
        }

        func getTranslations() async throws -> Data {
            try await ds.getTranslations()
        }
    }
}

/// Internal-protocol default so mocks that pre-date localisation still
/// conform without explicitly implementing `getTranslations()`. Mirrors
/// the default on the public `App8DataSource` protocol.
extension A8.DataSourceProtocol {
    func getTranslations() async throws -> Data {
        return Data(#"{"defaultLocale":"en","locales":{}}"#.utf8)
    }
}

// MARK: Granular DataSource definitions

extension A8.DataSource {

    protocol AssetSource: AnyObject, Sendable {
        func getAsset(asset: DSL.Model.Asset) async throws -> Data?
    }
}

extension A8.DataSource: A8.DataSource.AssetSource {

    func getAsset(asset: DSL.Model.Asset) async throws -> Data? {
        return try await getAsset(assetId: asset.id, assetName: asset.name)
    }
}
