import Testing
@testable import PhoneProbeCore

@Test func vpnPeerAcceptsHostOrHostCIDR() throws {
    let route = try ConnectionRoute(mode: .localVPN, peer: " 10.7.0.1/32\n")
    #expect(route.peerBytes == [10, 7, 0, 1])
    #expect(route.peerHost == "10.7.0.1")
    #expect(route.port(advertised: 54321) == 49152)
    let advertised = try ConnectionRoute(mode: .vpnAdvertisedPort, peer: "10.7.0.1")
    #expect(advertised.port(advertised: 54321) == 54321)
}

@Test(arguments: ["", "10.7.0.1/24", "10.7.0.1/", "10.7.0.1/32/32", "10.7.0.256",
    "127.0.0.1", "0.0.0.0", "224.0.0.1", "8.8.8.8", "10.7.0", "010.7.0.1", "10.7.0.-1", "localhost"])
func vpnPeerRejectsAmbiguousOrNonPrivateDestinations(_ input: String) {
    #expect(throws: ConnectionRoute.ValidationError.self) { try ConnectionRoute(mode: .localVPN, peer: input) }
}

@Test func directRouteDoesNotDependOnVPNConfiguration() throws {
    let route = try ConnectionRoute(mode: .direct, peer: "")
    #expect(route.peerBytes.isEmpty)
    #expect(route.port(advertised: 54321) == 54321)
}
