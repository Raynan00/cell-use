import DeviceHubCore
import DeviceHubMedia
import Foundation
import Testing

@Test func mediaFailureDetailsAreScopedAndPayloadFree() throws {
    let recorder = MediaFailureProbe()
    let first = SessionGeneration(rawValue: UUID())
    let second = SessionGeneration(rawValue: UUID())
    recorder.record(generation: first, source: .videoToolbox,
        error: .systemFailure(.completeFrame, .decoderUnavailable), status: -12903)
    recorder.record(generation: second, source: .nativeVideoFailure)
    let events = recorder.snapshot(generation: first)
    #expect(events.count == 1)
    #expect(events.first?.status == -12903)
    #expect(events.first?.detail?.contains("decoderUnavailable") == true)
    let encoded = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
    #expect(!encoded.contains(first.rawValue.uuidString))
    #expect(!encoded.contains(second.rawValue.uuidString))
    #expect(!encoded.contains("bytes"))
    #expect(!encoded.contains("image"))
    #expect(recorder.snapshot(generation: second).first?.source == .nativeVideoFailure)
}

@Test func mediaFailureRecorderBoundsHistory() {
    let recorder = MediaFailureProbe()
    let generation = SessionGeneration(rawValue: UUID())
    for _ in 0..<40 {
        recorder.record(generation: generation, source: .decoderOutput, error: .outputFrameMissing)
    }
    let events = recorder.snapshot(generation: generation)
    #expect(events.count == 32)
    #expect(events.first?.sequence == 9)
    #expect(events.last?.sequence == 40)
}

@Test func actualDecoderSelectionIsScopedSeparatelyFromCurrentPreference() throws {
    let recorder = MediaFailureProbe()
    let first = SessionGeneration(rawValue: UUID())
    let second = SessionGeneration(rawValue: UUID())
    recorder.decoderMode = .softwareOnly
    recorder.recordConfiguration(generation: first, mode: recorder.decoderMode,
        hardwareAccelerated: false, queryStatus: 0)
    recorder.decoderMode = .systemDefault
    recorder.recordConfiguration(generation: second, mode: recorder.decoderMode,
        hardwareAccelerated: nil, queryStatus: -12900)
    let firstConfiguration = recorder.decoderConfigurations(generation: first)
    #expect(firstConfiguration.count == 1)
    #expect(firstConfiguration.first?.requestedMode == .softwareOnly)
    #expect(firstConfiguration.first?.hardwareAccelerated == false)
    #expect(recorder.decoderConfigurations(generation: second).first?.hardwareAccelerated == nil)
    let text = String(decoding: try JSONEncoder().encode(firstConfiguration), as: UTF8.self)
    #expect(!text.contains(first.rawValue.uuidString))
}
