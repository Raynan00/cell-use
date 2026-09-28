#if os(iOS)
import Foundation
@preconcurrency import NetworkExtension

/// Host-app controller. Retain one instance per embedded provider identifier.
/// Starting the VPN does not establish pairing or a developer-service session.
@MainActor
public final class CellUseTunnelController {
    public let providerBundleIdentifier: String
    private var manager: NETunnelProviderManager?
    private var busy = false
    private var cancelled = false

    public init(providerBundleIdentifier: String) {
        self.providerBundleIdentifier = providerBundleIdentifier
    }

    public var status: NEVPNStatus { manager?.connection.status ?? .invalid }

    /// Saves the profile (iOS can ask for consent), starts it, and waits for connected.
    /// The timeout covers tunnel startup, not time spent in the system consent dialog.
    public func connect(configuration: TunnelConfiguration = .standard,
                        displayName: String = "cell-use local connection") async throws {
        guard !busy else { throw TunnelError.operationInProgress }
        guard !providerBundleIdentifier.isEmpty else { throw TunnelError.invalidConfiguration }
        busy = true
        cancelled = false
        defer { busy = false }

        let saved = try await NETunnelProviderManager.loadAllFromPreferences()
        try checkCancellation()
        let matches = saved.filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == providerBundleIdentifier
        }
        guard matches.count <= 1 else { throw TunnelError.invalidConfiguration }
        let manager = matches.first ?? NETunnelProviderManager()
        self.manager = manager
        let existing = manager.protocolConfiguration as? NETunnelProviderProtocol
        let existingConfiguration = try? TunnelConfiguration(providerValues: existing?.providerConfiguration)
        let state = manager.connection.status
        if state == .connected || state == .connecting || state == .reasserting {
            guard existingConfiguration == configuration else { throw TunnelError.configurationInUse }
            try await waitUntilConnected(manager)
            return
        }
        guard state != .disconnecting else { throw TunnelError.operationInProgress }

        let tunnel = NETunnelProviderProtocol()
        tunnel.providerBundleIdentifier = providerBundleIdentifier
        tunnel.serverAddress = configuration.deviceAddress
        tunnel.providerConfiguration = configuration.providerValues
        tunnel.disconnectOnSleep = false
        manager.protocolConfiguration = tunnel
        manager.localizedDescription = displayName
        manager.isEnabled = true
        manager.isOnDemandEnabled = false
        try await manager.saveToPreferences()
        try checkCancellation()
        // Reload the saved configuration before requesting its connection.
        try await manager.loadFromPreferences()
        try checkCancellation()
        try manager.connection.startVPNTunnel()
        do {
            try await waitUntilConnected(manager)
        } catch {
            manager.connection.stopVPNTunnel()
            throw error
        }
    }

    /// Stops only the profile selected by this controller, including pending startup.
    public func disconnect() {
        cancelled = true
        manager?.connection.stopVPNTunnel()
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
    }

    private func waitUntilConnected(_ manager: NETunnelProviderManager) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        var sawStarting = false
        while clock.now < deadline {
            try checkCancellation()
            switch manager.connection.status {
            case .connected: return
            case .connecting, .reasserting: sawStarting = true
            case .invalid, .disconnecting: throw TunnelError.connectionStopped
            case .disconnected:
                if sawStarting { throw TunnelError.connectionStopped }
            @unknown default: throw TunnelError.connectionStopped
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw TunnelError.connectionTimedOut
    }
}
#endif
