import SwiftUI
import CellUseTunnel

@main
struct TunnelHostApp: App {
    var body: some Scene {
        WindowGroup { TunnelHostView() }
    }
}

@MainActor
private struct TunnelHostView: View {
    @State private var tunnel = CellUseTunnelController(
        providerBundleIdentifier: Bundle.main.bundleIdentifier! + ".tunnel")
    @State private var message = "Ready to connect"
    @State private var connecting = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Embedded cell-use connection") {
                Text("This app contains its own local tunnel extension.")
                Text(message)
                Button("Connect") {
                    connecting = true
                    message = "Connecting…"
                    operation = Task { @MainActor in
                        defer { connecting = false }
                        do {
                            try await tunnel.connect()
                            message = "Tunnel connected. Developer-service peer: 10.7.0.1"
                        } catch is CancellationError {
                            message = "Connection cancelled"
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .disabled(connecting)
                Button("Disconnect") {
                    operation?.cancel()
                    tunnel.disconnect()
                    message = "Disconnect requested"
                }
            }
            Section("Integrate with your agent") {
                Text("After the tunnel connects, pair and open a native cell-use session using 10.7.0.1. This example demonstrates tunnel packaging; the full phone runtime is integrated separately.")
            }
        }
    }
}
