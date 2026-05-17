import UIKit
import Combine

@MainActor
@objc protocol BaseRouterProtocol: AnyObject {
    var baseViewController: UIViewController? { get set }
    var controllerForNavigation: UINavigationController? { get }
    init(viewController: UIViewController?)
    func show(viewController: UIViewController, animated: Bool, sender: Any?, completion: (() -> Void)?)
}

/// Needed to work around @objc limitations.
@MainActor
protocol ExtendedBaseRouterProtocol: CancellableHolder {

}

@MainActor
protocol CancellableHolder: AnyObject {
    var cancellables: Set<AnyCancellable> { get set }
}

// MARK: - Navigation functions

extension BaseRouterProtocol {

    var controllerForNavigation: UINavigationController? {
        baseViewController?.navigationController
    }

    var isOnTopOfStack: Bool {
        if let controllerForNavigation {
            return controllerForNavigation.topViewController === baseViewController
        } else {
            return false
        }
    }
    
    func dismiss() {
        baseViewController?.dismiss(animated: true, completion: nil)
    }
    
    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        baseViewController?.dismiss(animated: animated, completion: completion)
    }
    
    func pop(animated: Bool = true, completion: (() -> Void)? = nil) {
        if let nc = controllerForNavigation {
            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            nc.popViewController(animated: true)
            CATransaction.commit()
        }
        else if baseViewController?.presentingViewController != nil {
            baseViewController?.dismiss(animated: true, completion: completion)
        }
    }
    
    func pop<T: UIViewController>(toTopVcOfType type: T.Type, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let nc = controllerForNavigation else { return }
        guard let targetVC = nc.viewControllers.reversed().compactMap({ $0 as? T }).first else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        nc.popToViewController(targetVC, animated: animated)
        CATransaction.commit()
    }
    
    func popToRoot(animated: Bool = true) {
        controllerForNavigation?.popToRootViewController(animated: animated)
    }
    
    func show(viewController: UIViewController, animated: Bool = true, sender: Any? = nil, completion: (() -> Void)? = nil) {
        self.show(viewController: viewController, animated: animated, sender: sender, completion: completion)
    }
    
    func replace(viewController: UIViewController, sender: Any? = nil, completion: (() -> Void)? = nil) {
        if let navigationController = controllerForNavigation {
            navigationController.setViewControllers([viewController], animated: true)
        }
        else {
            baseViewController?.present(viewController, animated: true, completion: completion)
        }
    }
    
    func present(_ viewController: UIViewController, animated: Bool = true, sender: Any? = nil, completion: (() -> Void)? = nil) {
        baseViewController?.present(viewController, animated: animated, completion: completion)
    }

    func open(url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    func insertAndPop<T: UIViewController>(_ vc: T, index: Int, animated: Bool = true) -> () -> Void {
        return { [weak self] in
            guard let nc = self?.controllerForNavigation else { return }
            let targetIndex = index.clamped(to: 0 ... nc.viewControllers.count - 1)
            nc.viewControllers.insert(vc, at: targetIndex)
            nc.popToViewController(vc, animated: true)
        }
    }
}

@MainActor
class BaseRouter: NSObject, BaseRouterProtocol, ExtendedBaseRouterProtocol {
    weak var baseViewController: UIViewController?
    var controllerForNavigation: UINavigationController? {
        baseViewController?.navigationController
    }
    var cancellables = Set<AnyCancellable>()
    
    var bannerPresentingView: UIView? {
        return baseViewController?.view
    }
    
    required init(viewController: UIViewController?) {
        baseViewController = viewController
    }
    
    func show(viewController: UIViewController, animated: Bool = true, sender: Any? = nil, completion: (() -> Void)? = nil) {
        if let navigationController = controllerForNavigation {
            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            navigationController.pushViewController(viewController, animated: animated)
            CATransaction.commit()
        }
        else {
            baseViewController?.present(viewController, animated: animated, completion: completion)
        }
    }
}

extension BaseRouterProtocol {
    
    var dismissAction: @MainActor () -> Void {
        return { [weak self] in
            self?.dismiss()
        }
    }
    
    @MainActor
    func dismissPublisher() -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { [weak self] promise in
            guard let vc = self?.baseViewController else {
                promise(.failure(BaseRouterError.internalMemory))
                return
            }
            vc.dismiss(animated: true, completion: {
                promise(.success(()))
            })
        }
        .eraseToAnyPublisher()
    }
    
    var popAction: @MainActor () -> Void {
        return { [weak self] in
            self?.pop()
        }
    }
    
    var popToRootAction: @MainActor () -> Void {
        return { [weak self] in
            self?.popToRoot()
        }
    }
    
    @MainActor
    func openUrlAction(_ url: URL) -> @MainActor () -> Void {
        return { [weak self] in
            self?.open(url: url)
        }
    }
}

enum BaseRouterError: Error {
    case internalMemory
}
