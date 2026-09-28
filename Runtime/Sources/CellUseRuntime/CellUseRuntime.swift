import DeviceHubClient
import DeviceHubCore
import DeviceHubMedia
import Foundation
import ImageIO
import CellUse
import UniformTypeIdentifiers

/// Platform adapter: native screenshots and HID delivery, independent of the
/// provider's decision policy. No network connection is created by this adapter.
@MainActor
public final class CellUseRuntime {
    public private(set) var snapshot: PhoneActionRunner.Snapshot
    public var onUpdate: ((PhoneActionRunner.Snapshot) -> Void)?
    public var onObservation: ((RemoteDisplayFrame, PhoneActionRunner.Snapshot) -> Void)?
    public var onEnded: (() -> Void)?
    private var runner: PhoneActionRunner
    private let agent: any PhoneAgent
    private let session: DeviceSession
    private var agentTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var endedNotified = false
    private var latestFrame: RemoteDisplayFrame?
    private var currentInputReady = false
    public var runID: UUID { snapshot.runID }
    public var active: Bool { runner.active || snapshot.status == .idle }

    public init(runID: UUID, session: DeviceSession, agent: any PhoneAgent,
                configuration: PhoneActionRunner.Configuration = .init()) {
        self.runner = PhoneActionRunner(runID: runID, configuration: configuration)
        self.snapshot = runner.snapshot
        self.session = session; self.agent = agent
    }

    public func start(at time: Double = ProcessInfo.processInfo.systemUptime) {
        guard runner.snapshot.status == .idle else { return }
        runner.start(at: time)
        publish()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                self.runner.tick(at: ProcessInfo.processInfo.systemUptime)
                self.publish()
                if !self.runner.active { self.finishIfNeeded(); return }
            }
        }
    }

    public func cancel(_ reason: String, notify: Bool = true) {
        runner.stop(reason)
        agentTask?.cancel(); watchdog?.cancel()
        publish()
        if notify { finishIfNeeded() }
    }

    public func receive(_ frame: RemoteDisplayFrame, inputReady: Bool) {
        guard runner.active, frame.metadata.generation.rawValue == session.id.rawValue else { return }
        latestFrame = frame
        currentInputReady = inputReady
        let now = ProcessInfo.processInfo.systemUptime
        let age = Date().timeIntervalSince(frame.metadata.receivedAt)
        let metadata = PhoneFrame(runID: runID, width: frame.image.width, height: frame.image.height,
                                  capturedAt: now - age, portrait: frame.metadata.orientation == .portrait)
        let request = runner.offer(metadata, inputReady: inputReady, now: now)
        publish()
        guard request else { finishIfNeeded(); return }
        guard let png = Self.encodePNG(frame) else { cancel("screenshotEncodingFailed"); return }
        runner.noteScreenshotBytes(png.count, observationID: metadata.id)
        onObservation?(frame, runner.snapshot)
        let observation = PhoneObservation(frame: metadata, screenshotPNG: png,
            decisionIndex: runner.snapshot.observations.count - 1,
            acceptedTapCount: runner.snapshot.acceptedTapCount, acceptedInputCount: runner.snapshot.acceptedInputCount)
        publish()
        agentTask = Task { [weak self, agent] in
            do {
                let decision = try await agent.nextAction(for: observation)
                guard !Task.isCancelled, let self, self.runner.active else { return }
                if decision.action.isInput {
                    guard self.currentInputReady, let latest = self.latestFrame,
                          latest.metadata.orientation == .portrait,
                          latest.image.width == observation.frame.width,
                          latest.image.height == observation.frame.height,
                          (0...self.runner.configuration.maximumFrameAge).contains(Date().timeIntervalSince(latest.metadata.receivedAt)) else {
                        self.cancel("inputContextChanged"); return
                    }
                }
                let command = self.runner.resolve(decision, now: ProcessInfo.processInfo.systemUptime)
                self.publish()
                if let command {
                    do {
                        try await PhoneInputDelivery.deliver(command.action, contextIsValid: {
                            guard self.runner.active, self.currentInputReady, let latest = self.latestFrame else { return false }
                            return latest.metadata.orientation == .portrait && latest.image.width == command.imageWidth &&
                                latest.image.height == command.imageHeight &&
                                (0...self.runner.configuration.maximumFrameAge).contains(Date().timeIntervalSince(latest.metadata.receivedAt))
                        }, send: { event in
                            try await self.session.command(Self.nativeCommand(event, width: command.imageWidth, height: command.imageHeight))
                        })
                        guard !Task.isCancelled else { return }
                        self.runner.acknowledge(command: command.id, accepted: true, now: ProcessInfo.processInfo.systemUptime)
                    } catch {
                        self.runner.acknowledge(command: command.id, accepted: false, now: ProcessInfo.processInfo.systemUptime)
                    }
                    self.publish()
                }
                self.finishIfNeeded()
            } catch {
                guard !Task.isCancelled, let self, self.runner.active else { return }
                self.cancel("agentFailed")
            }
        }
    }

    public func updateInputReadiness(_ ready: Bool) { currentInputReady = ready }

    private static func nativeCommand(_ event: PhoneInputEvent, width: Int, height: Int) -> DeviceCommand {
        func point(_ x: Double, _ y: Double) -> TargetPixelPoint {
            TargetPixelPoint(x: x * Double(width), y: y * Double(height))
        }
        switch event {
        case let .tap(x, y): return .tap(point(x, y))
        case let .touch(x, y, phase):
            let nativePhase: TouchPhase = switch phase { case .began: .began; case .moved: .moved; case .ended: .ended }
            return .touch(TouchCommand(contactID: 0, point: point(x, y), phase: nativePhase))
        case let .character(character): return .keyTap(.character(character), modifiers: [])
        case .key(.enter): return .keyTap(.return, modifiers: [])
        case .key(.backspace): return .keyTap(.delete, modifiers: [])
        case .key(.selectAll): return .keyTap(.character("a"), modifiers: [.command])
        case .releaseAll: return .releaseAllInput
        }
    }

    private func publish() { snapshot = runner.snapshot; onUpdate?(snapshot) }

    private func finishIfNeeded() {
        guard [.completed, .stopped].contains(runner.snapshot.status), !endedNotified else { return }
        endedNotified = true
        watchdog?.cancel(); agentTask?.cancel()
        onEnded?()
    }

    private static func encodePNG(_ frame: RemoteDisplayFrame) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData,
                UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, frame.image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
