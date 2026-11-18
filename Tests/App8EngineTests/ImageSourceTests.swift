//
//  ImageSourceTests.swift
//  App8EngineTests
//
//  `image` without `type` (app8-dsl components/image.md, Image source):
//  `url` is remote, `asset` or `name` local, an http(s) `name` remote.
//

import XCTest
@testable import App8Engine

final class ImageSourceTests: XCTestCase {
    private typealias Props = DSL.Model.Component.Image.Properties

    private func props(_ json: String) throws -> Props {
        try JSONDecoder().decode(Props.self, from: Data(json.utf8))
    }

    func testUntypedSourcesAreInferred() throws {
        XCTAssertEqual(try props(#"{ "url": "https://example.com/a.jpg" }"#).type, .remoteAsset)
        XCTAssertEqual(try props(#"{ "url": "photo.jpg" }"#).type, .remoteAsset)
        XCTAssertEqual(try props(#"{ "asset": "logo" }"#).type, .localAsset)
        XCTAssertEqual(try props(#"{ "name": "logo" }"#).type, .localAsset)
        XCTAssertEqual(try props(#"{ "name": "https://example.com/b.png" }"#).type, .remoteAsset)
        XCTAssertEqual(try props(#"{}"#).type, .none)
    }

    func testAnExplicitTypeWins() throws {
        XCTAssertEqual(try props(#"{ "type": "remoteAsset", "name": "photo.jpg" }"#).type, .remoteAsset)
        XCTAssertEqual(try props(#"{ "type": "localAsset", "name": "logo" }"#).type, .localAsset)
    }
}
