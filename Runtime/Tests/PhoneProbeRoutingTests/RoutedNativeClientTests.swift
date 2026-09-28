import DeviceHubCore
import DeviceHubTransport
import Foundation
import PhoneProbeCore
import Testing
@testable import PhoneProbeRouting

private func fixture() throws -> NativeRemoteSessionRequest {
    try NativeRemoteSessionRequest(generation: SessionGeneration(rawValue: UUID()),
        controller: NativeControllerIdentity(identifier: UUID(), udid: "synthetic-controller",
            longTermSecretKey: Data(repeating: 1, count: 32), alternateIRK: Data(repeating: 2, count: 16)),
        target: NativeTargetPairingRecord(deviceID: DeviceID(rawValue: "synthetic-device"),
            accountIdentifier: "synthetic-account", peerIdentifier: "synthetic-peer",
            peerPublicKey: Data(repeating: 3, count: 32), peerAlternateIRK: Data(repeating: 4, count: 16),
            displayName: "Fixture", productType: "FixturePhone", completion: .committed),
        service: NativeRemoteService(endpoint: NativeResolvedEndpoint(family: .ipv6,
            address: Data([0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2]),
            scopeID: 8, port: 54321), identifier: UUID(), authTags: [Data([1, 2, 3, 4, 5, 6])]))
}

private actor Calls {
    var requests: [NativeRemoteSessionRequest] = []
    func add(_ value: NativeRemoteSessionRequest) { requests.append(value) }
}

private func stub(_ calls: Calls, failure: NativeSessionFailure? = nil) -> NativeSessionClient {
    NativeSessionClient(capabilities: .requiredLiveControl,
        makePairingSession: { (_) async throws(NativeSessionFailure) in inertSession() },
        makeRemoteSession: { (request) async throws(NativeSessionFailure) in
            await calls.add(request)
            return inertSession()
        },
        verifyRemotePairing: { (request) async throws(NativeSessionFailure) in
            await calls.add(request)
            if let failure { throw failure }
        })
}

private func inertSession() -> NativeSession {
    NativeSession(events: AsyncThrowingStream { $0.finish() },
        start: {}, completePersistence: { _, _ in }, send: { _ in }, cancel: {})
}

@Test func routingChangesOnlyDestinationAndPreservesAuthenticatedIdentity() throws {
    let original = try fixture()
    let route = try ConnectionRoute(mode: .localVPN, peer: "10.7.0.1/32")
    let routed = try RoutedNativeClient.request(original, route: route)
    #expect(routed.service.endpoint.address == Data([10, 7, 0, 1]))
    #expect(routed.service.endpoint.family == .ipv4)
    #expect(routed.service.endpoint.scopeID == 0)
    #expect(routed.service.endpoint.port == 49152)
    #expect(routed.service.identifier == original.service.identifier)
    #expect(routed.service.authTags == original.service.authTags)
    #expect(routed.generation == original.generation)
    #expect(routed.controller.identifier == original.controller.identifier)
    #expect(routed.controller.longTermSecretKey == original.controller.longTermSecretKey)
    #expect(routed.controller.alternateIRK == original.controller.alternateIRK)
    #expect(routed.controller.udid == original.controller.udid)
    #expect(routed.target.peerPublicKey == original.target.peerPublicKey)
    #expect(routed.target.peerAlternateIRK == original.target.peerAlternateIRK)
    #expect(routed.target.peerIdentifier == original.target.peerIdentifier)
    #expect(routed.target.deviceID == original.target.deviceID)
    #expect(routed.target.completion == original.target.completion)
    let direct = try RoutedNativeClient.request(original, route: ConnectionRoute(mode: .direct, peer: ""))
    #expect(direct.service.endpoint == original.service.endpoint)
    let advertised = try RoutedNativeClient.request(original,
        route: ConnectionRoute(mode: .vpnAdvertisedPort, peer: "10.7.0.1"))
    #expect(advertised.service.endpoint.port == original.service.endpoint.port)
}

@Test func discoveryAndSessionUseTheSameVPNRoute() async throws {
    let calls = Calls()
    let diagnostics = RouteDiagnostics(mode: .localVPN)
    let client = RoutedNativeClient.wrap(stub(calls),
        route: try ConnectionRoute(mode: .localVPN, peer: "10.7.0.1"), diagnostics: diagnostics, check: { _ in .tunnel })
    let request = try fixture()
    try await client.verifyRemotePairing(request)
    let session = try await client.makeRemoteSession(request)
    try await session.cancel()
    let captured = await calls.requests
    #expect(captured.count == 2)
    #expect(captured.allSatisfy { $0.service.endpoint.address == Data([10, 7, 0, 1]) && $0.service.endpoint.port == 49152 })
    let snapshot = await diagnostics.snapshot()
    #expect(snapshot.verificationSuccesses == 1)
    #expect(snapshot.verificationAttempts == 1)
}

@Test(arguments: [VPNRouteStatus.localAddress, .otherInterface, .unavailable])
func missingVPNNeverCallsNativeTransport(_ status: VPNRouteStatus) async throws {
    let calls = Calls()
    let diagnostics = RouteDiagnostics(mode: .localVPN)
    let client = RoutedNativeClient.wrap(stub(calls),
        route: try ConnectionRoute(mode: .localVPN, peer: "10.7.0.1"), diagnostics: diagnostics, check: { _ in status })
    let request = try fixture()
    await #expect(throws: NativeSessionFailure.self) { try await client.verifyRemotePairing(request) }
    await #expect(throws: NativeSessionFailure.self) { try await client.makeRemoteSession(request) }
    #expect(await calls.requests.isEmpty)
    #expect(await diagnostics.snapshot().verificationSuccesses == 0)
}

@Test func authenticationFailureIsPreservedWithoutFallbackOrFalseSuccess() async throws {
    let calls = Calls()
    let diagnostics = RouteDiagnostics(mode: .localVPN)
    let failure = NativeSessionFailure(code: "pair_verify_failed", stage: "pair_verify_m2_signature", retryable: false)
    let client = RoutedNativeClient.wrap(stub(calls, failure: failure),
        route: try ConnectionRoute(mode: .localVPN, peer: "10.7.0.1"), diagnostics: diagnostics, check: { _ in .tunnel })
    await #expect(throws: failure) { try await client.verifyRemotePairing(fixture()) }
    #expect(await calls.requests.count == 1)
    let snapshot = await diagnostics.snapshot()
    #expect(snapshot.verificationSuccesses == 0)
    #expect(snapshot.events.last?.stage == "pair_verify_m2_signature")
    let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    #expect(!json.contains("10.7.0.1"))
    #expect(!json.contains("synthetic-device"))
    #expect(!json.contains("synthetic-peer"))
}
