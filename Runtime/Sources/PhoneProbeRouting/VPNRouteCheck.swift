import Darwin
import Foundation
import PhoneProbeCore

enum VPNRouteStatus: String, Codable, Sendable {
    case direct, tunnel, localAddress, otherInterface, unavailable
}

/// UDP connect chooses a source through the routing table without sending data.
/// A utun existing somewhere is insufficient: this destination must use it.
enum VPNRouteCheck {
    static func status(for route: ConnectionRoute) -> VPNRouteStatus {
        guard route.mode != .direct else { return .direct }
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return .unavailable }
        defer { close(descriptor) }
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(49152).bigEndian
        guard route.peerHost.withCString({ inet_pton(AF_INET, $0, &destination.sin_addr) }) == 1 else {
            return .unavailable
        }
        let connected = withUnsafePointer(to: &destination) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return .unavailable }
        var source = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let found = withUnsafeMutablePointer(to: &source) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard found == 0 else { return .unavailable }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return .unavailable }
        defer { freeifaddrs(interfaces) }
        var cursor = interfaces
        var sourceOnTunnel = false
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, Int32(address.pointee.sa_family) == AF_INET else { continue }
            let ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            // Catch accidentally pasting the VPN's Tunnel IP instead of Device IP.
            if ip == destination.sin_addr.s_addr { return .localAddress }
            if ip == source.sin_addr.s_addr,
               String(cString: item.pointee.ifa_name).hasPrefix("utun") {
                sourceOnTunnel = true
            }
        }
        return sourceOnTunnel ? .tunnel : .otherInterface
    }
}
