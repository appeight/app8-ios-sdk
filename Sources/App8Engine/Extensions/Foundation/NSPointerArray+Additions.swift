import Foundation

extension NSPointerArray {

    subscript<T: AnyObject>(i: Int) -> T? {
        guard let pointer = self.pointer(at: i) else { return nil }
        return Unmanaged.fromOpaque(pointer).takeUnretainedValue()
    }
    
    func removeAll() {
        for _ in 0 ..< count {
            removePointer(at: 0)
        }
    }
    
    func setContent<T: AnyObject>(of array: [T]) {
        removeAll()
        for item in array {
            let pointer = Unmanaged.passUnretained(item).toOpaque()
            addPointer(pointer)
        }
    }
    
    func append<T: AnyObject>(_ object: T) {
        let pointer = Unmanaged.passUnretained(object).toOpaque()
        addPointer(pointer)
    }
    
    func append<T: AnyObject>(_ objects: [T]) {
        for object in objects {
            append(object)
        }
    }
    
    func forEach<T: AnyObject>(_ body: (T) throws -> Void) rethrows {
        compact()
        for i in .zero ..< count {
            if let object: T = self[i] {
                try body(object)
            }
        }
    }
    
    func contains<T: AnyObject>(where predicate: (T) throws -> Bool) rethrows -> Bool {
        compact()
        for i in .zero ..< count {
            if let object: T = self[i], try predicate(object) {
                return true
            }
        }
        return false
    }
    
    func removeAll<T: AnyObject>(where predicate: (T) throws -> Bool) rethrows {
        for i in (.zero ..< count).reversed() {
            if let object: T = self[i], try predicate(object) {
                removePointer(at: i)
            }
        }
    }
}
