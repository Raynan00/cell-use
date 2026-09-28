import Foundation
import Testing
@testable import PhoneProbeCore

@Test func transportSuccessDoesNotProveInput() {
    var evidence = ProbeEvidence()
    let generation = evidence.generation
    evidence.connect(generation: generation)
    evidence.image(generation: generation, whileBackgrounded: false)
    let unverifiedSubmission = evidence.submitInput(generation: generation)
    #expect(!unverifiedSubmission)
    evidence.verifySelfScreen(generation: generation)
    let verifiedSubmission = evidence.submitInput(generation: generation)
    #expect(verifiedSubmission)
    #expect(!evidence.targetActivated)
    evidence.receiveTargetActivation(generation: generation)
    #expect(evidence.targetActivated)
}

@Test func staleCallbacksAndPostCancellationEventsAreIgnored() {
    var evidence = ProbeEvidence()
    let generation = evidence.generation
    evidence.connect(generation: UUID())
    #expect(!evidence.connected)
    evidence.finish(generation: generation, cancelled: true)
    let stopped = evidence
    evidence.connect(generation: generation)
    evidence.image(generation: generation, whileBackgrounded: true)
    evidence.receiveTargetActivation(generation: generation)
    #expect(evidence == stopped)
}

@Test func aManualTapBeforeSubmissionDoesNotPass() {
    var evidence = ProbeEvidence()
    evidence.receiveTargetActivation(generation: evidence.generation)
    #expect(!evidence.targetActivated)
}

@Test func backgroundEvidenceRequiresActualBackgroundFrames() {
    var evidence = ProbeEvidence()
    let generation = evidence.generation
    evidence.image(generation: generation, whileBackgrounded: false)
    #expect(evidence.framesReceivedInBackground == 0)
    evidence.image(generation: generation, whileBackgrounded: true)
    evidence.expireBackgroundLease(generation: generation)
    #expect(evidence.framesReceivedInBackground == 1)
    #expect(evidence.backgroundLeaseExpired)
    #expect(!evidence.targetActivated)
}

@Test func challengeMustMatchWholeRandomMarker() {
    let marker = "PROBEABCD23456789"
    #expect(ProbeChecks.containsChallenge(["PROBE ABCD 23456789"], challenge: marker))
    #expect(!ProbeChecks.containsChallenge(["PROBE ABCD 23456780"], challenge: marker))
    #expect(!ProbeChecks.containsChallenge([marker], challenge: "PROBE"))
}

@Test func staleAndFutureFramesCannotAuthorizeInput() {
    let now = Date(timeIntervalSince1970: 100)
    #expect(ProbeChecks.isFresh(receivedAt: now.addingTimeInterval(-1), now: now))
    #expect(!ProbeChecks.isFresh(receivedAt: now.addingTimeInterval(-3), now: now))
    #expect(!ProbeChecks.isFresh(receivedAt: now.addingTimeInterval(1), now: now))
}

@Test func reportContainsOnlyEvidence() throws {
    let text = String(decoding: try JSONEncoder().encode(ProbeEvidence()), as: UTF8.self)
    #expect(!text.contains("pairingCode"))
    #expect(!text.contains("screenshot"))
    #expect(!text.contains("privateKey"))
}
