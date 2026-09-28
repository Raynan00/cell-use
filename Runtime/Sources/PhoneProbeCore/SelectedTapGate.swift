import Foundation

public struct SelectedTapGate {
    public enum Timing: String, Encodable, Sendable {
        case immediate, after60Seconds
        public var earliest: Double { self == .immediate ? 3 : 60 }
        public var deadline: Double { self == .immediate ? 20 : 85 }
    }
    public private(set) var timing: Timing = .immediate
    public private(set) var matchingFrames = 0
    public private(set) var attempted = false
    public private(set) var armed = false
    private var generation: UUID?
    public init() {}
    public mutating func arm(generation: UUID, timing: Timing = .immediate) -> Bool {
        guard !attempted else { return false }
        self.timing = timing
        self.generation = generation; armed = true; matchingFrames = 0
        return true
    }
    public mutating func disarm() { armed = false; matchingFrames = 0 }
    public mutating func observe(generation: UUID, eligible: Bool, matches: Bool, backgroundSeconds: Double = 3) -> Bool {
        guard armed, !attempted, self.generation == generation else { return false }
        guard backgroundSeconds.isFinite, backgroundSeconds <= timing.deadline else { disarm(); return false }
        guard backgroundSeconds >= timing.earliest else { matchingFrames = 0; return false }
        guard eligible, matches else { matchingFrames = 0; return false }
        matchingFrames += 1
        guard matchingFrames >= 2 else { return false }
        attempted = true; armed = false
        return true
    }
}
