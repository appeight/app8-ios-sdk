import UIKit

extension UIView {

    var mostParentView: UIView {
        return superview?.mostParentView ?? self
    }

    /// Recursive traversal across subviews with a custom action block
    /// - Parameter action: block to perform with a child view. return `true` to continue recursive traversal to current view's children, `false` otherwise
    func traverse(_ action: (UIView) -> Bool) {
        let shouldTraverseSubviews = action(self)
        if shouldTraverseSubviews {
            subviews.forEach { $0.traverse(action) }
        }
    }
    
    /// Recursive traversal across superviews with a custom action block
    /// - Parameter action: block to perform with a parent view. return `true` to continue recursive traversal to current view's parent, `false` otherwise
    func traverseParents(_ action: (UIView) -> Bool) {
        let shouldTraverseParent = action(self)
        if shouldTraverseParent, let parent = superview {
            parent.traverseParents(action)
        }
    }
    
    /// Recursive traversal across superviews with a custom action block
    /// - Parameter action: block to perform with a parent view. return `true` to continue recursive traversal to current view's parent, `false` otherwise
    func traverseTopToBottomAcrossParents(_ action: (UIView) -> Bool) {
        let shouldTraverseParent = action(self)
        for view in subviews.reversed() {
            let shouldContinue = action(view)
            if !shouldContinue {
                return
            }
        }
        if shouldTraverseParent, let parent = superview {
            parent.traverseTopToBottomAcrossParents(action)
        }
    }
    
    func firstSubview(where condition: (UIView) -> Bool) -> UIView? {
        if condition(self) {
            return self
        }
        for subview in subviews {
            if let targetView = subview.firstSubview(where: condition) {
                return targetView
            }
        }
        return nil
    }
    
    func filterSubviews(where condition: (UIView) -> Bool) -> [UIView] {
        var filtered: [UIView] = []
        if condition(self) {
            filtered.append(self)
        }
        for subview in subviews {
            filtered.append(contentsOf: subview.filterSubviews(where: condition))
        }
        return filtered
    }
    
    func removeAllConstraints(superviewDepth: Int? = nil) {
        removeSuperviewConstraints(superviewDepth: superviewDepth)
        removeConstraints(constraints)
        translatesAutoresizingMaskIntoConstraints = true
    }
    
    func removeSuperviewConstraints(superviewDepth: Int? = nil) {
        var _superview = self.superview
        
        var depth = 0
        while let superview = _superview {
            depth += 1
            if let superviewDepth, depth > superviewDepth { break }
            for constraint in superview.constraints {
                
                if let first = constraint.firstItem as? UIView, first == self {
                    superview.removeConstraint(constraint)
                }
                
                if let second = constraint.secondItem as? UIView, second == self {
                    superview.removeConstraint(constraint)
                }
            }
            
            _superview = superview.superview
        }
    }
    
    func findFirstChild<T>() -> T? {
        if let targetChild = self as? T {
            return targetChild
        }
        for child in subviews {
            if let target: T = child.findFirstChild() {
                return target
            }
        }
        return nil
    }
    
    func findFirstChild<T>(where condition: (T) -> Bool) -> T? {
        if let targetChild = self as? T {
            return targetChild
        }
        for child in subviews {
            if let target: T = child.findFirstChild(), condition(target) {
                return target
            }
        }
        return nil
    }
    
    func findFirstParent<T: UIView>() -> T? {
        if let targetParent = superview as? T {
            return targetParent
        } else if let parent = superview {
            return parent.findFirstParent()
        } else {
            return nil
        }
    }
}
