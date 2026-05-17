import Foundation

@MainActor
protocol ScreenLoaderProtocol: AnyObject {
    /// Load and decode a screen by its ID.
    ///
    /// - Important: `id` originates from untrusted DSL (navigation actions,
    ///   datasources). Implementations that resolve the id to a file or bundle
    ///   path **must** sanitize it — reject `..`, absolute paths, and any
    ///   separator that could escape the intended screen directory — to prevent
    ///   path traversal.
    func loadScreen(id: String) async throws -> DSL.Model.Component.`Any`
}
