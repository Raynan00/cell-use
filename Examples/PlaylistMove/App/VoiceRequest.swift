import AVFoundation
import FoundationModels
import Observation
import PlaylistMoveCore
import Speech

@Generable
private struct SpokenMove {
    @Guide(description: "True only if the user asks to copy music from Spotify into Apple Music.")
    var supportedRoute: Bool
    @Guide(description: "Exact source playlist name spoken by the user. Empty if no name was supplied.")
    var source: String
    @Guide(description: "Destination playlist name only if explicitly supplied, otherwise empty.")
    var destination: String
    @Guide(description: "Number of songs requested. Use 1 if unspecified. Preserve unsupported counts so validation can reject them.")
    var count: Int
}

@MainActor @Observable
final class VoiceRequest {
    private(set) var recording = false
    private(set) var working = false
    private(set) var transcript = ""
    private(set) var message = "Say which playlist you want to move."
    var onRequest: ((MoveRequest) -> Void)?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var recordingLimit: Task<Void, Never>?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var transcriber: SpeechTranscriber?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var audioActive = false
    var busy: Bool { recording || working }

    func start() {
        guard !busy else { return }
        let token = UUID(); generation = token
        working = true; transcript = ""; message = "Preparing on-device speech"
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                guard await AVAudioApplication.requestRecordPermission() else { throw VoiceError.microphone }
                try Task.checkCancellation()
                guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
                    throw VoiceError.unavailable
                }
                let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
                if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    self.message = "Downloading the English speech model"
                    try await installation.downloadAndInstall()
                }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                self.transcriber = transcriber
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
                try audio.setActive(true)
                self.audioActive = true
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("move-voice-\(UUID().uuidString).caf")
                self.audioURL = url
                let recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
                ])
                guard recorder.record() else { throw VoiceError.recording }
                self.recorder = recorder; self.recording = true; self.working = false
                self.message = "Listening. Tap Use recording when you're done."
                self.recordingLimit = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled else { return }
                    self?.finishRecording()
                }
            } catch {
                guard self.generation == token else { return }
                self.cancel(); self.message = error.localizedDescription
            }
        }
    }

    func finishRecording() {
        guard recording, let url = audioURL, let transcriber else { return }
        recordingLimit?.cancel(); recorder?.stop(); recorder = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioActive = false
        working = true; message = "Transcribing on your iPhone"
        let token = generation
        recordingLimit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.cancel(); self.message = "Voice input took too long. Try again or use the fields."
        }
        operation = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                self.analyzer = analyzer
                let file = try AVAudioFile(forReading: url)
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                var words = ""
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    words += String(result.text.characters) + " "
                }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                self.transcript = words.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !self.transcript.isEmpty else { throw VoiceError.empty }
                self.message = "Understanding your request"
                let session = LanguageModelSession(instructions: "Extract a playlist transfer request. Only Spotify to Apple Music is supported. Do not invent playlist names or change the requested song count. The user will review the fields before starting.")
                let answer = try await session.respond(to: self.transcript, generating: SpokenMove.self,
                                                       options: GenerationOptions(sampling: .greedy))
                try Task.checkCancellation()
                guard self.generation == token else { return }
                let value = answer.content
                let request = try MoveRequest(source: value.source, destination: value.destination,
                                              count: value.count, supportedRoute: value.supportedRoute)
                self.onRequest?(request)
                self.message = "Check the playlist names below, then tap Move."
                self.recordingLimit?.cancel()
                self.working = false; self.analyzer = nil; self.transcriber = nil; self.audioURL = nil
            } catch {
                guard self.generation == token else { return }
                self.cancel()
                self.message = "Couldn't use that request. Ask for one or five songs from a named Spotify playlist to Apple Music, or edit the fields below."
            }
        }
    }

    func cancel() {
        generation = UUID(); operation?.cancel(); recordingLimit?.cancel()
        recorder?.stop(); recorder = nil
        if audioActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        audioActive = false
        recording = false; working = false
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil; transcriber = nil
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
        message = "Voice input stopped. You can try again or use the fields."
    }
}

private enum VoiceError: LocalizedError {
    case microphone, unavailable, recording, empty
    var errorDescription: String? {
        switch self {
        case .microphone: "Allow microphone access in Settings to speak your request."
        case .unavailable: "On-device English speech is unavailable. You can use the fields instead."
        case .recording: "Couldn't start the microphone. Stop other audio capture and try again."
        case .empty: "No speech was heard. Please try again."
        }
    }
}
