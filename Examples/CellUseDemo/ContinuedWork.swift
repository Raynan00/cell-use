@preconcurrency import BackgroundTasks
import Foundation
import Observation
import PhoneProbeCore

/// A finite, user-started capture job. Submission is not evidence of execution.
@MainActor @Observable
final class ContinuedWork {
    static let shared = ContinuedWork()
    struct Snapshot: Encodable {
        var registered = false
        var registrationAttempts = 0
        let registrationMode = "concretePerRun"
        var bundleMatchesConfiguration = false
        var status = "idle"
        var errorCode: Int?
        var completedImages = 0
        let targetImages = 60
        var inputPlan: String?
        var requiresSelectedInput = false
        var selectedInputFinished = false
        var completionPolicy = "imageQuota"
        var resolvedAgentDecisions = 0
        var agentRunnerCompleted = false
        var progressCompletedUnits = 0
        var progressTotalUnits = 60
        var progressAdvances = 0
        var expirationElapsedSeconds: Double?
        var expirationSecondsSinceProgress: Double?
    }
    private(set) var snapshot = Snapshot()
    @ObservationIgnored private var task: BGContinuedProcessingTask?
    @ObservationIgnored private var identifier: String?
    @ObservationIgnored private var start: (() -> Void)?
    @ObservationIgnored private var expire: (() -> Void)?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var progress = ExtendedCaptureProgress()
    @ObservationIgnored private var agentProgress: ExtendedAgentProgress?
    @ObservationIgnored private var workStartedAt: Double?
    @ObservationIgnored private var lastProgressAt: Double?
    var running: Bool { task != nil }
    var pending: Bool { identifier != nil && task == nil }
    var agentWorkComplete: Bool { agentProgress?.complete == true }

    func prepareConfiguration() {
        guard let bundle = Bundle.main.bundleIdentifier else { return }
        let pattern = bundle + ".probe.*"
        let allowed = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        snapshot.bundleMatchesConfiguration = allowed.contains(pattern)
        guard snapshot.bundleMatchesConfiguration else {
            snapshot.status = "signingConfigurationMismatch"
            return
        }
        snapshot.status = "readyToRegister"
    }

