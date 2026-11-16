//
//  AnimatedVisibilityTests.swift
//  App8EngineTests
//
//  `properties.isHidden` in the wrapped `{ value, animation }` form (animated
//  visibility: a disclosure row in a stack opens and closes in one animated
//  layout pass, elsewhere it cross-fades) and `view.properties.transformRotation`.
//  docs/animations.md "Animated visibility" and "transformRotation".
//

import XCTest
@testable import App8Engine

@MainActor
final class AnimatedVisibilityTests: XCTestCase {

    private var harness: RenderHarness!

    override func tearDown() {
        HiddenTransition.isReduceMotionEnabled = { UIAccessibility.isReduceMotionEnabled }
        harness = nil
        super.tearDown()
    }

    // MARK: - Decoding

    private func decode<C: Decodable>(_ type: C.Type, _ json: String) throws -> C {
        try JSONDecoder().decode(C.self, from: Data(json.utf8))
    }

    private let wrappedHidden = """
    "isHidden": { "value": "{{ !includes(openRows, 'shipping') }}",
                  "animation": { "duration": 0.3, "cubicBezier": [0.33, 1, 0.68, 1] } }
    """

    func testWrappedIsHiddenDecodesOnEveryComponentType() throws {
        let view = try decode(DSL.Model.Component.View.C.self, "{ \"properties\": { \(wrappedHidden) } }")
        let label = try decode(DSL.Model.Component.Label.C.self, "{ \"properties\": { \"text\": \"Shipping\", \(wrappedHidden) } }")
        let icon = try decode(DSL.Model.Component.Icon.C.self,
                              "{ \"properties\": { \"type\": \"symbol\", \"name\": \"chevron.down\", \(wrappedHidden) } }")
        let stack = try decode(DSL.Model.Component.StackView.C.self, "{ \"properties\": { \"axis\": \"vertical\", \(wrappedHidden) } }")

        let expression = "{{ !includes(openRows, 'shipping') }}"
        for content in [view as any DSL.Model.Component.EntityContent, label, icon, stack] {
            XCTAssertEqual(content.hiddenFlag, expression, "\(type(of: content)): the wrapped value is the flag")
            let animation = try XCTUnwrap(content.hiddenAnimation?.inlineOrNil, "\(type(of: content))")
            XCTAssertEqual(animation.duration, 0.3, accuracy: 0.0001)
            guard case .cubicBezier(let x1, let y1, let x2, let y2) = animation.timing else {
                return XCTFail("cubic-bezier timing expected")
            }
            XCTAssertEqual([x1, y1, x2, y2], [0.33, 1, 0.68, 1])
        }
        // The typed properties see the wrapped value too (never "not hidden").
        XCTAssertEqual(view.properties.isHidden, expression)
        XCTAssertEqual(label.properties.isHidden, expression)
        XCTAssertEqual(icon.properties.isHidden, expression)
    }

