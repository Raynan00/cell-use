/// The image quota plus an optional, explicitly armed input-and-after-image step.
public struct ExtendedCaptureProgress {
    public let targetImages = 60
    public private(set) var completedImages = 0
    public private(set) var requiresSelectedInput = false
    public private(set) var selectedInputFinished = false
    public init() {}
    public mutating func requireSelectedInput() { requiresSelectedInput = true }
    public mutating func receivedImage(selectedInputFinished: Bool) {
        completedImages += 1
        self.selectedInputFinished = self.selectedInputFinished || selectedInputFinished
    }
    public var totalUnits: Int { targetImages + (requiresSelectedInput ? 1 : 0) }
    public var completedUnits: Int {
        min(completedImages, targetImages) + (requiresSelectedInput && selectedInputFinished ? 1 : 0)
    }
    public var complete: Bool { completedUnits >= totalUnits }
}
