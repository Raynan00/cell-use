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
        let words = elements.map { Self.normalized($0.text) }
        return words.contains(Self.normalized(title)) && words.contains { $0.contains(Self.normalized(artist)) }
    }
}

public enum TransferError: String, Error, Sendable {
    case invalidConfiguration, invalidAction, unknownElement, sourceNotVisible
    case songNotVisible, nothingToMove, duplicateSong, incompleteVerification, unsafeControl
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

    public mutating func recordAttempt() throws {
        guard phase == .moving, let song = currentSong else { throw TransferError.invalidAction }
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
}

public struct ScreenshotRecommendation: Sendable {
    public let title: String
    public let artist: String
    public let evidence: String
    public init(title: String, artist: String, evidence: String) {
        self.title = title; self.artist = artist; self.evidence = evidence
    }
    public func validated(in screenText: String) throws -> Song {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let proof = Song.normalized(evidence)
        let songTitle = Song.normalized(title), songArtist = Song.normalized(artist)
        func containsWords(_ haystack: String, _ needle: String) -> Bool {
            (" " + haystack + " ").contains(" " + needle + " ")
        }
        guard !songTitle.isEmpty, !songArtist.isEmpty, !proof.isEmpty,
              containsWords(Song.normalized(screenText), proof),
              containsWords(proof, songTitle), containsWords(proof, songArtist) else { throw TransferError.songNotVisible }
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
