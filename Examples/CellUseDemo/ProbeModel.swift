import DeviceHubClient
import DeviceHubCore
import DeviceHubDiagnostics
import DeviceHubLive
import DeviceHubMedia
import DeviceHubPersistence
import DeviceHubTransport
import Foundation
import Observation
import PhoneProbeCore
import CellUse
import UIKit
import UserNotifications
import Vision

@MainActor @Observable
final class ProbeModel {
    private(set) var evidence = ProbeEvidence()
    private(set) var devices: [DeviceSummary] = []
    private(set) var message = "Preparing the native runtime…"
    private(set) var pairingCode: String?
    private(set) var challenge = ProbeModel.newChallenge()
    private(set) var pairing = false
    private(set) var connecting = false
    private(set) var closing = false
    private(set) var testing = false
    private(set) var inputReady = false
    private(set) var initialized = false
    private(set) var backgrounded = false
    private(set) var latestFrame: RemoteDisplayFrame?
    private(set) var receivedFrameCount = 0
    private(set) var lastSelfTapBlocker: String?
    private(set) var targetVisibleAtLastAttempt: Bool?
    private(set) var targetGeometryStatus: ProbeTargetGeometry.Status?
    private(set) var lastFailure: DeviceHubError?
    private(set) var notificationsAvailable = false
    private(set) var discoveryActive = false
    private(set) var discoveryMessage = "Discovery has not started."
    private(set) var discoveryStarts = 0
    private(set) var discoverySnapshots = 0
    private(set) var discoveryEndReason: AvailabilityObserver<[DeviceSummary]>.EndReason?
    private(set) var transportEvents: [TransportEvent] = []
    private(set) var mediaFailures: [MediaFailureProbe.Event] = []
    private(set) var decoderConfigurations: [MediaFailureProbe.DecoderConfiguration] = []
    private(set) var backgroundSample: RemoteDisplayFrame?
    private(set) var backgroundFrameTimings: [Double] = []
    private(set) var backgroundSampleDelay: Double?
    private(set) var lifecycleEvents: [LifecycleEvent] = []
    let continuedWork = ContinuedWork.shared
    private(set) var extendedRun = false
    private(set) var calculator = CalculatorEvidence()
    struct CalculatorEvidence: Encodable {
        var status = "notArmed"
        var matchingZeroFrames = 0
        var commandSubmitted = false
        var resultVerified = false
        var commandDelay: Double?
        var verificationDelay: Double?
        var recognition: CalculatorOCR.Diagnostics?
        var recognitionDurationSeconds: Double?
        var staleRecognitionFrames = 0
        var recognitionErrorStage: String?
        var recognitionErrorCode: Int?
    }
    private(set) var selectedTap = SelectedTapEvidence()
    private(set) var selectedReference: RemoteDisplayFrame?
    private(set) var selectedPoint: CGPoint?
    private(set) var selectedResult: RemoteDisplayFrame?
    @ObservationIgnored private var selectedSignature: ScreenMatch.Signature?
    @ObservationIgnored private var selectedGate = SelectedTapGate()
    @ObservationIgnored private var selectedAcceptedAt: Date?
    @ObservationIgnored private var selectedBackgroundEntry: Double?
    struct SelectedTapEvidence: Encodable {
        var status = "captureCalculatorFirst"
        var targetSelected = false
        var armed = false
        var matchingFrames = 0
        var comparison: ScreenMatch.Comparison?
        var commandAttempted = false
        var commandAccepted = false
        var minimumBackgroundSeconds: Double?
        var commandBackgroundSeconds: Double?
        var afterImageBackgroundSeconds: Double?
        var afterImageReceived = false
        var afterImageChanged = false
        var userConfirmedZeroToSeven = false
        let verificationMethod = "userSelectedTargetAndVisualComparison"
    }
    struct SequenceActionEvidence: Encodable {
        let step: Int
        var freshFramesBeforeCommand = 0
        var commandAttempted = false
        var commandAccepted = false
        var commandBackgroundSeconds: Double?
        var acceptedBackgroundSeconds: Double?
        var afterImageBackgroundSeconds: Double?
    }
    struct SequenceEvidence: Encodable {
        var status = "notArmed"
        var consecutiveFreshFrames = 0
        var intermediateImageReceived = false
        var finalImageReceived = false
        var userConfirmedZeroSevenSeventySeven = false
        var stopReason: String?
        var actions = [SequenceActionEvidence(step: 1), SequenceActionEvidence(step: 2)]
        let minimumBackgroundSeconds = 3
        let mode = "transportOnly"
        let verificationMethod = "orderedAcknowledgedTapsWithFreshFramesAndUserConfirmed77"
    }
    private(set) var sequence = SequenceEvidence()
    private(set) var sequenceIntermediate: RemoteDisplayFrame?
    private(set) var sequenceResult: RemoteDisplayFrame?
    @ObservationIgnored private var sequenceGate = SelectedSequenceGate(mode: .transportOnly)
    @ObservationIgnored private var sequenceAcceptedAt: Date?
    @ObservationIgnored private var sequenceBackgroundEntry: Double?

