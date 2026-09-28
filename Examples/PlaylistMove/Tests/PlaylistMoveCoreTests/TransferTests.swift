import XCTest
@testable import PlaylistMoveCore

final class TransferTests: XCTestCase {
    private func screen(_ labels: [String]) -> [ScreenText] {
        labels.enumerated().map { ScreenText(id: $0.offset, text: $0.element, x: 0.5, y: 0.2 + Double($0.offset) * 0.08) }
    }
    func testTransferNeedsDestinationEvidenceBeforeSuccess() throws {
        var ledger = try TransferLedger(source: "Late Night", destination: "Late Night Move", limit: 1)
        let song = Song(title: "Example", artist: "Artist")
        try ledger.capture([song], screen: screen(["Late Night", "Example", "Artist"]))
        try ledger.recordAttempt()
        XCTAssertEqual(ledger.phase, .verifying)
        XCTAssertThrowsError(try ledger.verify(screen: screen(["Search", "Example", "Artist"])))
        try ledger.verify(screen: screen(["Late Night Move", "Example (Live)", "Artist"]))
        XCTAssertTrue(ledger.verified.isEmpty)
        try ledger.verify(screen: screen(["Late Night Move", "Example", "Artist"]))
        XCTAssertEqual(ledger.phase, .completed)
    }
    func testHallucinatedSongIsRejected() throws {
        var ledger = try TransferLedger(source: "Source", destination: "Copy", limit: 1)
        XCTAssertThrowsError(try ledger.capture([Song(title: "Imagined", artist: "Artist")], screen: screen(["Source", "Actual", "Artist"])))
        XCTAssertTrue(ledger.songs.isEmpty)
    }
    func testDuplicateInventoryDoesNotInflateProgress() throws {
        var ledger = try TransferLedger(source: "Source", destination: "Copy", limit: 5)
        let song = Song(title: "Track", artist: "Artist")
        let visible = screen(["Source", "Track", "Artist"])
        try ledger.capture([song, song], screen: visible)
        try ledger.capture([song], screen: visible)
        XCTAssertEqual(ledger.songs.count, 1)
        XCTAssertEqual(ledger.phase, .reading)
    }
    func testOnlyCurrentScreenElementsCanBeTapped() throws {
        XCTAssertThrowsError(try GroundedAction.tap(elementID: 9, screen: screen(["Add to Playlist"])))
        XCTAssertThrowsError(try GroundedAction.tap(elementID: 0, screen: screen(["Delete Playlist"])))
        XCTAssertEqual(try GroundedAction.tap(elementID: 0, screen: screen(["Add to Playlist"])).kind, "tap")
        XCTAssertThrowsError(try GroundedAction.text("line\nbreak"))
        XCTAssertThrowsError(try GroundedAction.text(String(repeating: "x", count: 33)))
    }
}
