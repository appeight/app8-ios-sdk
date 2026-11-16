import UserNotifications

/// `requestNotificationPermission` (actions.md): the system prompt when the
/// app has not asked yet, else the stored answer. Provisional and ephemeral
/// authorization count as granted. Registering for remote pushes is the host's.
@MainActor
enum NotificationPermission {

    static func request(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    Task { @MainActor in completion(granted) }
                }
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in completion(true) }
            case .denied:
                Task { @MainActor in completion(false) }
            @unknown default:
                Task { @MainActor in completion(false) }
            }
        }
    }
}
