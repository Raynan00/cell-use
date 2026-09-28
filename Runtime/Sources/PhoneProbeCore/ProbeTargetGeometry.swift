import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The target and visible area must be expressed in the same screen space.
/// Geometry stays in memory; only Status belongs in an evidence report.
public struct ProbeTargetGeometry: Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case valid, unavailable, invalidBounds, clipped, occluded
    }

    public let status: Status
    public let target: CGRect
    public let screen: CGRect

    public init(unavailable status: Status) {
        self.status = status == .valid ? .unavailable : status
        target = .zero
        screen = .zero
    }

    public init(target: CGRect, screen: CGRect, visibleArea: CGRect, hitTestMatches: Bool) {
        self.target = target
        self.screen = screen
        guard Self.isUsable(target), Self.isUsable(screen) else {
            status = .invalidBounds
            return
        }
        guard Self.isUsable(visibleArea), screen.contains(target), visibleArea.contains(target) else {
            status = .clipped
            return
        }
        status = hitTestMatches ? .valid : .occluded
    }

    public var normalizedCenter: CGPoint? {
        guard status == .valid else { return nil }
        return CGPoint(x: (target.midX - screen.minX) / screen.width,
                       y: (target.midY - screen.minY) / screen.height)
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }
}
