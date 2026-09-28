import CoreGraphics
import DeviceHubClient
import DeviceHubCore
import Foundation
import CellUse
import CellUseRuntime
import Testing

private actor Commands {
    var values: [DeviceCommand] = []
    func record(_ value: DeviceCommand) { values.append(value) }
}

private func session(_ commands: Commands) -> DeviceSession {
    DeviceSession(id: DeviceSessionID(rawValue: UUID()), device: DeviceSummary(
        id: DeviceID(rawValue: "fixture"), name: "Fixture", productType: "Fixture",
        operatingSystemVersion: nil, pairingState: .paired, reachability: .reachable),
        events: AsyncThrowingStream { $0.finish() }, frames: AsyncStream { $0.finish() },
        command: { await commands.record($0) }, disconnect: {})
}

private func frame(_ generation: UUID) throws -> RemoteDisplayFrame {
    let context = try #require(CGContext(data: nil, width: 100, height: 200,
        bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    return RemoteDisplayFrame(metadata: .screenshot(ScreenshotMetadata(
        generation: SessionGeneration(rawValue: generation), receivedAt: Date(),
        pixelSize: PixelSize(width: 100, height: 200), orientation: .portrait)), image: image)
}

private func configuration() -> PhoneActionRunner.Configuration {
    var config = PhoneActionRunner.Configuration()
    config.initialDelay = 0.001; config.requiredFrames = 1; config.afterTapDelay = 0.001
    return config
}

@Test @MainActor func runtimeRejectsForeignSessionFramesThenDeliversFromOwnedSession() async throws {
    let commands = Commands(), native = session(Commands())
    // Use one observable transport for the test runtime.
    let owned = session(commands)
    let runtime = CellUseRuntime(runID: UUID(), session: owned,
        agent: ScriptedPhoneAgent(actions: [.tap(x: 0.25, y: 0.75), .finish]), configuration: configuration())
    runtime.start(at: ProcessInfo.processInfo.systemUptime - 0.01)
    runtime.receive(try frame(native.id.rawValue), inputReady: true)
    #expect(runtime.snapshot.observations.isEmpty)
    runtime.receive(try frame(owned.id.rawValue), inputReady: true)
    for _ in 0..<100 where runtime.snapshot.acceptedInputCount == 0 { try await Task.sleep(for: .milliseconds(5)) }
    let recorded = await commands.values
    #expect(recorded == [.tap(TargetPixelPoint(x: 25, y: 150))])
    #expect(runtime.snapshot.acceptedInputCount == 1)
    runtime.receive(try frame(owned.id.rawValue), inputReady: true)
    for _ in 0..<100 where runtime.snapshot.status != .completed { try await Task.sleep(for: .milliseconds(5)) }
    #expect(runtime.snapshot.status == .completed)
    runtime.cancel("testEnded", notify: false)
    await owned.disconnect(); await native.disconnect()
}

private actor DelayedAgent: PhoneAgent {
    private var continuation: CheckedContinuation<Void, Never>?
    var requested = false
    func nextAction(for observation: PhoneObservation) async throws -> PhoneDecision {
        await withCheckedContinuation { continuation = $0; requested = true }
        // Deliberately ignores task cancellation to emulate a late provider.
        return PhoneDecision(observation: observation, action: .typeText("do not type"))
    }
    func reply() { continuation?.resume(); continuation = nil }
}

@Test @MainActor func cancelledRuntimeRejectsLateProviderReply() async throws {
    let commands = Commands(), agent = DelayedAgent()
    let owned = session(commands)
    let runtime = CellUseRuntime(runID: UUID(), session: owned, agent: agent, configuration: configuration())
    runtime.start(at: ProcessInfo.processInfo.systemUptime - 0.01)
    runtime.receive(try frame(owned.id.rawValue), inputReady: true)
    for _ in 0..<100 {
        if await agent.requested { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    let requested = await agent.requested
    #expect(requested)
    runtime.cancel("hostStopped")
    await agent.reply()
    try await Task.sleep(for: .milliseconds(30))
    let recorded = await commands.values
    #expect(recorded.isEmpty && runtime.snapshot.inputs.isEmpty)
    #expect(runtime.snapshot.stopReason == "hostStopped")
    await owned.disconnect()
}
