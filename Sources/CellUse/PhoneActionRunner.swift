import Foundation

/// A deterministic coordinator. The platform adapter supplies frames, invokes
/// the provider asynchronously, delivers commands and ticks the watchdog clock.
public struct PhoneActionRunner {
    public struct Configuration: Sendable {
        public var maximumTaps = 8
        public var maximumInputs = 16
        public var maximumDecisions = 16
        public var runTimeout: Double = 22
        public var decisionTimeout: Double = 5
        public var deliveryTimeout: Double = 5
        public var frameTimeout: Double = 8
        public var maximumFrameAge: Double = 2
        public var maximumDecisionFrameAge: Double = 5
        public var initialDelay: Double = 3
        public var afterTapDelay: Double = 1
        public var requiredFrames = 2
        public init() {}
        var valid: Bool {
            maximumInputs > 0 && maximumInputs <= 100 && maximumTaps > 0 && maximumTaps <= 100 && maximumDecisions > 0 && maximumDecisions <= 200 &&
            requiredFrames > 0 && requiredFrames <= 10 &&
            [runTimeout, decisionTimeout, deliveryTimeout, frameTimeout, maximumFrameAge,
             maximumDecisionFrameAge, initialDelay, afterTapDelay].allSatisfy { $0.isFinite && $0 > 0 }
        }
    }
    public enum Status: String, Codable, Sendable {
        case idle, observing, deciding, delivering, waiting, completed, stopped
    }
    public struct DecisionRecord: Codable, Sendable {
        public let observationID: UUID
        public let index: Int
        public let requestedSeconds: Double
        public var actionKind: String?
        public var resolvedSeconds: Double?
        public var screenshotBytes: Int?
    }
    public struct InputRecord: Codable, Sendable {
        public let kind: String
        public let commandID: UUID
        public let observationID: UUID
        public let index: Int
        public let submittedSeconds: Double
        public var acceptedSeconds: Double?
    }
    public struct Snapshot: Codable, Sendable {
        public let runID: UUID
        public var status: Status = .idle
        public var stopReason: String?
        public var observations: [DecisionRecord] = []
        public var inputs: [InputRecord] = []
        public var taps: [InputRecord] { inputs.filter { $0.kind == "tap" } }
        public var acceptedInputCount: Int { inputs.filter { $0.acceptedSeconds != nil }.count }
        public var waitCount = 0
        public var consecutiveFrames = 0
        public var acceptedTapCount: Int { taps.filter { $0.acceptedSeconds != nil }.count }
    }
    public struct InputCommand: Sendable {
        public let id: UUID
        public let observationID: UUID
        public let action: PhoneAction
        public let imageWidth: Int
        public let imageHeight: Int
    }
    public private(set) var snapshot: Snapshot
    public let configuration: Configuration
    public var active: Bool { ![Status.idle, .completed, .stopped].contains(snapshot.status) }
    private var startedAt: Double = 0
    private var earliestFrame: Double = 0
    private var deadline: Double = 0
    private var lastFrameTime: Double?
    private var dimensions: (Int, Int)?
    private var pending: PhoneFrame?
    private var commandID: UUID?

    public init(runID: UUID = UUID(), configuration: Configuration = Configuration()) {
        self.snapshot = Snapshot(runID: runID); self.configuration = configuration
    }

    public mutating func start(at now: Double) {
        guard snapshot.status == .idle else { return }
        guard now.isFinite, configuration.valid else {
            snapshot.status = .stopped; snapshot.stopReason = "invalidConfiguration"; return
        }
        startedAt = now
        awaitFrames(at: now + configuration.initialDelay, waiting: false)
    }

    public mutating func stop(_ reason: String) {
        guard snapshot.status != .completed && snapshot.status != .stopped else { return }
        snapshot.status = .stopped; snapshot.stopReason = reason
        pending = nil; commandID = nil; snapshot.consecutiveFrames = 0
    }

    /// Must also be called by a timer when frames or an agent reply stop arriving.
    public mutating func tick(at now: Double) {
        guard active else { return }
        guard now.isFinite, now >= startedAt else { stop("invalidClock"); return }
        if now - startedAt > configuration.runTimeout { stop("runTimedOut"); return }
        if now > deadline {
            let reason = snapshot.status == .deciding ? "decisionTimedOut" :
                snapshot.status == .delivering ? "deliveryUncertainNoRetry" : "freshFrameTimedOut"
            stop(reason)
        }
    }

