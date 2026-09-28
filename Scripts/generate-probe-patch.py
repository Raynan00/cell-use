import difflib
import hashlib
import json
import argparse
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description='Regenerate the pinned transport patch from a pristine upstream checkout.')
parser.add_argument('--reference', type=Path, required=True, help='Unmodified checkout at the revision in dependencies.json')
reference = parser.parse_args().reference.resolve()
prefix = 'Packages/DeviceHubKit/Sources/'
changes = {}

path = prefix + 'DeviceHubMedia/DeviceHubMedia.swift'
original = (reference / path).read_text()
addition = '''

/// Phone Probe's bounded diagnostics and explicit decoder-selection experiment.
/// Selection is captured when each decoder is created; authentication is unchanged.
public final class MediaFailureProbe: @unchecked Sendable {
    public static let shared = MediaFailureProbe()

    public enum DecoderMode: String, Codable, Sendable {
        case systemDefault, softwareOnly
    }

    public struct DecoderConfiguration: Codable, Equatable, Sendable {
        public let requestedMode: DecoderMode
        public let hardwareAccelerated: Bool?
        public let hardwareQueryStatus: Int32
    }

    public enum Source: String, Codable, Sendable {
        case videoToolbox, decoderSubmission, decoderOutput, missingConfiguration
        case nativeVideoFailure, nativeBufferSaturated, nativeInvalidAccessUnit, nativeInvalidConfiguration
        case nativeInvalidSequence, nativeMissingConfiguration, nativeMultipleConsumers
        case videoStreamEnded, frameStreamEnded
        case videoConsumerFailure, frameConsumerFailure
    }

    public struct Event: Codable, Equatable, Sendable {
        public let sequence: Int
        public let source: Source
        public let detail: String?
        public let status: Int32?
        public let nativeCode: String?
        public let nativeStage: String?
    }

    private let lock = NSLock()
    private var sequence = 0
    private var entries: [(UUID, Event)] = []
    private var selectedMode: DecoderMode = .systemDefault
    private var configurations: [(UUID, DecoderConfiguration)] = []
    public init() {}

    public var decoderMode: DecoderMode {
        get { lock.withLock { selectedMode } }
        set { lock.withLock { selectedMode = newValue } }
    }

    public func recordConfiguration(generation: SessionGeneration, mode: DecoderMode,
                                    hardwareAccelerated: Bool?, queryStatus: Int32) {
        lock.withLock {
            configurations.append((generation.rawValue, DecoderConfiguration(requestedMode: mode,
                hardwareAccelerated: hardwareAccelerated, hardwareQueryStatus: queryStatus)))
            if configurations.count > 16 { configurations.removeFirst(configurations.count - 16) }
        }
    }

    public func decoderConfigurations(generation: SessionGeneration) -> [DecoderConfiguration] {
        lock.withLock { configurations.filter { $0.0 == generation.rawValue }.map { $0.1 } }
    }

    public func record(generation: SessionGeneration, source: Source,
                       error: MediaDecoderError? = nil, status: Int32? = nil,
                       nativeCode: String? = nil, nativeStage: String? = nil) {
        lock.withLock {
            sequence += 1
            // MediaDecoderError is a closed vocabulary with no payload strings.
            let detail = error.map { String(describing: $0) }
            entries.append((generation.rawValue,
                Event(sequence: sequence, source: source, detail: detail, status: status,
                      nativeCode: nativeCode, nativeStage: nativeStage)))
            if entries.count > 32 { entries.removeFirst(entries.count - 32) }
        }
    }

    public func snapshot(generation: SessionGeneration) -> [Event] {
        lock.withLock { entries.filter { $0.0 == generation.rawValue }.map { $0.1 } }
    }
}
'''
changes[path] = (original, original.rstrip() + '\n' + addition)

path = prefix + 'DeviceHubTransport/RemoteSessionMediaOperation.swift'
original = (reference / path).read_text()
modified = original.replace('''                    else {
                        throw DeviceHubError.decoderFailed''', '''                    else {
                        MediaFailureProbe.shared.record(generation: generation, source: .missingConfiguration)
                        throw DeviceHubError.decoderFailed''')
