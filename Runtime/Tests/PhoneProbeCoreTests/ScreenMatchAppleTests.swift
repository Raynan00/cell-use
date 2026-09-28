#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import Testing
@testable import PhoneProbeCore

@Test func screenSignatureIgnoresStatusBarButRejectsChangedContent() throws {
    func image(statusChange: Bool = false, bodyChange: Bool = false) throws -> CGImage {
        let width = 1206, height = 2622
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 1300..<1550 { for x in 100..<400 { pixels[y * width + x] = 255 } }
        if statusChange {
            for y in 40..<140 { for x in 50..<300 { pixels[y * width + x] = 255 } }
        }
        if bodyChange {
            for y in 800..<880 { for x in 990..<1090 { pixels[y * width + x] = 255 } }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    let reference = try #require(ScreenMatch.signature(image()))
    let clock = try #require(ScreenMatch.signature(image(statusChange: true)))
    let changed = try #require(ScreenMatch.signature(image(bodyChange: true)))
    #expect(ScreenMatch.compare(reference, clock).matches)
    #expect(!ScreenMatch.compare(reference, changed).matches)
}
#endif
