import CellUse
import CellUseRuntime
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
import PlaylistMoveCore
import UIKit
import UserNotifications

@MainActor @Observable
final class PlaylistMoveModel {
    var source = "Late Night"
    var destination = "Late Night Move"
    var trackLimit = 1
    var playlistLink = ""
    var peer = "10.7.0.1"
    private(set) var devices: [DeviceSummary] = []
    private(set) var message = "Preparing the connection"
    private(set) var pairingCode: String?
    private(set) var pairing = false
    private(set) var connecting = false
    private(set) var connected = false
    private(set) var inputReady = false
    private(set) var running = false
    private(set) var armed = false
    private(set) var report: MoveReport?
    private(set) var reportURL: URL?
    private(set) var latestImage: UIImage?
    private(set) var modelIssue: String?
    @ObservationIgnored private var client: DeviceHubClient?
    @ObservationIgnored private var session: DeviceSession?
    @ObservationIgnored private var runtime: CellUseRuntime?
    @ObservationIgnored private var agent: LocalPlaylistAgent?
    @ObservationIgnored private var events: Task<Void, Never>?
    @ObservationIgnored private var frames: Task<Void, Never>?
    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private let availability = AvailabilityObserver<[DeviceSummary]>()
    @ObservationIgnored private let work = TransferWork()
    @ObservationIgnored private var lease: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var backgrounded = false
    @ObservationIgnored private var epoch = UUID()

    var busy: Bool { pairing || connecting || running || armed || work.active }
    var canRun: Bool { connected && inputReady && !busy && modelIssue == nil }

    func prepare() async {
        guard client == nil else { modelIssue = LocalPlaylistAgent.availability; return }
        modelIssue = LocalPlaylistAgent.availability
        do {
            let route = try ConnectionRoute(mode: .localVPN, peer: peer)
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let diagnostics = try DeviceHubDiagnosticsRuntime.live(applicationSupportDirectory: directory)
            let native = RoutedNativeClient.wrap(try NativeSessionClient.deviceHubLive(probeScreenshots: true),
                route: route, diagnostics: RouteDiagnostics(mode: route.mode))
            let config = try DeviceHubTransportConfiguration(controllerDisplayName: "Playlist Move", controllerModel: "Mac17,7", remoteTargetPolicy: .authenticatedDevices)
            let persistence = PairingPersistenceClient.live(descriptor: .pairingVault(service: "\(Bundle.main.bundleIdentifier ?? "PlaylistMove").pairing"))
            let ready = DeviceHubClient.live(nativeSessions: native, configuration: config,
                diagnostics: diagnostics.recorder, pairingPersistence: persistence)
            client = ready
            devices = try await ready.pairedDevices()
            availability.start(source: { ready.availability() }, onValue: { [weak self] devices in
                self?.devices = devices
            }, onEnd: { [weak self] _ in
                guard let self, !self.running else { return }
                self.message = "Discovery ended. Reconnect to refresh it."
            })
            message = "Keep the local tunnel enabled. Pair once, then connect to this iPhone."
        } catch { message = error.localizedDescription }
    }

    func refreshConnection() async {
        guard !busy else { return }
        await disconnect()
        await availability.stop()
        client = nil
        await prepare()
    }