modified = modified.replace('''                case .failed:
                    throw''', '''                case let .failed(failure):
                    switch failure.reason {
                    case .bufferSaturated:
                        MediaFailureProbe.shared.record(generation: generation, source: .nativeBufferSaturated)
                    case .invalidAccessUnit:
                        MediaFailureProbe.shared.record(generation: generation, source: .nativeInvalidAccessUnit)
                    case .invalidConfiguration:
                        MediaFailureProbe.shared.record(generation: generation, source: .nativeInvalidConfiguration)
                    case .invalidSequence:
                        MediaFailureProbe.shared.record(generation: generation, source: .nativeInvalidSequence)
                    case .missingConfiguration:
                        MediaFailureProbe.shared.record(generation: generation, source: .nativeMissingConfiguration)
                    case .multipleConsumers:
                        MediaFailureProbe.shared.record(generation: generation, source: .nativeMultipleConsumers)
                    case let .native(native):
                        MediaFailureProbe.shared.record(generation: generation, source: .nativeVideoFailure,
                            nativeCode: native.code, nativeStage: native.stage)
                    }
                    throw''')
modified = modified.replace('''            throw DeviceHubError.decoderFailed
        } catch is CancellationError''', '''            MediaFailureProbe.shared.record(generation: generation, source: .videoStreamEnded)
            throw DeviceHubError.decoderFailed
        } catch is CancellationError''')
needle = '''        } catch let error as MediaDecoderError {
            await terminateForMediaFailure('''
assert modified.count(needle) == 2
modified = modified.replace(needle, '''        } catch let error as MediaDecoderError {
            MediaFailureProbe.shared.record(generation: generation, source: .decoderSubmission, error: error)
            await terminateForMediaFailure(''', 1)
modified = modified.replace(needle, '''        } catch let error as MediaDecoderError {
            MediaFailureProbe.shared.record(generation: generation, source: .decoderOutput, error: error)
            await terminateForMediaFailure(''', 1)
needle = '''        } catch {
            await terminateForMediaFailure(.decoderFailed)'''
assert modified.count(needle) == 2
modified = modified.replace(needle, '''        } catch {
            MediaFailureProbe.shared.record(generation: generation, source: .videoConsumerFailure)
            await terminateForMediaFailure(.decoderFailed)''', 1)
modified = modified.replace(needle, '''        } catch {
            MediaFailureProbe.shared.record(generation: generation, source: .frameConsumerFailure)
            await terminateForMediaFailure(.decoderFailed)''', 1)
modified = modified.replace('''            await terminateForMediaFailure(.decoderFailed)
        } catch is CancellationError''', '''            MediaFailureProbe.shared.record(generation: generation, source: .frameStreamEnded)
            await terminateForMediaFailure(.decoderFailed)
        } catch is CancellationError''')
changes[path] = (original, modified)

path = prefix + 'DeviceHubMedia/HEVCVideoDecoder.swift'
original = (reference / path).read_text()
modified = original.replace('''        guard status == noErr else {
            DeviceHubMediaTrace.emit(''', '''        guard status == noErr else {
            MediaFailureProbe.shared.record(generation: generation, source: .videoToolbox,
                error: mediaSystemError(operation: .submitFrame, status: status), status: status)
            DeviceHubMediaTrace.emit(''', 1)
modified = modified.replace('''        guard creationStatus == noErr, let session else {
            throw''', '''        guard creationStatus == noErr, let session else {
            MediaFailureProbe.shared.record(generation: generation, source: .videoToolbox,
                error: mediaSystemError(operation: .createDecompressionSession, status: creationStatus),
                status: creationStatus)
            throw''', 1)
modified = modified.replace('''        guard status == noErr else {
            fail(''', '''        guard status == noErr else {
            MediaFailureProbe.shared.record(generation: metadata.generation, source: .videoToolbox,
                error: mediaSystemError(operation: .completeFrame, status: status), status: status)
            fail(''', 1)
modified = modified.replace('''        guard conversionStatus == noErr, let image else {
            fail(''', '''        guard conversionStatus == noErr, let image else {
            MediaFailureProbe.shared.record(generation: metadata.generation, source: .videoToolbox,
                error: mediaSystemError(operation: .createImage, status: conversionStatus),
                status: conversionStatus)
            fail(''', 1)
