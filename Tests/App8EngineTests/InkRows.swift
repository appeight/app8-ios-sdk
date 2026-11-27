//
//  InkRows.swift
//  App8EngineTests
//
//  Measures drawn ink (rendered pixels) of a view: which rows and columns
//  contain dark pixels. Shared by the text rendering tests.
//

import UIKit

/// Rows of a rendered view that contain dark ink, in points.
@MainActor
struct InkRows {
    /// Runs of consecutive ink rows (one per text line when lines do not touch).
    let bands: [ClosedRange<CGFloat>]
    /// Leftmost and rightmost ink column, in points.
    let columns: ClosedRange<CGFloat>?

    var top: CGFloat { bands.first?.lowerBound ?? .nan }
    var bottom: CGFloat { bands.last?.upperBound ?? .nan }
    var centre: CGFloat { (top + bottom) / 2 }

    init(of view: UIView, scale: CGFloat, in rect: CGRect? = nil) {
        let size = view.bounds.size
        let width = Int(size.width * scale), height = Int(size.height * scale)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        view.layer.render(in: context)
        UIGraphicsPopContext()

        let x0 = max(0, Int((rect?.minX ?? 0) * scale)), x1 = min(width, Int((rect?.maxX ?? size.width) * scale))
        let y0 = max(0, Int((rect?.minY ?? 0) * scale)), y1 = min(height, Int((rect?.maxY ?? size.height) * scale))
        var bands: [ClosedRange<CGFloat>] = []
        var start: Int?
        var minX = Int.max, maxX = Int.min
        for y in y0..<y1 {
            var ink = false
            for x in x0..<x1 where pixels[(y * width + x) * 4] < 128 {
                ink = true
                minX = min(minX, x); maxX = max(maxX, x)
            }
            if ink, start == nil { start = y }
            if !ink, let s = start {
                bands.append(CGFloat(s) / scale ... CGFloat(y) / scale)
                start = nil
            }
        }
        if let s = start { bands.append(CGFloat(s) / scale ... CGFloat(y1) / scale) }
        self.bands = bands
        columns = minX <= maxX ? CGFloat(minX) / scale ... CGFloat(maxX + 1) / scale : nil
    }

    /// The ink columns of one band of `view` (a text line, an underline).
    static func columns(of band: ClosedRange<CGFloat>, in view: UIView, scale: CGFloat) -> ClosedRange<CGFloat>? {
        let rect = CGRect(x: 0, y: band.lowerBound, width: view.bounds.width, height: band.upperBound - band.lowerBound)
        return InkRows(of: view, scale: scale, in: rect).columns
    }
}
