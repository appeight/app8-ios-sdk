import Foundation

// MARK: - Base Protocol

protocol DebugStyleItemViewModelProtocol {
    var cellType: DebugStyleCellType { get }
}

enum DebugStyleCellType {
    case error
    case single
    case resolved
}

// MARK: - Error Style

protocol ErrorStyleItemViewModelProtocol: DebugStyleItemViewModelProtocol {
    var errorMessage: String { get }
    var jsonData: String { get }
}

struct ErrorStyleItemViewModel: ErrorStyleItemViewModelProtocol {
    let cellType: DebugStyleCellType = .error
    let errorMessage: String
    let jsonData: String

    init(errorMessage: String, jsonData: String) {
        self.errorMessage = errorMessage
        self.jsonData = jsonData
    }
}

// MARK: - Single Style

protocol SingleStyleItemViewModelProtocol: DebugStyleItemViewModelProtocol {
    var styleId: String { get }
    var styleType: String { get }
    var style: DSL.Model.Style.`Any` { get }
}

struct SingleStyleItemViewModel: SingleStyleItemViewModelProtocol {
    let cellType: DebugStyleCellType = .single
    let styleId: String
    let styleType: String
    let style: DSL.Model.Style.`Any`

    init(style: DSL.Model.Style.`Any`) {
        self.style = style
        self.styleId = style.id

        switch style.type {
        case .key(let key):
            self.styleType = key.rawValue
        case .custom(let customType):
            self.styleType = customType
        }
    }
}

// MARK: - Resolved Style

protocol ResolvedStyleItemViewModelProtocol: DebugStyleItemViewModelProtocol {
    var styleId: String { get }
    var styleType: String { get }
    var originalStyle: DSL.Model.Style.`Any` { get }
    var resolvedStyle: DSL.Model.Style.`Any` { get }
}

struct ResolvedStyleItemViewModel: ResolvedStyleItemViewModelProtocol {
    let cellType: DebugStyleCellType = .resolved
    let styleId: String
    let styleType: String
    let originalStyle: DSL.Model.Style.`Any`
    let resolvedStyle: DSL.Model.Style.`Any`

    init(original: DSL.Model.Style.`Any`, resolved: DSL.Model.Style.`Any`) {
        self.originalStyle = original
        self.resolvedStyle = resolved
        self.styleId = original.id

        switch original.type {
        case .key(let key):
            self.styleType = key.rawValue
        case .custom(let customType):
            self.styleType = customType
        }
    }
}
