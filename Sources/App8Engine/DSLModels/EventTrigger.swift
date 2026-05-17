extension DSL.Model {

    /// Event trigger definition for the `onEvent` array
    struct EventTrigger: Decodable, Sendable {

        /// Supported event types
        enum EventType: String, Decodable, Sendable {
            case timer
            case appear
            case disappear
        }

        /// The event type that triggers this action
        let event: EventType

        /// Initial delay in seconds before first fire (for timer events, default 0)
        let delay: Double?

        /// Interval in seconds between repeats (for repeating timer events)
        /// If not specified, uses `delay` value for backwards compatibility
        let interval: Double?

        /// Whether the timer should repeat (for timer events)
        let repeats: Bool?

        /// The action to execute when the event fires
        let action: Action
    }
}
