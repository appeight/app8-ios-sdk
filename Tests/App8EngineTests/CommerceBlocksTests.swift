//
//  CommerceBlocksTests.swift
//  App8EngineTests
//
//  DSL 0.5.0 commerce building blocks: context menu, native zoom, scroll zoom
//  and stretchy top, picker menu look + bindKey, tab badge colors, persisted
//  variables, object key access, two-way currentPageVariable.
//

import Foundation
import Testing
import UIKit
@testable import App8Engine

private func decodeComponent(_ json: String) throws -> DSL.Model.Component.`Any` {
    try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: Data(json.utf8))
}

// MARK: - Object key access

@MainActor
@Suite("Expressions: map[key]")
struct ObjectKeyAccessTests {
    let store: VariableStore
    let resolver = PropertyResolver()

    init() throws {
        store = VariableStore()
        try store.defineVariable(name: "selectedVariants", definition: VariableDefinition(type: .object, initialValue: ["mask-50": "100 ml", "3": "three"]))
        try store.defineVariable(name: "item", definition: VariableDefinition(type: .object, initialValue: ["handle": "mask-50", "variant": "50 ml"]))
        try store.defineVariable(name: "other", definition: VariableDefinition(type: .object, initialValue: ["handle": "serum", "variant": "30 ml"]))
    }

    private func eval(_ expression: String) throws -> Any {
        try resolver.resolve(expression, context: VariableContext(store: store))
    }

    @Test func stringKeyReadsProperty() throws {
        #expect(try eval("{{selectedVariants[item.handle]}}") as? String == "100 ml")
    }

    @Test func missingKeyIsNullAndFallsBack() throws {
        let expr = "{{selectedVariants[other.handle] != null ? selectedVariants[other.handle] : other.variant}}"
        #expect(try eval(expr) as? String == "30 ml")
        let hit = "{{selectedVariants[item.handle] != null ? selectedVariants[item.handle] : item.variant}}"
        #expect(try eval(hit) as? String == "100 ml")
    }

    @Test func numberKeyReadsStringKey() throws {
        #expect(try eval("{{selectedVariants[3]}}") as? String == "three")
    }
}

// MARK: - Persisted variables

