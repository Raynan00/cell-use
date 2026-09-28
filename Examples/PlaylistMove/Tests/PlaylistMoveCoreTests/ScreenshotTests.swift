import XCTest
@testable import PlaylistMoveCore

final class ScreenshotTests: XCTestCase {
    let recommendation = ScreenshotRecommendation(title: "Song One", artist: "Artist One", evidence: "Song One by Artist One")

    func testScreenshotInventoryStartsAtSpotifyAndStillRequiresVerification() throws {
        var ledger = try TransferLedger(recommendations: [recommendation, recommendation],
            screenText: "user123: Song One by Artist One is great", destination: "Comment Section")
        XCTAssertEqual(ledger.service, .spotify)
        XCTAssertEqual(ledger.phase, .moving)
        XCTAssertEqual(ledger.limit, 1)
        try ledger.recordAttempt()
        XCTAssertEqual(ledger.phase, .verifying)
        XCTAssertThrowsError(try ledger.verify(screen: [ScreenText(id: 0, text: "Search", x: 0.5, y: 0.5)]))
        let labels = ["Comment Section", "Song One", "Artist One"]
        try ledger.verify(screen: labels.enumerated().map { ScreenText(id: $0.offset, text: $0.element, x: 0.5, y: 0.5) })
        XCTAssertEqual(ledger.phase, .completed)
    }

    func testGuessedArtistsAndFabricatedEvidenceAreRejected() throws {
        XCTAssertThrowsError(try recommendation.validated(in: "Song One by someone else"))
        let guessed = ScreenshotRecommendation(title: "Song One", artist: "Artist Two", evidence: "Song One by Artist One")
        XCTAssertThrowsError(try guessed.validated(in: "Song One by Artist One"))
        let fragment = ScreenshotRecommendation(title: "One", artist: "Art", evidence: "One by Artist")
        XCTAssertThrowsError(try fragment.validated(in: "One by Artist"))
        XCTAssertThrowsError(try TransferLedger(recommendations: [], screenText: "nothing", destination: "Comments"))
        XCTAssertThrowsError(try TransferLedger(recommendations: [recommendation], screenText: recommendation.evidence, destination: " "))
    }

    func testTitleOnlyRecommendationMustResolveArtistBeforeItCanBeAdded() throws {
        let item = ScreenshotRecommendation(title: "Song One", artist: "", evidence: "try Song One")
        var ledger = try TransferLedger(recommendations: [item], screenText: "try Song One", destination: "Comments")
        XCTAssertEqual(ledger.currentSong?.artist, "")
        XCTAssertThrowsError(try ledger.recordAttempt())
        let song = Song(title: "Song One", artist: "Artist One")
        let results = ["Song One", "Artist One"].enumerated().map {
            ScreenText(id: $0.offset, text: $0.element, x: 0.5, y: 0.5)
        }
        XCTAssertThrowsError(try ledger.resolveCurrentSong(Song(title: "Song One", artist: "Guessed Artist"), screen: results))
        XCTAssertThrowsError(try ledger.resolveCurrentSong(Song(title: "Song One (Live)", artist: "Artist One"), screen: results))
        try ledger.resolveCurrentSong(song, screen: results)
        XCTAssertEqual(ledger.currentSong, song)
        try ledger.recordAttempt()
        XCTAssertEqual(ledger.attempted, [song.id])
        try ledger.verify(screen: results + [ScreenText(id: 2, text: "Comments", x: 0.5, y: 0.2)])
        XCTAssertEqual(ledger.phase, .completed)
    }

    func testMissingArtistDoesNotMakeSongVisibleOrAllowInventedTitles() throws {
        let item = ScreenshotRecommendation(title: "Imagined Song", artist: "", evidence: "Actual Song")
        XCTAssertThrowsError(try item.validated(in: "Actual Song"))
        XCTAssertFalse(Song(title: "Actual Song", artist: "").visible(in: [
            ScreenText(id: 0, text: "Actual Song", x: 0.5, y: 0.5)
        ]))
    }

    func testEvidenceUsesActualNumberedLinesIncludingWrappedComments() throws {
        let lines = ["someone123", "Song One", "by Artist One", "12 likes"]
        let item = try ScreenshotRecommendation(title: "Song One", artist: "Artist One", firstLine: 2, lastLine: 3, lines: lines)
        XCTAssertEqual(try item.validated(in: lines.joined(separator: "\n")), Song(title: "Song One", artist: "Artist One"))
        XCTAssertThrowsError(try ScreenshotRecommendation(title: "Song One", artist: "", firstLine: 0, lastLine: 3, lines: lines))
        XCTAssertThrowsError(try ScreenshotRecommendation(title: "Song One", artist: "", firstLine: 3, lastLine: 2, lines: lines))
        XCTAssertThrowsError(try ScreenshotRecommendation(title: "Song One", artist: "", firstLine: 2, lastLine: 10, lines: lines))
        let unrelated = try ScreenshotRecommendation(title: "Song One", artist: "", firstLine: 4, lastLine: 4, lines: lines)
        XCTAssertThrowsError(try unrelated.validated(in: lines.joined(separator: "\n")))
    }
}
