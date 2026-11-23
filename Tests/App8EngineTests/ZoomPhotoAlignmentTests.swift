//
//  ZoomPhotoAlignmentTests.swift
//  App8EngineTests
//
//  A zoom into a photo drawn aspect-fit (a full-screen photo viewer) lines up
//  with the photo, not the image view's frame: UIKit fits the alignment rect
//  into the source, so it is the source-shaped part of the drawn picture.
//  The zoomed screen's floating controls over the photo are found to fade
//  instead of scaling.
//

import XCTest
@testable import App8Engine

@MainActor
final class ZoomPhotoAlignmentTests: XCTestCase {

    private func screen() -> UIView { UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874)) }

    private func photo(_ size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// An image component: a wrapper whose UIImageView fills it.
    private func imageElement(frame: CGRect, image: UIImage?, mode: UIView.ContentMode) -> UIView {
        let wrapper = UIView(frame: frame)
        let imageView = UIImageView(frame: wrapper.bounds)
        imageView.image = image
        imageView.contentMode = mode
        wrapper.addSubview(imageView)
        return wrapper
    }

    func testAspectFitPhotoLinesUpWithItsPictureInTheSourceShape() {
        let root = screen()
        // A 4:5 photo, aspect-fit edge to edge: drawn 402 × 502.5, centred.
        let page = imageElement(frame: root.bounds, image: photo(CGSize(width: 800, height: 1000)), mode: .scaleAspectFit)
        root.addSubview(page)
        let picture = ZoomPhoto.pictureRect(of: page, in: root, fallbackAspect: nil)
        XCTAssertEqual(picture.width, 402, accuracy: 0.01)
        XCTAssertEqual(picture.height, 502.5, accuracy: 0.01)
        XCTAssertEqual(picture.midY, 437, accuracy: 0.01)
        // From a 2:3 card: the 2:3 part of that picture (335 × 502.5), which
        // UIKit scales 1.2× onto the card, as the card's aspect-filled photo.
        let rect = ZoomPhoto.alignmentRect(of: page, in: root, photoAspect: nil, sourceShape: CGSize(width: 402, height: 603))
        XCTAssertEqual(rect.width, 335, accuracy: 0.01)
        XCTAssertEqual(rect.height, 502.5, accuracy: 0.01)
        XCTAssertEqual(rect.midX, 201, accuracy: 0.01)
        XCTAssertEqual(rect.midY, 437, accuracy: 0.01)
    }

    func testPhotoNotLoadedYetUsesTheSourcePhotosAspect() {
        let root = screen()
        let page = imageElement(frame: root.bounds, image: nil, mode: .scaleAspectFit)
        root.addSubview(page)
        let picture = ZoomPhoto.pictureRect(of: page, in: root, fallbackAspect: 1)
        XCTAssertEqual(picture, CGRect(x: 0, y: 236, width: 402, height: 402))
    }

    func testAnyOtherElementLinesUpWithItsFrame() {
        let root = screen()
        let fill = imageElement(frame: CGRect(x: 0, y: 0, width: 402, height: 603), image: photo(CGSize(width: 800, height: 1000)), mode: .scaleAspectFill)
        let box = UIView(frame: CGRect(x: 16, y: 100, width: 180, height: 240))
        root.addSubview(fill)
        root.addSubview(box)
        XCTAssertEqual(ZoomPhoto.alignmentRect(of: fill, in: root, photoAspect: nil, sourceShape: CGSize(width: 100, height: 100)), fill.frame)
        XCTAssertEqual(ZoomPhoto.alignmentRect(of: box, in: root, photoAspect: nil, sourceShape: CGSize(width: 100, height: 100)), box.frame)
        XCTAssertNil(ZoomPhoto.imageView(in: box))
        XCTAssertNotNil(ZoomPhoto.imageView(in: fill))
        XCTAssertEqual(ZoomPhoto.aspect(of: fill) ?? 0, 0.8, accuracy: 0.001)
    }

    func testOverlaysAreTheControlsAboveThePhoto() {
        let root = screen()
        let pager = UIView(frame: root.bounds)
        let page = imageElement(frame: pager.bounds, image: photo(CGSize(width: 10, height: 10)), mode: .scaleAspectFit)
        pager.addSubview(page)
        let background = UIView(frame: root.bounds)
        let counter = UILabel(frame: CGRect(x: 16, y: 80, width: 40, height: 14))
        let close = UIView(frame: CGRect(x: 350, y: 66, width: 44, height: 44))
        let hidden = UIView(frame: CGRect(x: 0, y: 800, width: 402, height: 40))
        hidden.isHidden = true
        root.addSubview(background)   // below the pager: zooms with it
        root.addSubview(pager)
        root.addSubview(counter)
        root.addSubview(close)
        root.addSubview(hidden)
        let overlays = ZoomOverlays.overlays(over: page, in: root)
        XCTAssertEqual(overlays.count, 2)
        XCTAssertTrue(overlays.contains { $0 === counter })
        XCTAssertTrue(overlays.contains { $0 === close })
    }

    func testOverlaysOnlyWhereTheyCoverTheAlignedElement() {
        let root = screen()
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 500))
        let count = UILabel(frame: CGRect(x: 16, y: 470, width: 40, height: 14))
        let title = UILabel(frame: CGRect(x: 16, y: 520, width: 300, height: 30))
        root.addSubview(card)
        root.addSubview(count)
        root.addSubview(title)
        let overlays = ZoomOverlays.overlays(over: card, in: root)
        XCTAssertEqual(overlays.count, 1)
        XCTAssertTrue(overlays.first === count)
    }
}
