import Foundation

/// Evidence is deliberately independent of the transport and contains no device
/// identifiers, pairing data, images, coordinates, or observed screen text.
public struct ProbeEvidence: Codable, Equatable, Sendable {
    public private(set) var generation = UUID()
    public private(set) var connected = false
    public private(set) var observedImage = false
    public private(set) var selfScreenVerified = false
    public private(set) var commandSubmitted = false
    public private(set) var targetActivated = false
    public private(set) var framesReceivedInBackground = 0
    public private(set) var backgroundLeaseExpired = false
    public private(set) var cancelled = false
    public private(set) var ended = false
    public private(set) var lastStage = Stage.idle

    public enum Stage: String, Codable, Sendable {
        case idle, pairing, locating, verifyingPairing, openingTunnel
        case discoveringServices, preparingDeveloperServices, capturingScreenshot
        case startingDisplay, ready, verifyingSelfScreen, sendingInput
        case verifiedInput, background, backgroundExpired, failed, stopped
    }

    public init() {}

    public mutating func stage(_ stage: Stage, generation: UUID) {
        guard generation == self.generation, !ended else { return }
        lastStage = stage
    }

    public mutating func connect(generation: UUID) {
        guard generation == self.generation, !ended else { return }
        connected = true
    }

    public mutating func image(generation: UUID, whileBackgrounded: Bool) {
        guard generation == self.generation, !ended else { return }
        observedImage = true
        if whileBackgrounded { framesReceivedInBackground += 1 }
    }

    public mutating func verifySelfScreen(generation: UUID) {
        guard generation == self.generation, observedImage, !ended else { return }
        selfScreenVerified = true
    }

    public mutating func submitInput(generation: UUID) -> Bool {
        guard generation == self.generation, connected, selfScreenVerified, !ended else { return false }
        commandSubmitted = true
        targetActivated = false
        lastStage = .sendingInput
        return true
    }

    public mutating func receiveTargetActivation(generation: UUID) {
        guard generation == self.generation, commandSubmitted, !ended else { return }
        targetActivated = true
        lastStage = .verifiedInput
    }

    public mutating func expireBackgroundLease(generation: UUID) {
        guard generation == self.generation, !ended else { return }
        backgroundLeaseExpired = true
        lastStage = .backgroundExpired
    }

    public mutating func finish(generation: UUID, cancelled: Bool) {
        guard generation == self.generation, !ended else { return }
        self.cancelled = cancelled
        ended = true
        if cancelled { lastStage = .stopped }
    }
}

public enum ProbeChecks {
    /// OCR may introduce spaces; require the complete per-run random marker.
    public static func containsChallenge(_ observations: [String], challenge: String) -> Bool {
        let expected = normalize(challenge)
        guard expected.count >= 12 else { return false }
        return observations.contains { normalize($0).contains(expected) }
    }

    public static func isFresh(receivedAt: Date, now: Date, maximumAge: TimeInterval = 2) -> Bool {
        let age = now.timeIntervalSince(receivedAt)
        return age >= 0 && age <= maximumAge
    }

    private static func normalize(_ value: String) -> String {
        value.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
