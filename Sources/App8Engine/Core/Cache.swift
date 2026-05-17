import Foundation

/// Thread-safe generic cache.
/// Reads are concurrent; writes use a barrier.
final class Cache<Key: Hashable, Value>: @unchecked Sendable where Key: Sendable, Value: Sendable {
    private var storage: [Key: Value] = [:]
    private let queue = DispatchQueue(
        label: "cache.generic.\(UUID().uuidString)",
        qos: .userInitiated,
        attributes: .concurrent
    )

    @inlinable
    func get(_ key: Key) -> Value? {
        queue.sync { storage[key] }
    }

    @inlinable
    func set(_ key: Key, _ value: Value) {
        queue.async(flags: .barrier) { self.storage[key] = value }
    }

    @inlinable
    func remove(_ key: Key) {
        queue.async(flags: .barrier) { self.storage.removeValue(forKey: key) }
    }

    @inlinable
    func removeAll() {
        queue.async(flags: .barrier) { self.storage.removeAll() }
    }

    /// Optional subscript: set to `nil` removes the key.
    subscript(key: Key) -> Value? {
        get { get(key) }
        set {
            if let v = newValue {
                set(key, v)
            } else {
                remove(key)
            }
        }
    }

    /// Get-or-insert-Default subscript (atomic).
    /// If the key is missing, inserts `defaultValue()` under a barrier and returns it.
    subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        get {
            if let existing = get(key) { return existing }

            let value = defaultValue()
            return queue.sync(flags: .barrier) {
                if let existing = storage[key] {
                    return existing
                } else {
                    storage[key] = value
                    return value
                }
            }
        }
        set {
            set(key, newValue)
        }
    }
}
