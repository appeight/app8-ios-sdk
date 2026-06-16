//
//  ScreenTransitionTests.swift
//  App8Engine
//
//  Decode + resolution coverage for the screen-transition DSL. Animator and
//  gesture behavior is verified manually in the TransitionGallery example app;
//  these tests lock down the pure model and preset-expansion layer.
//

import Foundation
import Testing
@testable import App8Engine

private typealias Transition = DSL.Model.ScreenTransition

// MARK: - Helpers

private func decodeTransition(
    _ json: String,
    resolver: ((String) -> Transition.Inline?)? = nil,
    animationResolver: ((String) -> DSL.Model.Animation.Inline?)? = nil
) throws -> Transition {
    let decoder = JSONDecoder()
    if let resolver { decoder.userInfo[.app8TransitionResolver] = resolver }
    if let animationResolver { decoder.userInfo[.app8AnimationResolver] = animationResolver }
    return try decoder.decode(Transition.self, from: Data(json.utf8))
}

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

// MARK: - Reference forms

@Test
func transitionDecodesBareStringPreset() throws {
    let t = try decodeTransition(#""slide""#)
    let inline = try #require(t.inlineOrNil)
    #expect(inline.preset == .slide)
}

@Test
func transitionUnknownBareStringFallsBackToSystem() throws {
    let t = try decodeTransition(#""totally-unknown""#)
    let inline = try #require(t.inlineOrNil)
    #expect(inline.preset == .system)
}

@Test
func transitionDecodesFlatInline() throws {
    let t = try decodeTransition(#"""
    { "mode": "modal", "preset": "cover", "edge": "bottom" }
    """#)
    let inline = try #require(t.inlineOrNil)
    #expect(inline.mode == .modal)
    #expect(inline.preset == .cover)
    #expect(inline.edge == .bottom)
}

@Test
func transitionDecodesWrappedInline() throws {
    let t = try decodeTransition(#"""
    { "id": "hero", "type": "transition", "content": { "preset": "fade" } }
    """#)
    let inline = try #require(t.inlineOrNil)
    #expect(inline.id == "hero")
    #expect(inline.preset == .fade)
}

@Test
func transitionPreservesPointerWithoutResolver() throws {
    let t = try decodeTransition(#"{ "id": "hero" }"#)
    #expect(t.isPointer)
    #expect(t.pointerId == "hero")
    #expect(t.inlineOrNil == nil)
}

@Test
func transitionResolvesPointerWithResolver() throws {
    var target = Transition.Inline.empty
    target.id = "hero"
    target.preset = .slide
    let t = try decodeTransition(#"{ "id": "hero" }"#) { id in id == "hero" ? target : nil }
    let inline = try #require(t.inlineOrNil)
    #expect(inline.preset == .slide)
}

// MARK: - TransitionLength

@Test
func lengthDecodesPoints() throws {
    let translate = try decode(Transition.Translation.self, #"{ "x": 40, "y": 0 }"#)
    #expect(translate.x.resolved(against: 1000) == 40)
}

@Test
func lengthDecodesPercentFraction() throws {
    let translate = try decode(Transition.Translation.self, #"{ "x": "100%", "y": "-50%" }"#)
    #expect(translate.x.resolved(against: 320) == 320)
    #expect(translate.y.resolved(against: 600) == -300)
}

// MARK: - TransitionState defaults

@Test
func transitionStateDefaultsToIdentity() throws {
    let state = try decode(Transition.TransitionState.self, #"{}"#)
    #expect(state.opacity == nil)
    #expect(state.translate.x.resolved(against: 100) == 0)
    #expect(state.scale.x == 1)
    #expect(state.scale.y == 1)
    #expect(state.rotate == 0)
    #expect(state.anchor.x == 0.5)
}

@Test
func scaleDecodesFromSingleNumberOrObject() throws {
    let uniform = try decode(Transition.Scale.self, #"0.5"#)
    #expect(uniform.x == 0.5)
    #expect(uniform.y == 0.5)

    let anisotropic = try decode(Transition.Scale.self, #"{ "x": 0.5, "y": 1.5 }"#)
    #expect(anisotropic.x == 0.5)
    #expect(anisotropic.y == 1.5)
}

// MARK: - Preset expansion

@Test
func slidePresetExpandsToOffscreenIncoming() throws {
    let t = try decodeTransition(#"{ "preset": "slide", "edge": "trailing" }"#)
    let resolved = try #require(Transition.resolve(t))
    #expect(resolved.kind == .custom)
    #expect(resolved.mode == .push)
    // Incoming enters from the trailing edge (one full container width to the right).
    #expect(resolved.to.begin.translate.x.resolved(against: 100) == 100)
    #expect(resolved.to.end.translate.x.resolved(against: 100) == 0)
}

@Test
func zoomPresetDefaultsToModalMode() throws {
    let t = try decodeTransition(#"{ "preset": "zoom" }"#)
    let resolved = try #require(Transition.resolve(t))
    #expect(resolved.mode == .modal)
    #expect(resolved.to.begin.scale.x == 0.92)
    #expect(resolved.to.begin.opacity == 0)
}

@Test
func coverPresetDefaultsToBottomEdge() throws {
    let t = try decodeTransition(#"{ "preset": "cover", "mode": "modal" }"#)
    let resolved = try #require(Transition.resolve(t))
    #expect(resolved.edge == .bottom)
    // Enters from the bottom: +1 container height.
    #expect(resolved.to.begin.translate.y.resolved(against: 800) == 800)
}

@Test
func nonePresetResolvesToNoneKind() throws {
    let t = try decodeTransition(#"{ "preset": "none" }"#)
    let resolved = try #require(Transition.resolve(t))
    #expect(resolved.kind == .none)
}

@Test
func systemPresetResolvesToSystemKind() throws {
    let t = try decodeTransition(#""system""#)
    let resolved = try #require(Transition.resolve(t))
    #expect(resolved.kind == .system)
}

// MARK: - Custom keyframes + explicit reverse

@Test
func customKeyframesOverridePresetSeed() throws {
    let t = try decodeTransition(#"""
    {
      "mode": "push",
      "to":   { "begin": { "opacity": 0, "scale": 0.6, "rotate": -12 }, "end": {} },
      "from": { "begin": {}, "end": { "opacity": 0.4 } }
    }
    """#)
    let resolved = try #require(Transition.resolve(t))
    #expect(resolved.to.begin.opacity == 0)
    #expect(resolved.to.begin.scale.x == 0.6)
    #expect(resolved.to.begin.rotate == -12)
    #expect(resolved.from.end.opacity == 0.4)
    // No explicit reverse → auto-invert (nil reverse participants).
    #expect(resolved.reverseFrom == nil)
    #expect(resolved.reverseTo == nil)
}

@Test
func raiseDefaultsToIncomingAndDecodesOutgoing() throws {
    let defaulted = try #require(Transition.resolve(try decodeTransition(#"{ "preset": "slide" }"#)))
    #expect(defaulted.raise == .incoming)

    let outgoing = try #require(Transition.resolve(try decodeTransition(#"""
    { "mode": "push", "raise": "outgoing",
      "from": { "begin": {}, "end": { "translate": { "x": 0, "y": "100%" } } },
      "to": { "begin": {}, "end": {} } }
    """#)))
    #expect(outgoing.raise == .outgoing)
}

@Test
func explicitReverseDecodesAndResolves() throws {
    let t = try decodeTransition(#"""
    {
      "preset": "slide",
      "reverse": { "from": { "begin": {}, "end": { "opacity": 0 } }, "to": { "begin": {}, "end": {} } }
    }
    """#)
    let resolved = try #require(Transition.resolve(t))
    let reverseFrom = try #require(resolved.reverseFrom)
    #expect(reverseFrom.end.opacity == 0)
}

// MARK: - Animation resolution

@Test
func transitionResolvesAnimationPointerViaResolver() throws {
    let smooth = DSL.Model.Animation.Inline(
        id: "smooth", duration: 0.7, delay: 0, timing: .curve(.easeInOut), options: []
    )
    // Decode with the animation resolver available so the inline `animation`
    // pointer resolves at decode time.
    let t = try decodeTransition(
        #"{ "preset": "fade", "animation": { "id": "smooth" } }"#,
        animationResolver: { id in id == "smooth" ? smooth : nil }
    )
    let resolved = try #require(Transition.resolve(t))
    #expect(resolved.animation.duration == 0.7)
}

// MARK: - Manifest + screen wiring (mirrors the TransitionGallery example shapes)

@Test
func appManifestDecodesTransitionsRegistryAndDefault() throws {
    let json = #"""
    {
      "title": "Gallery",
      "navigation": { "startFlow": "main", "flows": [ { "id": "main", "startScreen": "menu" } ] },
      "animations": [ { "id": "smooth", "type": "animation", "content": { "duration": 0.45, "curve": "easeInOut" } } ],
      "transitions": [
        { "id": "slideTrans", "type": "transition", "content": { "preset": "slide", "edge": "trailing", "animation": { "id": "smooth" } } },
        { "id": "coverModal", "type": "transition", "content": { "preset": "cover", "mode": "modal", "dimming": { "color": "#000000", "opacity": 0.5 } } }
      ],
      "defaultTransition": { "id": "slideTrans" }
    }
    """#
    let app = try decode(DSL.Model.App.self, json)
    #expect(app.transitions?.count == 2)
    // No transition resolver during this decode → registry entries stay pointers
    // until the engine installs the resolver. Default is a pointer too.
    #expect(app.defaultTransition?.pointerId == "slideTrans")
}

@Test
func screenContentDecodesTransitionDefault() throws {
    let json = #"""
    {
      "type": "screen",
      "id": "detailDefault",
      "content": {
        "properties": {},
        "transition": { "preset": "fade" },
        "children": []
      }
    }
    """#
    let component = try decode(DSL.Model.Component.`Any`.self, json)
    let entity: DSL.Model.Component.ConcreteEntity<DSL.Model.Component.View.C>? = component.asConcreteEntity()
    let screenContent = try #require(entity?.content)
    let transition = try #require(screenContent.transition)
    // A screen root's `transition` is the screen-default ScreenTransition form.
    #expect(transition.screenOrNil?.inlineOrNil?.preset == .fade)
}

@Test
func dimmingAndInteractiveDecode() throws {
    let t = try decodeTransition(#"""
    {
      "preset": "cover",
      "mode": "modal",
      "dimming": { "color": "#000000", "opacity": 0.5 },
      "interactive": { "enabled": true, "edge": "bottom", "threshold": 0.25, "velocity": 650 }
    }
    """#)
    let resolved = try #require(Transition.resolve(t))
    let dimming = try #require(resolved.dimming)
    #expect(dimming.opacity == 0.5)
    let interactive = try #require(resolved.interactive)
    #expect(interactive.enabled)
    #expect(interactive.threshold == 0.25)
    #expect(interactive.edge == .bottom)
}

// MARK: - Shared-element (hero / composite) participation

private func decodeComponentTransition(
    _ json: String,
    animationResolver: ((String) -> DSL.Model.Animation.Inline?)? = nil
) throws -> DSL.Model.ComponentTransition {
    let decoder = JSONDecoder()
    if let animationResolver { decoder.userInfo[.app8AnimationResolver] = animationResolver }
    return try decoder.decode(DSL.Model.ComponentTransition.self, from: Data(json.utf8))
}

@Test
func componentTransitionDecodesElementWhenKeyPresent() throws {
    let ct = try decodeComponentTransition(#"""
    { "key": "hero", "morph": "frame", "fallback": "slideTop", "stagger": 0.05 }
    """#)
    let element = try #require(ct.elementOrNil)
    #expect(ct.screenOrNil == nil)
    #expect(element.key == "hero")
    #expect(element.morph == .frame)
    #expect(element.fallback == .slideTop)
    #expect(element.stagger == 0.05)
}

@Test
func componentTransitionElementDefaults() throws {
    let ct = try decodeComponentTransition(#"{ "key": "card" }"#)
    let element = try #require(ct.elementOrNil)
    #expect(element.morph == .frameFade)   // default
    #expect(element.fallback == .fade)     // default
    #expect(element.stagger == nil)
    #expect(element.animation == nil)
}

@Test
func componentTransitionDecodesScreenForBareStringAndPresetObject() throws {
    // Bare string ⇒ screen preset.
    let bare = try decodeComponentTransition(#""fade""#)
    #expect(bare.elementOrNil == nil)
    #expect(bare.screenOrNil?.inlineOrNil?.preset == .fade)

    // Preset object (no `key`) ⇒ screen transition.
    let object = try decodeComponentTransition(#"{ "preset": "slide", "edge": "leading" }"#)
    #expect(object.elementOrNil == nil)
    #expect(object.screenOrNil?.inlineOrNil?.preset == .slide)

    // Pointer object (no `key`) ⇒ screen transition pointer.
    let pointer = try decodeComponentTransition(#"{ "id": "slideTrans" }"#)
    #expect(pointer.elementOrNil == nil)
    #expect(pointer.screenOrNil?.pointerId == "slideTrans")
}

@Test
func sharedPresetResolvesToSharedKind() throws {
    let t = try decodeTransition(#"{ "preset": "shared" }"#)
    let resolved = try #require(Transition.resolve(t))
    #expect(resolved.kind == .shared)
    #expect(resolved.isAnimated)
    // Default backdrop fades the incoming screen in.
    #expect(resolved.to.begin.opacity == 0)
}

@Test
func elementAnimationPointerResolvesViaResolver() throws {
    let dramatic = DSL.Model.Animation.Inline(
        id: "dramatic", duration: 0.6, delay: 0,
        timing: .cubicBezier(x1: 0.16, y1: 1, x2: 0.3, y2: 1), options: []
    )
    let ct = try decodeComponentTransition(
        #"{ "key": "hero", "animation": { "id": "dramatic" } }"#,
        animationResolver: { id in id == "dramatic" ? dramatic : nil }
    )
    let element = try #require(ct.elementOrNil)
    let inline = try #require(element.animation?.inline(resolveBy: { _ in nil }))
    #expect(inline.duration == 0.6)
}

@Test
func componentExposesElementTransitionTypeErased() throws {
    // A child component declaring an element context surfaces it through the
    // type-erased `elementTransition` accessor used by the render pipeline.
    let json = #"""
    {
      "id": "hero-card",
      "type": "view",
      "content": {
        "properties": {},
        "transition": { "key": "hero", "morph": "frameFade" },
        "children": []
      }
    }
    """#
    let component = try decode(DSL.Model.Component.`Any`.self, json)
    let element = try #require(component.elementTransition)
    #expect(element.key == "hero")
    #expect(element.morph == .frameFade)
    // The component id is untouched and independent of the transition key.
    #expect(component.id == "hero-card")
}
