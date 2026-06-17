//
//  CVideoViewPlaybackTests.swift
//  App8Engine
//
//  Drives a real `CVideoView` through end-to-end playback against a bundled
//  fixture clip, locking the runtime fixes for the video component:
//    - startup is gated on item readiness (so `rate` / seek actually apply),
//    - lifecycle triggers (`onVideoReady` / `onVideoStart` / `onVideoComplete`)
//      and `onTimeMark` fire and update bound variables,
//    - a finished non-looping clip freezes on its last frame (the player keeps
//      its item and pauses rather than blanking).
//
//  These reproduce the on-device bugs that the decode-only unit tests missed.
//

import XCTest
import UIKit
import AVFoundation
import Combine
@testable import App8Engine

@MainActor
final class CVideoViewPlaybackTests: XCTestCase {

    private var service: App8Service!
    private var window: UIWindow!
    private var parent: VariableStore!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        let url = Bundle.module.url(forResource: "tiny", withExtension: "mp4")!
        let data = try! Data(contentsOf: url)
        service = App8Service(publicDataSource: FixtureVideoDataSource(videoData: data), context: App8Context())
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        parent = VariableStore()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        parent = nil
        window = nil
        service = nil
        super.tearDown()
    }

    /// A non-looping clip with `rate: 2.0` and lifecycle actions. Asserts the
    /// deterministic core: ready → start (rate applied) → complete (variable
    /// updated) → frozen last frame.
    func testNonLoopingPlaybackFiresLifecycleAppliesRateAndFreezes() throws {
        try parent.defineVariable(name: "readyFlag", definition: VariableDefinition(type: .string, initialValue: "no"))
        try parent.defineVariable(name: "startFlag", definition: VariableDefinition(type: .string, initialValue: "no"))
        try parent.defineVariable(name: "completeFlag", definition: VariableDefinition(type: .string, initialValue: "no"))

        let json = """
        {
            "type": "video", "id": "test-video",
            "content": {
                "properties": {
                    "type": "remoteAsset", "name": "tiny.mp4",
                    "autoplay": true, "loop": false, "muted": true,
                    "rate": 2.0, "endBehavior": "freezeLastFrame"
                },
                "style": { "contentMode": "scaleAspectFill" },
                "layout": {
                    "width": 200, "height": 200,
                    "constraints": [
                        { "type": "top", "target": "superview" },
                        { "type": "leading", "target": "superview" }
                    ]
                },
                "actions": {
                    "onVideoReady": [ { "type": "updateVariable", "variableName": "readyFlag", "value": "yes" } ],
                    "onVideoStart": [ { "type": "updateVariable", "variableName": "startFlag", "value": "yes" } ],
                    "onVideoComplete": [ { "type": "updateVariable", "variableName": "completeFlag", "value": "yes" } ]
                }
            }
        }
        """

        let (view, vm) = try makeVideoView(json: json)

        let readyExp = expectation(description: "onVideoReady fired")
        readyExp.assertForOverFulfill = false
        let startExp = expectation(description: "onVideoStart fired")
        startExp.assertForOverFulfill = false
        let completeExp = expectation(description: "onVideoComplete fired")
        completeExp.assertForOverFulfill = false

        // Captured at the moment playback starts (rate must be live, not the
        // post-completion paused rate of 0).
        var rateAtStart: Float?

        vm.variableStore.anyVariableChanged
            .sink { [weak self, weak vm, weak view] _ in
                guard let self, let vm, let view else { return }
                if vm.variableStore.getValue(name: "readyFlag") as? String == "yes" {
                    readyExp.fulfill()
                }
                if vm.variableStore.getValue(name: "startFlag") as? String == "yes" {
                    if rateAtStart == nil { rateAtStart = self.playerLayer(in: view)?.player?.rate }
                    startExp.fulfill()
                }
                if vm.variableStore.getValue(name: "completeFlag") as? String == "yes" {
                    completeExp.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [readyExp, startExp, completeExp], timeout: 15.0)

        // Rate actually applied (the core "timing ignored" bug): the clip played
        // at 2× once the item was ready, instead of dropping the rate pre-ready.
        XCTAssertEqual(rateAtStart ?? 0, 2.0, accuracy: 0.01, "Configured rate should be live during playback")

        // Freeze: a finished non-looping clip keeps its item and is paused on the
        // last frame (the old bug drained the queue and blanked the layer).
        let player = playerLayer(in: view)?.player
        XCTAssertNotNil(player?.currentItem, "Player should retain its item after completion (frozen frame)")
        XCTAssertEqual(player?.rate ?? -1, 0, "Player should be paused after completion")
    }

    /// `onTimeMark` boundary observers fire and run their actions. Uses normal
    /// rate and an early mark so the (best-effort) boundary observer reliably
    /// lands within the play-through.
    func testTimeMarksFireBoundaryActions() throws {
        try parent.defineVariable(name: "markCount", definition: VariableDefinition(type: .number, initialValue: 0))
        try parent.defineVariable(name: "lastMark", definition: VariableDefinition(type: .string, initialValue: "—"))

        let json = """
        {
            "type": "video", "id": "test-video-marks",
            "content": {
                "properties": {
                    "type": "remoteAsset", "name": "tiny.mp4",
                    "autoplay": true, "loop": false, "muted": true,
                    "marks": [ { "id": "m1", "time": 0.3 } ]
                },
                "style": { "contentMode": "scaleAspectFill" },
                "layout": {
                    "width": 200, "height": 200,
                    "constraints": [
                        { "type": "top", "target": "superview" },
                        { "type": "leading", "target": "superview" }
                    ]
                },
                "actions": {
                    "onTimeMark": [
                        { "type": "incrementVariable", "variableName": "markCount", "by": 1 },
                        { "type": "updateVariable", "variableName": "lastMark", "value": "{{$markId}}" }
                    ]
                }
            }
        }
        """

        let (_, vm) = try makeVideoView(json: json)

        let markExp = expectation(description: "onTimeMark fired")
        markExp.assertForOverFulfill = false
        vm.variableStore.anyVariableChanged
            .sink { [weak vm] _ in
                guard let vm else { return }
                if ((vm.variableStore.getValue(name: "markCount") as? Int) ?? 0) >= 1 {
                    markExp.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [markExp], timeout: 15.0)

        XCTAssertEqual(vm.variableStore.getValue(name: "lastMark") as? String, "m1",
                       "Mark id overlay ($markId) should reach the action")
    }

    // MARK: - Helpers

    private func makeVideoView(json: String) throws -> (CVideoView, CVideoViewModel) {
        let data = json.data(using: .utf8)!
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
        let entity = try XCTUnwrap(component.asEntity())
        let vm = try XCTUnwrap(CVideoViewModel(
            component: entity,
            service: service,
            componentPath: "test-video",
            parentVariableStore: parent
        ))
        let view = CVideoView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.addSubview(view)
        view.configure(viewModel: vm, superview: window)
        window.layoutIfNeeded()
        return (view, vm)
    }

    private func playerLayer(in view: UIView) -> AVPlayerLayer? {
        if let layer = view.layer as? AVPlayerLayer { return layer }
        for sub in view.subviews {
            if let found = playerLayer(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - Fixture data source

/// Returns the bundled fixture bytes for any asset request, mirroring how the
/// host app feeds prefetched video data to the engine.
private final class FixtureVideoDataSource: App8DataSource, @unchecked Sendable {
    private let videoData: Data
    init(videoData: Data) { self.videoData = videoData }

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { videoData }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}
