import Foundation
import Testing
@testable import App8Engine

private func truncated(_ s: String, limit: Int = 2_000) -> String {
    guard s.count > limit else { return s }
    return s.prefix(limit) + "… (truncated)"
}

private enum Fixtures {
    static let subdir = "Fixtures"
    static func allJSON() -> [URL] {
        let jsonUrls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil)
        return (jsonUrls ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func loadString(_ url: URL) throws -> String {
        try String(decoding: Data(contentsOf: url), as: UTF8.self)
    }
}

@Test
func parsesAllValidFixtures() throws {
    let urls = Fixtures.allJSON()
    guard !urls.isEmpty else {
        return
    }

    for url in urls {
        let json = try Fixtures.loadString(url)
        do {
            let data = json.data(using: .utf8)!
            let app = try JSONDecoder().decode(DSL.Model.App.self, from: data)
            #expect((app.title ?? "").isEmpty == false, "Expected non-empty App title for \(url.lastPathComponent)")
        } catch {
            let note = """
            Failed to parse \(url.lastPathComponent): \(error)

            --- JSON preview ---
            \(truncated(json))
            """
            Issue.record(error, Comment(stringLiteral: note))
            throw error
        }
    }
}

// MARK: - State & Triggers Tests

@Test
func parsesComponentWithTriggers() throws {
    let json = """
    {
        "type": "button",
        "id": "test-button",
        "content": {
            "properties": { "text": "Press Me" },
            "style": {},
            "triggers": {
                "touchDown": "pressed",
                "touchUp": "normal"
            },
            "defaultStateName": "normal",
            "states": {
                "normal": {
                    "properties": { "text": "Normal" },
                    "style": { "alpha": 1.0 }
                },
                "pressed": {
                    "properties": { "text": "Pressed" },
                    "style": { "alpha": 0.5 }
                }
            }
        }
    }
    """

    let data = json.data(using: .utf8)!
    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)

    #expect(component.id == "test-button")
    #expect(component.type.isOneOf(.button))

    guard let entity: DSL.Model.Component.ConcreteEntity<DSL.Model.Component.Button.C> = component.asConcreteEntity() else {
        Issue.record("Expected ConcreteEntity<Button.C>")
        return
    }

    let content = entity.content
    #expect(content.defaultStateName == "normal")
    #expect(content.states?.count == 2)
    #expect(content.triggers?.count == 2)
    #expect(content.triggers?[.touchDown] == "pressed")
    #expect(content.triggers?[.touchUp] == "normal")
}

@Test
func parsesComponentWithStatesAndAnimation() throws {
    let json = """
    {
        "type": "view",
        "id": "test-view",
        "content": {
            "properties": {},
            "style": { "alpha": 1.0 },
            "defaultStateName": "normal",
            "states": {
                "normal": {
                    "properties": {},
                    "style": { "alpha": 1.0 },
                    "animation": { "duration": 0.3, "curve": "easeOut" }
                },
                "highlighted": {
                    "properties": {},
                    "style": { "alpha": 0.5 },
                    "animation": { "duration": 0.1, "curve": "easeIn" },
                    "childStates": {
                        "child-1": "active",
                        "child-2": "active"
                    }
                }
            }
        }
    }
    """

    let data = json.data(using: .utf8)!
    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)

    guard let entity: DSL.Model.Component.ConcreteEntity<DSL.Model.Component.View.C> = component.asConcreteEntity() else {
        Issue.record("Expected ConcreteEntity<View.C>")
        return
    }

    let content = entity.content
    #expect(content.defaultStateName == "normal")
    #expect(content.states?.count == 2)

    let normalState = content.states?["normal"]
    let normalInline = try #require(normalState?.animation?.inlineOrNil)
    #expect(normalInline.duration == 0.3)
    if case .curve(let named) = normalInline.timing { #expect(named == .easeOut) }
    else { Issue.record("expected .curve(.easeOut)") }

    let highlightedState = content.states?["highlighted"]
    let highlightedInline = try #require(highlightedState?.animation?.inlineOrNil)
    #expect(highlightedInline.duration == 0.1)
    if case .curve(let named) = highlightedInline.timing { #expect(named == .easeIn) }
    else { Issue.record("expected .curve(.easeIn)") }
    #expect(highlightedState?.childStates?["child-1"] == "active")
    #expect(highlightedState?.childStates?["child-2"] == "active")
}
