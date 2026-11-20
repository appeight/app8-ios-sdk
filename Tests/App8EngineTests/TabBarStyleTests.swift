//
//  TabBarStyleTests.swift
//  App8Engine
//
//  tabBarScreen.barStyle (tab-bar-screen.md, "Bar style").
//

import Foundation
import Testing
@testable import App8Engine

private func decodeTabs(_ barStyle: String?) throws -> DSL.Model.Component.TabBarScreen.TabBarScreenContent {
    let json = """
    {
      "tabs": [
        { "id": "home", "label": "HOME", "icon": "house", "screen": "a" },
        { "id": "bag", "label": "BAG", "icon": "bag", "screen": "b", "badge": "2" }
      ]\(barStyle.map { ", \"barStyle\": \($0)" } ?? "")
    }
    """
    return try JSONDecoder().decode(DSL.Model.Component.TabBarScreen.TabBarScreenContent.self, from: Data(json.utf8))
}

@Test
func tabBarWithoutBarStyleIsTheSystemBar() throws {
    let content = try decodeTabs(nil)
    #expect(content.barStyle == nil)
}

@Test
func barStyleDefaults() throws {
    let style = try #require(try decodeTabs("{}").barStyle)
    #expect(style.variant == .system)
    #expect(style.selection == .capsule)
    #expect(style.background == "glass")
    #expect(style.unselectedOpacity == 0.5)
    #expect(!style.isCustom)
}

@Test
func barStyleTextVariant() throws {
    let style = try #require(try decodeTabs("""
    { "variant": "text", "selection": "opacity", "background": "solid", "text": { "id": "tabLabel" },
      "unselectedOpacity": 1.7, "indicatorColor": "#111111", "height": 52 }
    """).barStyle)
    #expect(style.variant == .text)
    #expect(style.selection == .opacity)
    #expect(style.background == "solid")
    #expect(style.unselectedOpacity == 1) // clamped to 0...1
    #expect(style.indicatorColor == "#111111")
    #expect(style.height == 52)
    #expect((style.text?.value as? [String: Any])?["id"] as? String == "tabLabel")
    #expect(style.isCustom)
}

@Test
func barStyleComponentIsCustomWhateverTheVariant() throws {
    let style = try #require(try decodeTabs(#"{ "component": "MyBar" }"#).barStyle)
    #expect(style.component == "MyBar")
    #expect(style.isCustom)
}

@Test
func unknownBarStyleValuesFallBackToDefaults() throws {
    let style = try #require(try decodeTabs(#"{ "variant": "neon", "selection": "glow" }"#).barStyle)
    #expect(style.variant == .system)
    #expect(style.selection == .capsule)
}

@Test @MainActor
func textBarIsOneSlotPerTabWithItsLabels() throws {
    let style = try #require(try decodeTabs(#"{ "variant": "text", "text": { "id": "tabLabel" }, "selectedText": { "id": "tabLabelOn" } }"#).barStyle)
    let items = [StyledTabBarView.Item(id: "home", label: "HOME", icon: "house"),
                 StyledTabBarView.Item(id: "bag", label: "BAG", icon: "bag")]
    let component = try #require(StyledTabBarView.textBar(items: items, style: style))
    #expect(component.id == "tabBarItems")
    let entity: DSL.Model.Component.StackView.Entity = try #require(component.asConcreteEntity())
    #expect(entity.content.children.count == 2)
    let firstSlot = entity.content.children[0]
    #expect(firstSlot.id == "tabSlot0")
    // `selectedText` adds a second label per slot, cross-faded with the first.
    let slot: DSL.Model.Component.View.Entity = try #require(firstSlot.asConcreteEntity())
    #expect(slot.content.children.map(\.id) == ["tabText0", "tabTextOn0"])
}

@Test
func selectionEasingIsCubicEaseOut() {
    #expect(StyledTabBarView.easeOut(0) == 0)
    #expect(StyledTabBarView.easeOut(1) == 1)
    #expect(abs(StyledTabBarView.easeOut(0.5) - 0.875) < 0.0001)
    #expect(StyledTabBarView.easeOut(2) == 1)
}