@MainActor
@Suite("Persisted app variables")
struct PersistedVariableTests {

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "app8.test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func decodesPersistFlag() throws {
        let json = #"{ "type": "array", "initialValue": [], "persist": true }"#
        let def = try JSONDecoder().decode(VariableDefinition.self, from: Data(json.utf8))
        #expect(def.persist == true)
    }

    @Test func savesAndRestoresAcrossStores() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let def = VariableDefinition(type: .array, initialValue: [Any](), persist: true)

        let store1 = VariableStore()
        try store1.defineVariable(name: "wishlist", definition: def)
        let p1 = VariablePersistence(appId: "t", store: store1, logger: nil, defaults: defaults)
        p1.adopt(name: "wishlist", definition: def)
        try store1.setValue(name: "wishlist", value: ["mask", "serum"])
        p1.flush()

        let store2 = VariableStore()
        try store2.defineVariable(name: "wishlist", definition: def)
        let p2 = VariablePersistence(appId: "t", store: store2, logger: nil, defaults: defaults)
        p2.adopt(name: "wishlist", definition: def)
        #expect(store2.getValue(name: "wishlist") as? [String] == ["mask", "serum"])

        // resetVariables returns to initialValue and clears the stored value.
        store2.resetToInitialValues()
        #expect((store2.getValue(name: "wishlist") as? [Any])?.isEmpty == true)
        p2.flush()
        #expect(defaults.data(forKey: "var.wishlist") == nil)
    }

    @Test func typeMismatchIsDropped() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONSerialization.data(withJSONObject: ["oops"]), forKey: "var.cart")
        let def = VariableDefinition(type: .array, initialValue: [Any](), persist: true)
        let store = VariableStore()
        try store.defineVariable(name: "cart", definition: def)
        let p = VariablePersistence(appId: "t", store: store, logger: nil, defaults: defaults)
        p.adopt(name: "cart", definition: def)
        #expect((store.getValue(name: "cart") as? [Any])?.isEmpty == true)
        #expect(defaults.data(forKey: "var.cart") == nil)
    }

    @Test func persistenceIdFallsBack() throws {
        let app = try JSONDecoder().decode(DSL.Model.App.self, from: Data(#"{ "title": "Facetheory", "bundleId": "com.ft" }"#.utf8))
        #expect(app.persistenceId == "com.ft")
        let bare = try JSONDecoder().decode(DSL.Model.App.self, from: Data(#"{ "title": "Facetheory" }"#.utf8))
        #expect(bare.persistenceId == (Bundle.main.bundleIdentifier ?? "default"))
        let withId = try JSONDecoder().decode(DSL.Model.App.self, from: Data(#"{ "id": "ft", "bundleId": "com.ft" }"#.utf8))
        #expect(withId.persistenceId == "ft")
    }
}

// MARK: - Picker

@MainActor
@Suite("Picker menu look and bindKey")
struct PickerCommerceTests {

    static let variantMenu = """
    {
      "type": "view", "id": "root",
      "content": {
        "variables": {
          "selectedVariants": { "type": "object", "initialValue": {} },
          "item": { "type": "object", "initialValue": { "handle": "mask", "variant": "50", "variants": [ { "value": "50", "label": "50 ml" }, { "value": "100", "label": "100 ml" } ] } }
        },
        "children": [{
          "type": "picker",
          "id": "variantMenu",
          "content": {
            "properties": {
              "displayMode": "menu",
              "options": "{{item.variants}}",
              "selectedValue": "{{selectedVariants[item.handle] != null ? selectedVariants[item.handle] : item.variant}}",
              "bindVariable": "selectedVariants",
              "bindKey": "{{item.handle}}"
            },
            "style": { "label": { "fontSize": 13, "color": "#8A8A8A" }, "indicator": "chevron.up.chevron.down" },
            "layout": { "leading": 0, "top": 4 }
          }
        }]
      }
    }
    """

    @Test func decodesExpressionOptionsBindKeyAndStyle() throws {
        let component = try decodeComponent(Self.variantMenu)
        let root: DSL.Model.Component.View.Entity = try #require(component.asConcreteEntity())
        let picker: DSL.Model.Component.Picker.Entity = try #require(root.content.children.first?.asConcreteEntity())
        #expect(picker.content.properties.optionsExpression == "{{item.variants}}")
        #expect(picker.content.properties.options == nil)
        #expect(picker.content.properties.bindKey == "{{item.handle}}")
        #expect(picker.content.style?.label?.fontSize == 13)
        #expect(picker.content.style?.indicator == "chevron.up.chevron.down")
        #expect(picker.content.style?.usesPullDownLook == true)
    }

    @Test func bindKeyWritesIntoObjectMap() throws {
        let harness = RenderHarness()
        try harness.render(Self.variantMenu)
        let vm: CPickerViewModel = try #require(harness.viewModel("root.variantMenu"))
        #expect(vm.currentOptions.map(\.label) == ["50 ml", "100 ml"])
        #expect(vm.currentSelection == "50")

        vm.selectionChanged.send("100")
        let map = vm.variableStore.getValue(name: "selectedVariants") as? [String: Any]
        #expect(map?["mask"] as? String == "100")

        let button = try #require(harness.find(UIButton.self))
        #expect(button.configuration != nil)
        #expect(button.showsMenuAsPrimaryAction)
        #expect(button.changesSelectionAsPrimaryAction)
    }
}

// MARK: - Tab bar badge colors

@Suite("Tab bar badge colors")
struct TabBadgeColorTests {
    @Test func decodesBarAndPerTabBadgeColors() throws {
        let json = """
        {
          "type": "tabBarScreen", "id": "main",
          "content": {
            "tabs": [
              { "id": "home", "label": "Home", "icon": "house", "screen": "home" },
              { "id": "bag", "label": "Bag", "icon": "bag", "screen": "bag", "badge": "{{length(cart)}}", "badgeColor": "#AA0000" }
            ],
            "badgeColor": "#2D4D3A",
            "badgeTextColor": "#FFFFFF"
          }
        }
        """
        let component = try decodeComponent(json)
        let entity: DSL.Model.Component.TabBarScreen.Entity = try #require(component.asConcreteEntity())
        #expect(entity.content.badgeColor == "#2D4D3A")
        #expect(entity.content.badgeTextColor == "#FFFFFF")
        #expect(entity.content.tabs[1].badgeColor == "#AA0000")
        #expect(entity.content.tabs[0].badgeColor == nil)
    }
}

// MARK: - Context menu

@MainActor
@Suite("Context menu")
struct ContextMenuTests {

    static let card = """
    {
      "type": "view",
      "id": "productCard",
      "content": {
        "variables": {
          "item": { "type": "object", "initialValue": { "handle": "mask", "title": "Mask" } },
          "wishlist": { "type": "array", "initialValue": ["mask"] }
        },
        "contextMenu": {
          "preview": { "component": { "type": "view", "id": "quick", "content": { "layout": { "height": 200 } } }, "width": 340 },
          "items": [
            { "id": "add", "title": "Add to bag", "icon": "bag", "actions": [ { "type": "updateVariable", "variableName": "item", "value": { "handle": "x" } } ] },
            { "id": "wish", "title": "{{wishlist.includes(item.handle) ? 'Remove from wishlist' : 'Add to wishlist'}}", "icon": "{{wishlist.includes(item.handle) ? 'heart.fill' : 'heart'}}", "actions": [ { "type": "toggleArrayValue", "variableName": "wishlist", "value": "{{item.handle}}" } ] },
            { "id": "gone", "title": "Hidden", "hidden": true, "actions": [] },
            { "id": "del", "title": "Remove", "destructive": true, "isEnabled": false, "actions": [] }
          ],
          "onPreviewTap": [ { "type": "navigation", "nextScreen": "product", "params": { "product": "{{item}}" } } ]
        }
      }
    }
    """

    @Test func decodesSpecShape() throws {
        let entity: DSL.Model.Component.View.Entity = try #require(try decodeComponent(Self.card).asConcreteEntity())
        let menu = try #require(entity.content.contextMenu)
        #expect(menu.items.map(\.id) == ["add", "wish", "gone", "del"])
        #expect(menu.preview?.width == 340)
        #expect(menu.onPreviewTap.count == 1)
        #expect(menu.items[3].destructive)
        #expect(menu.items[3].isEnabled == "false")
    }

    @Test func templatePreviewWithoutIdDecodes() throws {
        let json = #"{ "preview": { "component": { "templateId": "ProductQuickView" } }, "items": [] }"#
        let menu = try JSONDecoder().decode(DSL.Model.ContextMenu.self, from: Data(json.utf8))
        #expect(menu.preview?.component.templateId == "ProductQuickView")
    }

    @Test func menuEvaluatesItemsAtOpen() throws {
        let harness = RenderHarness()
        try harness.render(Self.card)
        let view = try #require(harness.find(CView.self))
        #expect(view.interactions.contains { $0 is UIContextMenuInteraction })
        let binders = view.interactions.compactMap { ($0 as? UIContextMenuInteraction)?.delegate as? ContextMenuBinder }
        let binder = try #require(binders.first)
        let menu = try #require(binder.makeMenu())
        let actions = menu.children.compactMap { $0 as? UIAction }
        #expect(actions.map(\.title) == ["Add to bag", "Remove from wishlist", "Remove"])
        #expect(actions[2].attributes.contains(.destructive))
        #expect(actions[2].attributes.contains(.disabled))
    }
}

// MARK: - Scroll view zoom / stretchy

@Suite("ScrollView zoom and stretchy top")
struct ScrollViewCommerceTests {
    @Test func decodesZoomAndStretchProperties() throws {
        let json = #"{ "minimumZoomScale": 1, "maximumZoomScale": 4, "doubleTapZoom": false, "stretchesTopChild": true }"#
        let props = try JSONDecoder().decode(DSL.Model.Component.ScrollView.Properties.self, from: Data(json.utf8))
        #expect(props.maximumZoomScale == 4)
        #expect(props.doubleTapZoom == false)
        #expect(props.stretchesTopChild == true)
        #expect(props.zoomEnabled)
        let plain = try JSONDecoder().decode(DSL.Model.Component.ScrollView.Properties.self, from: Data("{}".utf8))
        #expect(!plain.zoomEnabled)
    }
}

// MARK: - Native zoom transition

@Suite("Native zoom transition")
struct NativeZoomTransitionTests {
    @Test func zoomWithSourceKeyResolvesToNativeZoomPush() throws {
        let json = #"{ "preset": "zoom", "sourceKey": "{{'card-' + item.handle}}", "alignmentKey": "hero", "dismissGesture": "down" }"#
        let transition = try JSONDecoder().decode(DSL.Model.ScreenTransition.self, from: Data(json.utf8))
        let inline = try #require(transition.inlineOrNil)
        let resolved = DSL.Model.ScreenTransition.resolve(inline)
        #expect(resolved.kind == .nativeZoom)
        #expect(resolved.mode == .push)
        #expect(resolved.nativeZoom?.sourceKeyExpression == "{{'card-' + item.handle}}")
        #expect(resolved.nativeZoom?.alignmentKeyExpression == "hero")
        #expect(resolved.nativeZoom?.dismissGesture == .down)
    }

    @Test func plainZoomKeepsModalScalePreset() throws {
        let transition = try JSONDecoder().decode(DSL.Model.ScreenTransition.self, from: Data(#""zoom""#.utf8))
        let resolved = DSL.Model.ScreenTransition.resolve(try #require(transition.inlineOrNil))
        #expect(resolved.kind == .custom)
        #expect(resolved.mode == .modal)
    }

    @MainActor
    @Test func keyLocatorResolvesExpressionKeys() throws {
        let harness = RenderHarness()
        try harness.render("""
        {
          "type": "view", "id": "screen",
          "content": {
            "variables": { "item": { "type": "object", "initialValue": { "handle": "mask" } } },
            "children": [{
              "type": "view", "id": "card",
              "content": { "transition": { "key": "{{'card-' + item.handle}}" }, "layout": { "width": 100, "height": 100 } }
            }]
          }
        }
        """)
        let found = TransitionKeyLocator.view(forKey: "card-mask", in: harness.superview)
        #expect(found?.accessibilityIdentifier == "card")
        #expect(TransitionKeyLocator.view(forKey: "card-other", in: harness.superview) == nil)
    }
}

// MARK: - updateVariable key / collection "fill" sizes

@MainActor
@Suite("updateVariable key and fill item sizes")
struct CommerceAddendumTests {

    @Test func updateVariableWithKeySetsOneKey() throws {
        let store = VariableStore()
        try store.defineVariable(name: "selectedVariants", definition: VariableDefinition(type: .object, initialValue: ["serum": "30"]))
        try store.defineVariable(name: "product", definition: VariableDefinition(type: .object, initialValue: ["handle": "mask"]))
        let json = #"{ "type": "updateVariable", "variableName": "selectedVariants", "key": "{{product.handle}}", "value": "100" }"#
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: Data(json.utf8))
        try VariableActionHandler().execute(action: action, store: store, context: VariableContext(store: store))
        let map = try #require(store.getValue(name: "selectedVariants") as? [String: Any])
        #expect(map["mask"] as? String == "100")
        #expect(map["serum"] as? String == "30")
    }

    @Test func horizontalLayoutDecodesFillSizes() throws {
        let json = #"{ "type": "horizontal", "itemWidth": "fill", "itemHeight": "fill", "pagingStyle": "paging" }"#
        let layout = try JSONDecoder().decode(DSL.Model.Component.Collection.Layout.self, from: Data(json.utf8))
        #expect(layout.itemWidthFill && layout.itemHeightFill)
        #expect(layout.itemWidth == nil && layout.itemHeight == nil)
        let fixed = try JSONDecoder().decode(DSL.Model.Component.Collection.Layout.self, from: Data(#"{ "type": "horizontal", "itemWidth": 280, "itemHeight": 200 }"#.utf8))
        #expect(fixed.itemWidth == 280 && fixed.itemHeight == 200 && !fixed.itemHeightFill)
    }

    @Test func fillPagerItemsMatchCollectionHeight() throws {
        let harness = RenderHarness()
        try harness.render("""
        {
          "type": "view", "id": "root",
          "content": {
            "variables": { "pages": { "type": "array", "initialValue": ["a", "b", "c"] } },
            "children": [{
              "type": "collection", "id": "pager",
              "content": {
                "properties": { "data": "{{pages}}", "layout": { "type": "horizontal", "itemWidth": "fill", "itemHeight": "fill", "pagingStyle": "paging" } },
                "layout": { "top": 0, "leading": 0, "trailing": 0, "height": 500 },
                "template": { "type": "view", "id": "page", "content": {} }
              }
            }]
          }
        }
        """)
        harness.drain(0.3)
        let collection = try #require(harness.find(UICollectionView.self))
        collection.layoutIfNeeded()
        let attrs = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        #expect(abs(attrs.frame.height - collection.bounds.height) < 1)
        #expect(abs(attrs.frame.width - collection.bounds.width) < 1)
    }
}

// MARK: - Native QA fixes

@MainActor
@Suite("Native QA fixes")
struct NativeQAFixTests {

    @Test func jsonNumberOnePrintsAsNumberNotTrue() throws {
        let restored = try JSONSerialization.jsonObject(with: Data(#"[{"key":"a","quantity":1}]"#.utf8)) as! [Any]
        let store = VariableStore()
        try store.defineVariable(name: "cart", definition: VariableDefinition(type: .array, initialValue: [Any]()))
        try store.setValue(name: "cart", value: restored)
        let text = try PropertyResolver().resolveToString("{{find(cart, item.key == 'a').quantity}} ADDED", context: VariableContext(store: store))
        #expect(text == "1 ADDED")
        let native = VariablePersistence.native(restored) as? [[String: Any]]
        #expect(native?.first?["quantity"] as? Int == 1)
        #expect(VariablePersistence.native(NSNumber(value: true)) as? Bool == true)
    }

    @Test func computedSeesEarlierSiblings() throws {
        let store = VariableStore()
        try store.defineVariables([
            "item": VariableDefinition(type: .object, initialValue: ["handle": "h", "variant": "50"]),
            "selVariant": VariableDefinition(type: .string, computed: "{{item.variant}}"),
            "cardKey": VariableDefinition(type: .string, computed: "{{item.handle + '|' + selVariant}}"),
        ])
        #expect(store.getValue(name: "cardKey") as? String == "h|50")
    }

    @Test func pickerButtonCarriesTheDSLId() throws {
        let harness = RenderHarness()
        try harness.render(PickerCommerceTests.variantMenu)
        let button = try #require(harness.find(UIButton.self))
        #expect(button.accessibilityIdentifier == "variantMenu")
    }
}
