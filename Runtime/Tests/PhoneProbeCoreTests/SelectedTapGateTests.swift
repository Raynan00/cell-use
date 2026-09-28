import Foundation
import Testing
@testable import PhoneProbeCore

@Test func delayedTapNeedsTwoMatchesAfterSixtySeconds() {
    let generation = UUID()
    var gate = SelectedTapGate()
    let armed = gate.arm(generation: generation, timing: .after60Seconds)
    #expect(armed)
    for seconds in [3.0, 25, 59.999] {
        let submitted = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: seconds)
        #expect(!submitted)
        #expect(gate.matchingFrames == 0)
    }
    let wrongRun = gate.observe(generation: UUID(), eligible: true, matches: true, backgroundSeconds: 60)
    #expect(!wrongRun)
    let first = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: 60)
    #expect(!first)
    let stale = gate.observe(generation: generation, eligible: false, matches: true, backgroundSeconds: 61)
    #expect(!stale)
    #expect(gate.matchingFrames == 0)
    let second = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: 62)
    #expect(!second)
    let submitted = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: 63.5)
    #expect(submitted)
    let retry = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: 65)
    #expect(!retry)
    let rearm = gate.arm(generation: generation, timing: .after60Seconds)
    #expect(!rearm)
}

@Test(arguments: [85.001, Double.infinity, Double.nan])
func delayedTapExpiresWithoutSubmitting(seconds: Double) {
    let generation = UUID()
    var gate = SelectedTapGate()
    _ = gate.arm(generation: generation, timing: .after60Seconds)
    _ = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: 84)
    let submitted = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: seconds)
    #expect(!submitted)
    #expect(!gate.armed)
    #expect(!gate.attempted)
}

@Test func returningBeforeDelayedTapRequiresExplicitRearming() {
    let generation = UUID()
    var gate = SelectedTapGate()
    _ = gate.arm(generation: generation, timing: .after60Seconds)
    _ = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: 60)
    gate.disarm()
    let submitted = gate.observe(generation: generation, eligible: true, matches: true, backgroundSeconds: 62)
    #expect(!submitted)
}

@Test func selectedTapRequiresConsecutiveEligibleFramesAndNeverRetries() {
    let generation = UUID()
    var gate = SelectedTapGate()
    let check7 = gate.arm(generation: generation)
    #expect(check7)
    let check8 = !gate.observe(generation: UUID(), eligible: true, matches: true)
    #expect(check8)
    let check9 = !gate.observe(generation: generation, eligible: true, matches: true)
    #expect(check9)
    let check10 = !gate.observe(generation: generation, eligible: false, matches: true)
    #expect(check10)
    let check11 = !gate.observe(generation: generation, eligible: true, matches: true)
    #expect(check11)
    let check12 = !gate.observe(generation: generation, eligible: true, matches: false)
    #expect(check12)
    let check13 = !gate.observe(generation: generation, eligible: true, matches: true)
    #expect(check13)
    let check14 = gate.observe(generation: generation, eligible: true, matches: true)
    #expect(check14)
    let check15 = !gate.observe(generation: generation, eligible: true, matches: true)
    #expect(check15)
    let check16 = !gate.arm(generation: generation)
    #expect(check16)
}

@Test func disarmingPreventsLateSelectedTap() {
    let generation = UUID()
    var gate = SelectedTapGate()
    let check22 = gate.arm(generation: generation)
    #expect(check22)
    let check23 = !gate.observe(generation: generation, eligible: true, matches: true)
    #expect(check23)
    gate.disarm()
    let check25 = !gate.observe(generation: generation, eligible: true, matches: true)
    #expect(check25)
}
