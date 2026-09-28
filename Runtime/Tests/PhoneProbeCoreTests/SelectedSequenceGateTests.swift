import Foundation
import Testing
@testable import PhoneProbeCore

private func observe(_ gate: inout SelectedSequenceGate, _ id: UUID, _ seconds: Double,
                     zero: Bool = false, seven: Bool = false, eligible: Bool = true,
                     after: Bool = true, timestamp: Double? = nil) -> SelectedSequenceGate.Decision {
    gate.observe(generation: id, backgroundSeconds: seconds, frameTimestamp: timestamp ?? seconds,
                 eligible: eligible, afterAcceptance: after, matchesZero: zero, matchesSeven: seven)
}

private func firstTap(_ id: UUID) -> SelectedSequenceGate {
    var gate = SelectedSequenceGate()
    _ = gate.arm(generation: id)
    _ = observe(&gate, id, 60, zero: true)
    _ = observe(&gate, id, 62, zero: true)
    return gate
}

@Test func sequenceRequiresIntermediateReferenceAndAcknowledgedDelivery() {
    let id = UUID()
    var gate = SelectedSequenceGate()
    _ = gate.arm(generation: id)
    let early = observe(&gate, id, 59.9, zero: true)
    #expect(early == .none)
    let firstMatch = observe(&gate, id, 60, zero: true)
    #expect(firstMatch == .none)
    let first = observe(&gate, id, 62, zero: true)
    #expect(first == .tap(1))
    let pending = observe(&gate, id, 63, seven: true)
    #expect(pending == .none)
    _ = gate.acknowledge(generation: id, step: 1, accepted: true, backgroundSeconds: 62.1)
    let old = observe(&gate, id, 64, seven: true, after: false)
    #expect(old == .none)
    let unchanged = observe(&gate, id, 65, zero: true)
    #expect(unchanged == .none)
    let match = observe(&gate, id, 66, seven: true)
    #expect(match == .none)
    let second = observe(&gate, id, 68, seven: true)
    #expect(second == .tap(2))
    let pendingFinal = observe(&gate, id, 69)
    #expect(pendingFinal == .none)
    _ = gate.acknowledge(generation: id, step: 2, accepted: true, backgroundSeconds: 68.1)
    let preAckImage = observe(&gate, id, 70, after: false)
    #expect(preAckImage == .none)
    let final = observe(&gate, id, 72)
    #expect(final == .captureFinalImage)
    #expect(gate.stage == .complete)
    #expect(gate.attemptedActions == 2)
    let again = observe(&gate, id, 74, seven: true)
    #expect(again == .none)
    let rearm = gate.arm(generation: id)
    #expect(!rearm)
}

@Test func sequenceRejectsStaleDuplicateAmbiguousAndWrongRunFrames() {
    let id = UUID()
    var gate = SelectedSequenceGate()
    _ = gate.arm(generation: id)
    let wrongRun = observe(&gate, UUID(), 60, zero: true)
    #expect(wrongRun == .none)
    _ = observe(&gate, id, 60, zero: true)
    let duplicate = observe(&gate, id, 61, zero: true, timestamp: 60)
    #expect(duplicate == .none)
    #expect(gate.matchingFrames == 0)
    _ = observe(&gate, id, 62, zero: true)
    let stale = observe(&gate, id, 64, zero: true, eligible: false)
    #expect(stale == .none)
    #expect(gate.matchingFrames == 0)
    _ = observe(&gate, id, 66, zero: true)
    let ambiguous = observe(&gate, id, 68, zero: true, seven: true)
    #expect(ambiguous == .none)
    #expect(gate.matchingFrames == 0)
}

@Test func uncertainSequenceDeliveryAndForegroundReturnAreTerminal() {
    let id = UUID()
    var gate = firstTap(id)
    _ = gate.acknowledge(generation: id, step: 1, accepted: false, backgroundSeconds: 62.1)
    #expect(gate.stage == .stopped)
    _ = observe(&gate, id, 64, seven: true)
    let retry = observe(&gate, id, 66, seven: true)
    #expect(retry == .none)
    let rearm = gate.arm(generation: id)
    #expect(!rearm)
    gate = firstTap(id)
    gate.stop("returnedToForeground")
    let lateAck = gate.acknowledge(generation: id, step: 1, accepted: true, backgroundSeconds: 62.1)
    #expect(!lateAck)
    #expect(gate.stage == .stopped)
}

@Test func sequenceTimesOutWhenExpectedSevenNeverAppears() {
    let id = UUID()
    var gate = firstTap(id)
    _ = gate.acknowledge(generation: id, step: 1, accepted: true, backgroundSeconds: 62.1)
    _ = observe(&gate, id, 64, zero: true)
    let timeout = observe(&gate, id, 77.2, seven: true)
    #expect(timeout == .none)
    #expect(gate.stage == .stopped)
    #expect(gate.attemptedActions == 1)
}

@Test func secondTapNeedsConsecutiveUnambiguousSevenFrames() {
    let id = UUID()
    var gate = firstTap(id)
    _ = gate.acknowledge(generation: id, step: 1, accepted: true, backgroundSeconds: 62.1)
    _ = observe(&gate, id, 64, seven: true)
    let ambiguous = observe(&gate, id, 66, zero: true, seven: true)
    #expect(ambiguous == .none)
    #expect(gate.matchingFrames == 0)
    _ = observe(&gate, id, 68, seven: true)
    let unexpected = observe(&gate, id, 70)
    #expect(unexpected == .none)
    #expect(gate.matchingFrames == 0)
    let first = observe(&gate, id, 72, seven: true)
    #expect(first == .none)
    let second = observe(&gate, id, 74, seven: true)
    #expect(second == .tap(2))
}

@Test(arguments: [85.001, Double.nan, Double.infinity])
func sequenceCannotStartLateOrWithInvalidTiming(seconds: Double) {
    let id = UUID()
    var gate = SelectedSequenceGate()
    _ = gate.arm(generation: id)
    let late = observe(&gate, id, seconds, zero: true)
    #expect(late == .none)
    #expect(gate.stage == .stopped)
    #expect(gate.attemptedActions == 0)
}

@Test func sequenceIgnoresWrongAcknowledgementAndRequiresPostSecondImage() {
    let id = UUID()
    var gate = firstTap(id)
    let wrongStep = gate.acknowledge(generation: id, step: 2, accepted: true, backgroundSeconds: 62.1)
    let wrongRun = gate.acknowledge(generation: UUID(), step: 1, accepted: true, backgroundSeconds: 62.1)
    #expect(!wrongStep && !wrongRun)
    _ = gate.acknowledge(generation: id, step: 1, accepted: true, backgroundSeconds: 62.1)
    _ = observe(&gate, id, 64, seven: true)
    _ = observe(&gate, id, 66, seven: true)
    _ = gate.acknowledge(generation: id, step: 2, accepted: true, backgroundSeconds: 66.1)
    let timeout = observe(&gate, id, 76.2)
    #expect(timeout == .none)
    #expect(gate.stage == .stopped)
}
