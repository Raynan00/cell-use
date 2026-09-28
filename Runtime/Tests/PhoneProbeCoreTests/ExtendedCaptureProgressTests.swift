import Testing
@testable import PhoneProbeCore

@Test func captureOnlyCompletesAtSixtyImages() {
    var progress = ExtendedCaptureProgress()
    for _ in 0..<59 { progress.receivedImage(selectedInputFinished: false) }
    #expect(!progress.complete)
    progress.receivedImage(selectedInputFinished: false)
    #expect(progress.complete)
    #expect(progress.completedUnits == 60)
}

@Test func delayedInputKeepsJobOpenBeyondImageQuota() {
    var progress = ExtendedCaptureProgress()
    progress.requireSelectedInput()
    for _ in 0..<80 { progress.receivedImage(selectedInputFinished: false) }
    #expect(!progress.complete)
    #expect(progress.completedImages == 80)
    #expect(progress.completedUnits == 60)
    #expect(progress.totalUnits == 61)
    progress.receivedImage(selectedInputFinished: true)
    #expect(progress.complete)
    #expect(progress.completedUnits == 61)
}

@Test func inputMilestoneDoesNotSkipRemainingImages() {
    var progress = ExtendedCaptureProgress()
    progress.requireSelectedInput()
    progress.receivedImage(selectedInputFinished: true)
    #expect(!progress.complete)
    for _ in 0..<59 { progress.receivedImage(selectedInputFinished: false) }
    #expect(progress.complete)
    #expect(progress.selectedInputFinished)
}
