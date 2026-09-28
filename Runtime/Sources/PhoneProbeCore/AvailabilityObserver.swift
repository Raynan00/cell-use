/// Owns discovery independently of a presenting view's task. Only one stream
/// can run at a time; explicit stop awaits cancellation before a retry starts.
@MainActor
public final class AvailabilityObserver<Value: Sendable> {
    public enum EndReason: String, Codable, Sendable {
        case sourceFinished, cancelled
    }

    private var task: Task<Void, Never>?
    public var isRunning: Bool { task != nil }

    public init() {}
    deinit { task?.cancel() }

    @discardableResult
    public func start(
        source: @escaping @MainActor () -> AsyncStream<Value>,
        onValue: @escaping @MainActor (Value) -> Void,
        onEnd: @escaping @MainActor (EndReason) -> Void
    ) -> Bool {
        guard task == nil else { return false }
        task = Task { [weak self] in
            for await value in source() {
                guard !Task.isCancelled else { break }
                onValue(value)
            }
            let reason: EndReason = Task.isCancelled ? .cancelled : .sourceFinished
            self?.task = nil
            onEnd(reason)
        }
        return true
    }

    public func stop() async {
        guard let task else { return }
        task.cancel()
        await task.value
    }
}
