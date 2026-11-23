//
//  ThemedColorOneSideTests.swift
//  App8EngineTests
//
//  A themed color may give only one side; that side serves both appearances.
//  { "id": … } sides resolve against the app's color styles; an unknown id counts
//  as absent (the other side is used; neither side: clear).
//

import XCTest
@testable import App8Engine

final class ThemedColorOneSideTests: XCTestCase {

    private typealias Themed = DSL.Model.Style.Color.Themed

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    private func hex(_ c: UIColor, _ tc: UITraitCollection) -> String {
        String(DSL.Model.Style.Color.Hex(c.resolvedColor(with: tc)).value.uppercased().prefix(6))
    }

    private func themed(_ json: String) throws -> Themed {
        try JSONDecoder().decode(Themed.self, from: Data(json.utf8))
    }

    /// Decodes the styles plus one extra color and resolves pointers like App8.swift (multi-pass).
    private func resolved(_ json: String) throws -> Themed {
        let stylesJSON = """
        [
            { "id": "tokenBlue", "type": "color", "content": { "light": "#1E6FD9", "dark": "#0B1F4D" } },
            { "id": "tokenOrange", "type": "color", "content": { "light": "#F08C00" } },
            { "id": "tokenGreen", "type": "color", "content": "#2E7D32" },
            { "id": "subject", "type": "color", "content": \(json) }
        ]
        """
        var styles = try JSONDecoder().decode([DSL.Model.Style.`Any`].self, from: Data(stylesJSON.utf8))
        var dict: [String: DSL.Model.Style.`Any`] = [:]
        for s in styles { dict[s.id] = s }
        for _ in 0..<3 {
            for i in styles.indices {
                var copy = styles[i]
                copy.resolveStylePointers { dict[$0]?.asEntity() }
                styles[i] = copy
                dict[copy.id] = copy
            }
        }
        let entity: DSL.Model.Style.ConcreteEntity<Themed>? = dict["subject"]?.asConcreteEntity()
        return try XCTUnwrap(entity?.content)
    }

    func testOneSideServesBoth() throws {
        let l = try themed(##"{ "light": "#2E7D32" }"##)
        XCTAssertEqual(hex(l.ui, light), "2E7D32")
        XCTAssertEqual(hex(l.ui, dark), "2E7D32")
        let d = try themed(##"{ "dark": "#6A1B9A" }"##)
        XCTAssertEqual(hex(d.ui, light), "6A1B9A")
        XCTAssertEqual(hex(d.ui, dark), "6A1B9A")
        XCTAssertThrowsError(try themed("{}"))
    }

    func testRefsResolveAgainstColorStyles() throws {
        let blue = try resolved(##"{ "light": { "id": "tokenBlue" }, "dark": { "id": "tokenBlue" } }"##)
        XCTAssertEqual(hex(blue.ui, light), "1E6FD9")
        XCTAssertEqual(hex(blue.ui, dark), "0B1F4D")
        let orange = try resolved(##"{ "light": { "id": "tokenOrange" }, "dark": { "id": "tokenOrange" } }"##)
        XCTAssertEqual(hex(orange.ui, dark), "F08C00")
        let green = try resolved(##"{ "light": { "id": "tokenGreen" }, "dark": { "id": "tokenGreen" } }"##)
        XCTAssertEqual(hex(green.ui, dark), "2E7D32")
        let lightOnlyRef = try resolved(##"{ "light": { "id": "tokenOrange" } }"##)
        XCTAssertEqual(hex(lightOnlyRef.ui, dark), "F08C00")
    }

    func testUnknownRefFallsBackThenClear() throws {
        let red = try resolved(##"{ "light": { "id": "noSuchToken" }, "dark": "#C62828" }"##)
        XCTAssertEqual(hex(red.ui, light), "C62828")
        let none = try resolved(##"{ "light": { "id": "noSuchToken" }, "dark": { "id": "noSuchToken" } }"##)
        XCTAssertEqual(none.ui.resolvedColor(with: light).cgColor.alpha, 0)
    }
}
