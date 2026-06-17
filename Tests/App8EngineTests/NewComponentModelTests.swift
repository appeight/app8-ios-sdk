//
//  NewComponentModelTests.swift
//  App8Engine
//

import Foundation
import Testing
@testable import App8Engine

private enum TestError: Error { case castFailed }

private func componentJSON(type: String, properties: String, style: String = "{}") -> String {
    """
    {
        "type": "\(type)",
        "id": "test-\(type)",
        "content": {
            "properties": \(properties),
            "style": \(style),
            "layout": {}
        }
    }
    """
}

private func decodeComponent<C: DSL.Model.Component.EntityContent>(_ json: String, as type: C.Type) throws -> C {
    let data = json.data(using: .utf8)!
    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
    guard let entity: DSL.Model.Component.ConcreteEntity<C> = component.asConcreteEntity() else {
        Issue.record("Expected ConcreteEntity<\(C.self)>")
        throw TestError.castFailed
    }
    return entity.content
}

// MARK: - ActivityIndicator Model Tests

@Test
func activityIndicatorDecodesAllProperties() throws {
    let json = componentJSON(type: "activityIndicator", properties: """
    { "isAnimating": "{{isLoading}}", "hidesWhenStopped": false }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.ActivityIndicator.C.self)
    #expect(content.properties.isAnimating == "{{isLoading}}")
    #expect(content.properties.hidesWhenStopped == false)
}

@Test
func activityIndicatorDecodesWithDefaults() throws {
    let json = componentJSON(type: "activityIndicator", properties: "{}")

    let content = try decodeComponent(json, as: DSL.Model.Component.ActivityIndicator.C.self)
    #expect(content.properties.isAnimating == nil)
    #expect(content.properties.hidesWhenStopped == nil)
}

@Test
func activityIndicatorDecodesLiteralTrue() throws {
    let json = componentJSON(type: "activityIndicator", properties: """
    { "isAnimating": "true" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.ActivityIndicator.C.self)
    #expect(content.properties.isAnimating == "true")
}

// MARK: - Toggle Model Tests

@Test
func toggleDecodesAllProperties() throws {
    let json = componentJSON(type: "toggle", properties: """
    { "isOn": "{{darkMode}}", "bindVariable": "darkMode", "isEnabled": "{{canToggle}}" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Toggle.C.self)
    #expect(content.properties.isOn == "{{darkMode}}")
    #expect(content.properties.bindVariable == "darkMode")
    #expect(content.properties.isEnabled == "{{canToggle}}")
}

@Test
func toggleDecodesMinimal() throws {
    let json = componentJSON(type: "toggle", properties: "{}")

    let content = try decodeComponent(json, as: DSL.Model.Component.Toggle.C.self)
    #expect(content.properties.isOn == nil)
    #expect(content.properties.bindVariable == nil)
    #expect(content.properties.isEnabled == nil)
}

@Test
func toggleDecodesLiteralIsOn() throws {
    let json = componentJSON(type: "toggle", properties: """
    { "isOn": "true" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Toggle.C.self)
    #expect(content.properties.isOn == "true")
}

// MARK: - Slider Model Tests

@Test
func sliderDecodesAllProperties() throws {
    let json = componentJSON(type: "slider", properties: """
    { "value": "{{volume}}", "minimumValue": 0, "maximumValue": 100, "step": 5, "bindVariable": "volume", "isEnabled": "true" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Slider.C.self)
    #expect(content.properties.value == "{{volume}}")
    #expect(content.properties.minimumValue == 0)
    #expect(content.properties.maximumValue == 100)
    #expect(content.properties.step == 5)
    #expect(content.properties.bindVariable == "volume")
    #expect(content.properties.isEnabled == "true")
}

@Test
func sliderDecodesDefaults() throws {
    let json = componentJSON(type: "slider", properties: "{}")

    let content = try decodeComponent(json, as: DSL.Model.Component.Slider.C.self)
    #expect(content.properties.value == nil)
    #expect(content.properties.minimumValue == nil)
    #expect(content.properties.maximumValue == nil)
    #expect(content.properties.step == nil)
}

@Test
func sliderDecodesFloatRange() throws {
    let json = componentJSON(type: "slider", properties: """
    { "minimumValue": 0.0, "maximumValue": 1.0, "step": 0.1 }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Slider.C.self)
    #expect(content.properties.minimumValue == 0.0)
    #expect(content.properties.maximumValue == 1.0)
    #expect(content.properties.step == 0.1)
}

// MARK: - PageControl Model Tests

@Test
func pageControlDecodesAllProperties() throws {
    let json = componentJSON(type: "pageControl", properties: """
    { "numberOfPages": "{{totalPhotos}}", "currentPage": "{{currentIndex}}", "bindVariable": "currentIndex", "hidesForSinglePage": false }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.PageControl.C.self)
    #expect(content.properties.numberOfPages == "{{totalPhotos}}")
    #expect(content.properties.currentPage == "{{currentIndex}}")
    #expect(content.properties.bindVariable == "currentIndex")
    #expect(content.properties.hidesForSinglePage == false)
}

@Test
func pageControlDecodesLiteralNumbers() throws {
    let json = componentJSON(type: "pageControl", properties: """
    { "numberOfPages": "5", "currentPage": "0" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.PageControl.C.self)
    #expect(content.properties.numberOfPages == "5")
    #expect(content.properties.currentPage == "0")
}

// MARK: - Picker Model Tests

@Test
func pickerDecodesMenuMode() throws {
    let json = componentJSON(type: "picker", properties: """
    {
        "options": [
            { "value": "red", "label": "Red" },
            { "value": "blue", "label": "Blue", "icon": "circle.fill" }
        ],
        "selectedValue": "{{color}}",
        "bindVariable": "color",
        "displayMode": "menu",
        "placeholder": "Choose color"
    }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Picker.C.self)
    let props = content.properties
    #expect(props.options?.count == 2)
    #expect(props.options?[0].value == "red")
    #expect(props.options?[0].label == "Red")
    #expect(props.options?[0].icon == nil)
    #expect(props.options?[1].icon == "circle.fill")
    #expect(props.selectedValue == "{{color}}")
    #expect(props.bindVariable == "color")
    #expect(props.displayMode == .menu)
    #expect(props.placeholder == "Choose color")
}

@Test
func pickerDecodesSegmentedMode() throws {
    let json = componentJSON(type: "picker", properties: """
    {
        "options": [{ "value": "s", "label": "S" }, { "value": "m", "label": "M" }, { "value": "l", "label": "L" }],
        "selectedValue": "m",
        "displayMode": "segmented"
    }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Picker.C.self)
    #expect(content.properties.options?.count == 3)
    #expect(content.properties.displayMode == .segmented)
    #expect(content.properties.selectedValue == "m")
}

@Test
func pickerDefaultsToNoMode() throws {
    let json = componentJSON(type: "picker", properties: """
    { "options": [{ "value": "a", "label": "A" }] }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Picker.C.self)
    #expect(content.properties.displayMode == nil)
}

// MARK: - Shimmer Model Tests

@Test
func shimmerDecodesAllProperties() throws {
    let json = componentJSON(type: "shimmer", properties: """
    { "isAnimating": "{{isLoading}}", "duration": 2.0, "direction": "rightToLeft" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Shimmer.C.self)
    #expect(content.properties.isAnimating == "{{isLoading}}")
    #expect(content.properties.duration == 2.0)
    #expect(content.properties.direction == .rightToLeft)
}

@Test
func shimmerDecodesDefaults() throws {
    let json = componentJSON(type: "shimmer", properties: "{}")

    let content = try decodeComponent(json, as: DSL.Model.Component.Shimmer.C.self)
    #expect(content.properties.isAnimating == nil)
    #expect(content.properties.duration == nil)
    #expect(content.properties.direction == nil)
}

@Test
func shimmerDecodesAllDirections() throws {
    for dir in ["leftToRight", "rightToLeft", "topToBottom"] {
        let json = componentJSON(type: "shimmer", properties: """
        { "direction": "\(dir)" }
        """)
        let content = try decodeComponent(json, as: DSL.Model.Component.Shimmer.C.self)
        #expect(content.properties.direction?.rawValue == dir)
    }
}

// MARK: - Polyline (Shape extension) Model Tests

@Test
func shapePolylineDecodesPoints() throws {
    let json = componentJSON(type: "shape", properties: """
    {
        "kind": "polyline",
        "lineWidth": 2,
        "strokeColor": "#34C759",
        "smooth": true,
        "closed": false,
        "points": [
            { "x": "0", "y": "0.8" },
            { "x": "0.5", "y": "0.3" },
            { "x": "1.0", "y": "0.2" }
        ]
    }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Shape.C.self)
    let props = content.properties
    #expect(props.kind == .polyline)
    #expect(props.lineWidth == 2)
    #expect(props.strokeColor == "#34C759")
    #expect(props.smooth == true)
    #expect(props.closed == false)
    #expect(props.points?.count == 3)
    #expect(props.points?[0].x == "0")
    #expect(props.points?[0].y == "0.8")
    #expect(props.points?[2].x == "1.0")
    #expect(props.points?[2].y == "0.2")
}

@Test
func shapePolylineDecodesWithExpressionPoints() throws {
    let json = componentJSON(type: "shape", properties: """
    {
        "kind": "polyline",
        "points": [
            { "x": "{{p1x}}", "y": "{{p1y}}" },
            { "x": "{{p2x}}", "y": "{{p2y}}" }
        ]
    }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Shape.C.self)
    #expect(content.properties.points?[0].x == "{{p1x}}")
    #expect(content.properties.points?[0].y == "{{p1y}}")
}

@Test
func shapePolylineDefaultsNilForNonPolyline() throws {
    let json = componentJSON(type: "shape", properties: """
    { "kind": "arc", "progress": "0.5" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Shape.C.self)
    #expect(content.properties.kind == .arc)
    #expect(content.properties.points == nil)
    #expect(content.properties.smooth == nil)
    #expect(content.properties.closed == nil)
}

// MARK: - Video Model Tests

@Test
func videoDecodesLocalAsset() throws {
    let json = componentJSON(type: "video", properties: """
    { "type": "localAsset", "name": "intro.mp4" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Video.C.self)
    guard case .asset(let asset) = content.properties.model else {
        Issue.record("Expected .asset model")
        return
    }
    #expect(asset.name == "intro.mp4")
    // Flags default to true when omitted.
    #expect(content.properties.autoplay == true)
    #expect(content.properties.loop == true)
    #expect(content.properties.muted == true)
}

@Test
func videoDecodesFlagOverrides() throws {
    let json = componentJSON(type: "video", properties: """
    { "type": "localAsset", "name": "clip", "autoplay": false, "loop": false, "muted": false }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Video.C.self)
    #expect(content.properties.autoplay == false)
    #expect(content.properties.loop == false)
    #expect(content.properties.muted == false)
}

@Test
func videoDecodesNoneType() throws {
    let json = componentJSON(type: "video", properties: """
    { "type": "none" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Video.C.self)
    guard case .none = content.properties.model else {
        Issue.record("Expected .none model")
        return
    }
}

@Test
func videoDecodesGravityStyle() throws {
    let json = componentJSON(type: "video", properties: """
    { "type": "localAsset", "name": "intro" }
    """, style: """
    { "contentMode": "scaleAspectFit" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Video.C.self)
    #expect(content.style?.videoGravity == .resizeAspect)
}

@Test
func videoEndBehaviorDefaultsToFreeze() throws {
    let json = componentJSON(type: "video", properties: """
    { "type": "localAsset", "name": "intro" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Video.C.self)
    #expect(content.properties.endBehavior == .freezeLastFrame)
    #expect(content.properties.poster == nil)
    #expect(content.properties.endPoster == nil)
    #expect(content.properties.marks == nil)
    #expect(content.properties.startDelay == nil)
    #expect(content.properties.startTime == nil)
    #expect(content.properties.rate == nil)
    // `loop: true` (default) drives the looping path.
    #expect(content.properties.loops == true)
}

@Test
func videoDecodesPosterTimingAndMarks() throws {
    let json = componentJSON(type: "video", properties: """
    {
        "type": "localAsset", "name": "intro", "loop": false,
        "endBehavior": "showPoster",
        "poster": { "type": "remoteAsset", "id": "p1", "name": "poster.png" },
        "endPoster": { "type": "url", "url": "https://cdn.example/end.png" },
        "startDelay": 1.5, "startTime": 2, "rate": 0.5,
        "marks": [ { "id": "m1", "time": 0.35 }, { "id": "m2", "time": 0.57 } ]
    }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Video.C.self)
    let props = content.properties
    #expect(props.endBehavior == .showPoster)
    #expect(props.loops == false)
    #expect(props.poster?.kind == .remoteAsset)
    #expect(props.poster?.id == "p1")
    #expect(props.poster?.name == "poster.png")
    #expect(props.endPoster?.kind == .url)
    #expect(props.endPoster?.url == "https://cdn.example/end.png")
    #expect(props.startDelay == 1.5)
    #expect(props.startTime == 2)
    #expect(props.rate == 0.5)
    #expect(props.marks?.count == 2)
    #expect(props.marks?.first?.id == "m1")
    #expect(props.marks?.first?.time == 0.35)
}

@Test
func videoEndBehaviorLoopImpliesLooping() throws {
    let json = componentJSON(type: "video", properties: """
    { "type": "localAsset", "name": "intro", "loop": false, "endBehavior": "loop" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.Video.C.self)
    #expect(content.properties.endBehavior == .loop)
    #expect(content.properties.loops == true)
}

@Test
func videoPosterRemoteAssetHelper() throws {
    let remote = DSL.Model.Component.Video.PosterSource(kind: .remoteAsset, name: "p.png", id: "p1")
    #expect(remote.remoteAsset?.id == "p1")
    let urlPoster = DSL.Model.Component.Video.PosterSource(kind: .url, url: "https://x/y.png")
    #expect(urlPoster.remoteAsset?.url == "https://x/y.png")
    let firstFrame = DSL.Model.Component.Video.PosterSource(kind: .firstFrame)
    #expect(firstFrame.remoteAsset == nil)
    let local = DSL.Model.Component.Video.PosterSource(kind: .localAsset, name: "bundled")
    #expect(local.remoteAsset == nil)
}

@Test
func videoDecodesPlaybackActionsAndAnalytics() throws {
    let json = """
    {
        "type": "video",
        "id": "test-video",
        "content": {
            "properties": { "type": "localAsset", "name": "intro", "loop": false },
            "style": {},
            "layout": {},
            "actions": {
                "onVideoComplete": [ { "type": "emit", "name": "intro.finished" } ],
                "onTimeMark": [ { "type": "updateVariable", "variableName": "step", "value": 1 } ]
            },
            "analytics": { "onVideoComplete": "introDone" }
        }
    }
    """

    let content = try decodeComponent(json, as: DSL.Model.Component.Video.C.self)
    #expect(content.actions?[.onVideoComplete]?.first?.type == .emit)
    #expect(content.actions?[.onVideoComplete]?.first?.name == "intro.finished")
    #expect(content.actions?[.onTimeMark]?.first?.type == .updateVariable)
    #expect(content.analytics?[.onVideoComplete]?.name == "introDone")
}

// MARK: - DatePicker Model Tests

@Test
func datePickerDecodesAllProperties() throws {
    let json = componentJSON(type: "datePicker", properties: """
    {
        "selectedDate": "{{birthDate}}",
        "bindVariable": "birthDate",
        "datePickerMode": "date",
        "displayStyle": "inline",
        "minimumDate": "1900-01-01",
        "maximumDate": "2026-04-04",
        "isEnabled": "true"
    }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.DatePicker.C.self)
    let props = content.properties
    #expect(props.selectedDate == "{{birthDate}}")
    #expect(props.bindVariable == "birthDate")
    #expect(props.datePickerMode == .date)
    #expect(props.displayStyle == .inline)
    #expect(props.minimumDate == "1900-01-01")
    #expect(props.maximumDate == "2026-04-04")
    #expect(props.isEnabled == "true")
}

@Test
func datePickerDecodesDefaults() throws {
    let json = componentJSON(type: "datePicker", properties: "{}")

    let content = try decodeComponent(json, as: DSL.Model.Component.DatePicker.C.self)
    #expect(content.properties.selectedDate == nil)
    #expect(content.properties.bindVariable == nil)
    #expect(content.properties.datePickerMode == nil)
    #expect(content.properties.displayStyle == nil)
    #expect(content.properties.minimumDate == nil)
    #expect(content.properties.maximumDate == nil)
}

@Test
func datePickerDecodesAllModes() throws {
    for mode in ["date", "time", "dateAndTime", "countdownTimer"] {
        let json = componentJSON(type: "datePicker", properties: """
        { "datePickerMode": "\(mode)" }
        """)
        let content = try decodeComponent(json, as: DSL.Model.Component.DatePicker.C.self)
        #expect(content.properties.datePickerMode?.rawValue == mode)
    }
}

@Test
func datePickerDecodesAllStyles() throws {
    for style in ["compact", "inline", "wheels"] {
        let json = componentJSON(type: "datePicker", properties: """
        { "displayStyle": "\(style)" }
        """)
        let content = try decodeComponent(json, as: DSL.Model.Component.DatePicker.C.self)
        #expect(content.properties.displayStyle?.rawValue == style)
    }
}

@Test
func datePickerDecodesCompactWithBinding() throws {
    let json = componentJSON(type: "datePicker", properties: """
    { "bindVariable": "eventDate", "displayStyle": "compact" }
    """)

    let content = try decodeComponent(json, as: DSL.Model.Component.DatePicker.C.self)
    #expect(content.properties.bindVariable == "eventDate")
    #expect(content.properties.displayStyle == .compact)
}
