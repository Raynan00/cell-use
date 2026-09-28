import Foundation

/// OCR geometry only; callers never persist arbitrary recognized text.
public struct ScreenText: Sendable {
    public let text: String
    public let x: Double
    public let y: Double
    public init(_ text: String, x: Double, y: Double) { self.text = text; self.x = x; self.y = y }
}

public struct CalculatorScreen: Sendable {
    public let sevenX: Double
    public let sevenY: Double
    public let display: String

    /// Recognize the full portrait digit grid and a single numeric display above it.
    /// Never infer a tap from a lone digit or hard-coded screen coordinates.
    public struct Inspection: Sendable {
        public let screen: CalculatorScreen?
        public let reason: String
        public var missingDigits: [String] = []
        public var ambiguousDigits: [String] = []
    }

    public static func detect(_ text: [ScreenText]) -> Self? { inspect(text).screen }

    public static func inspect(_ text: [ScreenText]) -> Inspection {
        let digits = ["7", "8", "9", "4", "5", "6", "1", "2", "3"]
        var keys: [ScreenText] = []
        var missing: [String] = []
        var ambiguous: [String] = []
        for digit in digits {
            let matches = text.filter { $0.text == digit && $0.y > 0.42 && $0.y < 0.94 && $0.x < 0.78 }
            if matches.isEmpty { missing.append(digit) }
            else if matches.count > 1 { ambiguous.append(digit) }
            else if let key = matches.first, key.x.isFinite, key.y.isFinite { keys.append(key) }
        }
        guard keys.count == 9 else {
            return Inspection(screen: nil, reason: "incompleteOrAmbiguousGrid",
                              missingDigits: missing, ambiguousDigits: ambiguous)
        }
        let dx = keys[1].x - keys[0].x
        let dy = keys[3].y - keys[0].y
        guard (0.12...0.3).contains(dx), (0.045...0.17).contains(dy),
              (0.05...0.30).contains(keys[0].x), (0.42...0.72).contains(keys[0].y) else { return Inspection(screen: nil, reason: "gridGeometryMismatch") }
        for (i, key) in keys.enumerated() {
            guard abs(key.x - (keys[0].x + Double(i % 3) * dx)) < 0.035,
                  abs(key.y - (keys[0].y + Double(i / 3) * dy)) < 0.025 else { return Inspection(screen: nil, reason: "gridGeometryMismatch") }
        }
        // Require the bottom zero key as well as the complete 1-9 grid.
        guard text.contains(where: { $0.text == "0" && $0.y > keys[6].y + 0.035 &&
            $0.y < 0.98 && $0.x < 0.60 }) else { return Inspection(screen: nil, reason: "bottomZeroMissing") }
        let displays = text.filter { token in
            token.y > 0.1 && token.y < keys[0].y - 0.06 && token.x > 0.35 &&
            !token.text.isEmpty && token.text.allSatisfy { $0.isASCII && $0.isNumber }
        }
        guard displays.count == 1, let display = displays.first else { return Inspection(screen: nil, reason: "displayMissingOrAmbiguous") }
        return Inspection(screen: Self(sevenX: keys[0].x, sevenY: keys[0].y, display: display.text), reason: "recognized")
    }
}
