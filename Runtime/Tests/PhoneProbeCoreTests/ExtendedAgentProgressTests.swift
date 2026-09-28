import Testing
@testable import PhoneProbeCore

@Test func realImagesAdvanceProgressBeforeDelayedAgentStarts() {
    var progress = ExtendedAgentProgress(completedImages: 3)
    #expect(progress.completedUnits == 3)
    for _ in 0..<27 { progress.receivedImage() }
    #expect(progress.completedImages == 30)
    #expect(progress.completedUnits == 30 && progress.totalUnits == 65)
    #expect(progress.resolvedDecisions == 0 && !progress.complete)
}

@Test func captureQuotaCannotCompleteAnUnfinishedAgent() {
    var progress = ExtendedAgentProgress()
    for _ in 0..<70 { progress.receivedImage() }
    progress.updateRunner(resolvedDecisions: 3, completed: false)
    #expect(progress.completedUnits == 63 && !progress.complete)
    progress.updateRunner(resolvedDecisions: 4, completed: false)
    #expect(progress.completedUnits == 64 && !progress.complete)
    progress.updateRunner(resolvedDecisions: 4, completed: true)
    #expect(progress.completedUnits == 65 && progress.complete)
}

@Test func agentCompletionWaitsForRemainingCaptureWorkWithoutReplayingActions() {
    var progress = ExtendedAgentProgress(completedImages: 50)
    progress.updateRunner(resolvedDecisions: 4, completed: true)
    #expect(progress.completedUnits == 55 && !progress.complete)
    for _ in 0..<10 { progress.receivedImage() }
    #expect(progress.completedUnits == 65 && progress.complete)
    // Delayed duplicate/stale reports cannot move real progress backwards.
    progress.updateRunner(resolvedDecisions: -1, completed: false)
    #expect(progress.complete && progress.completedUnits == 65)
}

@Test func partialCompletionFlagDoesNotSatisfyAgentMilestone() {
    var progress = ExtendedAgentProgress(completedImages: 60)
    progress.updateRunner(resolvedDecisions: 2, completed: true)
    #expect(!progress.complete && progress.completedUnits == 62)
}
