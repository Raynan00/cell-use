import Foundation

public struct PhonePairedDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum PhoneSetupIssue: Error, Equatable, Sendable {
    case tunnel, pairing, developerMode, unlockPhone, prepareServices, localNetwork
    case unreachable, anotherSession, incompatibleRuntime, screenUnavailable
    case inputUnavailable, portraitRequired, connectionLost, invalidSelection, failed

    public var message: String {
        switch self {
        case .tunnel: "Approve the app's VPN connection and try again. Check the embedded extension's signing if it cannot start."
        case .pairing: "Pair this iPhone in Settings, then return to the app."
        case .developerMode: "Enable Developer Mode in Settings > Privacy & Security and complete the restart prompts."
        case .unlockPhone: "Unlock the iPhone and try again."
        case .prepareServices: "Prepare this iPhone's developer services with a compatible desktop tool, then reconnect."
        case .localNetwork: "Allow local-network access for this app in Settings."
        case .unreachable: "Keep the iPhone awake with Wi-Fi enabled and reconnect the local tunnel."
        case .anotherSession: "Close the other device-control session and try again."
        case .incompatibleRuntime: "Use a runtime build compatible with this iOS version."
        case .screenUnavailable: "A fresh screenshot is not available. Reconnect with the phone awake."
        case .inputUnavailable: "The screen is connected, but input is not ready. Reconnect the session."
        case .portraitRequired: "Keep the iPhone in portrait orientation."
        case .connectionLost: "The session ended. Connect again to start a new session."
        case .invalidSelection: "Select a device from this app's saved pairings."
        case .failed: "Connection setup failed. Try connecting again."
        }
    }
}

public enum PhoneConnectionState: Equatable, Sendable {
    case idle, startingTunnel, pairingRequired, pairing(code: String?)
    case chooseDevice([PhonePairedDevice]), connecting, checkingReadiness, ready
    case needsAction(PhoneSetupIssue), stopping

    public var isReady: Bool { self == .ready }
}

public enum PhoneConnectionEvent: Sendable {
    case inputReady(Bool)
    /// Monotonic capture time in the same clock domain as systemUptime.
    case frame(capturedAt: Double, portrait: Bool)
    case ended(PhoneSetupIssue)
}

/// Boundary for connection backends. Implementations own their streams and close
/// resources before returning from close(). Pairing must respond to cancellation.
@MainActor public protocol PhoneConnectionDriver: AnyObject {
    var onEvent: ((PhoneConnectionEvent) -> Void)? { get set }
    func startTunnel() async throws
    func savedDevices() async throws -> [PhonePairedDevice]
    func pair(onCode: @escaping @MainActor (String) -> Void) async throws -> PhonePairedDevice
    func open(deviceID: String) async throws
    func close() async
}

/// UI-independent setup flow. Retain it in the host and explicitly disconnect
/// when its connection is no longer needed. It never forgets saved pairings.
@MainActor public final class PhoneConnectionSetup {
    public private(set) var state: PhoneConnectionState = .idle
    public var onChange: ((PhoneConnectionState) -> Void)?
    private let driver: any PhoneConnectionDriver
    private let now: () -> Double
    private let maximumFrameAge: Double
    private let readinessTimeout: Double
    private var operation: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?
    private var generation = UUID()
    private var stopping = false
    private var preparing = false
    private var observing = false
    private var inputReady = false
    private var frame: (time: Double, portrait: Bool)?
    private var waitingSince: Double?

    public init(driver: any PhoneConnectionDriver, maximumFrameAge: Double = 2,
                readinessTimeout: Double = 30) {
        precondition(maximumFrameAge.isFinite && maximumFrameAge > 0)
        precondition(readinessTimeout.isFinite && readinessTimeout > 0)
        self.driver = driver
        self.maximumFrameAge = maximumFrameAge
        self.readinessTimeout = readinessTimeout
        self.now = { ProcessInfo.processInfo.systemUptime }
    }

    // Deterministic clock for testing readiness transitions without sleeping.
    init(driver: any PhoneConnectionDriver, now: @escaping () -> Double,
         maximumFrameAge: Double = 2, readinessTimeout: Double = 30) {
        self.driver = driver; self.now = now
        self.maximumFrameAge = maximumFrameAge; self.readinessTimeout = readinessTimeout
    }

