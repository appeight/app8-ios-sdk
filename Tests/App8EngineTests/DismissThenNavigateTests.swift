//
//  DismissThenNavigateTests.swift
//  App8EngineTests
//
//  `dismiss` followed by `navigation` in one action list: the push waits for
//  the modal to be gone, then lands on the presenting screen's stack.
//

import XCTest
@testable import App8Engine

@MainActor
private final class StubScreenLoader: ScreenLoaderProtocol {
    /// Each load, with whether a modal was still up at that moment.
    var loads: [(id: String, modalUp: Bool)] = []
    weak var flow: FlowViewController?

    func loadScreen(id: String) async throws -> DSL.Model.Component.`Any` {
        loads.append((id, flow?.presentedModal != nil))
        let json = ##"{ "id": "\##(id)", "type": "screen", "content": { "properties": { "backgroundColor": "#FFFFFF" } } }"##
        return try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
    }
}

@MainActor
final class DismissThenNavigateTests: XCTestCase {

    /// Polls without blocking the main actor (async tests run on it).
    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Logic tests run without a host app, so UIKit never finishes a modal
    /// transition here. The test checks the engine's contract around it:
    /// the dismissal gate opens synchronously, the modal ignores the
    /// navigation that follows, and the flow handles it only once the modal
    /// is gone.
    func testNavigationAfterDismissWaitsAndRunsOnPresentingStack() async throws {
        let context = App8Context()
        let service = App8Service(publicDataSource: StubDataSourceForNavigation(), context: context)
        let app = try JSONDecoder().decode(DSL.Model.App.self, from: Data("""
        { "id": "nav-test", "navigation": { "startFlow": "main", "flows": [ { "id": "main", "startScreen": "home" } ] } }
        """.utf8))
        let loader = StubScreenLoader()
        let coordinator = FlowCoordinator(app: app, screenLoader: loader, appService: service, context: context)
        defer { coordinator.stop() }
        let rootVC = try await coordinator.start()
        let flowVC = try XCTUnwrap(coordinator.currentFlowViewController)
        loader.flow = flowVC

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = rootVC
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        NotificationCenter.default.post(name: .app8NavigationRequest, object: NavigationRequest(type: .presentModal(
            screenId: "sheet", params: [:], style: .fullScreen, detents: nil, grabber: nil)))
        await waitFor { flowVC.presentedModal != nil }
        let modal = try XCTUnwrap(flowVC.presentedModal)

        // The modal screen runs: [dismiss, navigation → details].
        let sheet = try XCTUnwrap(service.componentRegistry.viewModel(forId: "sheet") as? CViewModel)
        let actions = try JSONDecoder().decode([DSL.Model.Action].self, from: Data("""
        [ { "type": "dismiss" }, { "type": "navigation", "nextScreen": "details" } ]
        """.utf8))
        for action in actions { sheet.executeAction(action) }
        XCTAssertNotNil(context.pendingDismissal, "dismiss opens the gate before the navigation is posted")

        await waitFor { loader.loads.contains { $0.id == "details" } && context.pendingDismissal == nil }
        let detailsLoads = loader.loads.filter { $0.id == "details" }
        XCTAssertEqual(detailsLoads.count, 1, "only the flow handles the navigation; the leaving modal ignores it")
        XCTAssertEqual(detailsLoads.first?.modalUp, false, "the navigation runs after the modal is gone")
        XCTAssertEqual(modal.stackDepth, 1, "nothing was pushed inside the dismissed modal")
        XCTAssertNil(flowVC.presentedModal)
        XCTAssertNil(context.pendingDismissal)
    }
}

private final class StubDataSourceForNavigation: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
}