    func pair() {
        guard !busy, !connected, let client else { return }
        pairing = true
        message = "In Settings, open Privacy & Security, Developer Mode, then Playlist Move."
        pairingTask = Task { [weak self] in
            guard let self else { return }
            defer { self.pairing = false; self.pairingCode = nil; self.endLease() }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            do {
                for try await event in client.pair(PairingRequest()) {
                    try Task.checkCancellation()
                    switch event {
                    case .waitingForCodeEntry(let code):
                        self.pairingCode = code.displayValue
                        let content = UNMutableNotificationContent()
                        content.title = "Playlist Move pairing code"; content.body = code.displayValue
                        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "move-pairing", content: content, trigger: nil))
                    case .paired(let device):
                        if !self.devices.contains(where: { $0.id == device.id }) { self.devices.append(device) }
                        self.message = "Paired. Return to Playlist Move and connect."
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["move-pairing"])
                    default: break
                    }
                }
            } catch { if !Task.isCancelled { self.message = error.localizedDescription } }
        }
    }

    func connect(_ device: DeviceSummary) {
        guard !busy, !connected, let client else { return }
        connecting = true
        let token = UUID(); epoch = token
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let opened = try await client.connect(device.id)
                guard !Task.isCancelled, self.epoch == token else { await opened.disconnect(); return }
                self.session = opened; self.connecting = false; self.connected = true
                self.message = "Connected. Open the Spotify playlist, then return here to start."
                self.events = Task { [weak self] in
                    do {
                        for try await update in opened.events {
                            guard let self, !Task.isCancelled, self.epoch == token else { return }
                            switch update.event {
                            case .hidReadinessChanged(let readiness):
                                self.inputReady = readiness == .ready
                                self.runtime?.updateInputReadiness(self.inputReady)
                            case .ended(let error):
                                self.stop(reason: error.map { String(describing: $0) } ?? "Connection ended")
                            default: break
                            }
                        }
                    } catch { if !Task.isCancelled { self?.stop(reason: error.localizedDescription) } }
                }
                self.frames = Task { [weak self] in
                    for await frame in opened.frames {
                        guard let self, !Task.isCancelled, self.epoch == token else { return }
                        self.latestImage = UIImage(cgImage: frame.image)
                        if self.running && self.backgrounded {
                            self.work.sawFrame()
                            self.runtime?.receive(frame, inputReady: self.inputReady)
                        }
                    }
                    if !Task.isCancelled { self?.stop(reason: "Screen stream ended") }
                }
            } catch {
                guard self.epoch == token else { return }
                self.connecting = false; self.message = error.localizedDescription
            }
        }
    }

    func arm() {
        guard canRun, let session else { return }
        do {
            let launchURL = try SpotifyLaunch.url(playlistLink: playlistLink)
            guard UIApplication.shared.canOpenURL(launchURL) else {
                message = "Install Spotify and sign in before starting a transfer."
                return
            }
            let ledger = try TransferLedger(source: source, destination: destination, limit: trackLimit)
            let provider = LocalPlaylistAgent(ledger: ledger)
            let id = session.id.rawValue
            var config = PhoneActionRunner.Configuration()
            config.maximumTaps = 100; config.maximumInputs = 100; config.maximumDecisions = 120
            config.runTimeout = 600; config.decisionTimeout = 35; config.deliveryTimeout = 8
            config.maximumDecisionFrameAge = 40; config.frameTimeout = 10; config.initialDelay = 4
            let runner = CellUseRuntime(runID: id, session: session, agent: provider, configuration: config)
            agent = provider; runtime = runner; report = provider.report
            reportURL = nil
            provider.onChange = { [weak self] update in
                guard let self else { return }
                var update = update; update.runner = self.runtime?.snapshot
                self.report = update
                self.message = update.events.last?.note ?? "Reading the playlist"
                self.work.resolvedDecisions(update.events.count)
                self.saveReport()
            }
            runner.onUpdate = { [weak self] snapshot in self?.report?.runner = snapshot }
            runner.onEnded = { [weak self] in self?.finishRun() }
            work.submit(start: { [weak self] in
                guard let self else { return }
                self.armed = true
                self.message = "Opening Spotify. The transfer begins after four seconds."
                UIApplication.shared.open(launchURL, options: [:]) { [weak self] opened in
                    Task { @MainActor in
                        guard let self, self.runtime?.snapshot.runID == id,
                              self.armed || self.running else { return }
                        if !opened { self.stop(reason: "Couldn't open Spotify. Check that it is installed, then reconnect.") }
                    }
                }
            }, expire: { [weak self] reason in self?.stop(reason: reason) })
        } catch RequestError.invalidPlaylistLink {
            message = "Use a full open.spotify.com/playlist/ link, or leave the link empty."
        } catch { message = "Check playlist names. Destination must be 1 to 32 English keyboard characters." }
    }

    func sceneChanged(background: Bool) {
        backgrounded = background
        if background, pairing, lease == .invalid {
            lease = UIApplication.shared.beginBackgroundTask(withName: "Playlist pairing") { [weak self] in
                Task { @MainActor in self?.pairingTask?.cancel(); self?.endLease() }
            }
        }
        if background, armed {
            armed = false; running = true; runtime?.start()
        } else if !background {
            modelIssue = LocalPlaylistAgent.availability
            endLease()
            if running { stop(reason: "Paused when you returned to Playlist Move") }
        }
    }

    func stop(reason: String = "Stopped by you") {
        armed = false; running = false
        runtime?.cancel(reason, notify: false)
        report?.runner = runtime?.snapshot
        if report?.ledger.phase != .completed { report?.ledger.stop(reason) }
        message = reason; work.finish(success: false)
        pairingTask?.cancel(); endLease(); saveReport()
        Task { await disconnect() }
    }

    private func finishRun() {
        let successful = report?.ledger.phase == .completed && runtime?.snapshot.status == .completed
        armed = false; running = false
        report?.runner = runtime?.snapshot
        if !successful, report?.ledger.phase != .stopped { report?.ledger.stop(runtime?.snapshot.stopReason ?? "Run ended before playlist verification") }
        message = successful ? "Playlist copied and checked in Apple Music." : report?.ledger.stopReason ?? "Transfer stopped"
        work.finish(success: successful); saveReport()
        Task { await disconnect() }
    }

    private func disconnect() async {
        epoch = UUID(); connectionTask?.cancel(); events?.cancel(); frames?.cancel()
        let old = session; session = nil
        connected = false; inputReady = false; connecting = false
        if let old { await old.disconnect() }
    }
    private func endLease() {
        if lease != .invalid { UIApplication.shared.endBackgroundTask(lease); lease = .invalid }
    }
    private func saveReport() {
        guard let report else { return }
        do {
            let dir = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = reportURL ?? dir.appendingPathComponent("playlist-move-\(UUID().uuidString).json")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            reportURL = url
        } catch { /* The in-memory report remains available for the current run. */ }
    }
}
