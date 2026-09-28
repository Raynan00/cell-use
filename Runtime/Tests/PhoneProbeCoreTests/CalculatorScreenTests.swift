import Testing
@testable import PhoneProbeCore

private func calculator(_ display: String = "0") -> [ScreenText] {
    ["7", "8", "9", "4", "5", "6", "1", "2", "3"].enumerated().map {
        ScreenText($0.element, x: 0.13 + Double($0.offset % 3) * 0.23,
                   y: 0.55 + Double($0.offset / 3) * 0.09)
    } + [ScreenText("0", x: 0.36, y: 0.82), ScreenText(display, x: 0.83, y: 0.29)]
}

@Test func calculatorRequiresCompleteGridAndUnambiguousDisplay() {
    #expect(CalculatorScreen.detect(calculator())?.display == "0")
    #expect(CalculatorScreen.detect(calculator("7"))?.display == "7")
    #expect(CalculatorScreen.detect(calculator("77"))?.display == "77")
    #expect(CalculatorScreen.detect(Array(calculator().dropFirst())) == nil)
    #expect(CalculatorScreen.detect(calculator() + [ScreenText("0", x: 0.5, y: 0.2)]) == nil)
    #expect(CalculatorScreen.detect([ScreenText("7", x: 0.1, y: 0.6)]) == nil)
}

@Test func calculatorRejectsRotatedOrDisplacedKeys() {
    let transposed = calculator().map { ScreenText($0.text, x: $0.y, y: $0.x) }
    #expect(CalculatorScreen.detect(transposed) == nil)
    var shifted = calculator()
    shifted[4] = ScreenText("5", x: 0.65, y: 0.64)
    #expect(CalculatorScreen.detect(shifted) == nil)
}

@Test func calculatorExplainsBlockedInputWithoutReportingScreenText() {
    let missing = CalculatorScreen.inspect(Array(calculator().dropFirst()))
    #expect(missing.reason == "incompleteOrAmbiguousGrid")
    #expect(missing.missingDigits == ["7"])
    let duplicate = CalculatorScreen.inspect(calculator() + [ScreenText("8", x: 0.37, y: 0.55)])
    #expect(duplicate.ambiguousDigits == ["8"])
    #expect(CalculatorScreen.inspect(Array(calculator().dropLast())).reason == "displayMissingOrAmbiguous")
    #expect(CalculatorScreen.inspect(calculator().filter { !($0.text == "0" && $0.y > 0.8) }).reason == "bottomZeroMissing")
}

@Test func calculatorAcceptsObservedPortraitGeometry() {
    // Approximate digit centers measured from the local test capture; no image or personal UI retained.
    let keys = ["7", "8", "9", "4", "5", "6", "1", "2", "3"].enumerated().map {
        ScreenText($0.element, x: 0.148 + Double($0.offset % 3) * 0.235,
                   y: 0.557 + Double($0.offset / 3) * 0.108)
    } + [ScreenText("0", x: 0.383, y: 0.881), ScreenText("0", x: 0.909, y: 0.345)]
    #expect(CalculatorScreen.detect(keys)?.display == "0")
}
