import Foundation
import Testing
@testable import PhoneProbeCore

private func frame(_ gate: inout SelectedSequenceGate, _ id: UUID, _ time: Double,
                   eligible: Bool = true, after: Bool = true, stamp: Double? = nil) -> SelectedSequenceGate.Decision {
    gate.observe(generation: id, backgroundSeconds: time, frameTimestamp: stamp ?? time,
                 eligible: eligible, afterAcceptance: after, matchesZero: false, matchesSeven: false)
}

@Test func transportSequenceWorksWithoutAnyVisualReferenceMatch() {
    let id = UUID()
    var gate = SelectedSequenceGate(mode: .transportOnly)
    _ = gate.arm(generation: id)
    let early = frame(&gate, id, 2.9)
    #expect(early == .none)
    _ = frame(&gate, id, 3)
    let first = frame(&gate, id, 4.7)
    #expect(first == .tap(1))
    let unacknowledged = frame(&gate, id, 5)
    #expect(unacknowledged == .none)
    _ = gate.acknowledge(generation: id, step: 1, accepted: true, backgroundSeconds: 4.8)
    let tooOld = frame(&gate, id, 5.5, after: false)
    #expect(tooOld == .none)
    _ = frame(&gate, id, 6.4)
    let second = frame(&gate, id, 8.1)
    #expect(second == .tap(2))
    let noFinalAck = frame(&gate, id, 8.5)
    #expect(noFinalAck == .none)
    _ = gate.acknowledge(generation: id, step: 2, accepted: true, backgroundSeconds: 8.2)
    let beforeAcceptance = frame(&gate, id, 9, after: false)
    #expect(beforeAcceptance == .none)
    let result = frame(&gate, id, 9.8)
    #expect(result == .captureFinalImage)
    #expect(gate.stage == .complete)
    let third = frame(&gate, id, 11)
    #expect(third == .none)
    #expect(gate.attemptedActions == 2)
}

@Test func transportSequenceStillRejectsStaleDuplicateAndWrongRunFrames() {
    let id = UUID()
    var gate = SelectedSequenceGate(mode: .transportOnly)
    _ = gate.arm(generation: id)
    _ = frame(&gate, id, 3)
    let duplicate = frame(&gate, id, 4, stamp: 3)
    #expect(duplicate == .none)
    #expect(gate.matchingFrames == 0)
    _ = frame(&gate, id, 5)
    let stale = frame(&gate, id, 6, eligible: false)
    #expect(stale == .none)
    #expect(gate.matchingFrames == 0)
    let wrongRun = frame(&gate, UUID(), 7)
    #expect(wrongRun == .none)
    _ = frame(&gate, id, 8)
    let late = frame(&gate, id, 12.1)
    #expect(late == .none)
    #expect(gate.stopReason == "freshFrameTimedOut")
}

@Test(arguments: [false, true])
func transportSequenceNeverRetriesUncertainDeliveryOrResumesAfterReturn(foregroundReturn: Bool) {
    let id = UUID()
    var gate = SelectedSequenceGate(mode: .transportOnly)
    _ = gate.arm(generation: id)
    _ = frame(&gate, id, 3)
    _ = frame(&gate, id, 4.7)
    if foregroundReturn { gate.stop("returnedToForeground") }
    _ = gate.acknowledge(generation: id, step: 1, accepted: foregroundReturn, backgroundSeconds: 4.8)
    _ = frame(&gate, id, 6.4)
    let retry = frame(&gate, id, 8.1)
    #expect(retry == .none)
    #expect(gate.stage == .stopped)
    #expect(gate.attemptedActions == 1)
    let rearm = gate.arm(generation: id)
    #expect(!rearm)
}

@Test func transportSequenceCannotAdvanceWithoutPostCommandScreenshots() {
    let id = UUID()
    var gate = SelectedSequenceGate(mode: .transportOnly)
    _ = gate.arm(generation: id)
    _ = frame(&gate, id, 3)
    _ = frame(&gate, id, 4.7)
    _ = gate.acknowledge(generation: id, step: 1, accepted: true, backgroundSeconds: 4.8)
    _ = frame(&gate, id, 6.4, after: false)
    let deadline = frame(&gate, id, 12.9)
    #expect(deadline == .none)
    #expect(gate.attemptedActions == 1)
    #expect(gate.stage == .stopped)
}
