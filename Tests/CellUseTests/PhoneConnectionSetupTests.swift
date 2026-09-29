import Foundation
import Testing
@testable import CellUse

@MainActor private final class SetupDriver: PhoneConnectionDriver {
    var onEvent: ((PhoneConnectionEvent) -> Void)?
    var devices = [PhonePairedDevice(id: "phone", name: "My iPhone")]
    var calls: [String] = []
    var openIssue: PhoneSetupIssue?
    var tunnelIssue: PhoneSetupIssue?
    var onOpen: (() -> Void)?
    var delayedOpen = false
    var delayedClose = false
    var suspended: CheckedContinuation<Void, Never>?
    var closing: CheckedContinuation<Void, Never>?
    func startTunnel() async throws { calls.append("tunnel"); if let tunnelIssue { throw tunnelIssue } }
    func savedDevices() async throws -> [PhonePairedDevice] { calls.append("saved"); return devices }
    func pair(onCode: @escaping @MainActor (String) -> Void) async throws -> PhonePairedDevice {
        calls.append("pair"); onCode("123456")
        return PhonePairedDevice(id: "new", name: "This iPhone")
    }
    func open(deviceID: String) async throws {
        calls.append("open:" + deviceID)
        if let openIssue { throw openIssue }
        if delayedOpen { await withCheckedContinuation { suspended = $0 } }
        onOpen?()
    }
    func close() async {
        calls.append("close")
        if delayedClose { await withCheckedContinuation { closing = $0 } }
    }
}

@MainActor private func settle(_ condition: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        await Task.yield()
    }
    throw WaitFailure.timedOut
}
private enum WaitFailure: Error { case timedOut }

@Test @MainActor func setupReusesPairingAndRequiresFreshPortraitAndInput() async throws {
    let driver = SetupDriver()
    var now = 10.0
    let setup = PhoneConnectionSetup(driver: driver, now: { now })
    setup.connect(); setup.connect()
    try await settle { setup.state == .checkingReadiness }
    #expect(driver.calls.filter { $0 == "tunnel" }.count == 1)
    #expect(!driver.calls.contains("pair"))
    driver.onEvent?(.inputReady(true))
    #expect(!setup.state.isReady)
    driver.onEvent?(.frame(capturedAt: 1, portrait: true))
    #expect(!setup.state.isReady)
    driver.onEvent?(.frame(capturedAt: 10, portrait: false))
    #expect(!setup.state.isReady)
    driver.onEvent?(.frame(capturedAt: 10, portrait: true))
    #expect(setup.state == .ready)
    now = 13; setup.tick()
    #expect(setup.state == .checkingReadiness)
    driver.onEvent?(.frame(capturedAt: 13, portrait: true))
    #expect(setup.state == .ready)
    driver.onEvent?(.inputReady(false))
    #expect(!setup.state.isReady)
    await setup.disconnect()
    #expect(setup.state == .idle)
}

@Test @MainActor func setupPairingContinuesWithoutASecondConnectAction() async throws {
    let driver = SetupDriver(); driver.devices = []
    let setup = PhoneConnectionSetup(driver: driver)
    var states: [PhoneConnectionState] = []
    setup.onChange = { states.append($0) }
    setup.connect()
    try await settle { setup.state == .pairingRequired }
    #expect(!driver.calls.contains("pair"))
    // Wait for the setup operation's defer after its final state callback.
    await Task.yield()
    setup.pair()
    try await settle { setup.state == .checkingReadiness }
    #expect(states.contains(.pairing(code: "123456")))
    #expect(driver.calls.contains("open:new"))
    #expect(!String(describing: setup.state).contains("123456"))
    await setup.disconnect()
}

@Test @MainActor func setupNeverGuessesBetweenSavedDevices() async throws {
    let driver = SetupDriver()
    driver.devices.append(PhonePairedDevice(id: "other", name: "Other iPhone"))
    let setup = PhoneConnectionSetup(driver: driver)
    setup.connect()
    try await settle { setup.state == .chooseDevice(driver.devices) }
    #expect(!driver.calls.contains(where: { $0.hasPrefix("open:") }))
    await Task.yield()
    setup.connect(deviceID: "other")
    try await settle { setup.state == .checkingReadiness }
    #expect(driver.calls.contains("open:other"))
    await setup.disconnect()
}

