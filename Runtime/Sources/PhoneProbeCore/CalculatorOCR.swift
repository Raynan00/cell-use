#if canImport(Vision)
import CoreGraphics
import CoreML
import Foundation
import Vision

/// CPU-only recognition shared by the phone and the macOS fixture test.
public enum CalculatorOCR {
    public struct Failure: Error, Sendable {
        public let stage: String
        public let code: Int
    }
    public struct Diagnostics: Encodable, Sendable {
        public let strategy = "numericColumns"
        public var observations = 0
        public var lowConfidenceObservations = 0
        public var acceptedTokens = 0
        public var reason = "notRead"
        public var missingDigits: [String] = []
        public var ambiguousDigits: [String] = []
        public var regions: [RegionDiagnostics] = []
    }
    public struct RegionDiagnostics: Encodable, Sendable {
        public let region: String
        public var observations = 0
        public var singleDigits = 0
        public var groupedDigits = 0
        public var nonNumeric = 0
        public var missingCharacterBoxes = 0
        public var lowConfidence = 0
    }
    public struct Reading: Sendable {
        public let screen: CalculatorScreen?
        public let diagnostics: Diagnostics
    }

    public static func read(_ image: CGImage) throws -> Reading {
        var diagnostics = Diagnostics()
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var tokens = try recognize(image, rect: full, region: "screen", diagnostics: &diagnostics)
            .filter { $0.y <= 0.42 || $0.x >= 0.78 }
        // These are search regions, never tap coordinates. Recognize each numeric
        // column independently so neighboring keys are not treated as one word.
        // The unchanged full-grid validator derives the tap from observed glyphs.
        for column in 0..<3 {
            let rect = CGRect(x: Double(image.width) * Double(column) * 0.26,
                              y: Double(image.height) * 0.42,
                              width: Double(image.width) * 0.26,
                              height: Double(image.height) * 0.56).integral.intersection(full)
            tokens += try recognize(image, rect: rect, region: "column\(column + 1)", diagnostics: &diagnostics)
        }
        diagnostics.acceptedTokens = tokens.count
        let inspection = CalculatorScreen.inspect(tokens)
        diagnostics.reason = inspection.reason
        diagnostics.missingDigits = inspection.missingDigits
        diagnostics.ambiguousDigits = inspection.ambiguousDigits
        return Reading(screen: inspection.screen, diagnostics: diagnostics)
    }

    private static func recognize(_ image: CGImage, rect: CGRect, region: String,
                                  diagnostics: inout Diagnostics) throws -> [ScreenText] {
        guard let crop = image.cropping(to: rect) else { return [] }
        var regionDiagnostics = RegionDiagnostics(region: region)
        defer { diagnostics.regions.append(regionDiagnostics) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01
        // Explicit stage selection replaces the deprecated CPU-only hint.
        let stages: [VNComputeStage: [MLComputeDevice]]
        do { stages = try request.supportedComputeStageDevices }
        catch { throw Failure(stage: "computeDevices", code: (error as NSError).code) }
        guard !stages.isEmpty else { throw Failure(stage: "noComputeStages", code: 0) }
        for (stage, devices) in stages {
            guard let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) else {
                throw Failure(stage: "cpuUnavailable", code: 0)
            }
            request.setComputeDevice(cpu, for: stage)
        }
        do { try VNImageRequestHandler(cgImage: crop).perform([request]) }
        catch { throw Failure(stage: region, code: (error as NSError).code) }
        var tokens: [ScreenText] = []
        func token(_ text: String, _ box: CGRect) -> ScreenText {
            ScreenText(text, x: (rect.minX + box.midX * rect.width) / Double(image.width),
                       y: (rect.minY + (1 - box.midY) * rect.height) / Double(image.height))
        }
        for observation in request.results ?? [] {
            diagnostics.observations += 1
            regionDiagnostics.observations += 1
            guard let value = observation.topCandidates(1).first else { continue }
            guard value.confidence >= 0.7 else {
                diagnostics.lowConfidenceObservations += 1
                regionDiagnostics.lowConfidence += 1
                continue
            }
            let string = value.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let position = token(string, observation.boundingBox)
            let digits = string.filter { $0.isASCII && $0.isNumber }
            let numeric = !digits.isEmpty && string.allSatisfy { ($0.isASCII && $0.isNumber) || $0.isWhitespace }
            if numeric {
                if digits.count == 1 { regionDiagnostics.singleDigits += 1 }
                else { regionDiagnostics.groupedDigits += 1 }
            } else { regionDiagnostics.nonNumeric += 1 }
            if position.y > 0.42, numeric, digits.count > 1 {
                for index in value.string.indices {
                    let character = value.string[index]
                    guard character.isASCII && character.isNumber else { continue }
                    guard let bounds = try? value.boundingBox(for: index..<value.string.index(after: index)) else {
                        regionDiagnostics.missingCharacterBoxes += 1
                        continue
                    }
                    tokens.append(token(String(character), bounds.boundingBox))
                }
            } else {
                tokens.append(position)
            }
        }
        return tokens
    }
}
#endif
