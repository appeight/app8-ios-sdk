//
//  AssetReferenceCollectorTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class AssetReferenceCollectorTests: XCTestCase {

    private func decode(_ json: String) throws -> DSL.Model.Component.`Any` {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: data)
    }

    private func collect(
        _ component: DSL.Model.Component.`Any`,
        fontIndex: [String: DSL.Model.Asset] = [:]
    ) -> App8.AssetReferenceSet {
        let resolver: FontAssetResolver = { name in fontIndex[name] }
        let collector = AssetReferenceCollector(fontAssetResolver: resolver)
        return collector.collect(component: component)
    }

    // MARK: - Image refs

    func testRemoteAssetImageAtRootDecodedAsImageReference() throws {
        let json = """
        {
          "id": "root",
          "type": "image",
          "content": {
            "properties": {
              "type": "remoteAsset",
              "id": "asset-1",
              "name": "logo.png",
              "url": "https://example.com/logo.png"
            }
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.images.count, 1)
        let ref = refs.images.first
        XCTAssertEqual(ref?.id, "asset-1")
        XCTAssertEqual(ref?.name, "logo.png")
        XCTAssertEqual(ref?.url, "https://example.com/logo.png")
    }

    func testRemoteAssetImageDeepInTreeIsFound() throws {
        let json = """
        {
          "id": "root",
          "type": "view",
          "content": {
            "children": [
              { "id": "row", "type": "view", "content": {
                "children": [
                  { "id": "img", "type": "image", "content": {
                    "properties": { "type": "remoteAsset", "id": "deep", "name": "hero.png" }
                  }}
                ]
              }}
            ]
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.images.count, 1)
        XCTAssertEqual(refs.images.first?.id, "deep")
        XCTAssertEqual(refs.images.first?.name, "hero.png")
    }

    func testDuplicateAssetRefsAreDeduplicated() throws {
        let json = """
        {
          "id": "root",
          "type": "view",
          "content": {
            "children": [
              { "id": "a", "type": "image", "content": {
                "properties": { "type": "remoteAsset", "id": "same", "name": "x.png" }
              }},
              { "id": "b", "type": "image", "content": {
                "properties": { "type": "remoteAsset", "id": "same", "name": "x.png" }
              }}
            ]
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.images.count, 1)
    }

    func testImageRefWithUnresolvedExpressionIsSkipped() throws {
        let json = """
        {
          "id": "root",
          "type": "image",
          "content": {
            "properties": {
              "type": "remoteAsset",
              "id": "{{user.avatarId}}",
              "name": "{{user.avatarName}}"
            }
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.images.count, 0, "Refs with only {{...}} placeholders should be skipped")
    }

    func testLocalAssetDoesNotProduceImageRef() throws {
        let json = """
        {
          "id": "root",
          "type": "image",
          "content": {
            "properties": { "type": "localAsset", "name": "bundled-logo" }
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.images.count, 0)
    }

    // MARK: - Font refs

    func testTextStyleFontFamilyShortcutCapturesPostScriptName() throws {
        // Matches the production DSL shape: inline `text` object on the
        // label's style with no entity wrapper.
        let json = """
        {
          "id": "title",
          "type": "label",
          "content": {
            "properties": { "text": "Hello" },
            "style": {
              "text": {
                "fontSize": 16,
                "fontFamily": "MyFont-Bold"
              }
            }
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        let psNames = Set(refs.fonts.map { $0.postScriptName })
        XCTAssertTrue(psNames.contains("MyFont-Bold"))
        XCTAssertNil(refs.fonts.first { $0.postScriptName == "MyFont-Bold" }?.asset,
                     "Without a font-family entry in styles, asset should be nil")
    }

    func testFontFamilyResolvesAssetViaResolver() throws {
        let json = """
        {
          "id": "title",
          "type": "label",
          "content": {
            "properties": { "text": "Hello" },
            "style": {
              "text": { "fontSize": 16, "fontFamily": "MyFont-Bold" }
            }
          }
        }
        """
        let component = try decode(json)
        let index: [String: DSL.Model.Asset] = [
            "MyFont-Bold": DSL.Model.Asset(id: "asset-font", name: "MyFont-Bold.ttf", url: nil)
        ]
        let refs = collect(component, fontIndex: index)
        let bold = refs.fonts.first { $0.postScriptName == "MyFont-Bold" }
        XCTAssertNotNil(bold?.asset)
        XCTAssertEqual(bold?.asset?.id, "asset-font")
        XCTAssertEqual(bold?.asset?.name, "MyFont-Bold.ttf")
    }

    func testTextWithoutFontFamilyProducesNoFontRefs() throws {
        let json = """
        {
          "id": "title",
          "type": "label",
          "content": {
            "properties": { "text": "Hello" },
            "style": {
              "text": { "fontSize": 16 }
            }
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.fonts.count, 0)
    }

    // MARK: - Mixed

    func testMixedScreenReturnsBothImagesAndFonts() throws {
        let json = """
        {
          "id": "screen",
          "type": "screen",
          "content": {
            "children": [
              { "id": "logo", "type": "image", "content": {
                "properties": { "type": "remoteAsset", "id": "asset-logo", "name": "logo.png" }
              }},
              { "id": "title", "type": "label", "content": {
                "properties": { "text": "Hi" },
                "style": {
                  "text": { "fontSize": 18, "fontFamily": "Inter-Bold" }
                }
              }}
            ]
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.images.count, 1)
        XCTAssertEqual(refs.fonts.count, 1)
        XCTAssertEqual(refs.images.first?.id, "asset-logo")
        XCTAssertEqual(refs.fonts.first?.postScriptName, "Inter-Bold")
    }

    // MARK: - Video posters

    func testVideoRemotePosterAndEndPosterAreCollected() throws {
        let json = """
        {
          "id": "intro",
          "type": "video",
          "content": {
            "properties": {
              "type": "remoteAsset",
              "id": "vid-1",
              "name": "intro.mp4",
              "loop": false,
              "endBehavior": "showPoster",
              "poster": { "type": "remoteAsset", "id": "poster-1", "name": "poster.png" },
              "endPoster": { "type": "url", "url": "https://cdn.example/end.png" }
            }
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        // video bytes + poster + endPoster.
        XCTAssertEqual(refs.images.count, 3)
        XCTAssertTrue(refs.images.contains { $0.id == "vid-1" })
        XCTAssertTrue(refs.images.contains { $0.id == "poster-1" })
        XCTAssertTrue(refs.images.contains { $0.url == "https://cdn.example/end.png" })
    }

    func testVideoLocalAndFramePostersAreNotPrefetched() throws {
        let json = """
        {
          "id": "intro",
          "type": "video",
          "content": {
            "properties": {
              "type": "localAsset",
              "name": "intro.mp4",
              "poster": { "type": "firstFrame" },
              "endPoster": { "type": "localAsset", "name": "bundled.png" }
            }
          }
        }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.images.count, 0)
    }

    // MARK: - Empty / pointer / pathological

    func testEmptyScreenReturnsEmptySet() throws {
        let json = """
        { "id": "empty", "type": "view", "content": { "children": [] } }
        """
        let component = try decode(json)
        let refs = collect(component)
        XCTAssertEqual(refs.images.count, 0)
        XCTAssertEqual(refs.fonts.count, 0)
    }
}