    private(set) var agentRun: OnDeviceAgentRun?
    var canArmAgentDemo: Bool { agentRun == nil && canArmSelectedTap }
    var agentHint: String {
        if let agentRun {
            if agentRun.demo != "calculator" {
                return agentRun.active ? (agentRun.demo == "swipe" ? "Armed. Open the main Settings list in portrait now. Leave it untouched for 20 seconds." : "Armed. Open a blank Notes draft with its cursor active and English (US) keyboard. Leave it untouched for 20 seconds.") : "Inspect the control result below. Reconnect for the other test."
            }
            return agentRun.active ? (extendedRun ? "Armed. Open Calculator at 0 now and leave it untouched for 110 seconds. The first decision waits until 60 seconds." : "Armed. Open Calculator at 0 now and leave it untouched for 25 seconds.") : "Inspect the runner result below. Reconnect for a new run."
        }
        if selectedPoint == nil { return "Capture Calculator at 0 and select the 7 key first." }
        if extendedRun && (!continuedWork.running || ProcessInfo.processInfo.systemUptime - runStartedAt > 25) {
            return "Start a fresh Extended run, then arm within 25 seconds."
        }
        if !hasSession || evidence.ended { return "Target saved. Connect again, then arm the agent demo." }
        if !inputReady { return "Waiting for input readiness." }
        return "Ready for the agent demo: tap, wait, tap, finish. Open Calculator at 0 after arming."
    }
    func armAgentDemo() {
        guard canArmAgentDemo, let session, let point = selectedPoint else { message = agentHint; return }
        if extendedRun && !continuedWork.requireAgentRun() { message = "Extended work is no longer running. Start a new run."; return }
        let agent = ScriptedPhoneAgent(actions: [.tap(x: point.x, y: point.y), .wait(seconds: 1),
                                                .tap(x: point.x, y: point.y), .finish])
        armRuntime(session: session, agent: agent, provider: "ScriptedPhoneAgent.tapWaitTapFinish", demo: "calculator")
    }
    var canArmControlDemo: Bool {
        !extendedRun && agentRun == nil && hasSession && inputReady && !backgrounded && !evidence.ended &&
        !selectedGate.attempted && !selectedGate.armed && sequenceGate.stage == .idle
    }
    func armControlDemo(_ demo: String) {
        guard canArmControlDemo, let session, ["swipe", "text"].contains(demo) else { return }
        let action: PhoneAction = demo == "swipe"
            ? .swipe(fromX: 0.5, fromY: 0.75, toX: 0.5, toY: 0.3, duration: 0.6)
            : .typeText("Phone harness test 20")
        armRuntime(session: session, agent: ScriptedPhoneAgent(actions: [action, .finish]),
                   provider: "ScriptedPhoneAgent." + demo, demo: demo)
    }
    private func armRuntime(session: DeviceSession, agent: any PhoneAgent, provider: String, demo: String) {
        let generation = evidence.generation
        agentRun = OnDeviceAgentRun(runID: generation, session: session, agent: agent, providerName: provider, extended: extendedRun, demo: demo) { [weak self] in
            Task { @MainActor in
                guard let self, self.evidence.generation == generation else { return }
                if self.extendedRun, self.continuedWork.running, let result = self.agentRun?.report.runner {
                    let completed = result.status == .completed
                    self.continuedWork.updateAgentProgress(resolvedDecisions: result.observations.filter { $0.resolvedSeconds != nil }.count, completed: completed)
                    if completed && !self.continuedWork.agentWorkComplete {
                        self.message = "Agent actions completed. Finishing the remaining capture evidence."
                        return
                    }
                    self.continuedWork.finish(success: completed)
                }
                await self.closeSession(generation: generation)
                self.message = "Agent runner ended. Inspect the result and View report."
            }
        }
        message = agentHint
    }

    var canArmSequence: Bool { !extendedRun && canArmSelectedTap }
    var sequenceHint: String {
        if selectedPoint == nil { return "Capture Calculator at 0, then select the center of 7 in its image." }
        if sequenceGate.active { return "Armed. Open Calculator at 0 now and leave it untouched for 15 seconds." }
        if sequenceGate.stage == .complete { return "Inspect both result images and confirm whether you observed 0, then 7, then 77." }
        if sequenceGate.stage == .stopped { return "Sequence stopped: \(sequenceGate.stopReason ?? "unknown"). Reconnect to try again." }
        if extendedRun { return "This quick test uses normal Connect. Stop, retry discovery, then Connect." }
        if !hasSession || evidence.ended { return "Target saved. Reconnect with normal Connect, then arm two taps." }
        if !inputReady { return "Waiting for input readiness." }
        return "Arm two taps, then open Calculator at 0 for 15 seconds. Screenshots are captured between taps; their contents do not gate the next action."
    }

    var selectedTapHint: String {
        if sequenceGate.active || sequenceGate.attemptedActions > 0 { return "The two-step test owns input for this run. Inspect its results below." }
        if selectedSignature == nil { return "Capture Calculator at 0, then use Select 7 in this image below." }
        if selectedGate.attempted { return "This run already attempted its one tap. Inspect the after-image or start a new run." }
        if selectedGate.armed { return extendedRun ? "Armed. Open Calculator at 0 now; leave it untouched for 90 seconds." : "Armed. Open Calculator at 0 for 15 seconds." }
        if !hasSession || evidence.ended { return "Target saved. Start an Extended run for the 60-second test." }
        if extendedRun && ProcessInfo.processInfo.systemUptime - runStartedAt > 25 {
            return "Too late to arm within this run's two-minute limit. Stop, retry discovery, then start Extended run again."
        }
        if !inputReady { return "Waiting for the input channel to become ready." }
        return extendedRun ? "Arm now, then open Calculator at 0 for 90 seconds. The tap waits at least 60 continuous background seconds." : "Target saved. Choose Extended run above for the delayed test, or arm here for a short test."
    }
    var canArmSelectedTap: Bool {
        agentRun == nil && hasSession && inputReady && !evidence.ended && !backgrounded && selectedSignature != nil && !selectedGate.attempted && !selectedGate.armed && sequenceGate.stage == .idle &&
        (!extendedRun || (continuedWork.running && ProcessInfo.processInfo.systemUptime - runStartedAt <= 25))
    }

    var routeMode: ConnectionRoute.Mode = .localVPN
    var vpnPeer = "10.7.0.1"
    private(set) var routeSnapshot = RouteDiagnostics.Snapshot(mode: .localVPN)
    private(set) var routeMessage = "Enable LocalDevVPN, then keep Wi-Fi on for discovery."
    private(set) var applyingRoute = false

    struct TransportEvent: Encodable {
        let sequence: UInt64
        let timestamp: Date
        let stage: DiagnosticStage
        let kind: DiagnosticEventKind
        let failureCode: DiagnosticFailureCode?
    }

    struct LifecycleEvent: Encodable {
        enum Kind: String, Encodable {
            case enteredBackground, enteredForeground, backgroundLeaseStarted
            case firstBackgroundFrame, sessionFailed, sessionEnded, backgroundLeaseExpired
        }
        let kind: Kind
        let elapsedSeconds: Double
        let backgrounded: Bool
        let receivedFrames: Int
        let backgroundSecondsRemaining: Double?
    }

    @ObservationIgnored private var client: DeviceHubClient?
    @ObservationIgnored private var diagnosticsRecorder: DiagnosticRecorder?
    @ObservationIgnored private var routeDiagnostics: RouteDiagnostics?
    @ObservationIgnored private let availability = AvailabilityObserver<[DeviceSummary]>()
    @ObservationIgnored private var discoveryStoppedByUser = false
    @ObservationIgnored private var session: DeviceSession?
    @ObservationIgnored private var nativeGeneration: SessionGeneration?
    @ObservationIgnored private var runStartedAt = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var backgroundStartedAt: Double?
    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var framesTask: Task<Void, Never>?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundLease: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var pendingTargetActivation = false
    @ObservationIgnored private var probeDeadline: Date?
    @ObservationIgnored private var calculatorSentAt: Date?
    @ObservationIgnored private var calculatorZeroLayout: CalculatorScreen?
    @ObservationIgnored private var calculatorArmed = false

    var hasSession: Bool { session != nil }
    var canStart: Bool { initialized && !pairing && !connecting && !closing && !hasSession && !applyingRoute && !continuedWork.pending }

    var canStartExtended: Bool {
        canStart || (initialized && hasSession && !extendedRun && !pairing && !connecting && !closing && !testing && !applyingRoute && !continuedWork.pending && selectedSignature != nil)
    }

