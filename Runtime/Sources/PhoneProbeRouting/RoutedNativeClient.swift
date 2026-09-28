import DeviceHubTransport
import Foundation
import PhoneProbeCore

actor RouteDiagnostics {
    struct Event: Encodable, Sendable {
        let sequence: Int
        let operation: String
        let outcome: String
        let code: String?
        let stage: String?
    }
    struct Snapshot: Encodable, Sendable {
        let mode: ConnectionRoute.Mode
        var path: VPNRouteStatus = .unavailable
        var verificationAttempts = 0
        var verificationSuccesses = 0
        var events: [Event] = []
    }
    private var value: Snapshot
    private var sequence = 0
    init(mode: ConnectionRoute.Mode) { value = Snapshot(mode: mode) }
    func snapshot() -> Snapshot { value }
    func path(_ path: VPNRouteStatus) { value.path = path }
    func record(_ operation: String, _ outcome: String, failure: NativeSessionFailure? = nil) {
        sequence += 1
        if operation == "verify", outcome == "started" { value.verificationAttempts += 1 }
        if operation == "verify", outcome == "succeeded" { value.verificationSuccesses += 1 }
        value.events.append(Event(sequence: sequence, operation: operation, outcome: outcome,
            code: failure?.code, stage: failure?.stage))
        value.events = Array(value.events.suffix(24))
    }
}

enum RoutedNativeClient {
    /// Change only the destination. Keep Bonjour identity, authentication tags,
    /// keys, target, and generation intact. Never fall back to unauthenticated I/O.
    static func request(_ request: NativeRemoteSessionRequest, route: ConnectionRoute)
        throws(NativeSessionFailure) -> NativeRemoteSessionRequest {
        guard route.mode != .direct else { return request }
        do {
            let endpoint = try NativeResolvedEndpoint(family: .ipv4, address: Data(route.peerBytes),
                scopeID: 0, port: route.port(advertised: request.service.endpoint.port))
            let service = try NativeRemoteService(endpoint: endpoint,
                identifier: request.service.identifier, authTags: request.service.authTags)
            return NativeRemoteSessionRequest(generation: request.generation,
                controller: request.controller, target: request.target, service: service)
        } catch {
            throw NativeSessionFailure(code: "invalid_argument", stage: "native_boundary", retryable: false)
        }
    }

    static func wrap(_ native: NativeSessionClient, route: ConnectionRoute,
        diagnostics: RouteDiagnostics,
        check: @escaping @Sendable (ConnectionRoute) -> VPNRouteStatus = VPNRouteCheck.status
    ) -> NativeSessionClient {
        NativeSessionClient(capabilities: native.capabilities,
            makePairingSession: { (request) async throws(NativeSessionFailure) in
                try await native.makePairingSession(request)
            },
            makeRemoteSession: { (original) async throws(NativeSessionFailure) in
                try await validateRoute(route, diagnostics: diagnostics, check: check)
                let routed = try request(original, route: route)
                await diagnostics.record("session", "creating")
                do throws(NativeSessionFailure) {
                    let session = try await native.makeRemoteSession(routed)
                    await diagnostics.record("session", "created")
                    return session
                } catch {
                    await diagnostics.record("session", "failed", failure: error)
                    throw error
                }
            },
            verifyRemotePairing: { (original) async throws(NativeSessionFailure) in
                try await validateRoute(route, diagnostics: diagnostics, check: check)
                let routed = try request(original, route: route)
                await diagnostics.record("verify", "started")
                do throws(NativeSessionFailure) {
                    try await native.verifyRemotePairing(routed)
                    await diagnostics.record("verify", "succeeded")
                } catch {
                    await diagnostics.record("verify", "failed", failure: error)
                    throw error
                }
            })
    }

    private static func validateRoute(_ route: ConnectionRoute, diagnostics: RouteDiagnostics,
        check: @Sendable (ConnectionRoute) -> VPNRouteStatus) async throws(NativeSessionFailure) {
        let status = check(route)
        await diagnostics.path(status)
        guard status == .direct || status == .tunnel else {
            let failure = NativeSessionFailure(code: "invalid_tunnel_address", stage: "native_boundary", retryable: true)
            await diagnostics.record("route", "unavailable", failure: failure)
            throw failure
        }
    }
}