    /// Starts the tunnel and reuses an existing pairing. Multiple pairings require
    /// an explicit selection; a missing pairing is surfaced without deleting data.
    public func connect(deviceID: String? = nil) { begin(pairing: false, deviceID: deviceID) }

    /// Call from the user's Pair action. Successful pairing continues to connection.
    public func pair() { begin(pairing: true, deviceID: nil) }

    public func disconnect() async {
        if let cleanup { await cleanup.value }
        guard !stopping else { return }
        stopping = true; generation = UUID(); observing = false
        publish(.stopping)
        monitor?.cancel(); monitor = nil
        let old = operation; old?.cancel()
        await old?.value
        operation = nil
        driver.onEvent = nil
        await driver.close()
        frame = nil; inputReady = false; waitingSince = nil
        stopping = false; publish(.idle)
    }

    private func begin(pairing: Bool, deviceID: String?) {
        guard !preparing, operation == nil, !stopping, !observing else { return }
        preparing = true
        let token = UUID(); generation = token
        frame = nil; inputReady = false; waitingSince = nil
        publish(.startingTunnel)
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.operation = nil; self.preparing = false }
            do {
                await self.driver.close()
                try self.validate(token)
                self.driver.onEvent = { [weak self] event in
                    guard let self, self.generation == token, !self.stopping else { return }
                    self.receive(event)
                }
                try await self.driver.startTunnel()
                try self.validate(token)
                let selected: PhonePairedDevice
                if pairing {
                    self.publish(.pairing(code: nil))
                    selected = try await self.driver.pair { [weak self] code in
                        guard let self, self.generation == token, !self.stopping else { return }
                        self.publish(.pairing(code: code))
                    }
                } else {
                    let devices = try await self.driver.savedDevices()
                    try self.validate(token)
                    if let deviceID {
                        guard let match = devices.first(where: { $0.id == deviceID }) else { throw PhoneSetupIssue.invalidSelection }
                        selected = match
                    } else if devices.count == 1 {
                        selected = devices[0]
                    } else {
                        self.publish(devices.isEmpty ? .pairingRequired : .chooseDevice(devices))
                        return
                    }
                }
                try self.validate(token)
                self.publish(.connecting)
                try await self.driver.open(deviceID: selected.id)
                try self.validate(token)
                self.observing = true
                self.waitingSince = self.now()
                self.tick()
                self.monitor = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        guard let self, self.generation == token, self.observing else { return }
                        self.tick()
                    }
                }
            } catch {
                self.observing = false
                await self.driver.close()
                guard self.generation == token, !self.stopping else { return }
                self.publish(error is CancellationError ? .idle : .needsAction(error as? PhoneSetupIssue ?? .failed))
            }
        }
    }

    private func validate(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token, !stopping else { throw CancellationError() }
    }

    private func receive(_ event: PhoneConnectionEvent) {
        switch event {
        case .inputReady(let ready): inputReady = ready
        case .frame(let time, let portrait): frame = (time, portrait)
        case .ended(let issue):
            // Native open can emit an end before returning. Cancel that operation
            // too, so it cannot later overwrite the terminal state with ready.
            fail(issue); return
        }
        if observing { tick() }
    }

    func tick() {
        guard observing else { return }
        let fresh = frame.map { (0...maximumFrameAge).contains(now() - $0.time) } ?? false
        if fresh, frame?.portrait == true, inputReady {
            waitingSince = nil; publish(.ready)
        } else {
            if waitingSince == nil { waitingSince = now() }
            publish(.checkingReadiness)
            if now() - (waitingSince ?? now()) >= readinessTimeout {
                fail(!fresh ? .screenUnavailable : frame?.portrait == false ? .portraitRequired : .inputUnavailable)
            }
        }
    }

    private func fail(_ issue: PhoneSetupIssue) {
        guard !stopping else { return }
        generation = UUID(); observing = false
        monitor?.cancel(); monitor = nil
        operation?.cancel()
        // Block reconnect until teardown has finished.
        stopping = true
        let pending = operation
        cleanup = Task { [weak self] in
            await pending?.value
            guard let self else { return }
            self.driver.onEvent = nil
            await self.driver.close()
            self.cleanup = nil; self.stopping = false
            self.publish(.needsAction(issue))
        }
        publish(.needsAction(issue))
    }

    private func publish(_ next: PhoneConnectionState) {
        guard state != next else { return }
        state = next; onChange?(next)
    }
}
