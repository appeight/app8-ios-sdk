//
//  PhotoStoreTests.swift
//  App8EngineTests
//
//  Photos (docs/photos.md): references, options, crop and scale, the JPEG
//  encode, storage, launch cleanup, the account reset and action decoding.
//  The capture UI runs in the simulator E2E (app8-conformance PhotoLog).
//

import Foundation
import Testing
import UIKit
@testable import App8Engine

@MainActor
@Suite(.serialized)
struct PhotoStoreTests {

    let id = "3f2b9c1e-6a4d-4e2f-9b1a-7c8d9e0f1a2b"

    @Test func references() {
        #expect(PhotoStore.photoId("photo://\(id)") == id)
        for v: Any? in [nil, 1, "", "photo://\(id.uppercased())", "photo://\(id).jpg", "https://x/\(id)", "photo://abc"] {
            #expect(PhotoStore.photoId(v) == nil)
        }
    }

    @Test func optionsDefaultAndClamp() {
        let d = PhotoProcessing.Options()
        #expect(d.maxDimension == 1600 && d.quality == 0.8 && d.aspectRatio == nil)
        let c = PhotoProcessing.Options(maxDimension: 10, quality: 3.0, aspectRatio: 0)
        #expect(c.maxDimension == 256 && c.quality == 1 && c.aspectRatio == nil)
        let s = PhotoProcessing.Options(maxDimension: "9000", quality: "0.01", aspectRatio: "0.75")
        #expect(s.maxDimension == 4096 && s.quality == 0.1 && s.aspectRatio == 0.75)
    }

    @Test func geometry() {
        let sq = PhotoProcessing.geometry(width: 4032, height: 3024, options: .init(aspectRatio: 1))
        #expect(sq.crop == CGRect(x: 504, y: 0, width: 3024, height: 3024))
        #expect(sq.size == CGSize(width: 1600, height: 1600))
        let p = PhotoProcessing.geometry(width: 4000, height: 3000, options: .init(aspectRatio: 0.75))
        #expect(p.crop == CGRect(x: 875, y: 0, width: 2250, height: 3000))
        #expect(p.size == CGSize(width: 1200, height: 1600))
        let small = PhotoProcessing.geometry(width: 800, height: 600, options: .init())
        #expect(small.size == CGSize(width: 800, height: 600))
    }

    /// A 3000×2000 image tagged `.right` (a portrait camera photo) comes out upright and square.
    @Test func encodeAppliesOrientationCropAndScale() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let raw = renderer.image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1500, height: 2000))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 1500, y: 0, width: 1500, height: 2000))
        }
        let rotated = UIImage(cgImage: raw.cgImage!, scale: 1, orientation: .right)  // upright: 2000×3000
        let out = try #require(PhotoProcessing.encode(rotated, options: .init(maxDimension: 1600, aspectRatio: 0.5)))
        #expect(out.width == 800 && out.height == 1600)
        let decoded = try #require(UIImage(data: out.data))
        #expect(decoded.size == CGSize(width: 800, height: 1600))
        #expect(decoded.imageOrientation == .up)
        // No metadata beyond the basics: no GPS or EXIF dictionary.
        let source = try #require(CGImageSourceCreateWithData(out.data as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        #expect(props[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(out.data.count < 400_000)
    }

    @Test func saveLoadDeleteSweepAndReset() async throws {
        let app = "photo-test-\(UUID().uuidString.prefix(8))"
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { _ in }.jpegData(compressionQuality: 0.8)!
        let kept = try PhotoStore.save(jpeg, appId: app)
        let orphan = try PhotoStore.save(jpeg, appId: app)
        let recent = try PhotoStore.save(jpeg, appId: app)
        #expect(await PhotoStore.loadImage(appId: app, id: kept) != nil)

        // Age two of them past the cleanup threshold.
        let old = Date(timeIntervalSinceNow: -2 * PhotoStore.sweepMinimumAge)
        for i in [kept, orphan] {
            try FileManager.default.setAttributes([.creationDate: old], ofItemAtPath: PhotoStore.fileURL(appId: app, id: i)!.path)
        }
        // A persisted value as VariablePersistence writes it (slashes escaped).
        let stored = String(data: try JSONSerialization.data(withJSONObject: [[["photo": "photo://\(kept)"]]]), encoding: .utf8)!
        #expect(stored.contains("photo:\\/\\/"))
        let removed = PhotoStore.sweep(appId: app, persistedJSON: [stored])
        #expect(removed == [orphan])
        #expect(FileManager.default.fileExists(atPath: PhotoStore.fileURL(appId: app, id: kept)!.path))
        #expect(FileManager.default.fileExists(atPath: PhotoStore.fileURL(appId: app, id: recent)!.path))

        PhotoStore.delete(appId: app, id: recent)
        #expect(await PhotoStore.loadImage(appId: app, id: recent) == nil)

        // Account switch: the host's reset removes photos with the variables.
        App8.clearPersistedData()
        #expect(await PhotoStore.loadImage(appId: app, id: kept) == nil)
        #expect(!FileManager.default.fileExists(atPath: PhotoStore.directory(appId: app)!.path))
    }

    @Test func actionsDecode() throws {
        let json = """
        [{ "type": "capturePhoto", "source": "camera", "camera": "front", "aspectRatio": 1, "maxDimension": "{{size}}",
           "quality": 0.7, "labels": { "camera": "Shoot" }, "resultVariable": "avatar",
           "onSuccess": { "type": "haptic", "hapticStyle": "success" }, "onCancel": [], "onError": [] },
         { "type": "deletePhoto", "ref": "{{entry.photo}}" }]
        """
        let actions = try JSONDecoder().decode([DSL.Model.Action].self, from: Data(json.utf8))
        #expect(actions[0].type == .capturePhoto)
        #expect(actions[0].source == "camera" && actions[0].camera == "front")
        #expect(actions[0].labels?["camera"] == "Shoot")
        #expect(actions[0].resultVariable == "avatar")
        #expect(actions[0].onSuccess?.actions.count == 1)
        #expect(actions[1].type == .deletePhoto && actions[1].ref == "{{entry.photo}}")
    }
}
