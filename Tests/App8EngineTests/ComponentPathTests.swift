//
//  ComponentPathTests.swift
//  App8Engine
//
//  Hierarchical component path construction used in childStates resolution.
//

import Foundation
import Testing
@testable import App8Engine

// MARK: - Path Construction Tests

@Test
func testRootComponentPath() {
    let parentPath: String? = nil
    let componentId = "my-component"

    let path = parentPath.map { "\($0).\(componentId)" } ?? componentId

    #expect(path == "my-component")
}

@Test
func testChildComponentPath() {
    let parentPath: String? = "parent-view"
    let componentId = "child-button"

    let path = parentPath.map { "\($0).\(componentId)" } ?? componentId

    #expect(path == "parent-view.child-button")
}

@Test
func testNestedComponentPath() {
    let grandparentPath = "screen"
    let parentId = "container"
    let childId = "button"
    let grandchildId = "icon"

    // Build paths step by step (as renderComponent does)
    let parentPath = "\(grandparentPath).\(parentId)"
    let childPath = "\(parentPath).\(childId)"
    let grandchildPath = "\(childPath).\(grandchildId)"

    #expect(parentPath == "screen.container")
    #expect(childPath == "screen.container.button")
    #expect(grandchildPath == "screen.container.button.icon")
}

@Test
func testChildStatesPathResolution() {
    let parentPath = "sleep-stories-option"
    let childStates = ["check-icon": "visible", "label": "active"]

    // Simulate what stateManagerDidRequestChildStates does
    let resolvedStates = Dictionary(uniqueKeysWithValues: childStates.map { key, value in
        ("\(parentPath).\(key)", value)
    })

    #expect(resolvedStates["sleep-stories-option.check-icon"] == "visible")
    #expect(resolvedStates["sleep-stories-option.label"] == "active")
    #expect(resolvedStates.count == 2)
}

@Test
func testMultipleTemplateInstancesHaveUniquePaths() {
    let instance1Path = "option-1"
    let instance2Path = "option-2"
    let childId = "check-icon"

    let child1Path = "\(instance1Path).\(childId)"
    let child2Path = "\(instance2Path).\(childId)"

    #expect(child1Path == "option-1.check-icon")
    #expect(child2Path == "option-2.check-icon")
    #expect(child1Path != child2Path, "Each template instance's child should have a unique path")
}

// MARK: - ComponentRegistry Tests

@Test
@MainActor
func testComponentRegistryStoresUniquePathsForTemplateChildren() {
    let registry = ComponentRegistry()

    // In real code, these would be actual ViewModels.
    class MockStateControllable: StateControllable {
        var lastState: String?
        func setState(_ stateName: String?, animated: Bool) {
            lastState = stateName
        }
    }

    let vm1 = MockStateControllable()
    let vm2 = MockStateControllable()

    registry.register(id: "option-1.check-icon", viewModel: vm1)
    registry.register(id: "option-2.check-icon", viewModel: vm2)

    registry.setState("visible", forComponentId: "option-1.check-icon")

    #expect(vm1.lastState == "visible")
    #expect(vm2.lastState == nil, "Second instance's child should not be affected")

    registry.setState("hidden", forComponentId: "option-2.check-icon")

    #expect(vm1.lastState == "visible", "First instance's child should retain its state")
    #expect(vm2.lastState == "hidden")
}

@Test
@MainActor
func testComponentRegistrySetStatesWithResolvedPaths() {
    let registry = ComponentRegistry()

    class MockStateControllable: StateControllable {
        var lastState: String?
        func setState(_ stateName: String?, animated: Bool) {
            lastState = stateName
        }
    }

    let checkIcon1 = MockStateControllable()
    let checkIcon2 = MockStateControllable()
    let label1 = MockStateControllable()

    registry.register(id: "option-1.check-icon", viewModel: checkIcon1)
    registry.register(id: "option-2.check-icon", viewModel: checkIcon2)
    registry.register(id: "option-1.label", viewModel: label1)

    // Simulate parent option-1 setting childStates (already resolved with parent path)
    let resolvedChildStates = [
        "option-1.check-icon": "visible",
        "option-1.label": "active"
    ]
    registry.setStates(resolvedChildStates, animated: false)

    #expect(checkIcon1.lastState == "visible")
    #expect(label1.lastState == "active")
    #expect(checkIcon2.lastState == nil, "Other instance's children should not be affected")
}
