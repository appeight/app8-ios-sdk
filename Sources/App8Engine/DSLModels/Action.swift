extension DSL.Model {

    public enum ActionTrigger: String, Codable, Hashable, Sendable {
        case tap
        case longPress
        // TextField triggers
        case onTextChange
        // Collection triggers
        case onItemTap
        case onRefresh
        case onLoadMore
        case onSelectionChange
        // Map triggers
        case onAnnotationTap
        case onRegionChange
        case onUserLocationUpdate
        // ScrollView triggers
        case onScrollThreshold
    }

    public struct Action: Decodable, Sendable {
        let type: `Type`

        // General
        var target: String?       // Component ID or "self"

        // Function execution
        var function: String?     // Name of function to execute

        // Navigation
        var destination: String?
        var nextScreen: String?   // ID of the screen to navigate to
        var isFinal: Bool?        // Whether this completes the entire flow
        var isBack: Bool?         // Whether this is a back navigation
        var toRoot: Bool?         // With isBack: pop to the navigation-stack root ("back to list")
        var params: [String: AnyCodableValue]?  // Parameters to pass during navigation
        var presentation: PresentationStyle?    // How to present (push, sheet, fullScreen, etc.)
        var detents: [SheetDetent]?             // For native sheets: medium | large | <points> | "NN%"
        var grabber: Bool?                      // For native sheets: show the drag grabber (default true)
        var transition: ScreenTransition?       // Custom screen transition (overrides screen/app defaults)

        // State
        var stateName: String?    // For setState action: the target state name
        var animated: Bool?       // For setState action: whether to animate (default: true)

        // Variable operations
        var variableName: String?              // Variable name for single-variable actions
        var value: AnyCodableValue?            // Value (can contain expressions as strings)
        var by: Double?                        // Increment/decrement amount
        var matchBy: String?                   // For toggleArrayValue: key to match when array contains objects (e.g. "id")
        var updates: [String: AnyCodableValue]? // For updateMultipleVariables
        var scope: VariableScope?              // Target scope for resetVariables

        // Tab selection
        var tabIndex: Int?                         // Index of tab to select (0-based)
        var tabId: String?                         // ID of tab to select (alternative to index)

        // Alert
        var alertTitle: String?                    // Alert title
        var alertMessage: String?                  // Alert message
        var alertActions: [AlertAction]?            // Alert buttons

        // Haptic
        var hapticStyle: HapticStyle?              // Feedback type: light, medium, heavy, success, warning, error, selection

        enum HapticStyle: String, Decodable, Sendable {
            case light, medium, heavy               // Impact feedback
            case success, warning, error             // Notification feedback
            case selection                           // Selection feedback
        }

        // URL
        var url: String?                            // URL to open (supports expressions)
        var urlPresentation: URLPresentation?       // How to present: external (default), sheet, fullScreen

        // Emit (host event bus)
        /// Event name for `.emit` actions. Convention: dotted lowercase
        /// (e.g. `connect.tapped`). Host code filters on this.
        var name: String?
        /// Payload values support `{{var}}` interpolation in string values;
        /// non-string scalars pass through unchanged.
        var payload: [String: AnyCodableValue]?

        enum URLPresentation: String, Decodable, Sendable {
            case external   // Default: hand off to system (UIApplication.shared.open) — Safari app, Phone, Mail, etc.
            case sheet      // In-app SFSafariViewController presented as a sheet
            case fullScreen // In-app SFSafariViewController presented full screen
        }

        struct AlertAction: Decodable, Sendable {
            let title: String
            let style: AlertActionStyle?
            /// Action to execute when this alert button is tapped
            let action: Action?

            enum AlertActionStyle: String, Decodable, Sendable {
                case `default`, cancel, destructive
            }
        }

        enum `Type`: String, Decodable, Sendable {
            case navigation
            case dismiss                  // Dismiss modal presentation
            case executeFunction
            case complete
            case completeFlow             // Complete flow and transition to destination
            case setState
            case selectTab                // Switch to a different tab

            // Variable actions
            case updateVariable           // Set single variable value
            case incrementVariable        // Add numeric amount to variable
            case toggleArrayValue         // Add/remove value from array
            case appendToArray            // Append value to end of array variable
            case updateMultipleVariables  // Batch update multiple variables
            case resetVariables           // Reset variables to initial values

            // Focus actions
            case focus                    // Focus a specific component by ID
            case focusNext                // Focus next focusable component
            case focusPrevious            // Focus previous focusable component
            case dismissKeyboard          // Resign first responder / dismiss keyboard

            // Alert
            case showAlert                // Show a native UIAlertController

            // Haptic feedback
            case haptic                   // Trigger haptic feedback

            // URL
            case openURL                  // Open a URL in Safari/system handler

            // Host event bus — engine forwards `name` + `payload` to subscribers
            // registered via `App8.Instance.subscribe(...)`. The engine itself
            // does nothing else; the host is expected to handle it.
            case emit
        }

        /// Presentation style for navigation
        enum PresentationStyle: String, Decodable, Sendable {
            case push          // Default hierarchical navigation
            case sheet         // iOS sheet with detents (default modal)
            case fullScreen    // Full screen modal
            case formSheet     // Smaller sheet (iPad optimized)
            case pageSheet     // Page sheet
            case crossDissolve // Full screen modal with fade transition

            /// Convert to ModalPresentationStyle for NavigationRequest
            var toModalPresentationStyle: ModalPresentationStyle {
                switch self {
                case .push:           return .sheet  // Fallback, shouldn't be used
                case .sheet:          return .sheet
                case .fullScreen:     return .fullScreen
                case .formSheet:      return .formSheet
                case .pageSheet:      return .pageSheet
                case .crossDissolve:  return .crossDissolve
                }
            }
        }

        /// A resting height for a native sheet (`UISheetPresentationController`).
        /// DSL forms: `"medium"` · `"large"` · a number (fixed points) · `"NN%"`
        /// (fraction of the largest available height). Several may be supplied so
        /// the sheet can be dragged between them.
        public enum SheetDetent: Decodable, Sendable, Equatable {
            case medium             // system ~half height
            case large              // system full height
            case fixed(Double)      // absolute height in points
            case fraction(Double)   // 0…1 of the largest detent height

            public init(from decoder: any Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let number = try? c.decode(Double.self) {
                    self = .fixed(number)
                    return
                }
                let raw = (try? c.decode(String.self)) ?? "large"
                let s = raw.trimmingCharacters(in: .whitespaces)
                switch s.lowercased() {
                case "medium": self = .medium
                case "large":  self = .large
                default:
                    if s.hasSuffix("%"), let pct = Double(s.dropLast()) {
                        self = .fraction(pct / 100)
                    } else if let n = Double(s) {
                        self = .fixed(n)
                    } else {
                        self = .large
                    }
                }
            }
        }

        /// Scope for variable operations
        enum VariableScope: String, Decodable, Sendable {
            case component  // Local component variables only
            case screen     // Screen-level variables
            case app        // App-level variables
            case all        // All scopes
        }
    }
}
