//
//  ImageDecodeTests.swift
//  App8EngineTests
//
//  Images in formats `byPreparingForDisplay()` does not prepare (an
//  indexed-colour PNG, as image CDNs serve for flat artwork) still display.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class ImageDecodeTests: XCTestCase {

    /// A 24 x 24 PNG with an 8-bit colour palette.
    private static let palettePNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAMAAADXqc3KAAADAFBMVEXf3/TS4drF47/hzc7Pz6y53JjN3Ee+yH2q12/fvKLXtITIuXPXqm+5uVequTy0qjNx3PmH3KxzyOaW4VKgzUmF3yt44Q+M0ieMyBmFt/R4ud5uucyCqt2PtFqbtBiTtAlf4dZQ4bRG4Z5V0rM34Xw30nRVyKo3yG4j4U8U4S0e0j8F4QsF0gseyDwFyApfubBQuZRGuYJVqpE3uWY3ql4juUEUuSUeqjMFuQkFqgm3hfSqh+bjnWTVmUjhjDzDoDnLjyTXghm3mRqqmwm+jAvacfXIc+a5eN65bsyqc8TheA+ZmeuMm9l/ncabh9GMjMR4lLGHgrBxjJ6HkUibc7KMc6GCc5Zzc4Rfm5NQm3xGm21VjHc3m1U3jE1Vgm83gkhfc21Qc1xGc1E3cz8jmzYUmx8ejCoFmwgFjAcegicFggcjcygUcxcFcwbhX9bSX8jIX77XUKzXRpe5X7CqX6K0UJC0Rn7hN3zSN3TIN265N2aqN16bX5OMX4WCX3yRUHRzX21zUFyRRmZzRlGbN1WMN02CN0hzNz/hI0/SI0rII0bcFCzIFCi5I0GqIzy0FCThBQvSBQvIBQq5BQmqBQmbIzaMIzGCIy6RFB1zKC5zHiNzFBebBQiMBQeCBQdzBQZfX1pQX0xGX0NVUEQ3XzQ3UCxVRjw3RidfNzRQNyxGNyc3Nx4jXyEUXxMeUBgFXwUFUAQeRhUFRgQjNxMUNwsFNwNfIyFQIxxGIxlVFBE3IxM3FAtfBQVQBQRGBQQ3BQMjIwwUIwceFAYFIwIFFAEjBQIUBQEFBQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACp41kVAAAB9klEQVR4nGM4fvzY0aP79+/bu2fP/Pnz5s6ZM2Xy5EkTJ0xgwClx5MihQ4d27965c+fO2bNnzJgxo7+/v6e7u5vh8OGDBw7s2rVj+7Zts2ZNnzZ1al9fb1dnZweyxMyZ06eBxbs6OzoYtm7dsnnz6tWrVq5Y0d7e1traUl1dVVlRUY4i0dYGEa+sKC9n2LRp48aNy5evWrZsWXNzc1NTU1lZWVFRURHDhg3r1q1bunTZ4sXNjY1N9fX1paWlhYWFhQzr169ds2bJkkULFyxoaKirra0pKSkuKMjPQ5Goq4OL5zHk5uZkZycnJyUmJISHh4WGhnh6eLi5ubpCJeLBEmFhoSGenu7ubq5eXgxZWTmZmfHxSXFx0UFBgYH+ftZWVi6OjnYMGRmpaSmxsVHR0RFBASBxaysXBwc7O4b0dJBETFRkRERQgK+Pt7ezk5ODra0NSCIlJcYEJBHg6+vj7ezsZG9va2PDYGlpZm5qYhJlZKQv7SsjKS/Hz2/Py8PDxWBhAZIwNjTQ15eWkpSUl+Pj4+Xm4uIESeiaGqtDJSDi3FycnAx6ema6purqhmpq0kJCEhLiIiIc7OwsLMwMOjqaWhqqqkpqygpCAhBxVpA4g7Y2SEJFSVFBQUBMVFSYg4OVlYmRASyhoaECkxAWBokzMTKwAQCjouGuQ1dqEwAAAABJRU5ErkJggg==")!

    func testPalettePNGDecodes() async throws {
        let raw = try XCTUnwrap(UIImage(data: Self.palettePNG), "UIKit reads the file")
        XCTAssertEqual(raw.size, CGSize(width: 24, height: 24))
        // On iOS 26, raw.byPreparingForDisplay() is nil for this file.
        let decoded = await ImageLoader.decodeForDisplay(data: Self.palettePNG)
        let image = try XCTUnwrap(decoded, "an image the system cannot prepare still displays")
        XCTAssertEqual(image.size.width * image.scale, 24, accuracy: 0.5)
    }
}
