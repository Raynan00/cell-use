import Foundation

/// The two /32 addresses used by the on-device developer-service route.
public struct TunnelConfiguration: Equatable, Sendable {
    public let interfaceAddress: String
    public let deviceAddress: String

    public static let standard = try! TunnelConfiguration(
        interfaceAddress: "10.7.1.1", deviceAddress: "10.7.0.1")

    public init(interfaceAddress: String, deviceAddress: String) throws {
        guard let local = Self.octets(interfaceAddress),
              let peer = Self.octets(deviceAddress),
              Self.isPrivate(local), Self.isPrivate(peer), local != peer else {
            throw TunnelError.invalidAddresses
        }
        self.interfaceAddress = interfaceAddress
        self.deviceAddress = deviceAddress
    }

    var providerValues: [String: String] {
        ["cellUseTunnelVersion": "1", "interfaceAddress": interfaceAddress,
         "deviceAddress": deviceAddress]
    }

    init(providerValues: [String: Any]?) throws {
        guard let values = providerValues,
              values["cellUseTunnelVersion"] as? String == "1",
              let local = values["interfaceAddress"] as? String,
              let peer = values["deviceAddress"] as? String else {
            throw TunnelError.invalidConfiguration
        }
        try self.init(interfaceAddress: local, deviceAddress: peer)
    }

    static func octets(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let bytes = parts.compactMap { UInt8($0) }
        guard bytes.count == 4,
              zip(parts, bytes).allSatisfy({ String($0.0) == String($0.1) }) else { return nil }
        return bytes
    }

    private static func isPrivate(_ bytes: [UInt8]) -> Bool {
        bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 192 && bytes[1] == 168)
    }
}

public enum TunnelError: Error, Equatable, Sendable, LocalizedError {
    case invalidAddresses
    case invalidConfiguration
    case operationInProgress
    case configurationInUse
    case connectionTimedOut
    case connectionStopped
    case packetWriteFailed

    public var errorDescription: String? {
        switch self {
        case .invalidAddresses: "Use two distinct private IPv4 addresses without subnet suffixes."
        case .invalidConfiguration: "The cell-use tunnel configuration is missing or incompatible."
        case .operationInProgress: "A tunnel operation is already in progress."
        case .configurationInUse: "Stop the tunnel before changing its addresses."
        case .connectionTimedOut: "The cell-use tunnel did not connect in time."
        case .connectionStopped: "The cell-use tunnel stopped before it connected."
        case .packetWriteFailed: "The system could not receive a tunnel packet."
        }
    }
}
