import SwiftUI
import PlaylistMoveCore
import PhotosUI

@main
struct PlaylistMoveApp: App {
    var body: some Scene { WindowGroup { PlaylistMoveView() } }
}

struct PlaylistMoveView: View {
    @State private var model = PlaylistMoveModel.shared
    @State private var voice = VoiceRequest()
    @State private var showSetup = true
    @State private var showRecording = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoLoading = false
    @State private var photoError: String?
    @Environment(\.scenePhase) private var scenePhase
    private let ink = Color(red: 0.06, green: 0.16, blue: 0.15)
    private let accent = Color(red: 0.1, green: 0.43, blue: 0.34)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label("PLAYLIST MOVE", systemImage: "arrow.triangle.swap")
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.6)
                    Spacer()
                    Button { showRecording = true } label: { Image(systemName: "record.circle").font(.title2) }
                        .accessibilityLabel("Recording guide")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.screenshotMode ? "Good comments.\nGreat playlist." : "New app.\nSame soundtrack.")
                        .font(.system(size: 43, weight: .semibold, design: .serif)).tracking(-1.7)
                    Text(model.screenshotMode ? "Song recommendations, ready to listen to." : "Your playlists, carried across by your iPhone.")
                        .font(.subheadline).foregroundStyle(ink.opacity(0.65))
                }
                Picker("Source", selection: $model.screenshotMode) {
                    Text("Comment screenshot").tag(true)
                    Text("Move a playlist").tag(false)
                }.pickerStyle(.segmented).disabled(model.busy || voice.busy || photoLoading)
                if model.screenshotMode {
                    screenshotSetup
                } else {
                HStack(spacing: 14) {
                    service("Spotify", caption: "FROM", symbol: "waveform", color: .green)
                    Image(systemName: "arrow.right").font(.headline).foregroundStyle(accent)
                    service("Apple Music", caption: "TO", symbol: "music.note", color: .pink)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        if voice.recording { voice.finishRecording() } else { voice.start() }
                    } label: {
                        Label(voice.recording ? "Use recording" : "Say your request",
                              systemImage: voice.recording ? "stop.circle.fill" : "mic.fill")
                            .font(.headline)
                    }.disabled(model.busy || voice.working)
                    if voice.working { ProgressView().controlSize(.small) }
                    Text(voice.message).font(.caption).foregroundStyle(.secondary)
                    if !voice.transcript.isEmpty { Text(voice.transcript).font(.callout) }
                    if voice.busy { Button("Cancel voice input") { voice.cancel() }.font(.caption) }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 15) {
                    field("SPOTIFY PLAYLIST", text: $model.source)
                    Divider()
                    field("NEW APPLE MUSIC PLAYLIST", text: $model.destination)
                    Picker("Songs to copy", selection: $model.trackLimit) {
                        Text("One song").tag(1)
                        Text("Five songs").tag(5)
                    }.pickerStyle(.segmented)
                    DisclosureGroup("Open a specific Spotify playlist") {
                        TextField("Paste playlist link (optional)", text: $model.playlistLink)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.top, 8)
                        Text("Use Share → Copy link in Spotify. This link opens the playlist; the agent reads the songs from its screen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.font(.callout)
                }
                .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 22))
                .disabled(model.busy || voice.busy)
                }

                if let issue = model.modelIssue {
                    Label(issue, systemImage: "sparkles").font(.callout)
                    Button("Check local model") { Task { await model.prepare() } }
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle().fill(model.connected ? accent : Color.gray.opacity(0.5)).frame(width: 7, height: 7)
                        Text(model.running ? "MOVING YOUR MUSIC" : model.armed ? "READY TO LEAVE" : "ON YOUR IPHONE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.2)
                    }
                    Text(model.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button(action: model.arm) {
                        HStack { Text(model.screenshotMode ? "Create playlist" : "Move my playlist"); Spacer(); Image(systemName: "arrow.up.right") }
                            .font(.headline).padding(18)
                            .foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 16))
                    }.disabled(!model.canRun || voice.busy || photoLoading).opacity(model.canRun && !voice.busy && !photoLoading ? 1 : 0.45)
                    if model.busy || model.connected {
                        Button("Stop and disconnect", role: .destructive) { model.stop() }.font(.callout)
                    }
                    Text("Spotify opens when you start. Keep the phone unlocked and in portrait while the playlist moves.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let report = model.report {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("The move").font(.title2.bold())
                            Spacer()
                            Text("\(report.ledger.verified.count)/\(report.ledger.limit) checked").font(.caption.monospaced())
                        }
                        ForEach(report.ledger.songs) { song in
                            HStack {
                                Image(systemName: report.ledger.verified.contains(song.id) ? "checkmark.circle.fill" : "music.note")
                                    .foregroundStyle(accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(song.title).font(.subheadline.bold())
                                    Text(song.artist).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        ForEach(report.events.suffix(5)) { event in
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(format: "%05.1fs", event.elapsed)).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(event.note).font(.caption)
                            }
                        }
                        if let url = model.reportURL {
                            ShareLink(item: url) { Label("Export run timeline", systemImage: "square.and.arrow.up") }.font(.callout)
                        }
                        if let image = model.latestImage {
                            DisclosureGroup("Last phone screen") {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 400).privacySensitive()
                            }.font(.caption)
                        }
                    }
                    .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 22))
                }

                DisclosureGroup("Connection setup", isExpanded: $showSetup) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Keep LocalDevVPN enabled and Developer Mode on. Sign in to Spotify. Playlist transfers to Apple Music also need an Apple Music subscription.")
                        TextField("Tunnel device IP", text: $model.peer)
                            .keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Refresh connection") { Task { await model.refreshConnection() } }.disabled(model.busy)
                        Button("Pair this iPhone", action: model.pair).disabled(model.busy || model.connected)
                        if let code = model.pairingCode { Text(code).font(.title.monospaced()).privacySensitive() }
                        ForEach(model.devices) { device in
                            Button("\(device.reachability == .reachable ? "Connect" : "Searching") · \(device.name)") {
                                model.connect(device)
                            }.disabled(model.busy || model.connected || device.reachability != .reachable)
                        }
                    }.font(.callout).padding(.top, 10)
                }.font(.subheadline).disabled(voice.busy)
                HStack {
                    Text("BUILT WITH CELL-USE").tracking(1.5)
                    Spacer()
                    Text("LOCAL AI")
                }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(24)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.92))
        .foregroundStyle(ink).tint(accent).preferredColorScheme(.light)
        .task {
            voice.onRequest = { request in
                guard !model.busy else { return }
                if model.source != request.source { model.playlistLink = "" }
                model.source = request.source; model.destination = request.destination; model.trackLimit = request.count
            }
            await model.prepare()
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            photoLoading = true; photoError = nil
            defer { photoLoading = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { throw ScreenshotError.invalidImage }
                try Task.checkCancellation()
                try model.receiveScreenshot(data, destination: model.screenshotDestination, autoStart: false)
            } catch {
                if !Task.isCancelled { photoError = error.localizedDescription }
            }
        }
        .onChange(of: model.importingScreenshot) { _, importing in
            if importing && voice.busy { voice.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if voice.busy { voice.cancel() }
                model.sceneChanged(background: true)
            }
            else if phase == .active { model.sceneChanged(background: false) }
        }
        .onChange(of: model.connected) { _, connected in if connected { showSetup = false } }
        .sheet(isPresented: $showRecording) { recordingGuide }
    }

    private var screenshotSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("SCREENSHOT → SPOTIFY", systemImage: "photo.on.rectangle")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text("In Photos, open your screenshot and say “Siri, playlist this.”")
                .font(.headline)
            DisclosureGroup("Set up the voice shortcut once") {
                Text("In Shortcuts, create “Playlist this”. Turn on Receive What's On Screen and accept Images. Add Playlist Move's Create Spotify Playlist from Image action. Set Image to Shortcut Input and Playlist name to Comment Section. In the input's If there's no input setting, choose Stop and Respond. Run it once to allow access before recording.")
                    .font(.callout).padding(.top, 8)
            }.font(.callout)
            field("SPOTIFY PLAYLIST NAME", text: $model.screenshotDestination).disabled(model.busy || photoLoading)
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose screenshot", systemImage: "photo")
            }.disabled(model.busy || photoLoading)
            if photoLoading || model.importingScreenshot || model.preparingScreenshotRun {
                HStack { ProgressView(); Text(model.message).font(.callout) }
                Button("Cancel") { model.stop(reason: "Screenshot request cancelled") }
            }
            if let photoError { Text(photoError).font(.caption).foregroundStyle(.red) }
            if let reason = model.screenshotReview { Text(reason).font(.callout).foregroundStyle(.orange) }
            ForEach(model.screenshotSongs) { song in
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.subheadline.bold())
                    Text(song.artist).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let image = model.screenshotPreview {
                DisclosureGroup("Source screenshot") {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).privacySensitive()
                }.font(.caption)
            }
        }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private func service(_ name: String, caption: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            Text(name).font(.system(size: 15, weight: .semibold))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            TextField(label, text: text).font(.body).autocorrectionDisabled()
        }
    }
    private var recordingGuide: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    Text("Open a comment screenshot in Photos. Say Siri, playlist this. Show Playlist Move reading the image, then Spotify opening and filling the playlist while your hands are away.")
                    Text("A second phone can film your hands leaving the screen. Use simultaneous iPhone Screen Recording for readable close-ups. Test Siri and microphone capture together before the full take.")
                    Text("Keep music playback off. The playlist transfer works without playing the tracks.")
                }
                Section("Edit") {
                    Text("Export the run timeline afterward. It includes real action timestamps and inference durations. Label any sped-up footage.")
                    Text("Image text recognition and playlist decisions run on the phone. Siri handles voice activation. Spotify still needs its normal network connection.")
                }
            }.navigationTitle("Record the demo")
                .toolbar { Button("Done") { showRecording = false } }
        }
    }
}
