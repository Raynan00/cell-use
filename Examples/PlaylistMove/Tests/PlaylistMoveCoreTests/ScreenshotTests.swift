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

    func testDemoCanAdvanceTitleOnlySongsWithoutClaimingDeterministicVerification() throws {
        let item = ScreenshotRecommendation(title: "planet telexa", artist: "", evidence: "planet telexa")
        var ledger = try TransferLedger(recommendations: [item], screenText: item.evidence, destination: "Comments")
        try ledger.recordAttempt(allowMissingArtist: true)
        XCTAssertEqual(ledger.attempted.count, 1)
        XCTAssertEqual(ledger.phase, .verifying)
        ledger.completeFromAgent()
        XCTAssertEqual(ledger.phase, .completed)
        XCTAssertTrue(ledger.verified.isEmpty)
    }

    func testImageInventoryCanRunWithoutOCRAndKeepsAgentAssessmentSeparate() throws {
        let song = Song(title: "Planet Telex", artist: "")
        var ledger = try TransferLedger(imageSongs: [song, song], destination: "Comments")
        XCTAssertEqual(ledger.songs, [song])
        XCTAssertEqual(ledger.limit, 1)
        XCTAssertEqual(ledger.service, .spotify)
        try ledger.recordAttempt(allowMissingArtist: true)
        ledger.completeFromAgent()
        XCTAssertEqual(ledger.phase, .completed)
        XCTAssertTrue(ledger.verified.isEmpty)
        XCTAssertThrowsError(try TransferLedger(imageSongs: [], destination: "Comments"))
        XCTAssertThrowsError(try TransferLedger(imageSongs: [Song(title: " ", artist: "")], destination: "Comments"))
    }

    func testImagePlaylistCaptureAccumulatesAcrossScreens() throws {
        var ledger = try TransferLedger(source: "Source", destination: "Destination", limit: 5)
        let first = Song(title: "First", artist: "")
        try ledger.captureFromAgent([first])
        XCTAssertEqual(ledger.phase, .reading)
        try ledger.captureFromAgent([first] + (2...5).map { Song(title: "Song \($0)", artist: "Artist") })
        XCTAssertEqual(ledger.songs.count, 5)
        XCTAssertEqual(ledger.phase, .moving)
        XCTAssertThrowsError(try ledger.captureFromAgent([first]))
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
