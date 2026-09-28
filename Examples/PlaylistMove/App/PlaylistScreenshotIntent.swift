import AppIntents
import Foundation
import UniformTypeIdentifiers

struct PlaylistScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Spotify Playlist from Image"
    static let description = IntentDescription("Read song recommendations in an image and create a Spotify playlist using the phone's screen controls.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var image: IntentFile

    @Parameter(title: "Playlist name", default: "Comment Section")
    var playlistName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create Spotify playlist \(\.$playlistName) from \(\.$image)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = PlaylistMoveModel.shared
        guard !model.busy else { throw ScreenshotError.busy }
        let data = image.data
        guard !data.isEmpty, data.count <= 25_000_000 else { throw ScreenshotError.invalidImage }
        try model.receiveScreenshot(data, destination: playlistName, autoStart: true)
        return .result(dialog: "Reading the recommendations in Playlist Move.")
    }
}
