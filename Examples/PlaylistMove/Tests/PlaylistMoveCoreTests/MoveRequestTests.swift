import XCTest
@testable import PlaylistMoveCore

final class MoveRequestTests: XCTestCase {
    func testVoiceRequestStaysWithinSupportedTransfer() throws {
        let request = try MoveRequest(source: " Late Night ", destination: "", count: 5, supportedRoute: true)
        XCTAssertEqual(request.source, "Late Night")
        XCTAssertEqual(request.destination, "Late Night Move")
        XCTAssertThrowsError(try MoveRequest(source: "Night", destination: "", count: 50, supportedRoute: true))
        XCTAssertThrowsError(try MoveRequest(source: "Night", destination: "", count: 5, supportedRoute: false))
        XCTAssertThrowsError(try MoveRequest(source: " ", destination: "Copy", count: 1, supportedRoute: true))
    }

    func testSpotifyLinkCannotLaunchAnUnrelatedURL() throws {
        let id = "37i9dQZF1DXcBWIGoYBM5M"
        XCTAssertEqual(try SpotifyLaunch.url(playlistLink: "https://open.spotify.com/playlist/\(id)?si=example").absoluteString,
                       "spotify:playlist:\(id)")
        XCTAssertEqual(try SpotifyLaunch.url(playlistLink: "spotify:playlist:\(id)").absoluteString, "spotify:playlist:\(id)")
        XCTAssertEqual(try SpotifyLaunch.url(playlistLink: "").absoluteString, "spotify:")
        for link in ["https://open.spotify.com.evil.test/playlist/\(id)", "https://open.spotify.com/track/\(id)",
                     "https://user@open.spotify.com/playlist/\(id)", "spotify:playlist:bad", "otherapp://anything"] {
            XCTAssertThrowsError(try SpotifyLaunch.url(playlistLink: link))
        }
    }
}
