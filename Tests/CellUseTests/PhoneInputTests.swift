import Foundation
import Testing
@testable import CellUse

@Test @MainActor func swipeHasOrderedEdgesAndNoRetryAfterPartialFailure() async throws {
    let action = PhoneAction.swipe(fromX: 0.5, fromY: 0.8, toX: 0.5, toY: 0.2, duration: 0.6)
    var events: [PhoneInputEvent] = []
    var delays: [Double] = []
    try await PhoneInputDelivery.deliver(action, contextIsValid: { true }, send: { events.append($0) }, sleep: { delays.append($0) })
    #expect(events.count == 13 && delays.count == 12)
    #expect(events.first == .touch(x: 0.5, y: 0.8, phase: .began))
    guard case let .touch(x, y, phase) = events.last else { Issue.record("Missing release"); return }
    #expect(x == 0.5 && abs(y - 0.2) < 0.0001 && phase == .ended)
    #expect(abs(delays.reduce(0, +) - 0.6) < 0.0001)
    events = []
    enum Interrupted: Error { case disconnected }
    do {
        try await PhoneInputDelivery.deliver(action, contextIsValid: { true }, send: {
            events.append($0)
            if events.count == 3 { throw Interrupted.disconnected }
        }, sleep: { _ in })
        Issue.record("Partial delivery must fail")
    } catch {}
    #expect(events.count == 4 && events.last == .releaseAll)
    #expect(events.filter { $0 == .touch(x: 0.5, y: 0.8, phase: .began) }.count == 1)
}

@Test @MainActor func textPreflightRejectsWholeStringAndDoesNotPressReturn() async throws {
    var events: [PhoneInputEvent] = []
    for text in ["", "hello\n", "helloé", String(repeating: "a", count: 33)] {
        do {
            try await PhoneInputDelivery.deliver(.typeText(text), contextIsValid: { true }, send: { events.append($0) }, sleep: { _ in })
            Issue.record("Unsupported text accepted")
        } catch {}
    }
    #expect(events.isEmpty)
    try await PhoneInputDelivery.deliver(.typeText("Hello 20!"), contextIsValid: { true }, send: { events.append($0) }, sleep: { _ in })
    #expect(events == Array("Hello 20!").map { .character($0) })
}

@Test @MainActor func changedContextStopsTextWithoutReplayingPrefix() async {
    var events: [PhoneInputEvent] = []
    do {
        try await PhoneInputDelivery.deliver(.typeText("abcd"), contextIsValid: { events.count < 2 }, send: { events.append($0) }, sleep: { _ in })
        Issue.record("Should stop after context changed")
    } catch {}
    #expect(events == [.character("a"), .character("b"), .releaseAll])
}

@Test @MainActor func cancellationReleasesAnActiveTouch() async {
    var events: [PhoneInputEvent] = []
    do {
        try await PhoneInputDelivery.deliver(.swipe(fromX: 0.5, fromY: 0.8, toX: 0.5, toY: 0.2, duration: 0.6),
            contextIsValid: { true }, send: { events.append($0) }, sleep: { _ in throw CancellationError() })
        Issue.record("Cancelled swipe completed")
    } catch {}
    #expect(events == [.touch(x: 0.5, y: 0.8, phase: .began), .releaseAll])
}

private func inputReadyRunner() -> (PhoneActionRunner, PhoneFrame) {
    var runner = PhoneActionRunner()
    runner.start(at: 0)
    _ = runner.offer(PhoneFrame(runID: runner.snapshot.runID, width: 1206, height: 2622, capturedAt: 3), inputReady: true, now: 3)
    let frame = PhoneFrame(runID: runner.snapshot.runID, width: 1206, height: 2622, capturedAt: 4.7)
    _ = runner.offer(frame, inputReady: true, now: 4.7)
    return (runner, frame)
}

@Test func newInputsRespectBindingsValidationAndRedactDiagnostics() throws {
    let actions: [PhoneAction] = [.typeText("private-example"), .swipe(fromX: 0.5, fromY: 0.8, toX: 0.5, toY: 0.2, duration: 0.6)]
    for action in actions {
        var (runner, frame) = inputReadyRunner()
        let decision = PhoneDecision(runID: frame.runID, observationID: frame.id, action: action)
        let result = runner.resolve(decision, now: 4.8)
        let command = try #require(result)
        #expect(command.action == action && runner.snapshot.inputs.count == 1)
        let duplicate = runner.resolve(decision, now: 4.9)
        #expect(duplicate == nil)
        runner.acknowledge(command: command.id, accepted: false, now: 5)
        runner.acknowledge(command: command.id, accepted: true, now: 5.1)
        #expect(runner.snapshot.stopReason == "deliveryUncertainNoRetry")
        #expect(runner.snapshot.acceptedInputCount == 0)
        let report = String(decoding: try JSONEncoder().encode(runner.snapshot), as: UTF8.self)
        #expect(!report.contains("private-example") && !report.contains("fromX"))
    }
    for action: PhoneAction in [.typeText("no\n"), .swipe(fromX: -1, fromY: 0.8, toX: 0.5, toY: 0.2, duration: 0.6),
        .swipe(fromX: 0.5, fromY: 0.8, toX: 0.5, toY: 0.2, duration: .nan)] {
        var (runner, frame) = inputReadyRunner()
        let command = runner.resolve(PhoneDecision(runID: frame.runID, observationID: frame.id, action: action), now: 4.8)
        #expect(command == nil && runner.snapshot.inputs.isEmpty && runner.snapshot.status == .stopped)
    }
}