@Test @MainActor func invalidSelectionAndServiceFailureRemainActionable() async throws {
    let driver = SetupDriver(), setup = PhoneConnectionSetup(driver: SetupDriver())
    setup.connect(deviceID: "unknown")
    try await settle { setup.state == .needsAction(.invalidSelection) }
    await setup.disconnect()
    driver.openIssue = .prepareServices
    let failed = PhoneConnectionSetup(driver: driver)
    failed.connect()
    try await settle { failed.state == .needsAction(.prepareServices) }
    #expect(driver.calls.last == "close")
    await failed.disconnect()
}

@Test @MainActor func oldSessionCallbacksCannotRestoreReadiness() async throws {
    let driver = SetupDriver()
    let connection = PhoneConnectionSetup(driver: driver, now: { 10 })
    connection.connect()
    try await settle { connection.state == .checkingReadiness }
    let old = driver.onEvent
    await connection.disconnect()
    connection.connect()
    try await settle { connection.state == .checkingReadiness }
    old?(.inputReady(true)); old?(.frame(capturedAt: 10, portrait: true))
    old?(.ended(.pairing))
    #expect(connection.state == .checkingReadiness)
    await connection.disconnect()
}

@Test @MainActor func cancellationClosesLateOpenBeforeReconnect() async throws {
    let driver = SetupDriver(); driver.delayedOpen = true
    let setup = PhoneConnectionSetup(driver: driver)
    setup.connect()
    try await settle { driver.suspended != nil }
    let stop = Task { await setup.disconnect() }
    try await settle { setup.state == .stopping }
    setup.connect()
    #expect(driver.calls.filter { $0 == "tunnel" }.count == 1)
    driver.suspended?.resume(); driver.suspended = nil
    await stop.value
    #expect(setup.state == .idle)
    #expect(driver.calls.last == "close")
}

@Test @MainActor func endedDuringOpenCannotBecomeReady() async throws {
    let driver = SetupDriver()
    driver.onOpen = { [weak driver] in driver?.onEvent?(.ended(.connectionLost)) }
    let setup = PhoneConnectionSetup(driver: driver)
    setup.connect()
    try await settle { setup.state == .needsAction(.connectionLost) }
    await setup.disconnect()
    #expect(setup.state == .idle)
    #expect(driver.calls.last == "close")
}

@Test @MainActor func readinessTimeoutClosesSessionAndReportsMissingInput() async throws {
    let driver = SetupDriver()
    var now = 10.0
    let setup = PhoneConnectionSetup(driver: driver, now: { now }, readinessTimeout: 5)
    setup.connect()
    try await settle { setup.state == .checkingReadiness }
    now = 16
    driver.onEvent?(.frame(capturedAt: now, portrait: true))
    try await settle { setup.state == .needsAction(.inputUnavailable) }
    await setup.disconnect()
    #expect(setup.state == .idle)
}

@Test @MainActor func failedTunnelNeverAttemptsPairingOrNativeConnection() async throws {
    let driver = SetupDriver(); driver.tunnelIssue = .tunnel
    let setup = PhoneConnectionSetup(driver: driver)
    setup.connect()
    try await settle { setup.state == .needsAction(.tunnel) }
    #expect(driver.calls == ["close", "tunnel", "close"])
    await setup.disconnect()
}

@Test @MainActor func concurrentDisconnectsBothWaitForTeardown() async throws {
    let driver = SetupDriver()
    let connection = PhoneConnectionSetup(driver: driver)
    connection.connect()
    try await settle { connection.state == .checkingReadiness }
    driver.delayedClose = true
    let first = Task { await connection.disconnect() }
    try await settle { driver.closing != nil }
    var secondFinished = false
    let second = Task { await connection.disconnect(); secondFinished = true }
    for _ in 0..<10 { await Task.yield() }
    #expect(!secondFinished)
    driver.delayedClose = false; driver.closing?.resume(); driver.closing = nil
    await first.value; await second.value
    #expect(connection.state == .idle)
    #expect(driver.calls.filter { $0 == "close" }.count == 2)
}
