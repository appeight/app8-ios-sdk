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
        // Video triggers
        case onVideoReady       // first frame displayed (AVPlayerLayer.isReadyForDisplay)
        case onVideoStart       // playback actually began (timeControlStatus -> .playing, first time)
        case onVideoPause       // playback paused
        case onVideoComplete    // played to end (non-looping)
        case onVideoLoop        // per loop cycle (AVPlayerLooper.loopCount increment)
        case onVideoStall       // buffering (timeControlStatus -> .waitingToPlayAtSpecifiedRate)
        case onVideoError       // AVPlayerItem.status == .failed
        case onTimeMark         // a marks[] boundary crossed (overlay: $markId)
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
        /// Variable name for single-variable actions. `variableName` is the
        /// documented key; `variable` decodes as an undocumented alias so a
        /// bundle behaves the same on every platform.
        @VariableNameKey var variableName: String?
        /// The `variable` alias, read only by `VariableNameKey` decoding.
        private let variable: String?
        var value: AnyCodableValue?            // Value (can contain expressions as strings)
        var key: String?                       // updateVariable on an object variable: set only this key (string/expression)
        /// incrementVariable / incrementArrayItem amount: a number or an expression (`"{{line.quantity}}"`).
        var by: AnyCodableValue?
        var matchBy: String?                   // For toggleArrayValue / incrementArrayItem: key to match when array contains objects (e.g. "id")
        var field: String?                     // For incrementArrayItem: numeric field to adjust (default "quantity")
        var updates: [String: AnyCodableValue]? // For updateMultipleVariables
        var scope: VariableScope?              // Target scope for resetVariables
        /// insertArrayItem: position (default 0, negative counts from the end).
        /// removeArrayItem: position of the element to remove.
        /// forEach: name the element's index is bound to inside `actions`.
        /// One key, read per action type, so it decodes as any JSON value.
        var index: AnyCodableValue?
        /// upsertArrayItem: where a new element goes when nothing matches (`start` | `end`, default `end`).
        var position: String?

        /// The variable an action writes.
        var targetVariable: String? { variableName }

        // Control flow
        /// forEach: the array to iterate (expression or literal array).
        var items: AnyCodableValue?
        /// forEach: name the element is bound to inside `actions` (default `item`).
        var `as`: String?
        /// forEach / with: nested actions (one action or an array).
        var actions: ActionList?
        /// with: names evaluated once and bound for `actions`.
        var values: [String: AnyCodableValue]?

        // HTTP request
        /// request: GET (default), POST, PUT, PATCH, DELETE.
        var method: String?
        /// request: header values (strings, `{{}}` allowed).
        var headers: [String: String]?
        /// request: JSON body (object / array / expressions), sent as application/json.
        var body: AnyCodableValue?
        /// request: variable that receives `{ status, body, headers }`.
        var resultVariable: String?
        /// request / reloadDatasource: run on success (request: 2xx, with
        /// `response` in scope). One action or an array.
        var onSuccess: ActionList?
        /// request / reloadDatasource: run on failure (request: any other
        /// status, or status 0 for a network failure / timeout / host rejection).
        var onError: ActionList?

        // Datasources
        /// reloadDatasource: the datasource path (`datasources/items`).
        var source: String?

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

        // requestNotificationPermission: what runs after the answer
        var onGranted: ActionList?
        var onDenied: ActionList?

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
            case incrementArrayItem       // Add `by` to a numeric field of the object matched by `matchBy`; inserts / removes it
            case insertArrayItem          // Insert `value` at `index` (default 0; negative counts from the end)
            case upsertArrayItem          // Replace the element matched by `matchBy`, else add it
            case removeArrayItem          // Remove elements matched by `matchBy`/`value`, or the one at `index`
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

            // Control flow
            case forEach                  // Run `actions` once per element of `items`
            case with                     // Bind `values` as names, then run `actions`

            // HTTP + datasources
            case request                  // HTTP request; `onSuccess` / `onError` see `response`
            case reloadDatasource         // Refetch `source` and update every variable bound to it

            // Notification permission: system prompt once, then onGranted / onDenied
            case requestNotificationPermission

            /// Variable-store actions run by `VariableActionHandler`.
            var isVariableAction: Bool {
                switch self {
                case .updateVariable, .incrementVariable, .toggleArrayValue, .appendToArray,
                     .incrementArrayItem, .insertArrayItem, .upsertArrayItem, .removeArrayItem,
                     .updateMultipleVariables, .resetVariables:
                    return true
                default:
                    return false
                }
            }
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

extension DSL.Model {
    /// Decodes `variableName`, falling back to the sibling `variable` key.
    @propertyWrapper
    public struct VariableNameKey: Decodable, Sendable {
        public var wrappedValue: String?
        public init(wrappedValue: String?) { self.wrappedValue = wrappedValue }
    }
}

extension KeyedDecodingContainer {
    /// Synthesized `Action` decoding calls this for `variableName`: the
    /// documented key wins, then the `variable` alias, else nil.
    func decode(_ type: DSL.Model.VariableNameKey.Type, forKey key: Key) throws -> DSL.Model.VariableNameKey {
        if let name = try decodeIfPresent(String.self, forKey: key) {
            return .init(wrappedValue: name)
        }
        if let alias = Key(stringValue: "variable"), let name = try decodeIfPresent(String.self, forKey: alias) {
            return .init(wrappedValue: name)
        }
        return .init(wrappedValue: nil)
    }
}
