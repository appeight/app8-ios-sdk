//
//  ZoomPhotoPrimeTests.swift
//  App8EngineTests
//
//  A card-to-detail zoom grows the destination screen out of the card. When the
//  destination's photo is still decoding (the card's decoded copy evicted from
//  the memory cache), the zoom grew an empty box and the photo popped in after
//  it. The zoom now shows the card's picture in the destination's empty photo
//  when both show the same image source, and nothing else.
//

import XCTest
@testable import App8Engine

@MainActor
final class ZoomPhotoPrimeTests: XCTestCase {

    private func photo(_ color: UIColor = .gray) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 30, height: 40))
        }
    }

    func testEmptyDestinationWithTheSameSourceShowsTheCardPhoto() {
        let card = UIImageView(image: photo())
        let page = UIImageView()
        XCTAssertTrue(ZoomPhoto.prime(page, key: "https://cdn/x.png?width=900", from: card, key: "https://cdn/x.png?width=900"))
        XCTAssertTrue(page.image === card.image)
    }

    func testADifferentPictureIsLeftAlone() {
        // a cart line's packshot zooming into a lifestyle first photo: never show the wrong picture
        let card = UIImageView(image: photo())
        let page = UIImageView()
        XCTAssertFalse(ZoomPhoto.prime(page, key: "https://cdn/life.jpg", from: card, key: "https://cdn/pack.jpg"))
        XCTAssertNil(page.image)
    }

    func testALoadedDestinationKeepsItsImage() {
        let own = photo(.red)
        let card = UIImageView(image: photo())
        let page = UIImageView(image: own)
        XCTAssertFalse(ZoomPhoto.prime(page, key: "u", from: card, key: "u"))
        XCTAssertTrue(page.image === own)
    }

    func testUnknownSourcesOrAnUnloadedCardDoNothing() {
        let page = UIImageView()
        XCTAssertFalse(ZoomPhoto.prime(page, key: nil, from: UIImageView(image: photo()), key: "u"))
        XCTAssertFalse(ZoomPhoto.prime(page, key: "u", from: UIImageView(), key: "u"))
        XCTAssertNil(page.image)
    }

    func testViewsWithoutImageComponentsAreNotPrimed() {
        // plain UIImageViews (no image component around them) have no known source
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 40))
        card.addSubview(UIImageView(image: photo()))
        card.subviews[0].frame = card.bounds
        let page = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        let pageImage = UIImageView(frame: page.bounds)
        page.addSubview(pageImage)
        XCTAssertFalse(ZoomPhoto.prime(page, from: card))
        XCTAssertNil(pageImage.image)
    }
}
