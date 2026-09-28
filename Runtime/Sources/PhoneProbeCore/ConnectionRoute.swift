import Foundation

/// The VPN peer is deliberately distinct from the phone's own interface address.
/// Addresses are configuration only and must not be included in evidence reports.
public struct ConnectionRoute: Sendable, Equatable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case localVPN
        case vpnAdvertisedPort
        case direct
    }

    public enum ValidationError: Error { case invalidPeer }
    public let mode: Mode
    public let peerBytes: [UInt8]
    public var peerHost: String { peerBytes.map(String.init).joined(separator: ".") }

    public init(mode: Mode, peer: String) throws {
        self.mode = mode
        if mode == .direct { peerBytes = []; return }
        let parts = peer.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 1 || (parts.count == 2 && parts[1] == "32") else {
            throw ValidationError.invalidPeer
        }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { throw ValidationError.invalidPeer }
        var bytes: [UInt8] = []
        for octet in octets {
            guard !octet.isEmpty, octet.utf8.allSatisfy({ (48...57).contains($0) }),
                  let byte = UInt8(octet), String(byte) == String(octet) else {
                throw ValidationError.invalidPeer
            }
            bytes.append(byte)
        }
        // This experiment accepts only a private IPv4 virtual peer.
        guard bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 192 && bytes[1] == 168) else {
            throw ValidationError.invalidPeer
        }
        peerBytes = bytes
    }

    public func port(advertised: UInt16) -> UInt16 {
        mode == .localVPN ? 49152 : advertised
    }
}
