import Foundation

public struct MoveRequest: Sendable {
    public let source: String
    public let destination: String
    public let count: Int

    public init(source: String, destination: String, count: Int, supportedRoute: Bool) throws {
        guard supportedRoute else { throw RequestError.unsupportedRoute }
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = requestedDestination.isEmpty ? source + " Move" : requestedDestination
        _ = try TransferLedger(source: source, destination: destination, limit: count)
        self.source = source; self.destination = destination; self.count = count
    }
}

public enum RequestError: Error, Sendable {
    case unsupportedRoute, invalidPlaylistLink
}

public enum SpotifyLaunch {
    public static func url(playlistLink: String) throws -> URL {
        let text = playlistLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return URL(string: "spotify:")! }
        let id: String
        if text.hasPrefix("spotify:playlist:") {
            id = String(text.dropFirst("spotify:playlist:".count))
        } else {
            guard let url = URLComponents(string: text), url.scheme == "https",
                  url.host == "open.spotify.com", url.user == nil, url.password == nil,
                  url.port == nil else { throw RequestError.invalidPlaylistLink }
            let path = url.path.split(separator: "/")
            guard path.count == 2, path[0] == "playlist" else { throw RequestError.invalidPlaylistLink }
            id = String(path[1])
        }
        guard id.utf8.count == 22, id.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }) else { throw RequestError.invalidPlaylistLink }
        return URL(string: "spotify:playlist:" + id)!
    }
}
