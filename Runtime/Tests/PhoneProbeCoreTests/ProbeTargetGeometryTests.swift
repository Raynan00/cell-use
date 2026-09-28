import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import PhoneProbeCore

@Test func targetUsesFullScreenCoordinatesIncludingSafeAreaOffset() {
    let screen = CGRect(x: 0, y: 0, width: 400, height: 900)
    let target = CGRect(x: 20, y: 200, width: 360, height: 64)
    let geometry = ProbeTargetGeometry(target: target, screen: screen,
        visibleArea: CGRect(x: 0, y: 60, width: 400, height: 806), hitTestMatches: true)
    #expect(geometry.status == .valid)
    #expect(geometry.normalizedCenter == CGPoint(x: 0.5, y: 232.0 / 900.0))
}

@Test func visibleCenterDoesNotAuthorizePartiallyClippedTarget() {
    let screen = CGRect(x: 0, y: 0, width: 400, height: 900)
    let geometry = ProbeTargetGeometry(target: CGRect(x: 20, y: 40, width: 360, height: 64),
        screen: screen, visibleArea: CGRect(x: 0, y: 60, width: 400, height: 800), hitTestMatches: true)
    #expect(geometry.status == .clipped)
    #expect(geometry.normalizedCenter == nil)
}

@Test func missingEmptyAndNonfiniteGeometryCannotAuthorizeInput() {
    let screen = CGRect(x: 0, y: 0, width: 400, height: 900)
    #expect(ProbeTargetGeometry(unavailable: .unavailable).normalizedCenter == nil)
    for target in [CGRect.zero, CGRect(x: CGFloat.nan, y: 10, width: 20, height: 20),
                   CGRect(x: 10, y: 10, width: CGFloat.infinity, height: 20)] {
        let geometry = ProbeTargetGeometry(target: target, screen: screen,
            visibleArea: screen, hitTestMatches: true)
        #expect(geometry.status == .invalidBounds)
        #expect(geometry.normalizedCenter == nil)
    }
}

@Test func overlayPreventsInputEvenWhenBoundsFit() {
    let screen = CGRect(x: 0, y: 0, width: 400, height: 900)
    let geometry = ProbeTargetGeometry(target: CGRect(x: 20, y: 200, width: 360, height: 64),
        screen: screen, visibleArea: screen, hitTestMatches: false)
    #expect(geometry.status == .occluded)
    #expect(geometry.normalizedCenter == nil)
}

@Test func nonzeroScreenOriginIsRemovedBeforePixelScaling() {
    let screen = CGRect(x: 100, y: 200, width: 400, height: 900)
    let geometry = ProbeTargetGeometry(target: CGRect(x: 120, y: 400, width: 360, height: 64),
        screen: screen, visibleArea: screen, hitTestMatches: true)
    #expect(geometry.normalizedCenter == CGPoint(x: 0.5, y: 232.0 / 900.0))
}
