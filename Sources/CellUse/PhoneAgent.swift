import Foundation

/// Coordinates are fractions of the full portrait screenshot, in [0, 1).
public enum PhoneAction: Codable, Sendable, Equatable {
    case tap(x: Double, y: Double)
    case swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double)
    /// Printable US-ASCII only, 1...32 characters. No implicit Return.
    case typeText(String)
    case wait(seconds: Double)
    case finish
}

extension PhoneAction {
    public var isInput: Bool {
        switch self { case .tap, .swipe, .typeText: true; case .wait, .finish: false }
    }
    public var kind: String {
        switch self { case .tap: "tap"; case .swipe: "swipe"; case .typeText: "typeText"; case .wait: "wait"; case .finish: "finish" }
    }
    public var inputValidationError: String? {
        func point(_ x: Double, _ y: Double) -> Bool { x.isFinite && y.isFinite && (0..<1).contains(x) && (0..<1).contains(y) }
        switch self {
        case let .tap(x, y): return point(x, y) ? nil : "invalidTap"
        case let .swipe(x, y, endX, endY, duration):
            return point(x, y) && point(endX, endY) && (x != endX || y != endY) && duration.isFinite && (0.2...1).contains(duration) ? nil : "invalidSwipe"
        case let .typeText(text):
            return (1...32).contains(text.utf8.count) && text.utf8.allSatisfy { (32...126).contains($0) } ? nil : "unsupportedText"
        case .wait, .finish: return "notInput"
        }
    }
}

public struct PhoneFrame: Codable, Sendable, Equatable {
    public let id: UUID
    public let runID: UUID
    public let width: Int
    public let height: Int
    /// Monotonic seconds in the host clock, not wall-clock time.
    public let capturedAt: Double
    public let portrait: Bool
    public init(id: UUID = UUID(), runID: UUID, width: Int, height: Int,
                capturedAt: Double, portrait: Bool = true) {
        self.id = id; self.runID = runID; self.width = width; self.height = height
        self.capturedAt = capturedAt; self.portrait = portrait
    }
}

/// Image data belongs to the provider; it is never embedded in runner diagnostics.
public struct PhoneObservation: Codable, Sendable {
    public let frame: PhoneFrame
    public let screenshotPNG: Data
    public let decisionIndex: Int
    public let acceptedTapCount: Int
    public let acceptedInputCount: Int
    public init(frame: PhoneFrame, screenshotPNG: Data, decisionIndex: Int, acceptedTapCount: Int, acceptedInputCount: Int? = nil) {
        self.frame = frame; self.screenshotPNG = screenshotPNG
        self.decisionIndex = decisionIndex; self.acceptedTapCount = acceptedTapCount
        self.acceptedInputCount = acceptedInputCount ?? acceptedTapCount
    }
}

/// One response authorizes at most one action for this exact observation.
public struct PhoneDecision: Codable, Sendable {
    public let version: Int
    public let runID: UUID
    public let observationID: UUID
    public let action: PhoneAction
    public init(version: Int = 1, runID: UUID, observationID: UUID, action: PhoneAction) {
        self.version = version; self.runID = runID; self.observationID = observationID; self.action = action
    }
    public init(observation: PhoneObservation, action: PhoneAction) {
        self.init(runID: observation.frame.runID, observationID: observation.frame.id, action: action)
    }
}

public protocol PhoneAgent: Sendable {
    func nextAction(for observation: PhoneObservation) async throws -> PhoneDecision
}

/// A deterministic integration client, not a model or visual recognizer.
public struct ScriptedPhoneAgent: PhoneAgent {
    public let actions: [PhoneAction]
    public init(actions: [PhoneAction]) { self.actions = actions }
    public func nextAction(for observation: PhoneObservation) async throws -> PhoneDecision {
        try Task.checkCancellation()
        let index = observation.decisionIndex
        let action: PhoneAction = actions.indices.contains(index) ? actions[index] : .finish
        return PhoneDecision(observation: observation, action: action)
    }
}