    func testWrappedLiteralBooleanAndBareFormsDecode() throws {
        let wrappedBool = try decode(DSL.Model.Component.View.C.self,
                                     #"{ "properties": { "isHidden": { "value": true, "animation": { "duration": 0.2 } } } }"#)
        XCTAssertEqual(wrappedBool.hiddenFlag, "true")
        XCTAssertNotNil(wrappedBool.hiddenAnimation)

        let bareBool = try decode(DSL.Model.Component.Label.C.self, #"{ "properties": { "text": "x", "isHidden": true } }"#)
        XCTAssertEqual(bareBool.hiddenFlag, "true")
        XCTAssertNil(bareBool.hiddenAnimation, "the bare form stays instant")

        let bareExpr = try decode(DSL.Model.Component.StackView.C.self, #"{ "properties": { "isHidden": "{{ hide }}" } }"#)
        XCTAssertEqual(bareExpr.hiddenFlag, "{{ hide }}")
        XCTAssertNil(bareExpr.hiddenAnimation)

        let wrappedNoAnimation = try decode(DSL.Model.Component.Icon.C.self,
                                            #"{ "properties": { "type": "symbol", "name": "x", "isHidden": { "value": "{{ hide }}" } } }"#)
        XCTAssertEqual(wrappedNoAnimation.hiddenFlag, "{{ hide }}")
        XCTAssertNil(wrappedNoAnimation.hiddenAnimation)
    }

    func testStateIsHiddenTakesTheWrappedForm() throws {
        let content = try decode(DSL.Model.Component.View.C.self, """
        { "properties": {},
          "states": { "closed": { "properties": { \(wrappedHidden) } } } }
        """)
        let state = try XCTUnwrap(content.states?["closed"])
        XCTAssertEqual(state.hiddenFlag, "{{ !includes(openRows, 'shipping') }}")
        XCTAssertNotNil(state.hiddenAnimation)
    }

    func testTransformRotationDecodes() throws {
        let number = try decode(DSL.Model.Component.View.Properties.self, #"{ "transformRotation": 45 }"#)
        XCTAssertEqual(number.transformRotation?.value, "45.0")
        XCTAssertNil(number.transformRotation?.animation)

        let expression = try decode(DSL.Model.Component.View.Properties.self, #"{ "transformRotation": "{{ open ? 180 : 0 }}" }"#)
        XCTAssertEqual(expression.transformRotation?.value, "{{ open ? 180 : 0 }}")

        let wrapped = try decode(DSL.Model.Component.View.Properties.self, """
        { "transformRotation": { "value": "{{ open ? 180 : 0 }}",
                                 "animation": { "duration": 0.3, "cubicBezier": [0.33, 1, 0.68, 1] } } }
        """)
        XCTAssertEqual(wrapped.transformRotation?.value, "{{ open ? 180 : 0 }}")
        XCTAssertEqual(wrapped.transformRotation?.animation?.inlineOrNil?.duration ?? 0, 0.3, accuracy: 0.0001)

        let wrappedNumber = try decode(DSL.Model.Component.View.Properties.self, #"{ "transformRotation": { "value": 90 } }"#)
        XCTAssertEqual(wrappedNumber.transformRotation?.value, "90.0")
    }

    // MARK: - Rendering

    private func view(_ path: String) -> UIView? {
        harness.service.componentRegistry.viewRegistry.view(forId: path)
    }

    private func settle(_ seconds: TimeInterval = 0.1) {
        harness.drain(seconds)
        harness.superview.layoutIfNeeded()
    }

    /// A FAQ list: three disclosure rows in a vertical stack. Each row is a
    /// 44 pt header and an 80 pt body whose `isHidden` follows `openRows`.
    private func renderFAQ(animated: Bool = true, bodyType: String = "view") throws -> CViewModel {
        harness = RenderHarness()
        let animation = animated
            ? #", "animation": { "duration": 0.3, "cubicBezier": [0.33, 1, 0.68, 1] }"#
            : ""
        func row(_ key: String, _ title: String) -> String {
            let body: String
            if bodyType == "text" {
                body = """
                { "id": "\(key)Body", "type": "view",
                  "content": { "properties": { "isHidden": { "value": "{{ !includes(openRows, '\(key)') }}"\(animation) } },
                               "children": [
                                 { "id": "\(key)Text", "type": "label",
                                   "content": { "properties": { "text": "Placeholder answer text that wraps over several lines in the body of this row, long enough for three or four lines.", "numberOfLines": 0 },
                                                "layout": { "constraints": [
                                                  { "type": "top", "target": "superview" },
                                                  { "type": "leading", "target": "superview", "constant": 16 },
                                                  { "type": "trailing", "target": "superview", "constant": -16 },
                                                  { "type": "bottom", "target": "superview", "constant": -12 } ] } } } ] } }
                """
            } else if bodyType == "label" {
                body = """
                { "id": "\(key)Body", "type": "label",
                  "content": { "properties": { "text": "Placeholder answer.",
                                               "isHidden": { "value": "{{ !includes(openRows, '\(key)') }}"\(animation) } },
                               "layout": { "height": 80 } } }
                """
            } else {
                body = """
                { "id": "\(key)Body", "type": "view",
                  "content": { "properties": { "isHidden": { "value": "{{ !includes(openRows, '\(key)') }}"\(animation) } },
                               "children": [
                                 { "id": "\(key)Text", "type": "view",
                                   "content": { "layout": { "height": 80, "top": 0, "leading": 0, "trailing": 0, "bottom": 0 } } } ] } }
                """
            }
            return """
            { "id": "\(key)", "type": "stackView",
              "content": { "properties": { "axis": "vertical" },
                           "children": [
                             { "id": "\(key)Head", "type": "view",
                               "content": { "layout": { "height": 44 },
                                            "children": [
                                              { "id": "\(key)Title", "type": "label",
                                                "content": { "properties": { "text": "\(title)" }, "layout": { "centerY": 0, "leading": 16 } } } ] } },
                             \(body)
                           ] } }
            """
        }
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "openRows": { "type": "array", "initialValue": ["care"] } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "faq", "type": "stackView",
                      "content": {
                        "properties": { "axis": "vertical" },
                        "layout": { "top": 0, "leading": 0, "trailing": 0 },
                        "children": [ \(row("shipping", "Shipping")), \(row("returns", "Returns")), \(row("care", "Care")) ] } }
                ]
            }
        }
        """)
        settle()
        return try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
    }

    private func setOpenRows(_ root: CViewModel, _ rows: [String]) throws {
        try root.variableStore.setValue(name: "openRows", value: rows)
        harness.drain(0.02) // the binder's main-queue hop
    }

    private func presentedHeight(_ view: UIView) -> CGFloat {
        view.layer.presentation()?.bounds.height ?? view.bounds.height
    }

    func testFirstApplyIsInstant() throws {
        _ = try renderFAQ()
        let shippingBody = try XCTUnwrap(view("root.faq.shipping.shippingBody"))
        let careBody = try XCTUnwrap(view("root.faq.care.careBody"))
        XCTAssertTrue(shippingBody.isHidden, "a section that starts closed is closed")
        XCTAssertFalse(careBody.isHidden, "a section that starts open is open")
        XCTAssertEqual(careBody.alpha, 1)
        XCTAssertNil(careBody.layer.animationKeys())
        XCTAssertEqual(try XCTUnwrap(view("root.faq")).frame.height, 44 * 3 + 80, accuracy: 0.5)
    }

    func testOpeningARowInAStackIsOneAnimatedLayoutPass() throws {
        let root = try renderFAQ()
        let faq = try XCTUnwrap(view("root.faq"))
        let body = try XCTUnwrap(view("root.faq.shipping.shippingBody"))
        let text = try XCTUnwrap(view("root.faq.shipping.shippingBody.shippingText"))
        let returnsRow = try XCTUnwrap(view("root.faq.returns"))
        let returnsTopBefore = returnsRow.frame.minY

        try setOpenRows(root, ["care", "shipping"])

        // Model values are final at once; presentation follows the curve.
        XCTAssertFalse(body.isHidden)
        XCTAssertEqual(body.alpha, 1)
        XCTAssertEqual(body.frame.height, 80, accuracy: 0.5)
        XCTAssertEqual(faq.frame.height, 44 * 3 + 80 * 2, accuracy: 0.5)
        XCTAssertTrue(body.clipsToBounds, "the body clips to its animating bounds")
        XCTAssertEqual(text.frame.height, 80, accuracy: 0.5, "content is laid out at its final size, not squeezed")

        harness.drain(0.1)
        let midBody = presentedHeight(body)
        let midStack = presentedHeight(faq)
        let midAlpha = CGFloat(body.layer.presentation()?.opacity ?? 1)
        let midReturnsTop = returnsRow.layer.presentation()?.frame.minY ?? returnsRow.frame.minY
        XCTAssertGreaterThan(midBody, 1, "mid-animation the body is partly open")
        XCTAssertLessThan(midBody, 79)
        XCTAssertGreaterThan(midStack, 44 * 3 + 80 + 1, "the stack grows on the same curve")
        XCTAssertLessThan(midStack, 44 * 3 + 160 - 1)
        XCTAssertGreaterThan(midAlpha, 0.01)
        XCTAssertLessThan(midAlpha, 0.99)
        XCTAssertGreaterThan(midReturnsTop, returnsTopBefore + 1, "the next row moves along, not jumping")
        XCTAssertLessThan(midReturnsTop, returnsTopBefore + 79)

        settle(0.5)
        XCTAssertFalse(body.isHidden)
        XCTAssertEqual(body.alpha, 1)
        XCTAssertFalse(body.clipsToBounds, "clipping is restored")
        XCTAssertEqual(returnsRow.frame.minY, returnsTopBefore + 80, accuracy: 0.5)
    }

    func testClosingARowEndsHiddenAtItsOwnAlpha() throws {
        let root = try renderFAQ()
        let faq = try XCTUnwrap(view("root.faq"))
        let body = try XCTUnwrap(view("root.faq.care.careBody"))
        let text = try XCTUnwrap(view("root.faq.care.careBody.careText"))

        try setOpenRows(root, [])
        XCTAssertTrue(body.isHidden, "touches stop the moment it starts disappearing")
        XCTAssertEqual(text.frame.height, 80, accuracy: 0.5, "content keeps its size while it is covered")
        harness.drain(0.1)
        let mid = presentedHeight(faq)
        XCTAssertGreaterThan(mid, 44 * 3 + 1)
        XCTAssertLessThan(mid, 44 * 3 + 79)

        settle(0.5)
        XCTAssertTrue(body.isHidden)
        XCTAssertEqual(body.alpha, 1, "alpha returns to the component's own value once hidden")
        XCTAssertEqual(faq.frame.height, 44 * 3, accuracy: 0.5)
    }

    func testInterruptedToggleSettlesOnTheLastValue() throws {
        let root = try renderFAQ()
        let faq = try XCTUnwrap(view("root.faq"))
        let body = try XCTUnwrap(view("root.faq.shipping.shippingBody"))

        try setOpenRows(root, ["care", "shipping"])
        harness.drain(0.08)
        try setOpenRows(root, ["care"])
        harness.drain(0.08)
        try setOpenRows(root, ["care", "shipping"])
        settle(0.6)
        XCTAssertFalse(body.isHidden)
        XCTAssertFalse(body.layer.isHidden)
        XCTAssertEqual(body.alpha, 1)
        XCTAssertEqual(faq.frame.height, 44 * 3 + 160, accuracy: 0.5)

        try setOpenRows(root, ["care"])
        harness.drain(0.08)
        try setOpenRows(root, ["care", "shipping"])
        harness.drain(0.08)
        try setOpenRows(root, ["care"])
        settle(0.6)
        XCTAssertTrue(body.isHidden)
        XCTAssertEqual(body.alpha, 1)
        XCTAssertEqual(faq.frame.height, 44 * 3 + 80, accuracy: 0.5)
    }

    func testTextContentIsRevealedNotSqueezed() throws {
        // A body whose height comes from a wrapping label (compression
        // resistance 750, no fixed height): the label keeps its full height
        // from the first frame while the body grows.
        let root = try renderFAQ(bodyType: "text")
        let body = try XCTUnwrap(view("root.faq.shipping.shippingBody"))
        let text = try XCTUnwrap(view("root.faq.shipping.shippingBody.shippingText"))
        let care = try XCTUnwrap(view("root.faq.care.careBody.careText"))
        let fullHeight = care.frame.height
        XCTAssertGreaterThan(fullHeight, 10)

        try setOpenRows(root, ["care", "shipping"])
        XCTAssertEqual(text.frame.height, fullHeight, accuracy: 0.5, "laid out at full size before the pass")
        harness.drain(0.1)
        let mid = presentedHeight(body)
        XCTAssertGreaterThan(mid, 1)
        XCTAssertLessThan(mid, fullHeight + 12 - 1)
        XCTAssertEqual(presentedHeight(text), fullHeight, accuracy: 0.5, "the text itself does not resize")
        settle(0.5)
        XCTAssertEqual(body.frame.height, fullHeight + 12, accuracy: 0.5)

        // Closing: the text keeps its size while the edge covers it.
        try setOpenRows(root, ["care"])
        XCTAssertEqual(text.frame.height, fullHeight, accuracy: 0.5)
        settle(0.5)
        XCTAssertTrue(body.isHidden)
    }

    func testLabelBodyAnimatesToo() throws {
        let root = try renderFAQ(bodyType: "label")
        let faq = try XCTUnwrap(view("root.faq"))
        let body = try XCTUnwrap(view("root.faq.shipping.shippingBody"))
        XCTAssertTrue(body.isHidden)
        try setOpenRows(root, ["care", "shipping"])
        harness.drain(0.1)
        XCTAssertLessThan(presentedHeight(faq), 44 * 3 + 160 - 1)
        settle(0.5)
        XCTAssertFalse(body.isHidden)
        XCTAssertEqual(faq.frame.height, 44 * 3 + 160, accuracy: 0.5)
    }

    func testBareIsHiddenStaysInstant() throws {
        let root = try renderFAQ(animated: false)
        let faq = try XCTUnwrap(view("root.faq"))
        let body = try XCTUnwrap(view("root.faq.shipping.shippingBody"))
        try setOpenRows(root, ["care", "shipping"])
        harness.superview.layoutIfNeeded()
        XCTAssertFalse(body.isHidden)
        XCTAssertNil(body.layer.animationKeys())
        XCTAssertEqual(presentedHeight(faq), 44 * 3 + 160, accuracy: 0.5)
    }

    func testReduceMotionAppliesAtOnce() throws {
        HiddenTransition.isReduceMotionEnabled = { true }
        let root = try renderFAQ()
        let faq = try XCTUnwrap(view("root.faq"))
        let body = try XCTUnwrap(view("root.faq.care.careBody"))
        try setOpenRows(root, [])
        harness.superview.layoutIfNeeded()
        XCTAssertTrue(body.isHidden)
        XCTAssertNil(body.layer.animationKeys())
        XCTAssertEqual(presentedHeight(faq), 44 * 3, accuracy: 0.5)
    }

    func testOutsideAStackItCrossFades() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "hide": { "type": "boolean", "initialValue": false } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "badge", "type": "view",
                      "content": {
                        "properties": { "isHidden": { "value": "{{ hide }}", "animation": { "duration": 0.3, "curve": "easeOut" } } },
                        "layout": { "top": 0, "leading": 0, "width": 40, "height": 40 } } }
                ]
            }
        }
        """)
        settle()
        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        let badge = try XCTUnwrap(view("root.badge"))
        let frame = badge.frame

        try root.variableStore.setValue(name: "hide", value: true)
        harness.drain(0.1)
        XCTAssertFalse(badge.isHidden, "still drawn while fading out")
        XCTAssertEqual(badge.alpha, 0)
        XCTAssertEqual(badge.frame, frame, "the frame does not change")
        settle(0.5)
        XCTAssertTrue(badge.isHidden)
        XCTAssertEqual(badge.alpha, 1)

        try root.variableStore.setValue(name: "hide", value: false)
        harness.drain(0.05)
        XCTAssertFalse(badge.isHidden)
        let opacity = CGFloat(badge.layer.presentation()?.opacity ?? 1)
        XCTAssertLessThan(opacity, 0.99, "fades back in")
        settle(0.5)
        XCTAssertEqual(badge.alpha, 1)
    }

    // MARK: - transformRotation

    func testTransformRotationAnimatesAndComposesWithStyleTransform() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "open": { "type": "boolean", "initialValue": false } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "turn", "type": "view",
                      "content": {
                        "properties": { "transformRotation": { "value": "{{ open ? 180 : 0 }}",
                                                               "animation": { "duration": 0.3, "cubicBezier": [0.33, 1, 0.68, 1] } } },
                        "layout": { "top": 0, "leading": 0, "width": 20, "height": 20 } } },
                    { "id": "fixed", "type": "view",
                      "content": {
                        "properties": { "transformRotation": 90 },
                        "style": { "transform": { "scale": 2 } },
                        "layout": { "top": 40, "leading": 0, "width": 20, "height": 20 } } }
                ]
            }
        }
        """)
        settle()
        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        let turn = try XCTUnwrap(view("root.turn"))
        XCTAssertEqual(turn.transform, .identity, "first apply: no rotation, no animation")

        try root.variableStore.setValue(name: "open", value: true)
        harness.drain(0.05)
        XCTAssertEqual(atan2(turn.transform.b, turn.transform.a), .pi, accuracy: 0.001, "clockwise 180 degrees")
        XCTAssertNotNil(turn.layer.animationKeys(), "the change animates with its descriptor")

        let fixed = try XCTUnwrap(view("root.fixed"))
        // rotate(90°) then scale(2): a = 0, b = 2, c = -2, d = 0.
        XCTAssertEqual(fixed.transform.a, 0, accuracy: 0.001)
        XCTAssertEqual(fixed.transform.b, 2, accuracy: 0.001)
        XCTAssertEqual(fixed.transform.c, -2, accuracy: 0.001)
        XCTAssertEqual(fixed.transform.d, 0, accuracy: 0.001)
    }
}
