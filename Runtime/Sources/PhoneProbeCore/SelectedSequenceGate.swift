import Foundation

/// Two explicitly authorized taps. The active app uses transportOnly; the earlier
/// referenceVerified policy remains for regression tests of build 15.
public struct SelectedSequenceGate {
    public enum Mode: String, Encodable, Sendable { case referenceVerified, transportOnly }
    public let mode: Mode
    public enum Stage: String, Encodable, Sendable {
        case idle, waitingForZero, waitingForInitialFrames, sendingFirst, waitingForSeven, waitingForPostTapFrames
        case sendingSecond, waitingForFinalImage, complete, stopped
    }
    public enum Decision: Equatable { case none, tap(Int), captureFinalImage }
    public private(set) var stage: Stage = .idle
    public private(set) var matchingFrames = 0
    public private(set) var attemptedActions = 0
    public private(set) var stopReason: String?
    private var generation: UUID?
    private var acceptedAt: Double?
    private var lastFrameTimestamp: Double?
    public var active: Bool { stage != .idle && stage != .complete && stage != .stopped }
    public init(mode: Mode = .referenceVerified) { self.mode = mode }

    public mutating func arm(generation: UUID) -> Bool {
        guard stage == .idle else { return false }
        self.generation = generation
        stage = mode == .transportOnly ? .waitingForInitialFrames : .waitingForZero
        return true
    }

    public mutating func stop(_ reason: String) {
        guard active else { return }
        stopReason = reason
        stage = .stopped
        matchingFrames = 0
    }

    /// Called only for the matching in-flight command. Failure is terminal.
    @discardableResult
    public mutating func acknowledge(generation: UUID, step: Int, accepted: Bool, backgroundSeconds: Double) -> Bool {
        guard self.generation == generation,
              (step == 1 && stage == .sendingFirst) || (step == 2 && stage == .sendingSecond) else { return false }
        guard accepted, backgroundSeconds.isFinite else { stop("deliveryUncertainNoRetry"); return false }
        acceptedAt = backgroundSeconds
        matchingFrames = 0
        stage = step == 1 ? (mode == .transportOnly ? .waitingForPostTapFrames : .waitingForSeven) : .waitingForFinalImage
        return true
    }

    public mutating func observe(generation: UUID, backgroundSeconds: Double,
                                 frameTimestamp: Double, eligible: Bool, afterAcceptance: Bool,
                                 matchesZero: Bool, matchesSeven: Bool) -> Decision {
        guard self.generation == generation, active else { return .none }
        guard backgroundSeconds.isFinite, backgroundSeconds >= 0, frameTimestamp.isFinite else {
            stop("invalidFrameTiming"); return .none
        }
        let deadline: Double
        switch stage {
        case .waitingForZero: deadline = 85
        case .waitingForInitialFrames: deadline = 12
        case .waitingForSeven: deadline = (acceptedAt ?? 0) + 15
        case .waitingForPostTapFrames: deadline = (acceptedAt ?? 0) + 8
        case .waitingForFinalImage: deadline = (acceptedAt ?? 0) + (mode == .transportOnly ? 5 : 10)
        default: return .none // Never issue another command before an acknowledgement.
        }
        guard backgroundSeconds <= deadline else { stop(mode == .transportOnly ? "freshFrameTimedOut" : "screenVerificationTimedOut"); return .none }
        guard lastFrameTimestamp.map({ frameTimestamp > $0 }) ?? true else {
            matchingFrames = 0; return .none
        }
        lastFrameTimestamp = frameTimestamp
        guard eligible else { matchingFrames = 0; return .none }
        if stage == .waitingForFinalImage {
            guard afterAcceptance else { return .none }
            stage = .complete
            return .captureFinalImage
        }
        let matches: Bool
        if mode == .transportOnly {
            matches = stage == .waitingForInitialFrames ? backgroundSeconds >= 3 : afterAcceptance
        } else if stage == .waitingForZero {
            matches = backgroundSeconds >= 60 && matchesZero && !matchesSeven
        } else {
            matches = afterAcceptance && matchesSeven && !matchesZero
        }
        guard matches else { matchingFrames = 0; return .none }
        matchingFrames += 1
        guard matchingFrames >= 2 else { return .none }
        attemptedActions += 1
        stage = attemptedActions == 1 ? .sendingFirst : .sendingSecond
        return .tap(attemptedActions)
    }
}
