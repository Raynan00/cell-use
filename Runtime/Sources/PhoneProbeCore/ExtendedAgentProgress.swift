/// Finite capture-and-agent experiment. Real images advance capture progress;
/// only the runner can satisfy the independent action-completion milestone.
public struct ExtendedAgentProgress {
    public let targetImages = 60
    public let targetDecisions = 4
    public private(set) var completedImages: Int
    public private(set) var resolvedDecisions = 0
    public private(set) var runnerCompleted = false

    public init(completedImages: Int = 0) {
        self.completedImages = max(0, completedImages)
    }
    public mutating func receivedImage() { completedImages += 1 }
    public mutating func updateRunner(resolvedDecisions: Int, completed: Bool) {
        self.resolvedDecisions = max(self.resolvedDecisions, min(targetDecisions, max(0, resolvedDecisions)))
        // Completion must accompany all four decisions, not just a partial run.
        runnerCompleted = runnerCompleted || (completed && resolvedDecisions >= targetDecisions)
    }
    public var totalUnits: Int { targetImages + targetDecisions + 1 }
    public var completedUnits: Int {
        min(completedImages, targetImages) + resolvedDecisions + (runnerCompleted ? 1 : 0)
    }
    public var complete: Bool { completedImages >= targetImages && runnerCompleted }
}
