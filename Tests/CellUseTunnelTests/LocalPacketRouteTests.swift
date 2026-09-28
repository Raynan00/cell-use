import Foundation
import Testing
@testable import CellUseTunnel

struct LocalPacketRouteTests {
    @Test func configurationRejectsInvalidOrBroadAddresses() throws {
        for address in ["127.0.0.1", "8.8.8.8", "0.0.0.0", "::1", "10.7.0.1/32",
                        "10.7.0", "10.7.0.256", "010.7.0.1", "10.7.0.1."] {
            #expect(throws: TunnelError.invalidAddresses) {
                try TunnelConfiguration(interfaceAddress: "10.7.1.1", deviceAddress: address)
            }
        }
        #expect(throws: TunnelError.invalidAddresses) {
            try TunnelConfiguration(interfaceAddress: "10.7.0.1", deviceAddress: "10.7.0.1")
        }
    }

    @Test func configurationRoundTripsAndRequiresVersion() throws {
        let custom = try TunnelConfiguration(interfaceAddress: "172.16.1.1", deviceAddress: "192.168.7.1")
        #expect(try TunnelConfiguration(providerValues: custom.providerValues) == custom)
        #expect(throws: TunnelError.invalidConfiguration) { try TunnelConfiguration(providerValues: nil) }
        var incompatible = custom.providerValues
        incompatible["cellUseTunnelVersion"] = "2"
        #expect(throws: TunnelError.invalidConfiguration) {
            try TunnelConfiguration(providerValues: incompatible)
        }
    }

    @Test func reflectionPreservesChecksumsPayloadAndOptions() throws {
        let route = LocalPacketRoute(configuration: .standard)
        for proto: UInt8 in [6, 17] {
            let original = packet(proto: proto, withOptions: true)
            let reflected = try #require(route.reflect(original))
            #expect(Array(reflected[12..<16]) == [10, 7, 0, 1])
            #expect(Array(reflected[16..<20]) == [10, 7, 1, 1])
            #expect(reflected[0..<12] == original[0..<12])
            #expect(reflected[20...] == original[20...])
            #expect(checksum(Array(reflected.prefix(24))) == 0)
            // TCP and UDP include both addresses in the transport pseudoheader.
            #expect(transportChecksum(reflected, headerLength: 24) == 0)
        }
    }

    @Test func dropsUnrelatedAddressesAndUnsupportedProtocols() {
        let route = LocalPacketRoute(configuration: .standard)
        for offset in [12, 16] {
            var unrelated = packet()
            unrelated[offset] = 192
            #expect(route.reflect(unrelated) == nil)
        }
        var ipv6 = packet(); ipv6[0] = 0x60
        #expect(route.reflect(ipv6) == nil)
        #expect(route.reflect(packet(proto: 1)) == nil)
        // Re-injecting an already reflected packet would create a loop.
        #expect(route.reflect(route.reflect(packet())!) == nil)
    }

    @Test func rejectsTruncationAndInconsistentLengths() {
        let route = LocalPacketRoute(configuration: .standard)
        let good = packet()
        for size in 0..<good.count { #expect(route.reflect(Data(good.prefix(size))) == nil) }
        var shortHeader = good; shortHeader[0] = 0x44
        #expect(route.reflect(shortHeader) == nil)
        var longHeader = good; longHeader[0] = 0x4f
        #expect(route.reflect(longHeader) == nil)
        var trailing = good; trailing.append(0)
        #expect(route.reflect(trailing) == nil)
    }

    @Test func preservesFragmentFieldsAndHandlesSlicedData() throws {
        let route = LocalPacketRoute(configuration: .standard)
        var fragment = packet()
        fragment[6] = 0x20; fragment[7] = 3
        let output = try #require(route.reflect(fragment))
        #expect(output[4..<12] == fragment[4..<12])
        let padded = Data([0, 0]) + packet()
        #expect(route.reflect(padded.dropFirst(2)) == route.reflect(packet()))
    }

    private func packet(proto: UInt8 = 17, withOptions: Bool = false) -> Data {
        let headerLength = withOptions ? 24 : 20
        let transportLength = proto == 6 ? 24 : 12
        var bytes = [UInt8](repeating: 0, count: headerLength + transportLength)
        bytes[0] = 0x40 | UInt8(headerLength / 4)
        bytes[3] = UInt8(bytes.count)
        bytes[8] = 64; bytes[9] = proto
        bytes.replaceSubrange(12..<20, with: [10, 7, 1, 1, 10, 7, 0, 1])
        if withOptions { bytes[20] = 1; bytes[21] = 1 }
        bytes[headerLength] = 0xc0; bytes[headerLength + 2] = 0xc0
        if proto == 6 { bytes[headerLength + 12] = 0x50 }
        else { bytes[headerLength + 5] = UInt8(transportLength) }
        bytes.replaceSubrange((bytes.count - 4)..<bytes.count, with: [1, 2, 3, 4])
        let transportSum = transportChecksum(Data(bytes), headerLength: headerLength)
        let checksumOffset = headerLength + (proto == 6 ? 16 : 6)
        bytes[checksumOffset] = UInt8(transportSum >> 8)
        bytes[checksumOffset + 1] = UInt8(transportSum & 255)
        let ipSum = checksum(Array(bytes.prefix(headerLength)))
        bytes[10] = UInt8(ipSum >> 8); bytes[11] = UInt8(ipSum & 255)
        return Data(bytes)
    }

    private func transportChecksum(_ packet: Data, headerLength: Int) -> UInt16 {
        let bytes = Array(packet)
        let length = bytes.count - headerLength
        return checksum(Array(bytes[12..<20]) + [0, bytes[9], UInt8(length >> 8), UInt8(length & 255)]
                        + Array(bytes[headerLength...]))
    }

    private func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        for index in stride(from: 0, to: bytes.count, by: 2) {
            sum += UInt32(bytes[index]) << 8
            if index + 1 < bytes.count { sum += UInt32(bytes[index + 1]) }
        }
        while sum > 0xffff { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }
}
