import Foundation

extension App8 {

    public enum Error: Swift.Error, LocalizedError {
        case appInitFailed
        case dataSourceDeallocated
        case invalidUTF8(String)
        case appDecodeFailed(underlying: Swift.Error)
        case appMissingInitialScreenId
        case stylesheetDecodeFailed(id: String, underlying: Swift.Error)
        case screenDecodeFailed(id: String, underlying: Swift.Error)
        case componentDecodeFailed(id: String, underlying: Swift.Error)
        case serviceNotAvailable
        case missingRequiredParams([String])
        case screenAnalysisFailed(String, Swift.Error)
        case screenNotFound(String)
        case notImplemented(String)

        public var errorDescription: String? {
            switch self {
            case .appInitFailed:
                return "App8 initialization failed."
            case .dataSourceDeallocated:
                return "App8DataSource is no longer available."
            case .invalidUTF8(let name):
                return "Resource is not valid UTF-8: \(name)"
            case .appDecodeFailed(let underlying):
                return "Failed to decode app model: \(underlying)"
            case .appMissingInitialScreenId:
                return "App is missing required initialScreenId."
            case .stylesheetDecodeFailed(let id, let underlying):
                return "Failed to decode stylesheet '\(id)': \(underlying)"
            case .screenDecodeFailed(let id, let underlying):
                return "Failed to decode screen '\(id)': \(underlying)"
            case .componentDecodeFailed(let id, let underlying):
                return "Failed to decode component '\(id)': \(underlying)"
            case .serviceNotAvailable:
                return "App8Service is not available."
            case .missingRequiredParams(let params):
                return "Missing required screen parameters: \(params.joined(separator: ", "))"
            case .screenAnalysisFailed(let screenId, let underlying):
                return "Failed to analyze screen '\(screenId)': \(underlying)"
            case .screenNotFound(let screenId):
                return "Screen '\(screenId)' not found."
            case .notImplemented(let api):
                return "\(api) is not implemented yet."
            }
        }
    }
}