    func startExtended(to device: DeviceSummary) {
        guard canStartExtended, !backgrounded else { return }
        if hasSession {
            let generation = evidence.generation
            closing = true
            Task {
                await closeSession(generation: generation)
                guard evidence.generation == generation, !discoveryStoppedByUser, !backgrounded else { return }
                startExtended(to: device)
            }
            return
        }
        continuedWork.submit(start: { [weak self] in
            guard let self, !self.backgrounded else {
                ContinuedWork.shared.finish(success: false)
                return
            }
            self.connect(to: device, extended: true)
        }, expire: { [weak self] in
            guard let self else { return }
            self.calculatorArmed = false
            self.calculator.status = "backgroundWorkExpired"
            self.agentRun?.cancel("backgroundWorkExpired", notify: false)
            Task { await self.stop() }
        })
    }

    func prepare() async {
        guard !initialized else { return }
        if let saved = UserDefaults.standard.string(forKey: "probe.routeMode"),
           let mode = ConnectionRoute.Mode(rawValue: saved) { routeMode = mode }
        vpnPeer = UserDefaults.standard.string(forKey: "probe.vpnPeer") ?? "10.7.0.1"
        await configureClient()
    }

    private func configureClient() async {
        do {
            let route = try ConnectionRoute(mode: routeMode, peer: vpnPeer)
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            let diagnostics = try DeviceHubDiagnosticsRuntime.live(applicationSupportDirectory: directory)
            diagnosticsRecorder = diagnostics.recorder
            let routeRecorder = RouteDiagnostics(mode: route.mode)
            routeDiagnostics = routeRecorder
            let native = RoutedNativeClient.wrap(try NativeSessionClient.deviceHubLive(probeScreenshots: true),
                route: route, diagnostics: routeRecorder)
            let configuration = try DeviceHubTransportConfiguration(
                controllerDisplayName: "cell-use", controllerModel: "Mac17,7",
                remoteTargetPolicy: .authenticatedDevices)
            let persistence = PairingPersistenceClient.live(
                descriptor: .pairingVault(service: "\(Bundle.main.bundleIdentifier ?? "PhoneProbe").pairing"))
            client = DeviceHubClient.live(nativeSessions: native, configuration: configuration,
                diagnostics: diagnostics.recorder, pairingPersistence: persistence)
            devices = try await client!.pairedDevices()
            initialized = true
            message = "Keep LocalDevVPN enabled. Your saved pairing will be verified through the selected route."
            await refreshRouteDiagnostics()
            startDiscovery()
        } catch {
            message = "Could not prepare the connection. Check the Device IP and bundled runtime."
        }
    }

    func applyRoute() async {
        guard !pairing, !connecting, !closing, !hasSession, !applyingRoute else { return }
        guard (try? ConnectionRoute(mode: routeMode, peer: vpnPeer)) != nil else {
            routeMessage = "Enter the private IPv4 Device IP from LocalDevVPN, optionally ending in /32."
            return
        }
        applyingRoute = true
        defer { applyingRoute = false }
        await availability.stop()
        client = nil
        initialized = false
        discoveryStarts = 0
        discoverySnapshots = 0
        transportEvents = []
        newRun()
        UserDefaults.standard.set(routeMode.rawValue, forKey: "probe.routeMode")
        UserDefaults.standard.set(vpnPeer, forKey: "probe.vpnPeer")
        await configureClient()
    }

    func refreshRouteDiagnostics() async {
        guard let routeDiagnostics else { return }
        let snapshot = await routeDiagnostics.snapshot()
        // An older client may still finish a verification while a route changes.
        guard self.routeDiagnostics === routeDiagnostics else { return }
        routeSnapshot = snapshot
        if snapshot.verificationSuccesses > 0 {
            routeMessage = "Pair verification succeeded through this route. Connect to test the next stage."
        } else if let event = snapshot.events.last, event.outcome == "failed" {
            routeMessage = "Verification failed: \(event.code ?? "unknown") at \(event.stage ?? "unknown")."
        } else {
            switch snapshot.path {
            case .direct: routeMessage = "Direct Wi-Fi route selected for comparison."
            case .tunnel: routeMessage = "VPN route detected. Waiting for pair verification…"
            case .localAddress: routeMessage = "That is an interface address. Use LocalDevVPN’s Device IP, not Tunnel IP."
            case .otherInterface: routeMessage = "Traffic is not using the VPN. Enable LocalDevVPN and check Device IP."
            case .unavailable: routeMessage = "Waiting for discovery. Keep Wi-Fi and LocalDevVPN enabled."
            }
        }
    }

