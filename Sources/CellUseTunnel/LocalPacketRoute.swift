import Foundation

/// Reflects only TCP/UDP traffic addressed to this tunnel's configured peer.
/// Source/destination exchange preserves IPv4 and TCP/UDP pseudoheader sums.
struct LocalPacketRoute: Sendable {
    private let source: [UInt8]
    private let destination: [UInt8]

    init(configuration: TunnelConfiguration) {
        source = TunnelConfiguration.octets(configuration.interfaceAddress)!
        destination = TunnelConfiguration.octets(configuration.deviceAddress)!
    }

    func reflect(_ packet: Data) -> Data? {
        var bytes = Array(packet)
        guard bytes.count >= 20, bytes[0] >> 4 == 4 else { return nil }
        let headerLength = Int(bytes[0] & 0x0f) * 4
        let totalLength = Int(bytes[2]) * 256 + Int(bytes[3])
        guard headerLength >= 20, headerLength <= bytes.count,
              totalLength == bytes.count, totalLength >= headerLength,
              bytes[9] == 6 || bytes[9] == 17,
              Array(bytes[12..<16]) == source,
              Array(bytes[16..<20]) == destination else { return nil }
        // Preserve options, fragmentation fields, payload and checksums verbatim.
        bytes.replaceSubrange(12..<16, with: destination)
        bytes.replaceSubrange(16..<20, with: source)
        return Data(bytes)
    }
}
