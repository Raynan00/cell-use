import DeviceHubCore
import DeviceHubMedia
import DeviceHubClient
import PhoneProbeCore
import SwiftUI
import UIKit

@main
struct PhoneProbeApp: App {
    init() { ContinuedWork.shared.prepareConfiguration() }
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

struct ProbeView: View {
    @State private var model = ProbeModel()
    @State private var showingReport = false
    @State private var showingTargetPicker = false
    @State private var targetPickerFrame: RemoteDisplayFrame?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("cell-use").font(.largeTitle.bold())
                    Text("Can this iPhone observe and control itself?")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    Text(model.challenge)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .textSelection(.disabled)
                    Text("Reusable agent runner demo").font(.headline)
                    Text("Connect, open Calculator at 0 for five seconds, then return and select the 7 key in its image. Start Extended run, arm the agent demo, then leave Calculator at 0 untouched for 110 seconds. The first action waits until 60 seconds; check whether it reaches 77.")
                        .font(.callout)
                    Text("Images received: \(model.receivedFrameCount)")
                        .font(.system(.callout, design: .monospaced))
                }
                .padding().background(.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))

                Text(model.message).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                if let code = model.pairingCode {
                    Text(code).font(.largeTitle.monospaced().bold()).privacySensitive()
                    Text("Enter this code in Developer Mode on this iPhone. It is omitted from the report.")
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("1 · Pair and connect").font(.headline)
                    Text("Normal Connect captures your target. Extended run gives the agent demo a longer execution window. Arm promptly after it connects.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Connection route").font(.subheadline.bold())
                    Picker("Connection route", selection: $model.routeMode) {
                        Text("Local VPN · port 49152").tag(ConnectionRoute.Mode.localVPN)
                        Text("Local VPN · advertised port").tag(ConnectionRoute.Mode.vpnAdvertisedPort)
                        Text("Direct Wi-Fi · comparison").tag(ConnectionRoute.Mode.direct)
                    }
                    .disabled(!model.canStart)
                    if model.routeMode != .direct {
                        TextField("LocalDevVPN Device IP", text: $model.vpnPeer)
                            .textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(!model.canStart)
                    }
                    Button("Apply route and retry") { Task { await model.applyRoute() } }
                        .buttonStyle(.bordered)
                        .disabled(model.pairing || model.connecting || model.closing || model.hasSession || model.applyingRoute)
                    Text(model.routeMessage).font(.caption).foregroundStyle(.secondary)
                    Text(model.discoveryMessage).font(.caption).foregroundStyle(.secondary)
                    if !model.discoveryActive {
                        Button("Retry discovery", action: model.startDiscovery)
                            .buttonStyle(.bordered).disabled(!model.canStart)
                    }
                    Button("Pair this iPhone", action: model.startPairing)
                        .buttonStyle(.bordered).disabled(!model.canStart)
                    ForEach(model.devices) { device in
                        Button {
                            model.connect(to: device)
                        } label: {
                            Label(device.reachability == .reachable
                                ? "Connect · \(device.name)"
                                : "Searching · \(device.name)", systemImage: "iphone")
                        }
                        .disabled(!model.canStart || !model.discoveryActive || device.reachability != .reachable)
                        Button("Extended run") { model.startExtended(to: device) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canStartExtended || device.reachability != .reachable || !model.continuedWork.snapshot.bundleMatchesConfiguration)
                    }
                    Button("Arm agent demo", action: model.armAgentDemo)
                        .buttonStyle(.borderedProminent).disabled(!model.canArmAgentDemo)
                    Button("Arm swipe test") { model.armControlDemo("swipe") }
                        .buttonStyle(.bordered).disabled(!model.canArmControlDemo)
                    Button("Arm text test") { model.armControlDemo("text") }
                        .buttonStyle(.bordered).disabled(!model.canArmControlDemo)
                    Text("New controls use normal Connect. Prepare Settings for swipe, or a blank Notes draft with an active cursor for text. Enable portrait rotation lock. After arming, switch directly to that app.")
                        .font(.caption)
                    Text(model.agentHint).font(.callout)
                    Text("Background work: \(model.continuedWork.snapshot.status)")
                        .font(.caption)
                    if !model.continuedWork.snapshot.bundleMatchesConfiguration {
                        Text("Extended run needs matching signing configuration. The normal Calculator test is still available; View report records this setup issue.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text("Choose the same iPhone running this app. Pairing another device is not proof of self-control.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("2 · Inspect background observation").font(.headline)
                    evidenceRow("Screen received", passed: model.evidence.observedImage)
                    evidenceRow("Input channel ready", passed: model.inputReady)
                    evidenceRow("Target selected", passed: model.selectedTap.targetSelected)
                    DisclosureGroup("Single-tap test (previous experiment)") {
                        evidenceRow("Tap accepted by transport", passed: model.selectedTap.commandAccepted)
                        evidenceRow("After-image received", passed: model.selectedTap.afterImageReceived)
                        evidenceRow("You confirmed 0 changed to 7", passed: model.selectedTap.userConfirmedZeroToSeven)
                        Text("Selected tap: \(model.selectedTap.status)").font(.caption)
                        Button(model.extendedRun ? "Arm tap after 60 seconds" : "Arm selected tap", action: model.armSelectedTap)
                            .buttonStyle(.borderedProminent).disabled(!model.canArmSelectedTap)
                        Text(model.selectedTapHint).font(.callout)
                        Text("Arming permits one tap only, after two fresh images match your selected reference. If disconnected, reconnect first; the selected reference is kept in memory.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Images received in background: \(model.evidence.framesReceivedInBackground)")
                    if let frame = model.backgroundSample, let delay = model.backgroundSampleDelay {
                        Text("Background sample · \(delay, specifier: "%.1f") seconds after leaving")
                            .font(.caption)
                        Image(uiImage: UIImage(cgImage: frame.image))
                            .resizable().scaledToFit().frame(maxHeight: 300)
                            .privacySensitive()
                        Button("Select 7 in this image") {
                            targetPickerFrame = frame
                            showingTargetPicker = true
                        }.buttonStyle(.bordered)
                        Text("Check whether this shows Calculator. The image stays in memory and is excluded from View report.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No image received beyond two seconds in the background yet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let run = model.agentRun { AgentRunnerPanel(run: run) }
                    if let result = model.selectedResult {
                        Text("After the tap - inspect the Calculator display").font(.headline)
                        Image(uiImage: UIImage(cgImage: result.image))
                            .resizable().scaledToFit().frame(maxHeight: 300).privacySensitive()
                        Button("I saw Calculator change from 0 to 7", action: model.confirmSelectedResult)
                            .buttonStyle(.bordered)
                            .disabled(!model.selectedTap.commandAccepted || !model.selectedTap.afterImageReceived)
                        Text("This records your confirmation, not automatic verification.").font(.caption)
                    }
                    if model.evidence.backgroundLeaseExpired {
                        Text("Background allowance expired").foregroundStyle(.orange)
                    }
                }

                HStack {
                    Button("Stop", role: .destructive) { Task { await model.stop() } }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("View report") {
                        Task {
                            await model.refreshDiagnostics()
                            showingReport = true
                        }
                    }.buttonStyle(.bordered)
                }
                Text("Research prototype · build 20 · iOS 27 · scripted client, no model")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .scrollDisabled(model.testing)
        .task {
            await model.prepare()
        }
        .task {
            while !Task.isCancelled {
                await model.refreshRouteDiagnostics()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in model.sceneChanged(isBackground: phase == .background) }
        .sheet(isPresented: $showingTargetPicker) {
            if let frame = targetPickerFrame {
                TargetPicker(frame: frame) { x, y in model.selectTarget(frame: frame, x: x, y: y) }
            }
        }
        .sheet(isPresented: $showingReport) {
            NavigationStack {
                ScrollView {
                    Text(model.report).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).padding()
                }
                .navigationTitle("Probe evidence")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Refresh") { Task { await model.refreshDiagnostics() } }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingReport = false } }
                    ToolbarItem(placement: .bottomBar) { ShareLink(item: model.report) }
                }
            }
        }
    }

    private func evidenceRow(_ title: String, passed: Bool) -> some View {
        Label(title, systemImage: passed ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(passed ? Color.green : Color.secondary)
            .font(.callout)
    }
}
