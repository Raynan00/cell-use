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
}
