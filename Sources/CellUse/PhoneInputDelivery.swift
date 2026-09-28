import Foundation

/// Transient input only. Never serialize these events into diagnostics.
public enum PhoneInputEvent: Sendable, Equatable {
    case tap(x: Double, y: Double)
    case touch(x: Double, y: Double, phase: Phase)
    case character(Character)
    case key(PhoneKey)
    case releaseAll
    public enum Phase: Sendable { case began, moved, ended }
}

/// Delivers one bounded action. Acceptance means the transport accepted the
/// commands, not that the target app produced the intended result.
@MainActor public enum PhoneInputDelivery {
    public enum Failure: Error { case invalidAction, contextChanged }
    public static func deliver(
        _ action: PhoneAction,
        contextIsValid: @MainActor () -> Bool,
        send: @MainActor (PhoneInputEvent) async throws -> Void,
        sleep: @MainActor (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async throws {
        // Validate the entire text/gesture before the first side effect.
        guard action.inputValidationError == nil else { throw Failure.invalidAction }
        func check() throws {
            try Task.checkCancellation()
            guard contextIsValid() else { throw Failure.contextChanged }
        }
        do {
            try check()
            switch action {
            case let .tap(x, y): try await send(.tap(x: x, y: y))
            case let .pressKey(key): try await send(.key(key))
            case let .swipe(x, y, endX, endY, duration):
                try await send(.touch(x: x, y: y, phase: .began))
                let steps = 12
                for index in 1...steps {
                    try await sleep(duration / Double(steps))
                    try check()
                    let fraction = Double(index) / Double(steps)
                    try await send(.touch(x: x + (endX - x) * fraction,
                                          y: y + (endY - y) * fraction,
                                          phase: index == steps ? .ended : .moved))
                }
            case let .typeText(text):
                for character in text {
                    try check()
                    try await send(.character(character))
                    try await sleep(0.06)
                }
            case .wait, .finish: throw Failure.invalidAction
            }
            try check()
        } catch {
            // Best effort even on cancellation; the session also releases input
            // on teardown. A partial gesture/string is never replayed here.
            try? await send(.releaseAll)
            throw error
        }
    }
}
