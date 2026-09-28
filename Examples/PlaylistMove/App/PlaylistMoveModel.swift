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
    static let shared = PlaylistMoveModel()
    var screenshotMode = true
    var screenshotDestination = "Comment Section"
    private(set) var screenshotPreview: UIImage?
    private(set) var screenshotSongs: [Song] = []
    private(set) var screenshotReview: String?
    private(set) var importingScreenshot = false
    private(set) var preparingScreenshotRun = false
    private(set) var countdown: Int?
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
    @ObservationIgnored private var screenshotDraft: ScreenshotSongs?
    @ObservationIgnored private var screenshotTask: Task<Void, Never>?
    @ObservationIgnored private var screenshotTimeout: Task<Void, Never>?
    @ObservationIgnored private var screenshotGeneration = UUID()
    @ObservationIgnored private var preparingConnection = false

    var busy: Bool { pairing || connecting || running || armed || work.active || importingScreenshot || preparingScreenshotRun }
    var canRun: Bool { connected && inputReady && !busy && modelIssue == nil && (!screenshotMode || (!screenshotSongs.isEmpty && screenshotReview == nil)) }

    func prepare() async {
        if preparingConnection {
            while preparingConnection && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            return
        }
        guard client == nil else { modelIssue = LocalPlaylistAgent.availability; return }
        preparingConnection = true
        defer { preparingConnection = false }
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
        guard !pairing, !connecting, !running, !armed, !work.active, !connected, let client else { return }
        connecting = true
        let token = UUID(); epoch = token
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let opened = try await client.connect(device.id)
                guard !Task.isCancelled, self.epoch == token else { await opened.disconnect(); return }
                self.session = opened; self.connecting = false; self.connected = true
                self.message = "Connected. Ready to build your playlist."
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
            let launchURL = try SpotifyLaunch.url(playlistLink: screenshotMode ? "" : playlistLink)
            guard UIApplication.shared.canOpenURL(launchURL) else {
                message = "Install Spotify and sign in before starting a transfer."
                return
            }
            let ledger: TransferLedger
            if screenshotMode {
                guard let draft = screenshotDraft, screenshotReview == nil else { return }
                ledger = try TransferLedger(imageSongs: draft.songs, destination: screenshotDestination)
            } else {
                ledger = try TransferLedger(source: source, destination: destination, limit: trackLimit)
            }
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
        if background, importingScreenshot || preparingScreenshotRun {
            cancelScreenshotRequest()
            message = "Request paused. Keep Playlist Move open until Spotify launches."
        }
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
        cancelScreenshotRequest()
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
        let service = report?.ledger.service == .spotify ? "Spotify" : "Apple Music"
        message = successful ? "The agent reports your playlist is ready in \(service)." : report?.ledger.stopReason ?? "Transfer stopped"
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

    func receiveScreenshot(_ data: Data, destination: String, autoStart: Bool) throws {
        guard !busy else { throw ScreenshotError.busy }
        guard !data.isEmpty, data.count <= 25_000_000 else { throw ScreenshotError.invalidImage }
        let image = try ScreenshotSongs.decode(data)
        let token = UUID(); screenshotGeneration = token
        screenshotMode = true; screenshotDestination = destination
        screenshotDraft = nil; screenshotSongs = []; screenshotReview = nil
        screenshotPreview = UIImage(cgImage: image)
        report = nil; reportURL = nil; importingScreenshot = true
        message = "Reading song recommendations on your iPhone"
        screenshotTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled, let self, self.screenshotGeneration == token else { return }
            self.cancelScreenshotRequest(); self.message = "The screenshot request took too long. Try again."
        }
        screenshotTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Siri can deliver the request during the foreground transition.
                for _ in 0..<100 {
                    if UIApplication.shared.applicationState == .active { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard UIApplication.shared.applicationState == .active else { throw ScreenshotError.notForeground }
                guard LocalPlaylistAgent.availability == nil else { throw ScreenshotError.modelUnavailable }
                let draft = try await ScreenshotSongs.extract(image)
                try Task.checkCancellation()
                guard self.screenshotGeneration == token else { return }
                let ledger = try TransferLedger(imageSongs: draft.songs, destination: destination)
                self.screenshotDraft = draft
                self.screenshotSongs = ledger.songs; self.screenshotReview = draft.reviewReason
                self.importingScreenshot = false
                if let reason = draft.reviewReason {
                    self.message = "Please check the screenshot: \(reason)"
                } else if autoStart {
                    self.preparingScreenshotRun = true
                    self.message = "\(ledger.songs.count) songs found. Connecting to this iPhone."
                    // Photos may have kept this app suspended long enough for an
                    // earlier session to go stale. Start a new input session.
                    await self.disconnect()
                    await self.prepare()
                    try Task.checkCancellation()
                    if !self.connected {
                        var requestedConnection = false
                        for _ in 0..<100 {
                            try Task.checkCancellation()
                            guard UIApplication.shared.applicationState == .active else { throw ScreenshotError.notForeground }
                            if !requestedConnection {
                                guard self.devices.count <= 1 else { throw ScreenshotError.connection }
                                if let device = self.devices.first, device.reachability == .reachable {
                                    self.connect(device); requestedConnection = true
                                }
                            }
                            if self.connected { break }
                            try await Task.sleep(for: .milliseconds(200))
                        }
                    }
                    guard self.connected else { throw ScreenshotError.connection }
                    for _ in 0..<50 {
                        if self.inputReady { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard self.inputReady else { throw ScreenshotError.notReady }
                    for seconds in (1...3).reversed() {
                        try Task.checkCancellation()
                        guard UIApplication.shared.applicationState == .active else { throw ScreenshotError.notForeground }
                        self.countdown = seconds
                        self.message = "Creating \(destination) in Spotify in \(seconds)…"
                        try await Task.sleep(for: .seconds(1))
                    }
                    try Task.checkCancellation()
                    guard self.screenshotGeneration == token, UIApplication.shared.applicationState == .active else { throw ScreenshotError.notForeground }
                    self.preparingScreenshotRun = false; self.countdown = nil
                    self.arm()
                } else {
                    self.message = "\(ledger.songs.count) recommendations ready. Tap Create playlist when you're ready."
                }
                self.screenshotTimeout?.cancel()
            } catch {
                guard self.screenshotGeneration == token else { return }
                self.importingScreenshot = false; self.preparingScreenshotRun = false; self.countdown = nil
                self.screenshotTimeout?.cancel()
                self.message = error.localizedDescription
            }
        }
    }

    func cancelScreenshotRequest() {
        screenshotGeneration = UUID(); screenshotTask?.cancel(); screenshotTimeout?.cancel()
        screenshotTask = nil; screenshotTimeout = nil
        importingScreenshot = false; preparingScreenshotRun = false; countdown = nil
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
