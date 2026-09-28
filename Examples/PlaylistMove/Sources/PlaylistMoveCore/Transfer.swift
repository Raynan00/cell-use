import Foundation
import CellUse

public struct ScreenText: Codable, Sendable, Equatable {
    public let id: Int
    public let text: String
    public let x: Double
    public let y: Double
    public init(id: Int, text: String, x: Double, y: Double) {
        self.id = id; self.text = text; self.x = x; self.y = y
    }
}

public struct Song: Codable, Sendable, Equatable, Identifiable {
    public let title: String
    public let artist: String
    public var id: String { Self.normalized(title) + "|" + Self.normalized(artist) }
    public init(title: String, artist: String) { self.title = title; self.artist = artist }
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
    public func visible(in elements: [ScreenText]) -> Bool {
        guard !Self.normalized(artist).isEmpty else { return false }
        let words = elements.map { Self.normalized($0.text) }
        return words.contains(Self.normalized(title)) && words.contains { $0.contains(Self.normalized(artist)) }
    }
}

public enum TransferError: String, LocalizedError, Sendable {
    case invalidConfiguration, invalidAction, unknownElement, sourceNotVisible
    case songNotVisible, nothingToMove, duplicateSong, incompleteVerification, unsafeControl

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Check the playlist name and song count. Use a playlist name of 1 to 32 English keyboard characters."
        case .invalidAction: "That action is not ready yet. Check the current phone screen."
        case .unknownElement: "The selected control is not present in this observation."
        case .sourceNotVisible: "The requested source playlist is not visible yet."
        case .songNotVisible: "A song could not be matched to the visible text. Check its title and artist."
        case .nothingToMove: "No song titles were found to move."
        case .duplicateSong: "That song is already in the list."
        case .incompleteVerification: "The destination playlist still needs to be checked."
        case .unsafeControl: "That control is outside this playlist task."
        }
    }
}

public struct TransferLedger: Codable, Sendable {
    public enum Service: String, Codable, Sendable { case appleMusic, spotify }
    public enum Phase: String, Codable, Sendable { case reading, moving, verifying, completed, stopped }
    public let source: String
    public let destination: String
    public let limit: Int
    public var service: Service = .appleMusic
    public private(set) var phase: Phase = .reading
    public private(set) var songs: [Song] = []
    public private(set) var attempted: [String] = []
    public private(set) var verified: [String] = []
    public private(set) var stopReason: String?

