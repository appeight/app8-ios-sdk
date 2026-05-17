//
//  ImageLoader.swift
//  App8Engine
//

import UIKit
import ImageIO

/// URLSession-based image loader with in-memory caching and request coalescing.
///
/// Caches decoded UIImage objects (not raw Data) using NSCache, which auto-evicts
/// under memory pressure. Images are decoded and optionally downsampled on a
/// background thread so UIKit never stalls the main thread on first render.
@MainActor
final class ImageLoader {

    /// Decoded image cache, keyed by URL string (or URL + size for thumbnails).
    private let imageCache = NSCache<NSString, UIImage>()

    /// Raw response-data cache, keyed by URL. NSCache auto-evicts under memory
    /// pressure (cost = byte count) so it cannot grow unbounded.
    private let dataCache = NSCache<NSString, NSData>()

    /// In-flight continuations keyed by URL — coalesces concurrent requests for the same URL.
    private var inFlight: [String: [CheckedContinuation<Data?, Never>]] = [:]

    /// Session with bounded timeouts so a stalling server can't hang a request.
    private let urlSession: URLSession

    weak var logger: A8Log?

    init() {
        imageCache.countLimit = 60
        imageCache.totalCostLimit = 100 * 1024 * 1024
        dataCache.totalCostLimit = 50 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: config)
    }

    /// Load a decoded UIImage ready for display, optionally downsampled to a target point size.
    /// Returns a pre-decoded image that won't stall the main thread on first render.
    ///
    /// - Parameters:
    ///   - urlString: The image URL.
    ///   - targetPointSize: If provided, downsamples the image during decode to this point size
    ///     (multiplied by screen scale). Reduces memory for images displayed smaller than their
    ///     native resolution.
    /// - Returns: A decoded UIImage, or nil on failure.
    func loadImage(urlString: String, targetPointSize: CGSize? = nil) async -> UIImage? {
        let cacheKey = imageCacheKey(url: urlString, size: targetPointSize)

        if let cached = imageCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        guard let data = await load(urlString: urlString) else { return nil }

        let decoded: UIImage?
        if let targetPointSize {
            decoded = await Self.downsample(data: data, to: targetPointSize)
        } else {
            decoded = await Self.decodeImage(data: data)
        }

        if let decoded {
            let cost = Self.estimatedCost(of: decoded)
            imageCache.setObject(decoded, forKey: cacheKey as NSString, cost: cost)
        }

        return decoded
    }

    /// Load raw image data from a URL string, returning cached data when available.
    func load(urlString: String) async -> Data? {
        if let cached = dataCache.object(forKey: urlString as NSString) {
            return cached as Data
        }

        // Coalesce with an in-flight request if one exists.
        if inFlight[urlString] != nil {
            return await withCheckedContinuation { continuation in
                inFlight[urlString]?.append(continuation)
            }
        }

        inFlight[urlString] = []

        let data = await fetchData(urlString: urlString)

        if let data {
            dataCache.setObject(data as NSData, forKey: urlString as NSString, cost: data.count)
        }

        let waiters = inFlight.removeValue(forKey: urlString) ?? []
        for waiter in waiters {
            waiter.resume(returning: data)
        }

        return data
    }

    /// Clear both data and decoded image caches.
    func clearCache() {
        dataCache.removeAllObjects()
        imageCache.removeAllObjects()
    }

    /// Decode image data into a display-ready UIImage. `byPreparingForDisplay()`
    /// manages its own serial decode queue to avoid overloading the system.
    private static func decodeImage(data: Data) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return await image.byPreparingForDisplay()
    }

    /// Downsample image data to a target point size during decode.
    /// Uses ImageIO's CGImageSource which decodes only the pixels needed,
    /// avoiding the full-resolution bitmap entirely.
    private static func downsample(data: Data, to pointSize: CGSize) async -> UIImage? {
        let scale = await MainActor.run { UIScreen.main.scale }
        let maxPixelSize = max(pointSize.width, pointSize.height) * scale

        return await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
                return nil as UIImage?
            }

            let downsampleOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
                return nil as UIImage?
            }

            return UIImage(cgImage: cgImage)
        }.value
    }

    /// Estimated memory cost of a decoded UIImage (width * height * 4 bytes per pixel).
    private static func estimatedCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.width * cgImage.height * 4
    }

    private func imageCacheKey(url: String, size: CGSize?) -> String {
        guard let size else { return url }
        return "\(url)@\(Int(size.width))x\(Int(size.height))"
    }

    private func fetchData(urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else {
            logger?.error("ImageLoader: invalid URL '\(urlString)'")
            return nil
        }

        // Only http(s) — blocks file://, ftp:// etc. (local-file read / SSRF).
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            logger?.error("ImageLoader: rejected non-http(s) URL '\(urlString)'")
            return nil
        }

        do {
            let (byteStream, response) = try await urlSession.bytes(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger?.error("ImageLoader: HTTP \(code) for '\(urlString)'")
                return nil
            }

            // Reject up front when the server declares an oversized body.
            if httpResponse.expectedContentLength > Int64(EngineLimits.maxImageBytes) {
                logger?.error("ImageLoader: '\(urlString)' declares \(httpResponse.expectedContentLength) bytes — exceeds limit")
                return nil
            }

            // Abort past the cap even if the server under-declared Content-Length.
            var data = Data()
            if httpResponse.expectedContentLength > 0 {
                data.reserveCapacity(Int(httpResponse.expectedContentLength))
            }
            for try await byte in byteStream {
                data.append(byte)
                if data.count > EngineLimits.maxImageBytes {
                    logger?.error("ImageLoader: '\(urlString)' exceeded \(EngineLimits.maxImageBytes) bytes — aborted")
                    return nil
                }
            }
            return data
        } catch {
            logger?.error("ImageLoader: failed to load '\(urlString)': \(error.localizedDescription)")
            return nil
        }
    }
}
