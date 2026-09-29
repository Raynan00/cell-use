#if os(iOS)
import CellUse
import CellUseTunnel
import DeviceHubClient
import DeviceHubCore
import DeviceHubDiagnostics
import DeviceHubMedia
import DeviceHubPersistence
import DeviceHubTransport
import Foundation
import PhoneProbeCore
import PhoneProbeRouting
import UIKit

/// Owns the embedded tunnel, saved pairing, discovery and native session streams.
/// Retain in your host app. The host owns UI and agent background execution time.
@MainActor public final class CellUseConnection {
    public struct Configuration: Sendable {
        public let appName: String
        public let providerBundleIdentifier: String
        public let pairingService: String
        public let tunnel: TunnelConfiguration

        /// Keep pairingService stable between releases to reuse the Keychain vault.
        public init(appName: String, providerBundleIdentifier: String,
                    pairingService: String, tunnel: TunnelConfiguration = .standard) {
            self.appName = appName; self.providerBundleIdentifier = providerBundleIdentifier
            self.pairingService = pairingService; self.tunnel = tunnel
        }
    }

    private let driver: NativeConnectionDriver
    private let setup: PhoneConnectionSetup
    public var state: PhoneConnectionState { setup.state }
    public var onStateChange: ((PhoneConnectionState) -> Void)? {
        get { setup.onChange }
        set { setup.onChange = newValue }
    }
    /// Runs on MainActor. Do not create another consumer of the session's streams.
    public var onFrame: ((RemoteDisplayFrame) -> Void)? {
        get { driver.onFrame }
        set { driver.onFrame = newValue }
    }

    /// Supply NativeSessionClient.deviceHubLive(probeScreenshots: true) from the
    /// app's DeviceHubLive target. All remaining connection composition lives here.
    public init(configuration: Configuration, nativeSessions: NativeSessionClient,
                diagnostics: DiagnosticRecorder? = nil) throws {
        guard !configuration.appName.isEmpty, !configuration.pairingService.isEmpty,
              !configuration.providerBundleIdentifier.isEmpty else { throw PhoneSetupIssue.failed }
        let route = try ConnectionRoute(mode: .localVPN, peer: configuration.tunnel.deviceAddress)
        let recorder = try diagnostics ?? ConnectionDiagnostics.makeRecorder()
        let native = RoutedNativeClient.wrap(nativeSessions, route: route,
            diagnostics: RouteDiagnostics(mode: route.mode))
        let transport = try DeviceHubTransportConfiguration(controllerDisplayName: configuration.appName,
            controllerModel: "Mac17,7", remoteTargetPolicy: .authenticatedDevices)
        let persistence = PairingPersistenceClient.live(descriptor: .pairingVault(service: configuration.pairingService))
        let client = DeviceHubClient.live(nativeSessions: native, configuration: transport,
            diagnostics: recorder, pairingPersistence: persistence)
        driver = NativeConnectionDriver(client: client,
            tunnel: CellUseTunnelController(providerBundleIdentifier: configuration.providerBundleIdentifier),
            configuration: configuration.tunnel, displayName: configuration.appName)
        setup = PhoneConnectionSetup(driver: driver)
    }

    public func connect(deviceID: String? = nil) { setup.connect(deviceID: deviceID) }
    public func pair() { setup.pair() }
    public func disconnect() async { await setup.disconnect() }

    /// Creates a runtime fed by this connection's existing frame/event consumers.
    /// Start it only after the host has obtained the required execution window.
    public func makeRuntime(agent: any PhoneAgent,
                            configuration: PhoneActionRunner.Configuration = .init()) throws -> CellUseRuntime {
        guard state.isReady, let session = driver.session else { throw PhoneSetupIssue.inputUnavailable }
        guard driver.runtime?.active != true else { throw PhoneSetupIssue.anotherSession }
        let runtime = CellUseRuntime(runID: session.id.rawValue, session: session, agent: agent, configuration: configuration)
        driver.runtime = runtime
        return runtime
    }
}

@MainActor private final class NativeConnectionDriver: PhoneConnectionDriver {
    var onEvent: ((PhoneConnectionEvent) -> Void)?
    var onFrame: ((RemoteDisplayFrame) -> Void)?
    private(set) var session: DeviceSession?
    var runtime: CellUseRuntime?
    private let client: DeviceHubClient
    private let tunnel: CellUseTunnelController
    private let configuration: TunnelConfiguration
    private let displayName: String
    private var discovery: Task<Void, Never>?
    private var events: Task<Void, Never>?
    private var frames: Task<Void, Never>?
    private var available: [DeviceSummary] = []
    private var token = UUID()
    private var inputReady = false

    init(client: DeviceHubClient, tunnel: CellUseTunnelController,
         configuration: TunnelConfiguration, displayName: String) {
        self.client = client; self.tunnel = tunnel
        self.configuration = configuration; self.displayName = displayName
    }

    func startTunnel() async throws {
        do { try await tunnel.connect(configuration: configuration, displayName: displayName) }
        catch is CancellationError { throw CancellationError() }
        catch { throw PhoneSetupIssue.tunnel }
        let generation = token
        discovery = Task { [weak self, client] in
            for await devices in client.availability() {
                guard !Task.isCancelled, let self, self.token == generation else { return }
                self.available = devices
            }
        }
    }

