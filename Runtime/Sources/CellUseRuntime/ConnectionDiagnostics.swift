import DeviceHubDiagnostics
import Foundation

enum ConnectionDiagnostics {
    /// Connection-scoped, bounded diagnostics. No files or upload destination.
    /// A host needing durable diagnostics can supply its own recorder instead.
    static func makeRecorder() throws -> DiagnosticRecorder {
        let installationID = UUID(), sessionID = UUID()
        let context: DiagnosticWireContext
        do {
            context = try DiagnosticWireContext(installationID: installationID, sessionID: sessionID,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0",
                buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")
        } catch {
            context = try DiagnosticWireContext(installationID: installationID, sessionID: sessionID,
                appVersion: "0.0", buildNumber: "0")
        }
        return try DiagnosticRecorder(context: context,
            policy: DiagnosticRetentionPolicy(maximumEventCount: 128, maximumEncodedByteCount: 65_536),
            persistence: DiagnosticPersistenceClient(load: { nil }, save: { _ in }, clear: {}),
            uploader: DiagnosticUploadClient(upload: { _ in throw .invalidConfiguration }),
            now: Date.init)
    }
}
