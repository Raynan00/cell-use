import Testing
@testable import PhoneProbeCore

@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    try #require(condition())
}

@Test @MainActor
func discoverySurvivesCancellationOfStartingViewTask() async throws {
    let observer = AvailabilityObserver<Int>()
    let pipe = AsyncStream<Int>.makeStream()
    var values: [Int] = []
    var end: AvailabilityObserver<Int>.EndReason?
    let viewTask = Task {
        observer.start(source: { pipe.stream }, onValue: { values.append($0) }, onEnd: { end = $0 })
        try? await Task.sleep(for: .seconds(60))
    }
    try await eventually { observer.isRunning }
    viewTask.cancel()
    await viewTask.value
    pipe.continuation.yield(42)
    try await eventually { values == [42] }
    #expect(end == nil)
    await observer.stop()
    #expect(end == .cancelled)
    #expect(!observer.isRunning)
}

@Test @MainActor
func duplicateStartsDoNotReplaceDiscoveryAndFinishedSourceCanRetry() async throws {
    let observer = AvailabilityObserver<Int>()
    let first = AsyncStream<Int>.makeStream()
    let second = AsyncStream<Int>.makeStream()
    var starts = 0
    var values: [Int] = []
    var reasons: [AvailabilityObserver<Int>.EndReason] = []
    let started = observer.start(source: { starts += 1; return first.stream },
        onValue: { values.append($0) }, onEnd: { reasons.append($0) })
    let duplicate = observer.start(source: { starts += 1; return second.stream },
        onValue: { values.append($0) }, onEnd: { reasons.append($0) })
    #expect(started && !duplicate)
    first.continuation.yield(1)
    first.continuation.finish()
    try await eventually { !observer.isRunning }
    #expect(starts == 1 && values == [1] && reasons == [.sourceFinished])
    observer.start(source: { starts += 1; return second.stream },
        onValue: { values.append($0) }, onEnd: { reasons.append($0) })
    second.continuation.yield(2)
    try await eventually { values == [1, 2] }
    await observer.stop()
    #expect(starts == 2 && reasons == [.sourceFinished, .cancelled])
}
