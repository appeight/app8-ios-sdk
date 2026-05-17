//
//  ActionModelTests.swift
//  App8Engine
//

import Foundation
import Testing
@testable import App8Engine

// MARK: - Helpers

private func decodeAction(_ json: String) throws -> DSL.Model.Action {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(DSL.Model.Action.self, from: data)
}

// MARK: - showAlert Action

@Test
func showAlertDecodesWithAllProperties() throws {
    let json = """
    {
        "type": "showAlert",
        "alertTitle": "Delete?",
        "alertMessage": "This cannot be undone.",
        "alertActions": [
            { "title": "Cancel", "style": "cancel" },
            { "title": "Delete", "style": "destructive" }
        ]
    }
    """
    let action = try decodeAction(json)
    #expect(action.type == .showAlert)
    #expect(action.alertTitle == "Delete?")
    #expect(action.alertMessage == "This cannot be undone.")
    #expect(action.alertActions?.count == 2)
    #expect(action.alertActions?[0].title == "Cancel")
    #expect(action.alertActions?[0].style == .cancel)
    #expect(action.alertActions?[1].title == "Delete")
    #expect(action.alertActions?[1].style == .destructive)
}

@Test
func showAlertDecodesMinimal() throws {
    let json = """
    { "type": "showAlert", "alertTitle": "Info" }
    """
    let action = try decodeAction(json)
    #expect(action.type == .showAlert)
    #expect(action.alertTitle == "Info")
    #expect(action.alertMessage == nil)
    #expect(action.alertActions == nil)
}

@Test
func showAlertActionWithFollowUp() throws {
    let json = """
    {
        "type": "showAlert",
        "alertTitle": "Confirm",
        "alertActions": [
            {
                "title": "OK",
                "style": "default",
                "action": { "type": "updateVariable", "variableName": "confirmed", "value": true }
            }
        ]
    }
    """
    let action = try decodeAction(json)
    #expect(action.alertActions?[0].action?.type == .updateVariable)
    #expect(action.alertActions?[0].action?.variableName == "confirmed")
}

// MARK: - haptic Action

@Test
func hapticDecodesAllStyles() throws {
    let styles = ["light", "medium", "heavy", "success", "warning", "error", "selection"]
    for style in styles {
        let json = """
        { "type": "haptic", "hapticStyle": "\(style)" }
        """
        let action = try decodeAction(json)
        #expect(action.type == .haptic)
        #expect(action.hapticStyle?.rawValue == style)
    }
}

@Test
func hapticDecodesWithoutStyle() throws {
    let json = """
    { "type": "haptic" }
    """
    let action = try decodeAction(json)
    #expect(action.type == .haptic)
    #expect(action.hapticStyle == nil)
}

// MARK: - openURL Action

@Test
func openURLDecodesWebURL() throws {
    let json = """
    { "type": "openURL", "url": "https://apple.com" }
    """
    let action = try decodeAction(json)
    #expect(action.type == .openURL)
    #expect(action.url == "https://apple.com")
}

@Test
func openURLDecodesPhoneURL() throws {
    let json = """
    { "type": "openURL", "url": "tel:+15551234567" }
    """
    let action = try decodeAction(json)
    #expect(action.url == "tel:+15551234567")
}

@Test
func openURLDecodesExpression() throws {
    let json = """
    { "type": "openURL", "url": "{{item.link}}" }
    """
    let action = try decodeAction(json)
    #expect(action.url == "{{item.link}}")
}

@Test
func openURLDefaultsToExternalPresentation() throws {
    let json = """
    { "type": "openURL", "url": "https://apple.com" }
    """
    let action = try decodeAction(json)
    #expect(action.urlPresentation == nil)
}

@Test
func openURLDecodesSheetPresentation() throws {
    let json = """
    { "type": "openURL", "url": "https://apple.com", "urlPresentation": "sheet" }
    """
    let action = try decodeAction(json)
    #expect(action.urlPresentation == .sheet)
}

@Test
func openURLDecodesFullScreenPresentation() throws {
    let json = """
    { "type": "openURL", "url": "https://apple.com", "urlPresentation": "fullScreen" }
    """
    let action = try decodeAction(json)
    #expect(action.urlPresentation == .fullScreen)
}

@Test
func openURLDecodesExternalPresentation() throws {
    let json = """
    { "type": "openURL", "url": "https://apple.com", "urlPresentation": "external" }
    """
    let action = try decodeAction(json)
    #expect(action.urlPresentation == .external)
}

// MARK: - ActionTrigger decoding (new triggers)

@Test
func longPressTriggerDecodes() throws {
    #expect(DSL.Model.ActionTrigger(rawValue: "longPress") == .longPress)
}

@Test
func onTextChangeTriggerDecodes() throws {
    #expect(DSL.Model.ActionTrigger(rawValue: "onTextChange") == .onTextChange)
}

@Test
func onScrollThresholdTriggerDecodes() throws {
    #expect(DSL.Model.ActionTrigger(rawValue: "onScrollThreshold") == .onScrollThreshold)
}

@Test
func unknownTriggerReturnsNil() throws {
    #expect(DSL.Model.ActionTrigger(rawValue: "bogusTrigger") == nil)
}

// MARK: - DatePicker in Actions (tap action on datePicker change)

@Test
func datePickerComponentDecodesInActionContext() throws {
    let json = """
    {
        "type": "datePicker",
        "id": "test-dp",
        "content": {
            "properties": {
                "bindVariable": "date",
                "datePickerMode": "date",
                "displayStyle": "compact"
            },
            "actions": {
                "tap": { "type": "haptic", "hapticStyle": "selection" }
            },
            "layout": { "height": 40 }
        }
    }
    """
    let data = json.data(using: .utf8)!
    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
    let entity: DSL.Model.Component.ConcreteEntity<DSL.Model.Component.DatePicker.C>? = component.asConcreteEntity()
    #expect(entity != nil)
    #expect(entity?.content.properties.bindVariable == "date")
    #expect(entity?.content.actions?[.tap]?.type == .haptic)
}