    func savedDevices() async throws -> [PhonePairedDevice] {
        do { return try await client.pairedDevices().map { PhonePairedDevice(id: $0.id.rawValue, name: $0.name) } }
        catch { throw Self.issue(error) }
    }

    func pair(onCode: @escaping @MainActor (String) -> Void) async throws -> PhonePairedDevice {
        // Pairing requires a visit to Settings. Hold only the system-granted lease
        // for that explicit operation; agent runs have a separate host-owned lease.
        let lifetime = PairingLifetime()
        let pairing = Task { @MainActor [client] () throws -> PhonePairedDevice in
            do {
                for try await event in client.pair(PairingRequest()) {
                    try Task.checkCancellation()
                    switch event {
                    case .waitingForCodeEntry(let code): onCode(code.displayValue)
                    case .paired(let device): return PhonePairedDevice(id: device.id.rawValue, name: device.name)
                    default: break
                    }
                }
                throw PhoneSetupIssue.pairing
            } catch is CancellationError { throw CancellationError() }
            catch { throw Self.issue(error) }
        }
        let lease = UIApplication.shared.beginBackgroundTask(withName: "cell-use pairing") {
            pairing.cancel()
            Task { @MainActor in lifetime.expired = true }
        }
        defer { if lease != .invalid { UIApplication.shared.endBackgroundTask(lease) } }
        let device = try await withTaskCancellationHandler(operation: { try await pairing.value }, onCancel: { pairing.cancel() })
        try Task.checkCancellation()
        guard !lifetime.expired, !pairing.isCancelled else { throw PhoneSetupIssue.pairing }
        return device
    }

    func open(deviceID: String) async throws {
        let generation = token
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !available.contains(where: { $0.id.rawValue == deviceID && $0.reachability == .reachable }) {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw PhoneSetupIssue.unreachable }
            try await Task.sleep(for: .milliseconds(150))
        }
        let opened: DeviceSession
        do { opened = try await client.connect(DeviceID(rawValue: deviceID)) }
        catch { throw Self.issue(error) }
        guard !Task.isCancelled, token == generation else { await opened.disconnect(); throw CancellationError() }
        session = opened
        let emit = onEvent
        events = Task { [weak self] in
            do {
                for try await update in opened.events {
                    guard !Task.isCancelled, let self, self.token == generation else { return }
                    switch update.event {
                    case .hidReadinessChanged(let readiness):
                        self.inputReady = readiness == .ready
                        self.runtime?.updateInputReadiness(self.inputReady)
                        emit?(.inputReady(self.inputReady))
                    case .ended(let error):
                        emit?(.ended(error.map { Self.issue($0) } ?? .connectionLost)); return
                    default: break
                    }
                }
                if !Task.isCancelled { emit?(.ended(.connectionLost)) }
            } catch { if !Task.isCancelled { emit?(.ended(Self.issue(error))) } }
        }
        frames = Task { [weak self] in
            for await frame in opened.frames {
                guard !Task.isCancelled, let self, self.token == generation else { return }
                guard frame.metadata.generation.rawValue == opened.id.rawValue else { continue }
                let capturedAt = ProcessInfo.processInfo.systemUptime - Date().timeIntervalSince(frame.metadata.receivedAt)
                emit?(.frame(capturedAt: capturedAt, portrait: frame.metadata.orientation == .portrait))
                self.runtime?.receive(frame, inputReady: self.inputReady)
                self.onFrame?(frame)
            }
            if !Task.isCancelled { emit?(.ended(.connectionLost)) }
        }
    }

    func close() async {
        token = UUID()
        runtime?.cancel("connectionClosed"); runtime = nil
        events?.cancel(); frames?.cancel(); discovery?.cancel()
        events = nil; frames = nil; discovery = nil
        available = []; inputReady = false
        let old = session; session = nil
        if let old { await old.disconnect() }
        tunnel.disconnect()
    }

    static func issue(_ error: Error) -> PhoneSetupIssue {
        if let issue = error as? PhoneSetupIssue { return issue }
        guard let failure = error as? DeviceHubError else { return .failed }
        switch failure {
        case .localNetworkDenied: return .localNetwork
        case .needsPairing, .pairingTimedOut, .pairingRejected, .incorrectPairingCode,
             .corruptPairingRecord, .peerAuthenticationFailed: return .pairing
        case .developerModeDisabled: return .developerMode
        case .deviceLocked: return .unlockPhone
        case .deviceBusy: return .anotherSession
        case .developerImageUnavailable, .developerImageIncompatible: return .prepareServices
        case .unsupportedProtocolVersion: return .incompatibleRuntime
        case .deviceOffline: return .unreachable
        case .decoderFailed, .mediaStalled: return .screenUnavailable
        case .connectionLost, .secureConnectionFailed: return .connectionLost
        case .malformedDeviceAnnouncement: return .failed
        }
    }
}

@MainActor private final class PairingLifetime {
    var expired = false
}
#endif
