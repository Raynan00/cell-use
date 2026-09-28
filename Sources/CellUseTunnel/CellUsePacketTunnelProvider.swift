#if os(iOS)
import Foundation
@preconcurrency import NetworkExtension
import Darwin

/// Subclass in your app's packet-tunnel extension and select it as the principal class.
open class CellUsePacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    // All mutable provider state is confined to this queue. Generation checks
    // discard callbacks from a stopped/replaced packet flow.
    private let queue = DispatchQueue(label: "dev.celluse.packet-route")
    private var generation: UUID?
    private var route: LocalPacketRoute?

    open override func startTunnel(options: [String: NSObject]?,
                                   completionHandler: @escaping (Error?) -> Void) {
        let completion = StartCompletion(completionHandler)
        queue.async {
            do {
                guard let tunnelProtocol = self.protocolConfiguration as? NETunnelProviderProtocol else {
                    throw TunnelError.invalidConfiguration
                }
                let configuration = try TunnelConfiguration(providerValues: tunnelProtocol.providerConfiguration)
                let id = UUID()
                self.generation = id
                self.route = LocalPacketRoute(configuration: configuration)
                let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: configuration.deviceAddress)
                let ipv4 = NEIPv4Settings(addresses: [configuration.interfaceAddress],
                                         subnetMasks: ["255.255.255.255"])
                ipv4.includedRoutes = [NEIPv4Route(destinationAddress: configuration.deviceAddress,
                                                  subnetMask: "255.255.255.255")]
                ipv4.excludedRoutes = [.default()]
                settings.ipv4Settings = ipv4
                settings.mtu = 1500
                // No DNS, IPv6 or default-route interception; no external server.
                self.setTunnelNetworkSettings(settings) { error in
                    self.queue.async {
                        guard self.generation == id else {
                            completion.call(TunnelError.connectionStopped)
                            return
                        }
                        if let error {
                            self.generation = nil
                            self.route = nil
                            completion.call(error)
                            return
                        }
                        self.readPackets(generation: id)
                        completion.call(nil)
                    }
                }
            } catch {
                self.generation = nil
                self.route = nil
                completion.call(error)
            }
        }
    }

    private func readPackets(generation id: UUID) {
        guard generation == id else { return }
        packetFlow.readPackets { packets, families in
            self.queue.async {
                guard self.generation == id, let route = self.route else { return }
                var reflected: [Data] = []
                for (packet, family) in zip(packets, families) where family.int32Value == AF_INET {
                    if let output = route.reflect(packet) { reflected.append(output) }
                }
                if !reflected.isEmpty && !self.packetFlow.writePackets(
                    reflected, withProtocols: reflected.map { _ in NSNumber(value: AF_INET) }) {
                    self.generation = nil
                    self.route = nil
                    self.cancelTunnelWithError(TunnelError.packetWriteFailed)
                    return
                }
                self.readPackets(generation: id)
            }
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason,
                                  completionHandler: @escaping () -> Void) {
        let completion = StopCompletion(completionHandler)
        queue.async {
            self.generation = nil
            self.route = nil
            completion.call()
        }
    }
}

// NetworkExtension's completion blocks predate Sendable annotations. Each is
// transferred to the serial provider queue and invoked exactly once there.
private final class StartCompletion: @unchecked Sendable {
    let call: (Error?) -> Void
    init(_ call: @escaping (Error?) -> Void) { self.call = call }
}
private final class StopCompletion: @unchecked Sendable {
    let call: () -> Void
    init(_ call: @escaping () -> Void) { self.call = call }
}
#endif
