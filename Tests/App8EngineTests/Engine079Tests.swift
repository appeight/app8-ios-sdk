//
//  Engine079Tests.swift
//  App8Engine
//
//  0.7.9: selectionIndicatorColor, itemWidth "auto", repeat loops, edges on a centre.
//

import UIKit
import Testing
@testable import App8Engine

@Test
func selectionIndicatorColorDecodes() throws {
    let json = ##"{ "tabs": [{ "id": "a", "label": "A", "icon": "house", "screen": "a" }], "selectionIndicatorColor": "#E0A10040" }"##
    let content = try JSONDecoder().decode(DSL.Model.Component.TabBarScreen.TabBarScreenContent.self, from: Data(json.utf8))
    #expect(content.selectionIndicatorColor == "#E0A10040")
    let plain = try JSONDecoder().decode(DSL.Model.Component.TabBarScreen.TabBarScreenContent.self, from: Data(#"{ "tabs": [] }"#.utf8))
    #expect(plain.selectionIndicatorColor == nil)
}

@Test @MainActor
func defaultSelectionIndicatorIsTenPercentBlackOrWhite() {
    let light = TabBarScreenViewController.defaultSelectionIndicatorColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    let dark = TabBarScreenViewController.defaultSelectionIndicatorColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    var w: CGFloat = 0, a: CGFloat = 0
    light.getWhite(&w, alpha: &a)
    #expect(w == 0 && abs(a - 0.1) < 0.001)
    dark.getWhite(&w, alpha: &a)
    #expect(w == 1 && abs(a - 0.1) < 0.001)
}

@Test
func itemWidthAutoDecodes() throws {
    let json = #"{ "type": "horizontal", "itemWidth": "auto", "itemHeight": 36 }"#
    let layout = try JSONDecoder().decode(DSL.Model.Component.Collection.Layout.self, from: Data(json.utf8))
    #expect(layout.itemWidthAuto)
    #expect(layout.itemWidth == nil)
    #expect(!layout.itemWidthFill)
}

@Test
func repeatLoopRotatesByTheAngle() throws {
    let anim = try JSONDecoder().decode(DSL.Model.Animation.Inline.self, from: Data(#"{ "duration": 10, "curve": "linear", "options": ["repeat"] }"#.utf8))
    let loop = try #require(RepeatLoop(property: .rotation, from: 0, to: -360, animation: anim))
    let ca = loop.makeAnimation()
    #expect(ca.keyPath == "transform.rotation.z")
    #expect(ca.isAdditive)
    #expect(ca.repeatCount == .infinity)
    #expect(abs((ca.fromValue as! CGFloat) - 2 * .pi) < 0.0001)
    #expect((ca.toValue as! Int) == 0)
    #expect(ca.duration == 10)
    // Without `repeat`, or with nothing to move, there is no loop.
    let once = try JSONDecoder().decode(DSL.Model.Animation.Inline.self, from: Data(#"{ "duration": 1 }"#.utf8))
    #expect(RepeatLoop(property: .rotation, from: 0, to: -360, animation: once) == nil)
    #expect(RepeatLoop(property: .rotation, from: -360, to: -360, animation: anim) == nil)
}

@Test
func repeatLoopRestValues() {
    #expect(RepeatLoop.Property.rotation.rest == 0)
    #expect(RepeatLoop.Property.translateX.rest == 0)
    #expect(RepeatLoop.Property.scale.rest == 1)
    #expect(RepeatLoop.Property.alpha.rest == 1)
}

@Test @MainActor
func repeatLoopsStayInstalledAndRestart() throws {
    let anim = try JSONDecoder().decode(DSL.Model.Animation.Inline.self, from: Data(#"{ "duration": 2, "curve": "linear", "options": ["repeat"] }"#.utf8))
    let view = UIView()
    let loops = RepeatLoops(layer: view.layer)
    loops.set(RepeatLoop(property: .rotation, from: 0, to: 360, animation: anim), for: .rotation)
    let first = try #require(view.layer.animation(forKey: "a8.repeat.rotation"))
    // The same loop again keeps the running animation (no restart on a re-apply).
    loops.set(RepeatLoop(property: .rotation, from: 0, to: 360, animation: anim), for: .rotation)
    #expect(view.layer.animation(forKey: "a8.repeat.rotation") === first)
    view.layer.removeAllAnimations()
    loops.restartAll()
    #expect(view.layer.animation(forKey: "a8.repeat.rotation") != nil)
    loops.set(nil, for: .rotation)
    #expect(view.layer.animation(forKey: "a8.repeat.rotation") == nil)
    #expect(loops.isEmpty)
}