assert modified.count('MediaFailureProbe.shared.record') == 4
modified = modified.replace('''    private let generation: SessionGeneration
''', '''    private let generation: SessionGeneration
    private let decoderMode: MediaFailureProbe.DecoderMode
''', 1)
modified = modified.replace('''        self.generation = generation
''', '''        self.generation = generation
        self.decoderMode = MediaFailureProbe.shared.decoderMode
''', 1)
modified = modified.replace('''        var session: VTDecompressionSession?
''', '''        let specification: CFDictionary? = decoderMode == .softwareOnly
            ? [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder:
                NSNumber(value: false)] as CFDictionary : nil
        var session: VTDecompressionSession?
''', 1)
modified = modified.replace('''            decoderSpecification: nil,
''', '''            decoderSpecification: specification,
''', 1)
modified = modified.replace('''        let propertyStatus = VTSessionSetProperty(
''', '''        var hardwareValue: CFTypeRef?
        let hardwareQueryStatus = VTSessionCopyProperty(session,
            key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: kCFAllocatorDefault, valueOut: &hardwareValue)
        let hardwareAccelerated = hardwareQueryStatus == noErr
            ? (hardwareValue as? NSNumber)?.boolValue : nil
        MediaFailureProbe.shared.recordConfiguration(generation: generation, mode: decoderMode,
            hardwareAccelerated: hardwareAccelerated, queryStatus: hardwareQueryStatus)
        // A software experiment must never silently run on a confirmed hardware decoder.
        if decoderMode == .softwareOnly && hardwareAccelerated == true {
            VTDecompressionSessionInvalidate(session)
            throw MediaDecoderError.systemFailure(.createDecompressionSession, .unsupportedFormat)
        }

        let propertyStatus = VTSessionSetProperty(
''', 1)
changes[path] = (original, modified)

# Build 9 adds a separate, bounded PNG observation operation. The existing
# one-shot screenshot and video/input operations retain their semantics.
def change(path, replacements):
    original = (reference / path).read_text()
    modified = original
    for before, after in replacements:
        assert modified.count(before) == 1, (path, before[:100])
        modified = modified.replace(before, after, 1)
    changes[path] = (original, modified)

change('Rust/DeviceHubFFI/include/device_hub_ffi.h', [(
    '#define DH_REMOTE_OPERATION_PAIR_VERIFY ((DhRemoteOperation)3)',
    '#define DH_REMOTE_OPERATION_PAIR_VERIFY ((DhRemoteOperation)3)\n'
    '// Phone Probe: bounded PNG observation with authenticated tap input.\n'
    '#define DH_REMOTE_OPERATION_SCREENSHOT_PROBE ((DhRemoteOperation)4)')])
change('Rust/DeviceHubFFI/src/abi.rs', [(
    '    PairVerify = 3,',
    '    PairVerify = 3,\n    /// Phone Probe: bounded PNG observation with tap input, without video.\n    ScreenshotProbe = 4,')])
change('Rust/DeviceHubFFI/src/model.rs', [(
    'pub(crate) enum RemoteMode {\n    Screenshot,',
    'pub(crate) enum RemoteMode {\n    ScreenshotProbe,\n    Screenshot,'), (
    '            value if value == crate::abi::DhRemoteOperation::Screenshot as u32 => {',
    '''            value if value == crate::abi::DhRemoteOperation::ScreenshotProbe as u32 => {
                if !offer.is_empty() {
                    return Err(ValidationError::new(
                        "Screenshot probes must not include a video negotiator offer.",
                    ));
                }
                RemoteMode::ScreenshotProbe
            }
            value if value == crate::abi::DhRemoteOperation::Screenshot as u32 => {'''), (
    '    fn matching_auth_tag() -> [u8; 6] {',
    '''    #[test]
    fn screenshot_probe_preserves_authentication_and_rejects_media_offers() {
        let mode = crate::abi::DhRemoteOperation::ScreenshotProbe as u32;
        let tag = matching_auth_tag();
        assert!(matches!(copy_remote_operation(mode, &tag, &[]).unwrap().mode,
                         RemoteMode::ScreenshotProbe));
        assert!(copy_remote_operation(mode, &[3; 6], &[]).is_err());
        assert!(copy_remote_operation(mode, &tag, b"unexpected-media-offer").is_err());
    }

    fn matching_auth_tag() -> [u8; 6] {''')])
change('Rust/DeviceHubFFI/src/session.rs', [(
    'if matches!(&operation.mode, crate::model::RemoteMode::ControlStream)',
    'if matches!(&operation.mode, crate::model::RemoteMode::ControlStream | crate::model::RemoteMode::ScreenshotProbe)')])
