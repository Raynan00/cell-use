@preconcurrency import BackgroundTasks
import Foundation

@MainActor
final class TransferWork {
    private var work: BGContinuedProcessingTask?
    private var identifier: String?
    private var timeout: Task<Void, Never>?
    private var start: (() -> Void)?
    private var expire: ((String) -> Void)?
    private var frames = 0
    private var decisions = 0
    var active: Bool { identifier != nil }

    func submit(start: @escaping () -> Void, expire: @escaping (String) -> Void) {
        guard !active, let bundle = Bundle.main.bundleIdentifier else { return }
        let allowed = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard allowed.contains(bundle + ".move.*") else {
            expire("The signing bundle and background task identifier do not match.")
            return
        }
        let id = bundle + ".move." + UUID().uuidString
        identifier = id; self.start = start; self.expire = expire
        frames = 0; decisions = 0
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] received in
            MainActor.assumeIsolated {
                guard let self, let task = received as? BGContinuedProcessingTask, self.identifier == received.identifier else {
                    received.setTaskCompleted(success: false); return
                }
                self.timeout?.cancel()
                self.work = task
                task.progress.totalUnitCount = 361
                task.progress.completedUnitCount = 0
                task.expirationHandler = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.work === task else { return }
                        let callback = self.expire
                        self.finish(success: false)
                        callback?("iOS ended the background run. Open Playlist Move to inspect its last action.")
                    }
                }
                let callback = self.start; self.start = nil
                callback?()
            }
        }
        guard registered else {
            finish(success: false); expire("Could not register the transfer task."); return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Playlist Move", subtitle: "Copying your music")
        request.strategy = .fail
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.identifier == id, self.work == nil else { return }
            self.finish(success: false); expire("iOS did not start the transfer task.")
        }
        Task { [weak self] in
            do { try await BGTaskScheduler.shared.submitTaskRequest(request) }
            catch {
                guard let self, self.identifier == id else { return }
                self.finish(success: false); expire(error.localizedDescription)
            }
        }
    }

    func sawFrame() { frames = min(240, frames + 1); progress() }
    func resolvedDecisions(_ count: Int) { decisions = min(120, count); progress() }
    private func progress() {
        guard let work else { return }
        work.progress.completedUnitCount = Int64(frames + decisions)
    }
    func finish(success: Bool) {
        timeout?.cancel(); timeout = nil
        if success, let work { work.progress.completedUnitCount = work.progress.totalUnitCount }
        work?.setTaskCompleted(success: success)
        if let identifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            BGTaskScheduler.shared.unregisterTask(withIdentifier: identifier)
        }
        work = nil; identifier = nil; start = nil; expire = nil
    }
}
