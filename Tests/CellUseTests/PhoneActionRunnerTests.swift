import Foundation
import Testing
@testable import CellUse

private func screen(_ runner: PhoneActionRunner, _ at: Double, width: Int = 1206, portrait: Bool = true) -> PhoneFrame {
    PhoneFrame(runID: runner.snapshot.runID, width: width, height: 2622, capturedAt: at, portrait: portrait)
}
private func ready(configuration: PhoneActionRunner.Configuration = .init()) -> (PhoneActionRunner, PhoneFrame) {
    var runner = PhoneActionRunner(configuration: configuration)
    runner.start(at: 0)
    let initial = configuration.initialDelay
    _ = runner.offer(screen(runner, initial), inputReady: true, now: initial)
    let frame = screen(runner, initial + 1.7)
    _ = runner.offer(frame, inputReady: true, now: frame.capturedAt)
    return (runner, frame)
}
private func reply(_ frame: PhoneFrame, _ action: PhoneAction) -> PhoneDecision {
    PhoneDecision(runID: frame.runID, observationID: frame.id, action: action)
}

@Test(arguments: [false, true]) func agentClientDrivesTapWaitTapFinishThroughFreshObservations(extended: Bool) async throws {
    let agent = ScriptedPhoneAgent(actions: [.tap(x: 0.2, y: 0.6), .wait(seconds: 1), .tap(x: 0.2, y: 0.6), .finish])
    var configuration = PhoneActionRunner.Configuration()
    if extended { configuration.initialDelay = 60; configuration.runTimeout = 95 }
    var (runner, frame) = ready(configuration: configuration)
    let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
    for index in 0..<4 {
        let observation = PhoneObservation(frame: frame, screenshotPNG: png, decisionIndex: index,
                                           acceptedTapCount: runner.snapshot.acceptedTapCount)
        runner.noteScreenshotBytes(png.count, observationID: frame.id)
        let decision = try await agent.nextAction(for: observation)
        let now = frame.capturedAt + 0.1
        let command = runner.resolve(decision, now: now)
        if index == 0 || index == 2 {
            let tap = try #require(command)
            #expect(tap.imageWidth == 1206 && tap.imageHeight == 2622)
            runner.acknowledge(command: tap.id, accepted: true, now: now + 0.02)
        } else { #expect(command == nil) }
        if index < 3 {
            let first = screen(runner, now + 1.8)
            let firstRequested = runner.offer(first, inputReady: true, now: first.capturedAt)
            #expect(!firstRequested)
            frame = screen(runner, now + 3.5)
            let nextRequested = runner.offer(frame, inputReady: true, now: frame.capturedAt)
            #expect(nextRequested)
        }
    }
    #expect(runner.snapshot.status == .completed)
    #expect(runner.snapshot.acceptedTapCount == 2)
    #expect(runner.snapshot.waitCount == 1)
    #expect(runner.snapshot.observations.map(\.actionKind) == ["tap", "wait", "tap", "finish"])
    #expect(runner.snapshot.observations.allSatisfy { $0.screenshotBytes == png.count })
    let report = String(decoding: try JSONEncoder().encode(runner.snapshot), as: UTF8.self)
    #expect(!report.contains("screenshotPNG"))
    if extended { #expect(runner.snapshot.taps.allSatisfy { $0.submittedSeconds >= 60 }) }
}

@Test func extendedWarmupCannotSubmitEarlyAndExpiryRejectsPendingDecision() {
    var configuration = PhoneActionRunner.Configuration()
    configuration.initialDelay = 60; configuration.runTimeout = 95
    var runner = PhoneActionRunner(configuration: configuration)
    runner.start(at: 0)
    for time in 1..<60 {
        let offered = runner.offer(screen(runner, Double(time)), inputReady: true, now: Double(time))
        #expect(!offered)
    }
    #expect(runner.active && runner.snapshot.observations.isEmpty)
    _ = runner.offer(screen(runner, 60), inputReady: true, now: 60)
    let frame = screen(runner, 61.7)
    let offered = runner.offer(frame, inputReady: true, now: 61.7)
    #expect(offered)
    runner.stop("backgroundWorkExpired")
    let command = runner.resolve(reply(frame, .tap(x: 0.2, y: 0.6)), now: 62)
    #expect(command == nil && runner.snapshot.taps.isEmpty)
    #expect(runner.snapshot.stopReason == "backgroundWorkExpired")
}

@Test func decisionsAreBoundToOneRunAndOneObservation() throws {
    var (runner, frame) = ready()
    let wrongRun = PhoneDecision(runID: UUID(), observationID: frame.id, action: .tap(x: 0.5, y: 0.5))
    let wrongFrame = PhoneDecision(runID: frame.runID, observationID: UUID(), action: .tap(x: 0.5, y: 0.5))
    let runResult = runner.resolve(wrongRun, now: 4.8)
    let frameResult = runner.resolve(wrongFrame, now: 4.8)
    #expect(runResult == nil && frameResult == nil)
    #expect(runner.snapshot.status == .deciding)
    let decision = reply(frame, .tap(x: 0.5, y: 0.5))
    let proposed = runner.resolve(decision, now: 4.8)
    let command = try #require(proposed)
    let duplicate = runner.resolve(decision, now: 4.9)
    #expect(duplicate == nil)
    let duringDelivery = runner.offer(screen(runner, 5), inputReady: true, now: 5)
    #expect(!duringDelivery)
    runner.acknowledge(command: UUID(), accepted: true, now: 5)
    #expect(runner.snapshot.acceptedTapCount == 0)
    runner.acknowledge(command: command.id, accepted: true, now: 5)
    let replay = runner.resolve(decision, now: 5.1)
    #expect(replay == nil)
    #expect(runner.snapshot.taps.count == 1)
}

@Test(arguments: [PhoneAction.tap(x: .nan, y: 0.5), .tap(x: 1, y: 0.5), .tap(x: -0.1, y: 0.5),
                  .tap(x: 0.5, y: .infinity), .wait(seconds: 0), .wait(seconds: 6), .wait(seconds: .nan)])
func malformedActionsNeverProduceCommands(action: PhoneAction) {
    var (runner, frame) = ready()
    let result = runner.resolve(reply(frame, action), now: 4.8)
    #expect(result == nil)
    #expect(runner.snapshot.status == .stopped)
    #expect(runner.snapshot.taps.isEmpty)
}

@Test func providerTimeoutAndCancellationRejectLateDecisions() {
    var (runner, frame) = ready()
    runner.tick(at: 9.8)
    #expect(runner.snapshot.stopReason == "decisionTimedOut")
    let late = runner.resolve(reply(frame, .tap(x: 0.2, y: 0.6)), now: 9.9)
    #expect(late == nil)
    (runner, frame) = ready()
    runner.stop("returnedToForeground")
    let cancelled = runner.resolve(reply(frame, .tap(x: 0.2, y: 0.6)), now: 4.9)
    #expect(cancelled == nil)
    #expect(runner.snapshot.taps.isEmpty)
}

@Test(arguments: [false, true])
func deliveryFailureOrTimeoutNeverRetries(timeout: Bool) throws {
    var (runner, frame) = ready()
    let proposed = runner.resolve(reply(frame, .tap(x: 0.2, y: 0.6)), now: 4.8)
    let command = try #require(proposed)
    if timeout { runner.tick(at: 9.9) }
    else { runner.acknowledge(command: command.id, accepted: false, now: 4.9) }
    runner.acknowledge(command: command.id, accepted: true, now: 10)
    let newObservation = runner.offer(screen(runner, 10), inputReady: true, now: 10)
    #expect(!newObservation)
    #expect(runner.snapshot.stopReason == "deliveryUncertainNoRetry")
    #expect(runner.snapshot.acceptedTapCount == 0)
    #expect(runner.snapshot.taps.count == 1)
}

@Test func framesMustBeFreshDistinctReadyPortraitAndAfterAcceptance() throws {
    var (runner, frame) = ready()
    let proposed = runner.resolve(reply(frame, .tap(x: 0.2, y: 0.6)), now: 4.8)
    let command = try #require(proposed)
    runner.acknowledge(command: command.id, accepted: true, now: 5)
    let tooEarly = runner.offer(screen(runner, 5.9), inputReady: true, now: 6)
    let stale = runner.offer(screen(runner, 6), inputReady: true, now: 8.1)
    let rotated = runner.offer(screen(runner, 8.2, portrait: false), inputReady: true, now: 8.2)
    let future = runner.offer(screen(runner, 9), inputReady: true, now: 8.3)
    let notReady = runner.offer(screen(runner, 8.3), inputReady: false, now: 8.3)
    #expect(!tooEarly && !stale && !rotated && !future && !notReady)
    _ = runner.offer(screen(runner, 8.4), inputReady: true, now: 8.4)
    let duplicate = runner.offer(screen(runner, 8.4), inputReady: true, now: 8.5)
    #expect(!duplicate)
    #expect(runner.snapshot.consecutiveFrames == 0)
    _ = runner.offer(screen(runner, 8.6), inputReady: true, now: 8.6)
    let changedSize = runner.offer(screen(runner, 8.7, width: 2000), inputReady: true, now: 8.7)
    #expect(!changedSize)
    #expect(runner.snapshot.stopReason == "screenDimensionsChanged")
}

@Test func decisionLimitsAndTapLimitsBoundProviderWork() throws {
    var config = PhoneActionRunner.Configuration(); config.maximumTaps = 1
    var (runner, frame) = ready(configuration: config)
    let proposed = runner.resolve(reply(frame, .tap(x: 0.2, y: 0.6)), now: 4.8)
    let command = try #require(proposed)
    runner.acknowledge(command: command.id, accepted: true, now: 4.9)
    _ = runner.offer(screen(runner, 6), inputReady: true, now: 6)
    frame = screen(runner, 7.7); _ = runner.offer(frame, inputReady: true, now: 7.7)
    let excess = runner.resolve(reply(frame, .tap(x: 0.2, y: 0.6)), now: 7.8)
    #expect(excess == nil)
    #expect(runner.snapshot.stopReason == "tapLimit")
    config.maximumDecisions = 1
    (runner, frame) = ready(configuration: config)
    _ = runner.resolve(reply(frame, .wait(seconds: 1)), now: 4.8)
    _ = runner.offer(screen(runner, 6), inputReady: true, now: 6)
    let more = runner.offer(screen(runner, 7.7), inputReady: true, now: 7.7)
    #expect(!more)
    #expect(runner.snapshot.stopReason == "decisionLimit")
}

@Test func watchdogBoundsRunsEvenWhenNoFrameOrReplyArrives() {
    var runner = PhoneActionRunner(); runner.start(at: 0); runner.tick(at: 11.1)
    #expect(runner.snapshot.stopReason == "freshFrameTimedOut")
    var config = PhoneActionRunner.Configuration(); config.runTimeout = 4
    runner = PhoneActionRunner(configuration: config); runner.start(at: 0); runner.tick(at: 4.1)
    #expect(runner.snapshot.stopReason == "runTimedOut")
    config.requiredFrames = 0
    runner = PhoneActionRunner(configuration: config); runner.start(at: 0)
    #expect(runner.snapshot.stopReason == "invalidConfiguration")
}

@Test func staleDecisionsAndUnsupportedVersionsAreRejected() {
    var config = PhoneActionRunner.Configuration(); config.maximumDecisionFrameAge = 0.1
    var (runner, frame) = ready(configuration: config)
    let stale = runner.resolve(reply(frame, .tap(x: 0.2, y: 0.6)), now: 5)
    #expect(stale == nil)
    #expect(runner.snapshot.stopReason == "staleDecision")
    (runner, frame) = ready()
    let unsupported = PhoneDecision(version: 2, runID: frame.runID, observationID: frame.id, action: .finish)
    _ = runner.resolve(unsupported, now: 4.8)
    #expect(runner.snapshot.stopReason == "unsupportedDecisionVersion")
}

@Test func agentWireContractRoundTripsScreenshotAndDecision() throws {
    let runner = PhoneActionRunner()
    let observation = PhoneObservation(frame: screen(runner, 3), screenshotPNG: Data([1, 2, 3]), decisionIndex: 0, acceptedTapCount: 0)
    let decoder = JSONDecoder(), encoder = JSONEncoder()
    let decoded = try decoder.decode(PhoneObservation.self, from: encoder.encode(observation))
    #expect(decoded.frame == observation.frame)
    #expect(decoded.screenshotPNG == observation.screenshotPNG)
    let decision = reply(observation.frame, .tap(x: 0.2, y: 0.6))
    let result = try decoder.decode(PhoneDecision.self, from: encoder.encode(decision))
    #expect(result.observationID == observation.frame.id)
    #expect(result.action == decision.action)
    #expect(throws: (any Error).self) {
        try decoder.decode(PhoneDecision.self, from: Data("{\"action\":{\"unknown\":{}}}".utf8))
    }
}