    private func register(identifier: String) -> Bool {
        snapshot.registrationAttempts += 1
        // The wildcard belongs in Info.plist. Register the concrete unique ID
        // that this request will submit, as demonstrated in Apple's WWDC sample.
        return BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] received in
            MainActor.assumeIsolated {
                guard let self, let work = received as? BGContinuedProcessingTask,
                      received.identifier == self.identifier else {
                    received.setTaskCompleted(success: false)
                    return
                }
                self.timeout?.cancel()
                self.task = work
                self.snapshot.status = "running"
                self.workStartedAt = ProcessInfo.processInfo.systemUptime
                self.lastProgressAt = self.workStartedAt
                work.progress.totalUnitCount = 60
                work.progress.completedUnitCount = 0
                work.expirationHandler = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.task === work else { return }
                        self.snapshot.status = "expiredOrCancelledBySystem"
                        let now = ProcessInfo.processInfo.systemUptime
                        self.snapshot.expirationElapsedSeconds = self.workStartedAt.map { now - $0 }
                        self.snapshot.expirationSecondsSinceProgress = self.lastProgressAt.map { now - $0 }
                        let callback = self.expire
                        self.finish(success: false, preserveStatus: true)
                        callback?()
                    }
                }
                let callback = self.start
                self.start = nil
                callback?()
            }
        }
    }

    func submit(start: @escaping () -> Void, expire: @escaping () -> Void) {
        guard snapshot.bundleMatchesConfiguration, !running, !pending, let bundle = Bundle.main.bundleIdentifier else { return }
        snapshot.status = "submitted"
        snapshot.errorCode = nil
        snapshot.completedImages = 0
        snapshot.inputPlan = nil
        snapshot.requiresSelectedInput = false
        snapshot.selectedInputFinished = false
        snapshot.completionPolicy = "imageQuota"
        snapshot.resolvedAgentDecisions = 0
        snapshot.agentRunnerCompleted = false
        snapshot.progressCompletedUnits = 0
        snapshot.progressTotalUnits = 60
        snapshot.progressAdvances = 0
        snapshot.expirationElapsedSeconds = nil
        snapshot.expirationSecondsSinceProgress = nil
        agentProgress = nil
        workStartedAt = nil
        lastProgressAt = nil
        progress = ExtendedCaptureProgress()
        let id = bundle + ".probe." + UUID().uuidString
        identifier = id
        self.start = start
        self.expire = expire
        snapshot.registered = register(identifier: id)
        guard snapshot.registered else {
            snapshot.status = "registrationRejected"
            finish(success: false, preserveStatus: true)
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: id,
            title: "cell-use", subtitle: "Checking 60 screen images")
        request.strategy = .fail
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.identifier == id, self.task == nil else { return }
            self.snapshot.status = "launchTimedOut"
            self.finish(success: false, preserveStatus: true)
        }
        Task { [weak self] in
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
                guard let self, self.identifier == id else {
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
                    return
                }
            } catch {
                guard let self, self.identifier == id else { return }
                self.snapshot.errorCode = (error as NSError).code
                self.snapshot.status = "submissionRejected"
                self.finish(success: false, preserveStatus: true)
            }
        }
    }

    func requireSelectedInput(plan: String = "singleDelayedTap") -> Bool {
        guard let task, snapshot.completionPolicy == "imageQuota" else { return false }
        progress.requireSelectedInput()
        snapshot.inputPlan = plan
        snapshot.requiresSelectedInput = true
        task.progress.totalUnitCount = Int64(progress.totalUnits)
        task.updateTitle("cell-use", subtitle: plan == "twoTapSequence" ? "60 images plus a two-tap sequence" : "60 images plus a delayed tap and after-image")
        return true
    }

    /// Capture and action milestones must both finish. Count actual images
    /// during the delayed observation phase; do not report an idle 0/5 task.
    func requireAgentRun() -> Bool {
        guard let task, snapshot.completionPolicy == "imageQuota" else { return false }
        snapshot.completionPolicy = "imageQuotaAndAgentRunner"
        snapshot.inputPlan = "agentTapWaitTapFinishAfter60Seconds"
        agentProgress = ExtendedAgentProgress(completedImages: snapshot.completedImages)
        publishAgentProgress(task)
        return true
    }

    func updateAgentProgress(resolvedDecisions: Int, completed: Bool) {
        guard let task, agentProgress != nil else { return }
        agentProgress?.updateRunner(resolvedDecisions: resolvedDecisions, completed: completed)
        publishAgentProgress(task)
    }

    private func publishAgentProgress(_ task: BGContinuedProcessingTask) {
        guard let agentProgress else { return }
        snapshot.completedImages = agentProgress.completedImages
        snapshot.resolvedAgentDecisions = agentProgress.resolvedDecisions
        snapshot.agentRunnerCompleted = agentProgress.runnerCompleted
        publishProgress(task, completed: agentProgress.completedUnits, total: agentProgress.totalUnits)
        task.updateTitle("cell-use", subtitle: "Images \(min(agentProgress.completedImages, agentProgress.targetImages))/60; decisions \(agentProgress.resolvedDecisions)/4")
    }

    private func publishProgress(_ task: BGContinuedProcessingTask, completed: Int, total: Int) {
        if completed > snapshot.progressCompletedUnits {
            snapshot.progressAdvances += 1
            lastProgressAt = ProcessInfo.processInfo.systemUptime
        }
        snapshot.progressCompletedUnits = completed
        snapshot.progressTotalUnits = total
        task.progress.totalUnitCount = Int64(total)
        task.progress.completedUnitCount = Int64(completed)
    }

    func receivedImage(selectedInputFinished: Bool = false) -> Bool {
        guard let task else { return false }
        if agentProgress != nil {
            agentProgress?.receivedImage()
            publishAgentProgress(task)
            return agentWorkComplete
        }
        progress.receivedImage(selectedInputFinished: selectedInputFinished)
        snapshot.completedImages = progress.completedImages
        snapshot.selectedInputFinished = progress.selectedInputFinished
        publishProgress(task, completed: progress.completedUnits, total: progress.totalUnits)
        let detail = progress.requiresSelectedInput ? "\(snapshot.completedImages) images; input plan \(progress.selectedInputFinished ? "captured" : "pending")" : "Checked \(snapshot.completedImages) of 60 images"
        task.updateTitle("cell-use", subtitle: detail)
        return progress.complete
    }

    func finish(success: Bool, preserveStatus: Bool = false) {
        timeout?.cancel()
        timeout = nil
        start = nil
        expire = nil
        if let task {
            self.task = nil
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
        } else if let identifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        if identifier != nil, !preserveStatus { snapshot.status = success ? "completed" : "stopped" }
        identifier = nil
    }
}