    func startPairing() {
        guard canStart, let client else { return }
        startDiscovery()
        newRun()
        pairing = true
        evidence.stage(.pairing, generation: evidence.generation)
        message = "Open this iPhone’s Settings → Privacy & Security → Developer Mode and select cell-use."
        let generation = evidence.generation
        pairingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.evidence.generation == generation {
                    self.pairing = false
                    self.pairingCode = nil
                    self.endBackgroundLease()
                    self.clearPairingNotification()
                }
            }
            do {
                // The code is needed while Settings is foregrounded on this very
                // phone. A local banner is ephemeral; it is never in our report.
                notificationsAvailable = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert])) ?? false
                guard !Task.isCancelled else { return }
                for try await event in client.pair(PairingRequest()) {
                    guard !Task.isCancelled, evidence.generation == generation else { return }
                    switch event {
                    case .advertising:
                        message = "Pairing is discoverable. Open Developer Mode in Settings on this iPhone."
                    case .waitingForCodeEntry(let code):
                        pairingCode = code.displayValue
                        await showPairingNotification(code.displayValue)
                    case .saving:
                        pairingCode = nil
                        message = "Saving the pairing in this app’s Keychain…"
                        clearPairingNotification()
                    case .paired(let device):
                        // Keep current discovery results: pairedDevices() only
                        // returns saved records with unavailable reachability.
                        if !devices.contains(where: { $0.id == device.id }) {
                            devices.append(device)
                        }
                        message = "Pairing saved. Return here and connect to this iPhone."
                    }
                }
            } catch {
                if !Task.isCancelled, evidence.generation == generation { fail(error) }
            }
        }
    }

    /// Discovery is owned by the model, not the view task or report sheet.
    func startDiscovery() {
        guard initialized, let client, !availability.isRunning else { return }
        discoveryStoppedByUser = false
        discoveryActive = true
        discoveryStarts += 1
        discoveryEndReason = nil
        discoveryMessage = "Searching for paired devices…"
        availability.start(source: { client.availability() }, onValue: { [weak self] snapshot in
            guard let self else { return }
            self.devices = snapshot
            self.discoverySnapshots += 1
            self.discoveryMessage = snapshot.contains(where: { $0.reachability == .reachable })
                ? "A paired device is reachable." : "Searching for paired devices…"
        }, onEnd: { [weak self] reason in
            guard let self else { return }
            self.discoveryActive = false
            self.discoveryEndReason = reason
            self.devices = self.devices.map { device in
                var copy = device
                copy.reachability = .unavailable
                return copy
            }
            self.discoveryMessage = reason == .cancelled
                ? "Discovery cancelled. Tap Retry discovery to start it again."
                : "Discovery ended. Tap View report for transport details, or Retry discovery."
            Task { [weak self] in await self?.refreshDiagnostics() }
        })
    }

    func refreshDiagnostics() async {
        await refreshRouteDiagnostics()
        if let nativeGeneration {
            mediaFailures = MediaFailureProbe.shared.snapshot(generation: nativeGeneration)
            decoderConfigurations = MediaFailureProbe.shared.decoderConfigurations(generation: nativeGeneration)
        }
        guard let diagnosticsRecorder else { return }
        let snapshot = await diagnosticsRecorder.snapshot()
        // Export only typed event metadata, never recorder context, identifiers,
        // addresses, pairing material, or screen contents.
        transportEvents = snapshot.events.suffix(24).map {
            TransportEvent(sequence: $0.sequence, timestamp: $0.timestamp,
                stage: $0.stage, kind: $0.kind, failureCode: $0.fields.failureCode)
        }
    }

    func connect(to device: DeviceSummary, extended: Bool = false) {
        guard canStart, let client else { return }
        guard discoveryActive,
              devices.contains(where: { $0.id == device.id && $0.reachability == .reachable }) else {
            message = "Waiting for device discovery. The pairing is saved, but no reachable connection has been found yet."
            return
        }
        newRun()
        extendedRun = extended
        calculator.status = "manualSelectionMode"
        calculatorArmed = false
        connecting = true
        let generation = evidence.generation
        evidence.stage(.locating, generation: generation)
        message = "Connecting to the selected paired device…"
        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let opened = try await client.connect(device.id)
                guard !Task.isCancelled, evidence.generation == generation else {
                    await opened.disconnect()
                    return
                }
                session = opened
                nativeGeneration = SessionGeneration(rawValue: opened.id.rawValue)
                connecting = false
                evidence.connect(generation: generation)
                eventsTask = Task { [weak self] in
                    do {
                        for try await update in opened.events {
                            guard !Task.isCancelled, let self,
                                  self.evidence.generation == generation,
                                  update.generation.rawValue == opened.id.rawValue else { return }
                            self.handle(update.event, generation: generation)
                        }
                        if !Task.isCancelled, let self, self.evidence.generation == generation {
                            await self.closeSession(generation: generation)
                        }
                    } catch {
                        if !Task.isCancelled, let self, self.evidence.generation == generation {
                            self.fail(error)
                            await self.closeSession(generation: generation)
                        }
                    }
                }
                framesTask = Task { [weak self] in
                    for await frame in opened.frames {
                        guard !Task.isCancelled, let self,
                              self.evidence.generation == generation,
                              frame.metadata.generation.rawValue == opened.id.rawValue else { return }
                        self.latestFrame = frame
                        self.receivedFrameCount += 1
                        if self.backgrounded, !self.evidence.ended,
                           let startedAt = self.backgroundStartedAt {
                            let delay = ProcessInfo.processInfo.systemUptime - startedAt
                            self.backgroundFrameTimings.append(delay)
                            self.backgroundFrameTimings = Array(self.backgroundFrameTimings.suffix(45))
                            // Keep one recent image from beyond the app-switch transition.
                            // It is memory-only and never included in the exported report.
                            if delay >= 2 {
                                self.backgroundSample = frame
                                self.backgroundSampleDelay = delay
                            }
                        }
                        if self.backgrounded && self.evidence.framesReceivedInBackground == 0 {
                            self.recordLifecycle(.firstBackgroundFrame)
                        }
                        self.evidence.image(generation: generation, whileBackgrounded: self.backgrounded)
                        if self.backgrounded { self.agentRun?.receive(frame, inputReady: self.inputReady) }
                        if self.extendedRun, let result = self.agentRun?.report.runner {
                            self.continuedWork.updateAgentProgress(resolvedDecisions: result.observations.filter { $0.resolvedSeconds != nil }.count, completed: result.status == .completed)
                        }
                        await self.checkSequence(frame, generation: generation)
                        guard !Task.isCancelled, self.evidence.generation == generation else { return }
                        await self.checkSelectedTap(frame, generation: generation)
                        guard !Task.isCancelled, self.evidence.generation == generation else { return }
                        if self.extendedRun && self.continuedWork.receivedImage(selectedInputFinished:
                            self.sequenceGate.stage == .complete ||
                            (self.selectedTap.commandAccepted && self.selectedTap.afterImageReceived &&
                            (self.selectedTap.commandBackgroundSeconds ?? 0) >= 60)) {
                            self.continuedWork.finish(success: true)
                            await self.closeSession(generation: generation)
                            self.message = "Extended job completed. Inspect any after-image and View report; completion still requires your confirmation of the Calculator result."
                            return
                        }
                    }
                }
            } catch {
                if !Task.isCancelled, evidence.generation == generation {
                    connecting = false
                    fail(error)
                    if extendedRun { continuedWork.finish(success: false) }
                }
            }
        }
    }

    func runSelfTap(target: ProbeTargetControl) {
        guard !testing else { return }
        lastSelfTapBlocker = nil
        let geometry = target.measure()
        targetGeometryStatus = geometry.status
        targetVisibleAtLastAttempt = geometry.status == .valid
        guard !backgrounded else {
            blockSelfTap("backgrounded", message: "Return to cell-use before testing. No tap was sent.")
            return
        }
        guard let session else {
            blockSelfTap("noSession", message: "Connect to this iPhone first. No tap was sent.")
            return
        }
        guard inputReady else {
            blockSelfTap("inputNotReady", message: "The input channel is not ready. No tap was sent.")
            return
        }
        guard let frame = latestFrame else {
            blockSelfTap("noFrame", message: "No screen image has arrived yet. No tap was sent.")
            return
        }
        guard frame.metadata.orientation == .portrait else {
            blockSelfTap("notPortrait", message: "The captured screen is not in portrait orientation. Hold the phone upright and retry.")
            return
        }
        guard let normalizedPoint = geometry.normalizedCenter else {
            switch geometry.status {
            case .unavailable, .invalidBounds:
                blockSelfTap("targetGeometryUnavailable", message: "The target’s screen position could not be measured. No tap was sent.")
            case .occluded:
                blockSelfTap("targetOccluded", message: "Another view covers the target or it is hidden. No tap was sent.")
            case .clipped:
                blockSelfTap("targetOffscreen", message: "Scroll to the top so Test target is fully visible, then use Run self-tap beneath it.")
            case .valid: break
            }
            return
        }
        guard ProbeChecks.isFresh(receivedAt: frame.metadata.receivedAt, now: Date()) else {
            blockSelfTap("staleFrame", message: "The latest screen image is stale. No tap was sent. View report includes its age and the frame count.")
            return
        }
        testing = true
        let generation = evidence.generation
        let expectedChallenge = challenge
        evidence.stage(.verifyingSelfScreen, generation: generation)
        message = "Checking the random marker in the captured screen. Keep your hands off the test target."
        probeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.evidence.generation == generation {
                    self.testing = false
                    self.pendingTargetActivation = false
                    self.probeDeadline = nil
                }
            }
            do {
                let matches = try await Self.recognizeChallenge(frame, expected: expectedChallenge)
                guard !Task.isCancelled, evidence.generation == generation else { return }
                guard matches else {
                    blockSelfTap("markerNotFound", message: "The captured image does not contain this run’s marker. No tap was sent.")
                    return
                }
                guard !backgrounded, inputReady else {
                    blockSelfTap("readinessChanged", message: "The app or input channel became unavailable during verification. No tap was sent.")
                    return
                }
                guard ProbeChecks.isFresh(receivedAt: frame.metadata.receivedAt, now: Date()) else {
                    blockSelfTap("frameExpiredDuringOCR", message: "The screen image expired during marker verification. No tap was sent.")
                    return
                }
                let currentGeometry = target.measure()
                targetGeometryStatus = currentGeometry.status
                targetVisibleAtLastAttempt = currentGeometry.status == .valid
                guard currentGeometry == geometry else {
                    blockSelfTap("targetMovedDuringOCR", message: "The target moved or became unavailable during verification. No tap was sent.")
                    return
                }
                evidence.verifySelfScreen(generation: generation)
                guard evidence.submitInput(generation: generation) else { return }
                let point = TargetPixelPoint(
                    x: Double(normalizedPoint.x) * Double(frame.image.width),
                    y: Double(normalizedPoint.y) * Double(frame.image.height))
                pendingTargetActivation = true
                probeDeadline = Date().addingTimeInterval(3)
                try await session.command(.tap(point))
                guard !Task.isCancelled, evidence.generation == generation else { return }
                try await Task.sleep(for: .seconds(2))
                if !evidence.targetActivated {
                    message = "Input was submitted, but the target did not activate. This is not a pass."
                }
            } catch {
                if !Task.isCancelled, evidence.generation == generation { fail(error) }
            }
        }
    }

    private func blockSelfTap(_ code: String, message: String) {
        lastSelfTapBlocker = code
        self.message = message
    }

    func testTargetActivated() {
        guard pendingTargetActivation, let deadline = probeDeadline, Date() <= deadline else {
            message = "Manual target press. Use Run self-tap to test the automation connection."
            return
        }
        pendingTargetActivation = false
        evidence.receiveTargetActivation(generation: evidence.generation)
        message = "Target activation observed after the submitted tap. Same-app probe passed; cross-app control is still untested."
    }

    func sceneChanged(isBackground: Bool) {
        let returnedFromBackground = backgrounded && !isBackground
        if backgrounded != isBackground {
            backgrounded = isBackground
            backgroundStartedAt = isBackground ? ProcessInfo.processInfo.systemUptime : nil
            recordLifecycle(isBackground ? .enteredBackground : .enteredForeground)
        }
        backgrounded = isBackground
        if isBackground, hasSession || pairing || connecting {
            if let started = backgroundStartedAt { agentRun?.beginBackground(at: started) }
            evidence.stage(.background, generation: evidence.generation)
            if !extendedRun || !continuedWork.running { beginBackgroundLease() }
        } else if !isBackground {
            if returnedFromBackground { agentRun?.cancel("returnedToForeground") }
            if returnedFromBackground { stopSequence("returnedToForegroundBeforeCompletion") }
            if returnedFromBackground, selectedGate.armed { disarmSelectedTap(status: "returnedBeforeTap") }
            if calculator.commandSubmitted && !calculator.resultVerified { calculator.status = "returnedBeforeVerification" }
            endBackgroundLease()
            if !discoveryStoppedByUser { startDiscovery() }
        }
    }

    func stop() async {
        agentRun?.cancel("stoppedByUser", notify: false)
        stopSequence("stoppedByUser")
        disarmSelectedTap(status: "stopped")
        calculatorArmed = false
        continuedWork.finish(success: false)
        closing = true
        discoveryStoppedByUser = true
        await availability.stop()
        let generation = evidence.generation
        pairingTask?.cancel()
        connectTask?.cancel()
        probeTask?.cancel()
        eventsTask?.cancel()
        framesTask?.cancel()
        pairing = false
        connecting = false
        testing = false
        pendingTargetActivation = false
        pairingCode = nil
        clearPairingNotification()
        evidence.finish(generation: generation, cancelled: true)
        await closeSession(generation: generation)
        message = "Stopped. Saved evidence describes only the stages actually observed."
    }

    var report: String {
        struct Report: Encodable {
            let schema = 20
            let build = "20"
            let runtime = "device-hub-ios@1fcdfb0a6799b62f05625d0cbb359bec57256b94+probe-png-input-v2"
            let observationMode = "pngWithTapInput"
            let screenshotWindowSeconds = 900
            let extendedRun: Bool
            let continuedWork: ContinuedWork.Snapshot
            let calculator: CalculatorEvidence
            let selectedTap: SelectedTapEvidence
            let sequence: SequenceEvidence
            let agentRun: OnDeviceAgentRun.Report?
            let backgroundObservationBeyond60Seconds: Bool
            let osVersion: String
            let evidence: ProbeEvidence
            let failure: DeviceHubError?
            let discoveryActive: Bool
            let discoveryStarts: Int
            let discoverySnapshots: Int
            let discoveryEndReason: AvailabilityObserver<[DeviceSummary]>.EndReason?
            let backgrounded: Bool
            let initialized: Bool
            let transportEvents: [TransportEvent]
            let mediaFailures: [MediaFailureProbe.Event]
            let backgroundFrameTimings: [Double]
            let backgroundSampleDelay: Double?
            let decoderConfigurations: [MediaFailureProbe.DecoderConfiguration]
            let lifecycleEvents: [LifecycleEvent]
            let route: RouteDiagnostics.Snapshot
            let pairedDeviceCount: Int
            let reachableDeviceCount: Int
            let inputReady: Bool
            let receivedFrameCount: Int
            let latestFrameAgeSeconds: Double?
            let latestFrameOrientation: ScreenOrientation?
            let lastSelfTapBlocker: String?
            let targetVisibleAtLastAttempt: Bool?
            let targetGeometryStatus: ProbeTargetGeometry.Status?
            let latestFrameKind: ScreenMetadata.Kind?
            let crossAppControlTested: Bool
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = Report(extendedRun: extendedRun, continuedWork: continuedWork.snapshot,
            calculator: calculator, selectedTap: selectedTap, sequence: sequence, agentRun: agentRun?.report, backgroundObservationBeyond60Seconds: backgroundFrameTimings.contains { $0 >= 60 },
            osVersion: UIDevice.current.systemVersion, evidence: evidence, failure: lastFailure,
            discoveryActive: discoveryActive, discoveryStarts: discoveryStarts,
            discoverySnapshots: discoverySnapshots, discoveryEndReason: discoveryEndReason,
            backgrounded: backgrounded, initialized: initialized, transportEvents: transportEvents,
            mediaFailures: mediaFailures, backgroundFrameTimings: backgroundFrameTimings,
            backgroundSampleDelay: backgroundSampleDelay,
            decoderConfigurations: decoderConfigurations, lifecycleEvents: lifecycleEvents,
            route: routeSnapshot,
            pairedDeviceCount: devices.count,
            reachableDeviceCount: devices.filter { $0.reachability == .reachable }.count,
            inputReady: inputReady, receivedFrameCount: receivedFrameCount,
            latestFrameAgeSeconds: latestFrame.map { Date().timeIntervalSince($0.metadata.receivedAt) },
            latestFrameOrientation: latestFrame?.metadata.orientation,
            lastSelfTapBlocker: lastSelfTapBlocker,
            targetVisibleAtLastAttempt: targetVisibleAtLastAttempt,
            targetGeometryStatus: targetGeometryStatus, latestFrameKind: latestFrame?.metadata.kind,
            crossAppControlTested: (agentRun?.report.runner.inputs.isEmpty == false) || sequence.actions.contains(where: { $0.commandAttempted }) || selectedTap.commandAttempted || calculator.commandSubmitted)
        return (try? String(decoding: encoder.encode(payload), as: UTF8.self)) ?? "Report encoding failed"
    }

    private func newRun() {
        agentRun?.cancel("replacedByNewRun", notify: false)
        agentRun = nil
        evidence = ProbeEvidence()
        runStartedAt = ProcessInfo.processInfo.systemUptime
        nativeGeneration = nil
        mediaFailures = []
        decoderConfigurations = []
        lifecycleEvents = []
        latestFrame = nil
        backgroundSample = nil
        backgroundSampleDelay = nil
        backgroundFrameTimings = []
        backgroundStartedAt = nil
        receivedFrameCount = 0
        calculator = CalculatorEvidence()
        sequence = SequenceEvidence()
        sequenceGate = SelectedSequenceGate(mode: .transportOnly)
        sequenceAcceptedAt = nil
        sequenceBackgroundEntry = nil
        sequenceIntermediate = nil
        sequenceResult = nil
        selectedTap = SelectedTapEvidence()
        selectedTap.targetSelected = selectedSignature != nil
        selectedGate = SelectedTapGate()
        selectedAcceptedAt = nil
        selectedBackgroundEntry = nil
        selectedResult = nil
        calculatorSentAt = nil
        calculatorZeroLayout = nil
        calculatorArmed = false
        lastSelfTapBlocker = nil
        targetVisibleAtLastAttempt = nil
        targetGeometryStatus = nil
        inputReady = false
        lastFailure = nil
        challenge = Self.newChallenge()
    }

    private func handle(_ event: DeviceSessionEvent, generation: UUID) {
        switch event {
        case .phaseChanged(let phase):
            evidence.stage(ProbeEvidence.Stage(rawValue: phase.rawValue) ?? .locating, generation: generation)
            message = phase.title
        case .hidReadinessChanged(let readiness):
            inputReady = readiness == .ready
            agentRun?.updateInputReadiness(inputReady)
        case .ended(let error):
            agentRun?.cancel("sessionEnded", notify: false)
            stopSequence("sessionEndedBeforeCompletion")
            if selectedGate.armed { disarmSelectedTap(status: "sessionEndedBeforeTap") }
            if extendedRun && continuedWork.running { continuedWork.finish(success: false) }
            if let error { fail(error) }
            else if !evidence.backgroundLeaseExpired {
                message = "Screenshot experiment ended. Check the background sample and View report."
            }
            evidence.finish(generation: generation, cancelled: false)
            inputReady = false
        default: break
        }
    }

    private func fail(_ error: Error) {
        recordLifecycle(.sessionFailed)
        lastFailure = error as? DeviceHubError
        evidence.stage(.failed, generation: evidence.generation)
        if let error = lastFailure {
            if case .decoderFailed = error {
                message = "The screen stream stopped. Open View report for the media failure details, then reconnect to retry."
            } else {
                message = "\(error.userFacing.title). \(error.userFacing.message)"
            }
        } else {
            message = "The probe failed at this stage. No completion is assumed."
        }
    }

    private func closeSession(generation: UUID) async {
        guard evidence.generation == generation else { return }
        agentRun?.cancel("sessionEnded", notify: false)
        stopSequence("sessionEndedBeforeCompletion")
        if selectedGate.armed { disarmSelectedTap(status: "sessionEndedBeforeTap") }
        recordLifecycle(.sessionEnded)
        if extendedRun && (continuedWork.running || continuedWork.pending) { continuedWork.finish(success: false) }
        closing = true
        inputReady = false
        let oldSession = session
        session = nil
        framesTask?.cancel()
        endBackgroundLease()
        if let oldSession { await oldSession.disconnect() }
        // Avoid changing a new run while old transport teardown was awaiting.
        if evidence.generation == generation {
            evidence.finish(generation: generation, cancelled: false)
            closing = false
        }
    }

    private func beginBackgroundLease() {
        guard backgroundLease == .invalid else { return }
        let generation = evidence.generation
        backgroundLease = UIApplication.shared.beginBackgroundTask(withName: "PhoneProbe") { [weak self] in
            Task { @MainActor in
                guard let self, self.evidence.generation == generation else { return }
                self.recordLifecycle(.backgroundLeaseExpired)
                self.evidence.expireBackgroundLease(generation: generation)
                self.pairingTask?.cancel()
                self.connectTask?.cancel()
                self.probeTask?.cancel()
                self.eventsTask?.cancel()
                self.framesTask?.cancel()
                self.endBackgroundLease()
                await self.closeSession(generation: generation)
                self.message = "iOS ended the background allowance. Persistent execution has not been established."
            }
        }
        recordLifecycle(.backgroundLeaseStarted)
    }

    private func recordLifecycle(_ kind: LifecycleEvent.Kind) {
        let remaining = UIApplication.shared.backgroundTimeRemaining
        lifecycleEvents.append(LifecycleEvent(kind: kind,
            elapsedSeconds: ProcessInfo.processInfo.systemUptime - runStartedAt,
            backgrounded: backgrounded, receivedFrames: receivedFrameCount,
            backgroundSecondsRemaining: remaining.isFinite && remaining >= 0 && remaining < 86400
                ? remaining : nil))
        lifecycleEvents = Array(lifecycleEvents.suffix(24))
    }

    private func endBackgroundLease() {
        guard backgroundLease != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundLease)
        backgroundLease = .invalid
    }

    private func showPairingNotification(_ code: String) async {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "cell-use pairing code"
        content.body = code
        let request = UNNotificationRequest(identifier: "phone-probe-pairing", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func clearPairingNotification() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["phone-probe-pairing"])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["phone-probe-pairing"])
    }

    private static func newChallenge() -> String {
        "PROBE" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
    }

    nonisolated private static func recognizeChallenge(_ frame: RemoteDisplayFrame, expected: String) async throws -> Bool {
        try await Task.detached {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: frame.image).perform([request])
            let observations = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return ProbeChecks.containsChallenge(observations, challenge: expected)
        }.value
    }

    func selectTarget(frame: RemoteDisplayFrame, x: Double, y: Double) {
        guard !backgrounded, agentRun == nil, !sequenceGate.active, frame.metadata.orientation == .portrait,
              x.isFinite, y.isFinite, (0.03...0.75).contains(x), (0.42...0.90).contains(y),
              let signature = ScreenMatch.signature(frame.image),
              ScreenMatch.compare(signature, signature).matches else {
            message = "Select the center of 7 in a clear portrait Calculator image."
            return
        }
        disarmSelectedTap(status: "targetSelected")
        selectedReference = frame
        selectedPoint = CGPoint(x: x, y: y)
        selectedSignature = signature
        selectedTap.targetSelected = true
        message = "Target saved. Arm two taps, then open Calculator at 0 for 15 seconds."
    }

    func armSelectedTap() {
        guard canArmSelectedTap else { message = selectedTapHint; return }
        let timing: SelectedTapGate.Timing = extendedRun ? .after60Seconds : .immediate
        if extendedRun && !continuedWork.requireSelectedInput() { message = "Extended work is no longer running. Start a new run."; return }
        guard selectedGate.arm(generation: evidence.generation, timing: timing) else { return }
        selectedTap.minimumBackgroundSeconds = timing.earliest
        selectedTap.armed = true
        selectedTap.matchingFrames = 0
        selectedTap.status = "armedReturnToCalculator"
        message = extendedRun ? "Armed for one tap after 60 background seconds. Open Calculator at 0 now and leave it untouched for 90 seconds." : "Armed for one tap. Open the same Calculator screen at 0 and leave it untouched for 15 seconds."
    }

    func confirmSelectedResult() {
        guard selectedTap.commandAccepted, selectedTap.afterImageReceived else { return }
        selectedTap.userConfirmedZeroToSeven = true
        selectedTap.status = "userConfirmedZeroToSeven"
    }

    private func disarmSelectedTap(status: String) {
        selectedGate.disarm()
        selectedTap.armed = false
        if !selectedTap.commandAttempted { selectedTap.status = status }
    }

    private func checkSelectedTap(_ frame: RemoteDisplayFrame, generation: UUID) async {
        guard sequenceGate.stage == .idle, backgrounded, !evidence.ended, (!extendedRun || continuedWork.running),
              generation == evidence.generation, let reference = selectedSignature,
              let point = selectedPoint, let began = backgroundStartedAt else { return }
        let fresh = ProbeChecks.isFresh(receivedAt: frame.metadata.receivedAt, now: Date())
        let portrait = frame.metadata.orientation == .portrait
        if selectedTap.commandAttempted {
            if selectedTap.commandAccepted, !selectedTap.afterImageReceived, selectedBackgroundEntry == began,
               fresh, portrait, let accepted = selectedAcceptedAt,
               frame.metadata.receivedAt.timeIntervalSince(accepted) >= 1 {
                selectedResult = frame
                selectedTap.afterImageReceived = true
                selectedTap.afterImageBackgroundSeconds = ProcessInfo.processInfo.systemUptime - began
                if let image = ScreenMatch.signature(frame.image) {
                    selectedTap.afterImageChanged = !ScreenMatch.compare(reference, image).matches
                }
                if !selectedTap.userConfirmedZeroToSeven { selectedTap.status = "inspectAfterImage" }
            }
            return
        }
        guard selectedGate.armed else { return }
        let delay = ProcessInfo.processInfo.systemUptime - began
        if delay > selectedGate.timing.deadline {
            disarmSelectedTap(status: "matchingScreenTimedOut")
            if extendedRun { await closeSession(generation: generation) }
            return
        }
        let comparison = ScreenMatch.signature(frame.image).map { ScreenMatch.compare(reference, $0) }
        selectedTap.comparison = comparison
        let eligible = fresh && portrait && inputReady
        let submit = selectedGate.observe(generation: generation, eligible: eligible, matches: comparison?.matches == true, backgroundSeconds: delay)
        selectedTap.matchingFrames = selectedGate.matchingFrames
        selectedTap.status = delay < selectedGate.timing.earliest ? "waitingForMinimumBackgroundTime" :
            (eligible ? (comparison?.matches == true ? "matchingReference" : "screenDoesNotMatchReference") : "waitingForFreshInputReadyFrame")
        guard submit, let session else { return }
        // Mark the attempt before awaiting transport; never retry uncertain delivery.
        selectedTap.armed = false
        selectedTap.commandAttempted = true
        selectedTap.commandBackgroundSeconds = ProcessInfo.processInfo.systemUptime - began
        selectedTap.status = "sendingSelectedTap"
        selectedBackgroundEntry = began
        do {
            try await session.command(.tap(TargetPixelPoint(x: point.x * Double(frame.image.width),
                                                           y: point.y * Double(frame.image.height))))
            guard !Task.isCancelled, evidence.generation == generation else { return }
            selectedAcceptedAt = Date()
            selectedTap.commandAccepted = true
            selectedTap.status = "tapAcceptedAwaitingImage"
        } catch {
            if evidence.generation == generation { selectedTap.status = "commandFailedNoRetry" }
        }
    }

    func armSequence() {
        guard canArmSequence else { message = sequenceHint; return }
        guard sequenceGate.arm(generation: evidence.generation) else { return }
        syncSequence()
        message = "Armed for two taps at the selected 7 key. Open Calculator at 0 now and leave it untouched for 15 seconds."
    }

    func confirmSequenceResult() {
        guard sequenceGate.stage == .complete, sequence.finalImageReceived,
              sequence.actions.allSatisfy({ $0.commandAccepted }), sequence.intermediateImageReceived else { return }
        sequence.userConfirmedZeroSevenSeventySeven = true
        sequence.status = "userConfirmedZeroSevenSeventySeven"
    }

    private func syncSequence() {
        if !sequence.userConfirmedZeroSevenSeventySeven { sequence.status = sequenceGate.stage.rawValue }
        sequence.consecutiveFreshFrames = sequenceGate.matchingFrames
        sequence.stopReason = sequenceGate.stopReason
    }

    private func stopSequence(_ reason: String) {
        guard sequenceGate.active else { return }
        sequenceGate.stop(reason)
        syncSequence()
    }

    private func checkSequence(_ frame: RemoteDisplayFrame, generation: UUID) async {
        guard sequenceGate.active, backgrounded, !evidence.ended, !extendedRun,
              generation == evidence.generation, let reference = selectedReference,
              let point = selectedPoint, let began = backgroundStartedAt else { return }
        if let entry = sequenceBackgroundEntry, entry != began { stopSequence("backgroundVisitChanged"); return }
        sequenceBackgroundEntry = began
        let now = Date()
        let delay = ProcessInfo.processInfo.systemUptime - began
        let decision = sequenceGate.observe(generation: generation, backgroundSeconds: delay,
            frameTimestamp: frame.metadata.receivedAt.timeIntervalSinceReferenceDate,
            eligible: ProbeChecks.isFresh(receivedAt: frame.metadata.receivedAt, now: now) &&
                frame.metadata.orientation == .portrait && inputReady &&
                frame.image.width == reference.image.width && frame.image.height == reference.image.height,
            afterAcceptance: sequenceAcceptedAt.map { frame.metadata.receivedAt.timeIntervalSince($0) >= 1 } ?? false,
            matchesZero: false, matchesSeven: false)
        syncSequence()
        if sequenceGate.stage == .stopped {
            await closeSession(generation: generation)
            return
        }
        switch decision {
        case .none: return
        case .captureFinalImage:
            sequenceResult = frame
            sequence.finalImageReceived = true
            sequence.actions[1].afterImageBackgroundSeconds = delay
            await closeSession(generation: generation)
            message = "Two taps accepted and both after-images captured. Inspect them and confirm whether Calculator reached 77."
        case .tap(let step):
            guard let session else { stopSequence("sessionUnavailable"); return }
            if step == 2 {
                sequenceIntermediate = frame
                sequence.intermediateImageReceived = true
                sequence.actions[0].afterImageBackgroundSeconds = delay
            }
            let index = step - 1
            sequence.actions[index].freshFramesBeforeCommand = sequenceGate.matchingFrames
            sequence.actions[index].commandAttempted = true
            sequence.actions[index].commandBackgroundSeconds = ProcessInfo.processInfo.systemUptime - began
            do {
                try await session.command(.tap(TargetPixelPoint(x: point.x * Double(frame.image.width),
                                                               y: point.y * Double(frame.image.height))))
                guard !Task.isCancelled, evidence.generation == generation else { return }
                let acceptedDelay = ProcessInfo.processInfo.systemUptime - began
                sequence.actions[index].commandAccepted = true
                sequence.actions[index].acceptedBackgroundSeconds = acceptedDelay
                sequenceAcceptedAt = Date()
                if !backgrounded || backgroundStartedAt != began { stopSequence("returnedDuringDelivery") }
                sequenceGate.acknowledge(generation: generation, step: step, accepted: true, backgroundSeconds: acceptedDelay)
            } catch {
                guard evidence.generation == generation else { return }
                sequenceGate.acknowledge(generation: generation, step: step, accepted: false,
                                         backgroundSeconds: ProcessInfo.processInfo.systemUptime - began)
            }
            syncSequence()
            if sequenceGate.stage == .stopped { await closeSession(generation: generation) }
        }
    }

    private func checkCalculator(_ frame: RemoteDisplayFrame, generation: UUID) async {
        guard calculatorArmed, (!extendedRun || continuedWork.running),
              backgrounded, inputReady, !evidence.ended,
              !calculator.resultVerified, let began = backgroundStartedAt,
              ProcessInfo.processInfo.systemUptime - began >= 3,
              frame.metadata.orientation == .portrait else { return }
        if let sent = calculatorSentAt, Date().timeIntervalSince(sent) > 12 {
            calculator.status = "resultNotVerified"
            return
        }
        do {
            let recognitionStarted = ProcessInfo.processInfo.systemUptime
            let reading = try await Task.detached {
                try CalculatorOCR.read(frame.image)
            }.value
            guard !Task.isCancelled, evidence.generation == generation, backgrounded,
                  calculatorArmed, (!extendedRun || continuedWork.running), !evidence.ended, inputReady else { return }
            calculator.recognition = reading.diagnostics
            calculator.recognitionDurationSeconds = ProcessInfo.processInfo.systemUptime - recognitionStarted
            guard ProbeChecks.isFresh(receivedAt: frame.metadata.receivedAt, now: Date()) else {
                calculator.staleRecognitionFrames += 1
                calculator.matchingZeroFrames = 0
                calculatorZeroLayout = nil
                if !calculator.commandSubmitted { calculator.status = "frameExpiredDuringRecognition" }
                return
            }
            guard let layout = reading.screen else {
                calculator.matchingZeroFrames = 0
                calculatorZeroLayout = nil
                if !calculator.commandSubmitted { calculator.status = "calculatorLayoutNotRecognized" }
                return
            }
            if calculator.commandSubmitted {
                if let sent = calculatorSentAt, frame.metadata.receivedAt > sent, layout.display == "7" {
                    calculator.resultVerified = true
                    calculator.status = "verifiedZeroToSeven"
                    calculator.verificationDelay = ProcessInfo.processInfo.systemUptime - began
                }
                return
            }
            guard layout.display == "0", let session else {
                calculator.status = "calculatorMustShowZero"
                calculator.matchingZeroFrames = 0
                calculatorZeroLayout = nil
                return
            }
            if let previous = calculatorZeroLayout,
               abs(previous.sevenX - layout.sevenX) < 0.015,
               abs(previous.sevenY - layout.sevenY) < 0.015 {
                calculator.matchingZeroFrames += 1
            } else { calculator.matchingZeroFrames = 1 }
            calculatorZeroLayout = layout
            guard calculator.matchingZeroFrames >= 2 else { return }
            // One semantic tap, once per connection. Never retry on ambiguous delivery.
            calculator.commandSubmitted = true
            calculator.status = "tapSubmitted"
            calculator.commandDelay = ProcessInfo.processInfo.systemUptime - began
            calculatorSentAt = Date()
            try await session.command(.tap(TargetPixelPoint(
                x: layout.sevenX * Double(frame.image.width),
                y: layout.sevenY * Double(frame.image.height))))
        } catch {
            if evidence.generation == generation {
                calculator.status = calculator.commandSubmitted ? "commandFailed" : "recognitionFailed"
                if let failure = error as? CalculatorOCR.Failure {
                    calculator.recognitionErrorStage = failure.stage
                    calculator.recognitionErrorCode = failure.code
                }
            }
        }
    }

}
