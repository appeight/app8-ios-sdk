//
//  RenderHarness.swift
//  App8EngineTests
//
//  Minimal render harness for tests that need real view models / views
//  (two-way binding, trigger dispatch, layer properties).
//

import UIKit
@testable import App8Engine

@MainActor
final class RenderHarness {
    let service: App8Service
    /// `nil` when created with `inWindow: false` — Mac Catalyst logic tests have
    /// no NSApplication, so a `UIWindow` can't be created there.
    let window: UIWindow?
    let superview: UIView

    /// View models hold `unowned` service refs and some views touch them in
    /// `removeFromSuperview`; keep services alive past view teardown.
    private static var retainedServices: [App8Service] = []

    init(size: CGSize = CGSize(width: 390, height: 844), inWindow: Bool = true) {
        service = App8Service(publicDataSource: HarnessStubDataSource(), context: App8Context())
        superview = UIView(frame: CGRect(origin: .zero, size: size))
        if inWindow {
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.makeKeyAndVisible()
            window.addSubview(superview)
            self.window = window
        } else {
            window = nil
        }
        Self.retainedServices.append(service)
    }

    @discardableResult
    func render(_ json: String) throws -> UIView {
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        service.renderComponent(component, superview: superview)
        superview.layoutIfNeeded()
        return superview
    }

    func viewModel<T>(_ path: String, as type: T.Type = T.self) -> T? {
        service.componentRegistry.viewModel(forId: path) as? T
    }

    func find<T: UIView>(_ type: T.Type, in view: UIView? = nil) -> T? {
        let root = view ?? superview
        if let match = root as? T { return match }
        for sub in root.subviews {
            if let found = find(type, in: sub) { return found }
        }
        return nil
    }

    /// `UIControl.sendActions(for:)` needs a `UIApplication`, which logic tests
    /// don't have — invoke the registered target/actions directly instead.
    func fire(_ control: UIControl, _ event: UIControl.Event) {
        for target in control.allTargets {
            for name in control.actions(forTarget: target, forControlEvent: event) ?? [] {
                _ = (target as NSObject).perform(Selector(name), with: control)
            }
        }
    }

    /// Spin the main run loop so debounced / async Combine sinks deliver.
    func drain(_ seconds: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

private final class HarnessStubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}
