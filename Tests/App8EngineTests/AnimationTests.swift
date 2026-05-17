//
//  AnimationTests.swift
//  App8Engine
//

import Foundation
import Testing
@testable import App8Engine

// MARK: - Helpers

private func decodeAnimation(_ json: String, resolver: ((String) -> DSL.Model.Animation.Inline?)? = nil) throws -> DSL.Model.Animation {
    let decoder = JSONDecoder()
    if let resolver {
        decoder.userInfo[.app8AnimationResolver] = resolver
    }
    return try decoder.decode(DSL.Model.Animation.self, from: Data(json.utf8))
}

// MARK: - Flat form

@Test
func animationDecodesFlatNamedCurve() throws {
    let anim = try decodeAnimation(#"{ "duration": 0.15, "curve": "easeOut" }"#)
    let inline = try #require(anim.inlineOrNil)
    #expect(inline.duration == 0.15)
    #expect(inline.delay == 0)
    if case .curve(let named) = inline.timing {
        #expect(named == .easeOut)
    } else {
        Issue.record("expected named curve, got \(inline.timing)")
    }
    #expect(inline.options.isEmpty)
}

@Test
func animationDecodesFlatLegacySpringWithoutParams() throws {
    let anim = try decodeAnimation(#"{ "duration": 0.4, "curve": "spring" }"#)
    let inline = try #require(anim.inlineOrNil)
    let spring = try #require(inline.springParameters)
    // Legacy `curve: "spring"` has no parameters → defaultSpring values
    #expect(spring.damping == DSL.Model.Animation.Spring.defaultSpring.damping)
    #expect(spring.velocity == DSL.Model.Animation.Spring.defaultSpring.velocity)
}

@Test
func animationDecodesStructuredSpring() throws {
    let anim = try decodeAnimation(#"""
    { "duration": 0.4, "spring": { "damping": 0.8, "velocity": 0.9 } }
    """#)
    let inline = try #require(anim.inlineOrNil)
    let spring = try #require(inline.springParameters)
    #expect(spring.damping == 0.8)
    #expect(spring.velocity == 0.9)
    #expect(spring.mass == nil)
    #expect(spring.stiffness == nil)
}

@Test
func animationDecodesCubicBezier() throws {
    let anim = try decodeAnimation(#"""
    { "duration": 0.2, "cubicBezier": [0.25, 0.1, 0.25, 1.0] }
    """#)
    let inline = try #require(anim.inlineOrNil)
    if case .cubicBezier(let x1, let y1, let x2, let y2) = inline.timing {
        #expect(x1 == 0.25); #expect(y1 == 0.1); #expect(x2 == 0.25); #expect(y2 == 1.0)
    } else {
        Issue.record("expected cubicBezier timing, got \(inline.timing)")
    }
}

@Test
func animationDecodesOptions() throws {
    let anim = try decodeAnimation(#"""
    { "duration": 0.2, "options": ["beginFromCurrent", "allowUserInteraction"] }
    """#)
    let inline = try #require(anim.inlineOrNil)
    #expect(inline.options.contains(.beginFromCurrent))
    #expect(inline.options.contains(.allowUserInteraction))
}

@Test
func animationDecodesDefaultsWhenFieldsAbsent() throws {
    let anim = try decodeAnimation(#"{ "duration": 0.3 }"#)
    let inline = try #require(anim.inlineOrNil)
    #expect(inline.duration == 0.3)
    #expect(inline.delay == 0)
    if case .curve(let named) = inline.timing {
        #expect(named == .easeInOut)
    } else {
        Issue.record("expected default easeInOut")
    }
}

// MARK: - Timing precedence

@Test
func animationPrefersSpringOverCubicBezierOverCurve() throws {
    let anim = try decodeAnimation(#"""
    {
      "duration": 0.3,
      "curve": "easeOut",
      "cubicBezier": [0.25, 0.1, 0.25, 1.0],
      "spring": { "damping": 0.5, "velocity": 0.0 }
    }
    """#)
    let inline = try #require(anim.inlineOrNil)
    #expect(inline.isSpring)
}

// MARK: - Wrapped form

@Test
func animationDecodesWrappedInline() throws {
    let anim = try decodeAnimation(#"""
    {
      "id": "fastPress",
      "type": "animation",
      "content": { "duration": 0.15, "curve": "easeOut" }
    }
    """#)
    let inline = try #require(anim.inlineOrNil)
    #expect(inline.id == "fastPress")
    #expect(inline.duration == 0.15)
}

// MARK: - Pointer form (registry resolution)

@Test
func animationPreservesPointerWithoutResolver() throws {
    let anim = try decodeAnimation(#"{ "id": "fastPress" }"#)
    #expect(anim.isPointer)
    #expect(anim.pointerId == "fastPress")
    #expect(anim.inlineOrNil == nil)
}

@Test
func animationResolvesPointerWithResolver() throws {
    let target = DSL.Model.Animation.Inline(
        id: "fastPress",
        duration: 0.15,
        delay: 0,
        timing: .curve(.easeOut),
        options: []
    )
    let anim = try decodeAnimation(#"{ "id": "fastPress" }"#) { id in
        id == "fastPress" ? target : nil
    }
    let inline = try #require(anim.inlineOrNil)
    #expect(inline.duration == 0.15)
    #expect(inline.id == "fastPress")
}

@Test
func animationLeavesPointerWhenResolverReturnsNil() throws {
    let anim = try decodeAnimation(#"{ "id": "missing" }"#) { _ in nil }
    #expect(anim.isPointer)
}

// MARK: - AnimatedValue<T>

@Test
func animatedValueDecodesBareString() throws {
    let json = #""hello""#
    let value = try JSONDecoder().decode(DSL.Model.AnimatedValue<String>.self, from: Data(json.utf8))
    #expect(value.value == "hello")
    #expect(value.animation == nil)
}

@Test
func animatedValueDecodesWrappedWithAnimation() throws {
    let json = #"""
    {
      "value": "{{ x }}",
      "animation": { "duration": 0.2, "curve": "easeOut" }
    }
    """#
    let value = try JSONDecoder().decode(DSL.Model.AnimatedValue<String>.self, from: Data(json.utf8))
    #expect(value.value == "{{ x }}")
    let inline = try #require(value.animation?.inlineOrNil)
    #expect(inline.duration == 0.2)
}

@Test
func animatedValueDecodesWrappedWithoutAnimation() throws {
    // `value` present but `animation` absent → animation is nil but value
    // is extracted from the object form.
    let json = #"{ "value": 42 }"#
    let value = try JSONDecoder().decode(DSL.Model.AnimatedValue<Int>.self, from: Data(json.utf8))
    #expect(value.value == 42)
    #expect(value.animation == nil)
}

// MARK: - Per-property animation: pointer resolution

@Test
func animatedValuePointerResolvesViaUserInfo() throws {
    let target = DSL.Model.Animation.Inline(
        id: "fastPress", duration: 0.1, delay: 0,
        timing: .curve(.easeOut), options: []
    )
    let decoder = JSONDecoder()
    decoder.userInfo[.app8AnimationResolver] = { @Sendable (id: String) -> DSL.Model.Animation.Inline? in
        id == "fastPress" ? target : nil
    }
    let json = #"""
    { "value": "{{ x }}", "animation": { "id": "fastPress" } }
    """#
    let value = try decoder.decode(DSL.Model.AnimatedValue<String>.self, from: Data(json.utf8))
    #expect(value.value == "{{ x }}")
    let inline = try #require(value.animation?.inlineOrNil)
    #expect(inline.id == "fastPress")
    #expect(inline.duration == 0.1)
}

// MARK: - Component property decode (bare + wrapped, in-scope components)

@Test
func cViewPropertiesDecodesBareTransform() throws {
    let json = #"""
    {
      "transformTranslateY": "{{ scrollY * -0.3 }}",
      "alpha": "{{ scrollY > 100 ? 0 : 1 }}",
      "backgroundColor": "{{ item.color }}"
    }
    """#
    let props = try JSONDecoder().decode(DSL.Model.Component.View.Properties.self, from: Data(json.utf8))
    #expect(props.transformTranslateY?.value == "{{ scrollY * -0.3 }}")
    #expect(props.transformTranslateY?.animation == nil)
    #expect(props.alpha?.value == "{{ scrollY > 100 ? 0 : 1 }}")
    #expect(props.backgroundColor?.value == "{{ item.color }}")
}

@Test
func cViewPropertiesDecodesWrappedTransformWithAnimation() throws {
    let json = #"""
    {
      "transformTranslateX": {
        "value": "{{ x }}",
        "animation": { "duration": 0.2, "curve": "easeOut" }
      },
      "alpha": {
        "value": "{{ visible ? 1 : 0 }}",
        "animation": { "duration": 0.5, "spring": { "damping": 0.7, "velocity": 0 } }
      }
    }
    """#
    let props = try JSONDecoder().decode(DSL.Model.Component.View.Properties.self, from: Data(json.utf8))

    let translateX = try #require(props.transformTranslateX)
    #expect(translateX.value == "{{ x }}")
    let translateXInline = try #require(translateX.animation?.inlineOrNil)
    #expect(translateXInline.duration == 0.2)

    let alpha = try #require(props.alpha)
    #expect(alpha.value == "{{ visible ? 1 : 0 }}")
    let alphaInline = try #require(alpha.animation?.inlineOrNil)
    #expect(alphaInline.duration == 0.5)
    #expect(alphaInline.isSpring)
}

@Test
func cLabelPropertiesDecodesBareBackgroundColor() throws {
    let json = #"""
    { "text": "Hi", "backgroundColor": "{{ item.bg }}" }
    """#
    let props = try JSONDecoder().decode(DSL.Model.Component.Label.Properties.self, from: Data(json.utf8))
    #expect(props.backgroundColor?.value == "{{ item.bg }}")
    #expect(props.backgroundColor?.animation == nil)
}

@Test
func cLabelPropertiesDecodesWrappedBackgroundColor() throws {
    let json = #"""
    {
      "text": "Hi",
      "backgroundColor": {
        "value": "{{ item.bg }}",
        "animation": { "duration": 0.4 }
      }
    }
    """#
    let props = try JSONDecoder().decode(DSL.Model.Component.Label.Properties.self, from: Data(json.utf8))
    let bg = try #require(props.backgroundColor)
    #expect(bg.value == "{{ item.bg }}")
    let inline = try #require(bg.animation?.inlineOrNil)
    #expect(inline.duration == 0.4)
}

@Test
func cIconPropertiesDecodesBareTintAndBackground() throws {
    let json = #"""
    {
      "type": "symbol",
      "name": "checkmark",
      "tintColor": "{{ item.iconColor }}",
      "backgroundColor": "{{ item.bg }}"
    }
    """#
    let props = try JSONDecoder().decode(DSL.Model.Component.Icon.Properties.self, from: Data(json.utf8))
    #expect(props.tintColor?.value == "{{ item.iconColor }}")
    #expect(props.tintColor?.animation == nil)
    #expect(props.backgroundColor?.value == "{{ item.bg }}")
}

@Test
func cIconPropertiesDecodesWrappedTint() throws {
    let json = #"""
    {
      "type": "symbol",
      "name": "checkmark",
      "tintColor": {
        "value": "{{ item.iconColor }}",
        "animation": { "duration": 0.3, "curve": "easeInOut" }
      }
    }
    """#
    let props = try JSONDecoder().decode(DSL.Model.Component.Icon.Properties.self, from: Data(json.utf8))
    let tint = try #require(props.tintColor)
    #expect(tint.value == "{{ item.iconColor }}")
    let inline = try #require(tint.animation?.inlineOrNil)
    #expect(inline.duration == 0.3)
}

@Test
func cShapePropertiesDecodesBareProgress() throws {
    let json = #"""
    { "kind": "arc", "progress": "{{ progress }}", "animationDuration": 0.6, "animationCurve": "easeInOut" }
    """#
    let props = try JSONDecoder().decode(DSL.Model.Component.Shape.Properties.self, from: Data(json.utf8))
    #expect(props.progress?.value == "{{ progress }}")
    #expect(props.progress?.animation == nil)
    // Legacy fallback fields preserved
    #expect(props.animationDuration == 0.6)
    #expect(props.animationCurve == "easeInOut")
}

@Test
func cShapePropertiesDecodesWrappedProgress() throws {
    let json = #"""
    {
      "kind": "arc",
      "progress": {
        "value": "{{ progress }}",
        "animation": { "duration": 0.8, "curve": "linear" }
      }
    }
    """#
    let props = try JSONDecoder().decode(DSL.Model.Component.Shape.Properties.self, from: Data(json.utf8))
    let progress = try #require(props.progress)
    #expect(progress.value == "{{ progress }}")
    let inline = try #require(progress.animation?.inlineOrNil)
    #expect(inline.duration == 0.8)
    if case .curve(let c) = inline.timing { #expect(c == .linear) }
    else { Issue.record("expected linear curve") }
}

// MARK: - Legacy fallback constants

@Test
func legacyFallbackConstantsMatchHistoricBehavior() throws {
    let transform = DSL.Model.Animation.Inline.legacyTransformVariableUpdate
    #expect(transform.duration == 0.3)
    #expect(transform.isSpring)
    let spring = try #require(transform.springParameters)
    #expect(spring.damping == 0.75)
    #expect(spring.velocity == 0.3)

    let alpha = DSL.Model.Animation.Inline.legacyAlphaVariableUpdate
    #expect(alpha.duration == 0.25)
    if case .curve(let curve) = alpha.timing { #expect(curve == .easeOut) }
    else { Issue.record("expected easeOut") }
}
