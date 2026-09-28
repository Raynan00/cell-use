import DeviceHubClient
import DeviceHubMedia
import Foundation
import Observation
import CellUse
import CellUseRuntime

@MainActor @Observable
final class OnDeviceAgentRun {
    struct Report: Encodable {
        let provider: String
        let apiVersion = 1
        let capabilities = ["tap", "swipe", "typeText", "wait", "finish"]
        var userConfirmedControlResult = false
        let executionMode: String
        let minimumBackgroundSeconds: Double
        let runTimeoutSeconds: Double
        var runner: PhoneActionRunner.Snapshot
        var intermediateImageReceived = false
        var finalImageReceived = false
        var userConfirmedZeroSevenSeventySeven = false
    }
    private(set) var report: Report
    private(set) var intermediateImage: RemoteDisplayFrame?
    private(set) var finalImage: RemoteDisplayFrame?
    @ObservationIgnored private let runtime: CellUseRuntime
    let demo: String
    var runID: UUID { runtime.runID }
    var active: Bool { runtime.active }

    init(runID: UUID, session: DeviceSession, agent: any PhoneAgent, providerName: String,
         extended: Bool = false, demo: String = "calculator", onEnded: @escaping () -> Void) {
        var configuration = PhoneActionRunner.Configuration()
        if extended { configuration.initialDelay = 60; configuration.runTimeout = 95 }
        self.demo = demo
        runtime = CellUseRuntime(runID: runID, session: session, agent: agent, configuration: configuration)
        report = Report(provider: providerName, executionMode: extended ? "continuedProcessing" : "ordinaryBackground",
                        minimumBackgroundSeconds: configuration.initialDelay, runTimeoutSeconds: configuration.runTimeout,
                        runner: runtime.snapshot)
        runtime.onUpdate = { [weak self] snapshot in self?.report.runner = snapshot }
        runtime.onObservation = { [weak self] frame, snapshot in
            guard let self else { return }
            if snapshot.acceptedInputCount == 1 && self.intermediateImage == nil {
                self.intermediateImage = frame; self.report.intermediateImageReceived = true
            }
            if (self.demo != "calculator" && snapshot.acceptedInputCount >= 1) || snapshot.acceptedTapCount == 2 {
                self.finalImage = frame; self.report.finalImageReceived = true
            }
        }
        runtime.onEnded = onEnded
    }
    func beginBackground(at time: Double) { runtime.start(at: time) }
    func receive(_ frame: RemoteDisplayFrame, inputReady: Bool) { runtime.receive(frame, inputReady: inputReady) }
    func cancel(_ reason: String, notify: Bool = true) { runtime.cancel(reason, notify: notify) }
    func updateInputReadiness(_ ready: Bool) { runtime.updateInputReadiness(ready) }
    func confirmDemoResult() {
        guard report.runner.status == .completed, report.runner.acceptedTapCount == 2,
              intermediateImage != nil, finalImage != nil else { return }
        report.userConfirmedZeroSevenSeventySeven = true
    }
    func confirmControlResult() {
        guard demo != "calculator", report.runner.status == .completed, finalImage != nil else { return }
        report.userConfirmedControlResult = true
    }
}
