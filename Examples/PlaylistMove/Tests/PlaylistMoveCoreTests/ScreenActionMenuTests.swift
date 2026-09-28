import XCTest
@testable import PlaylistMoveCore

final class ScreenActionMenuTests: XCTestCase {
    func testEveryOfferedControlMapsBackToItsActualElement() throws {
        let screen = [ScreenText(id: 2, text: "Search", x: 0.2, y: 0.1),
                      ScreenText(id: 19, text: "Search", x: 0.6, y: 0.8),
                      ScreenText(id: 27, text: "Planet Telex", x: 0.4, y: 0.3)]
        let menu = ScreenActionMenu(screen: screen)
        let controls = menu.choices.filter { $0.elementID != nil }
        XCTAssertEqual(controls.count, 6)
        XCTAssertEqual(Set(controls.map(\.value)).count, controls.count)
        for choice in controls {
            XCTAssertEqual(try menu.choice(for: choice.value), choice)
            XCTAssertTrue(screen.contains { $0.id == choice.elementID })
        }
        XCTAssertThrowsError(try menu.choice(for: "tap #0: Search"))
        XCTAssertThrowsError(try menu.choice(for: "tap #19: Planet Telex"))
    }

    func testNewObservationDoesNotRetainOldTargetsOrLoseKeyboardActions() throws {
        let old = ScreenActionMenu(screen: [ScreenText(id: 7, text: "Search", x: 0.5, y: 0.5)])
        let current = ScreenActionMenu(screen: [ScreenText(id: 7, text: "Cancel", x: 0.9, y: 0.1)])
        let oldTap = try XCTUnwrap(old.choices.first { $0.operation == "tap" })
        XCTAssertThrowsError(try current.choice(for: oldTap.value))
        XCTAssertEqual(try current.choice(for: "typeText").operation, "typeText")
        XCTAssertEqual(try current.choice(for: "enter").operation, "enter")
        XCTAssertEqual(try current.choice(for: "finish").operation, "finish")
        XCTAssertTrue(ScreenActionMenu(screen: []).choices.allSatisfy { $0.elementID == nil })
    }
}