    /// True means this exact frame should be encoded and offered to the provider.
    public mutating func offer(_ frame: PhoneFrame, inputReady: Bool, now: Double) -> Bool {
        tick(at: now)
        guard active, frame.runID == snapshot.runID,
              snapshot.status == .observing || snapshot.status == .waiting else { return false }
        guard frame.capturedAt.isFinite, frame.capturedAt <= now,
              now - frame.capturedAt <= configuration.maximumFrameAge,
              frame.capturedAt >= earliestFrame, inputReady, frame.portrait,
              frame.width > 0, frame.height > 0 else { snapshot.consecutiveFrames = 0; return false }
        if let lastFrameTime, frame.capturedAt <= lastFrameTime { snapshot.consecutiveFrames = 0; return false }
        lastFrameTime = frame.capturedAt
        if let dimensions, dimensions.0 != frame.width || dimensions.1 != frame.height {
            stop("screenDimensionsChanged"); return false
        }
        dimensions = (frame.width, frame.height)
        snapshot.status = .observing
        snapshot.consecutiveFrames += 1
        guard snapshot.consecutiveFrames >= configuration.requiredFrames else { return false }
        guard snapshot.observations.count < configuration.maximumDecisions else { stop("decisionLimit"); return false }
        pending = frame
        snapshot.status = .deciding
        deadline = now + configuration.decisionTimeout
        snapshot.observations.append(DecisionRecord(observationID: frame.id, index: snapshot.observations.count,
                                                   requestedSeconds: now - startedAt))
        return true
    }

    public mutating func noteScreenshotBytes(_ bytes: Int, observationID: UUID) {
        guard pending?.id == observationID, snapshot.status == .deciding else { return }
        snapshot.observations[snapshot.observations.count - 1].screenshotBytes = bytes
    }

    /// Returns a command only after consuming the observation's single decision.
    public mutating func resolve(_ decision: PhoneDecision, now: Double) -> InputCommand? {
        tick(at: now)
        guard snapshot.status == .deciding, decision.runID == snapshot.runID,
              let frame = pending, decision.observationID == frame.id else { return nil }
        guard decision.version == 1 else { stop("unsupportedDecisionVersion"); return nil }
        guard now - frame.capturedAt <= configuration.maximumDecisionFrameAge else { stop("staleDecision"); return nil }
        pending = nil
        let index = snapshot.observations.count - 1
        snapshot.observations[index].resolvedSeconds = now - startedAt
        switch decision.action {
        case .tap, .swipe, .typeText, .pressKey:
            if let error = decision.action.inputValidationError { stop(error); return nil }
            guard snapshot.inputs.count < configuration.maximumInputs else { stop("inputLimit"); return nil }
            if case .tap = decision.action, snapshot.taps.count >= configuration.maximumTaps { stop("tapLimit"); return nil }
            snapshot.observations[index].actionKind = decision.action.kind
            let id = UUID(); commandID = id
            snapshot.inputs.append(InputRecord(kind: decision.action.kind, commandID: id, observationID: frame.id,
                index: snapshot.inputs.count, submittedSeconds: now - startedAt))
            snapshot.status = .delivering; deadline = now + configuration.deliveryTimeout
            return InputCommand(id: id, observationID: frame.id, action: decision.action,
                                imageWidth: frame.width, imageHeight: frame.height)
        case .wait(let seconds):
            guard seconds.isFinite, (0.1...5).contains(seconds) else { stop("invalidWait"); return nil }
            snapshot.observations[index].actionKind = "wait"
            snapshot.waitCount += 1
            awaitFrames(at: now + seconds, waiting: true)
        case .finish:
            snapshot.observations[index].actionKind = "finish"
            snapshot.status = .completed; snapshot.consecutiveFrames = 0
        }
        return nil
    }

    public mutating func acknowledge(command id: UUID, accepted: Bool, now: Double) {
        tick(at: now)
        guard snapshot.status == .delivering, id == commandID else { return }
        commandID = nil
        guard accepted else { stop("deliveryUncertainNoRetry"); return }
        snapshot.inputs[snapshot.inputs.count - 1].acceptedSeconds = now - startedAt
        awaitFrames(at: now + configuration.afterTapDelay, waiting: false)
    }

    private mutating func awaitFrames(at time: Double, waiting: Bool) {
        earliestFrame = time; deadline = time + configuration.frameTimeout
        snapshot.consecutiveFrames = 0
        snapshot.status = waiting ? .waiting : .observing
    }
}
