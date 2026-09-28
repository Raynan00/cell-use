import Testing
@testable import PhoneProbeCore

@Test func selectedScreenRejectsLocalChangesHiddenByWholeImageAverage() {
    let pixels = [UInt8](repeating: 200, count: ScreenMatch.width * ScreenMatch.height)
    let reference = ScreenMatch.Signature(imageWidth: 1206, imageHeight: 2622, pixels: pixels)
    #expect(ScreenMatch.compare(reference, reference).matches)
    var changed = pixels
    for i in 0..<120 { changed[i] = 0 }
    let result = ScreenMatch.compare(reference, .init(imageWidth: 1206, imageHeight: 2622, pixels: changed))
    #expect(result.meanDifference < 0.012)
    #expect(!result.matches)
    #expect(!ScreenMatch.compare(reference, .init(imageWidth: 2622, imageHeight: 1206, pixels: pixels)).matches)
    #expect(!ScreenMatch.compare(reference, .init(imageWidth: 1206, imageHeight: 2622, pixels: [])).matches)
}

@Test func blankScreensCannotAuthorizeSelectedInput() {
    let blank = ScreenMatch.Signature(imageWidth: 1206, imageHeight: 2622,
        pixels: [UInt8](repeating: 0, count: ScreenMatch.width * ScreenMatch.height))
    #expect(!ScreenMatch.compare(blank, blank).matches)
}