change('Rust/DeviceHubFFI/src/protocol.rs', [(
    '        RemoteMode::Screenshot => {',
    '''        RemoteMode::ScreenshotProbe => {
            let cancellation = cancellation.ok_or_else(|| PublicFailure::new(
                "invalid_state", "png_input", false, "Missing owned cancellation channel."))?;
            run_png_input_probe(&readiness, &mut adapter, &mut handshake, &emitter,
                                controls, cancellation).await
        }
        RemoteMode::Screenshot => {'''), (
    'fn nonzero_video_ssrc(identifier: uuid::Uuid) -> u32 {',
    (root / 'Patches/png-input-loop.rs').read_text() + '\nfn nonzero_video_ssrc(identifier: uuid::Uuid) -> u32 {'), (
    '    emitter.screenshot(screenshot, dimensions)\n}',
    '    emitter.screenshot(screenshot, dimensions)?;\n    Ok(dimensions)\n}'), (
    '    emitter: &EventEmitter,\n) -> Result<(), PublicFailure> {\n    emitter.phase(\n        DhConnectionPhase::CapturingScreenshot,',
    '    emitter: &EventEmitter,\n) -> Result<crate::png::PngDimensions, PublicFailure> {\n    emitter.phase(\n        DhConnectionPhase::CapturingScreenshot,'), (
    '                        &video_udp,\n                        VIDEO_SENDER_PORT,',
    '                        Some(&video_udp),\n                        VIDEO_SENDER_PORT,'), (
    '    video_udp: &tcp::handle::UdpSocketHandle,\n    remote_video_port: u16,',
    '    video_udp: Option<&tcp::handle::UdpSocketHandle>,\n    remote_video_port: u16,'), (
    '        ControlCommand::VideoControlDatagram(datagram) => video_udp\n            .send_to',
    '        ControlCommand::VideoControlDatagram(datagram) => video_udp\n            .ok_or_else(video_control_delivery_failed)?\n            .send_to')])
change('Sources/DeviceHubLive/DeviceHubNativeInputMarshaller.swift', [(
    '    case controlStream\n    case pairVerify',
    '    case controlStream\n    case pairVerify\n    case screenshotProbe'), (
    '        case .pairVerify:\n            DH_REMOTE_OPERATION_PAIR_VERIFY',
    '        case .pairVerify:\n            DH_REMOTE_OPERATION_PAIR_VERIFY\n        case .screenshotProbe:\n            DH_REMOTE_OPERATION_SCREENSHOT_PROBE'), (
    '        case .pairVerify:\n            false',
    '        case .pairVerify, .screenshotProbe:\n            false')])
change('Sources/DeviceHubLive/DeviceHubNativeSessionClient.swift', [(
    'static func deviceHubLive() throws -> Self {\n        try DeviceHubNativeSessionFactory(environment: .live).client',
    'static func deviceHubLive(probeScreenshots: Bool = false) throws -> Self {\n        try DeviceHubNativeSessionFactory(environment: .live, probeScreenshots: probeScreenshots).client'), (
    '        case pairVerify(NativeRemoteSessionRequest)',
    '        case pairVerify(NativeRemoteSessionRequest)\n        case screenshotProbe(NativeRemoteSessionRequest)'), (
    '            case let .pairVerify(request):\n                request.generation',
    '            case let .pairVerify(request), let .screenshotProbe(request):\n                request.generation'), (
    '            case let .pairVerify(request):\n                try await executor.createRemote(',
    '            case let .screenshotProbe(request):\n                try await executor.createRemote(request, operation: .screenshotProbe)\n            case let .pairVerify(request):\n                try await executor.createRemote('), (
    '    private let environment: Environment',
    '    private let environment: Environment\n    private let probeScreenshots: Bool'), (
    '    init(environment: Environment) throws {',
    '    init(environment: Environment, probeScreenshots: Bool = false) throws {\n        self.probeScreenshots = probeScreenshots'), (
    '    ) async throws(NativeSessionFailure) -> NativeSession {\n        let relay = DeviceHubNativeSessionRelay()',
    '    ) async throws(NativeSessionFailure) -> NativeSession {\n        if probeScreenshots {\n            return try await makeControlOnlySession(.screenshotProbe(request))\n        }\n        let relay = DeviceHubNativeSessionRelay()')])

patch = ''.join(''.join(difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True),
    fromfile='a/' + path, tofile='b/' + path)) for path, (old, new) in changes.items())
destination = root / 'Patches/devicehub-media-diagnostics.patch'
destination.parent.mkdir(exist_ok=True)
destination.write_bytes(patch.encode())
manifest = json.loads((root / 'dependencies.json').read_text())
manifest['deviceHub']['probePatch'] = {
    'path': 'Patches/devicehub-media-diagnostics.patch',
    'sha256': hashlib.sha256(patch.encode()).hexdigest(),
    'files': {path: {'before': hashlib.sha256(old.encode()).hexdigest(),
                     'after': hashlib.sha256(new.encode()).hexdigest()}
              for path, (old, new) in changes.items()}
}
(root / 'dependencies.json').write_bytes((json.dumps(manifest, indent=2) + '\n').encode('utf-8'))
print('Generated probe patch for', len(changes), 'pinned source files')