    public init(source: String, destination: String, limit: Int) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...80).contains(source.count), (1...32).contains(destination.utf8.count),
              destination.utf8.allSatisfy({ (32...126).contains($0) }),
              [1, 5].contains(limit) else { throw TransferError.invalidConfiguration }
        self.source = source; self.destination = destination; self.limit = limit
    }

    public init(recommendations: [ScreenshotRecommendation], screenText: String, destination: String) throws {
        guard (1...5).contains(recommendations.count), !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...32).contains(destination.utf8.count), destination.utf8.allSatisfy({ (32...126).contains($0) }) else {
            throw TransferError.invalidConfiguration
        }
        var songs: [Song] = []
        for item in recommendations {
            let song = try item.validated(in: screenText)
            if !songs.contains(where: { $0.id == song.id }) { songs.append(song) }
        }
        self.source = "Comment screenshot"; self.destination = destination; self.limit = songs.count
        self.service = .spotify; self.songs = songs; self.phase = .moving
    }

    public var currentSong: Song? { songs.first { !attempted.contains($0.id) } }

    public mutating func resolveCurrentSong(_ candidate: Song, screen: [ScreenText]) throws {
        guard service == .spotify, phase == .moving, let current = currentSong,
              current.artist.isEmpty, Song.normalized(candidate.title) == Song.normalized(current.title),
              candidate.visible(in: screen), let index = songs.firstIndex(where: { $0.id == current.id }) else {
            throw TransferError.songNotVisible
        }
        guard !songs.contains(where: { $0.id == candidate.id }) else { throw TransferError.duplicateSong }
        songs[index] = candidate
    }

    public mutating func capture(_ candidates: [Song], screen: [ScreenText]) throws {
        guard phase == .reading,
              screen.contains(where: { Song.normalized($0.text) == Song.normalized(source) }) else {
            throw TransferError.sourceNotVisible
        }
        for song in candidates.prefix(limit) {
            guard !song.title.isEmpty, !song.artist.isEmpty, song.visible(in: screen) else {
                throw TransferError.songNotVisible
            }
        }
        for song in candidates.prefix(limit) where songs.count < limit {
            if !songs.contains(where: { $0.id == song.id }) { songs.append(song) }
        }
        guard !songs.isEmpty else { throw TransferError.nothingToMove }
        // A run copies only the explicitly captured inventory. Partial lists
        // stay in reading; the UI shows how many songs were found.
        if songs.count == limit { phase = .moving }
    }

    public mutating func recordAttempt(allowMissingArtist: Bool = false) throws {
        guard phase == .moving, let song = currentSong,
              allowMissingArtist || !song.artist.isEmpty else { throw TransferError.invalidAction }
        attempted.append(song.id)
        if attempted.count == songs.count { phase = .verifying }
    }

    public mutating func verify(screen: [ScreenText]) throws {
        guard phase == .verifying,
              screen.contains(where: { Song.normalized($0.text) == Song.normalized(destination) }) else {
            throw TransferError.incompleteVerification
        }
        for song in songs where song.visible(in: screen) && !verified.contains(song.id) {
            verified.append(song.id)
        }
        if verified.count == songs.count { phase = .completed }
    }

    public mutating func stop(_ reason: String) { phase = .stopped; stopReason = reason }

    /// The demo delegates completion judgment to its agent. This does not add
    /// entries to `verified`, which is reserved for deterministic screen checks.
    public mutating func completeFromAgent() { phase = .completed }
}

public struct ScreenshotRecommendation: Sendable {
    public let title: String
    public let artist: String
    public let evidence: String
    public init(title: String, artist: String, evidence: String) {
        self.title = title; self.artist = artist; self.evidence = evidence
    }
    public init(title: String, artist: String, firstLine: Int, lastLine: Int, lines: [String]) throws {
        guard firstLine >= 1, lastLine >= firstLine, lastLine <= lines.count else {
            throw TransferError.songNotVisible
        }
        self.init(title: title, artist: artist, evidence: lines[(firstLine - 1)..<lastLine].joined(separator: "\n"))
    }
    public func validated(in screenText: String) throws -> Song {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let proof = Song.normalized(evidence)
        let songTitle = Song.normalized(title), songArtist = Song.normalized(artist)
        func containsWords(_ haystack: String, _ needle: String) -> Bool {
            (" " + haystack + " ").contains(" " + needle + " ")
        }
        guard !songTitle.isEmpty, !proof.isEmpty,
              containsWords(Song.normalized(screenText), proof),
              containsWords(proof, songTitle),
              (artist.isEmpty || (!songArtist.isEmpty && containsWords(proof, songArtist))) else { throw TransferError.songNotVisible }
        return Song(title: title, artist: artist)
    }
}

public enum GroundedAction {
    public static func tap(elementID: Int, screen: [ScreenText]) throws -> PhoneAction {
        guard let item = screen.first(where: { $0.id == elementID }) else { throw TransferError.unknownElement }
        let label = Song.normalized(item.text)
        let prohibited = ["delete", "remove", "purchase", "subscribe", "buy", "sign out", "log out"]
        guard !prohibited.contains(where: { label == $0 || label.hasPrefix($0 + " ") }) else {
            throw TransferError.unsafeControl
        }
        let action = PhoneAction.tap(x: item.x, y: item.y)
        guard action.inputValidationError == nil else { throw TransferError.invalidAction }
        return action
    }
    public static func text(_ value: String) throws -> PhoneAction {
        let action = PhoneAction.typeText(value)
        guard action.inputValidationError == nil else { throw TransferError.invalidAction }
        return action
    }
}
