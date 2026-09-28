import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A visual guard for an explicitly selected target, not app identity or OCR.
public enum ScreenMatch {
    public static let width = 96
    public static let height = 192
    public struct Signature: Sendable {
        public let imageWidth: Int
        public let imageHeight: Int
        public let pixels: [UInt8]
        public init(imageWidth: Int, imageHeight: Int, pixels: [UInt8]) {
            self.imageWidth = imageWidth; self.imageHeight = imageHeight; self.pixels = pixels
        }
    }
    public struct Comparison: Encodable, Sendable {
        public let matches: Bool
        public let meanDifference: Double
        public let worstTileDifference: Double
    }
    public static func compare(_ reference: Signature, _ current: Signature) -> Comparison {
        guard reference.imageWidth == current.imageWidth, reference.imageHeight == current.imageHeight,
              reference.pixels.count == width * height, current.pixels.count == width * height,
              reference.pixels.filter({ $0 > 180 }).count >= 100 else {
            return Comparison(matches: false, meanDifference: 1, worstTileDifference: 1)
        }
        var sums = [Double](repeating: 0, count: 128)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                sums[(y / 12) * 8 + x / 12] += Double(abs(Int(reference.pixels[i]) - Int(current.pixels[i]))) / 255
            }
        }
        let mean = sums.reduce(0, +) / Double(width * height)
        let worst = (sums.max() ?? 144) / 144
        return Comparison(matches: mean <= 0.012 && worst <= 0.04,
                          meanDifference: mean, worstTileDifference: worst)
    }

    #if canImport(CoreGraphics)
    public static func signature(_ image: CGImage) -> Signature? {
        // Exclude clock/status indicators and the bottom home indicator.
        let region = CGRect(x: 0, y: Double(image.height) * 0.12,
                            width: Double(image.width), height: Double(image.height) * 0.84).integral
        guard let crop = image.cropping(to: region) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Signature(imageWidth: image.width, imageHeight: image.height, pixels: pixels) : nil
    }
    #endif
}
