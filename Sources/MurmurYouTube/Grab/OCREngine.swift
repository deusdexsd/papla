import CoreGraphics
import Foundation
import Vision

/// A handful of languages worth offering in Ustawienia. Vision supports more (see
/// `VNRecognizeTextRequest.supportedRecognitionLanguages`), but a long list nobody uses is
/// worse than a short one that covers what actually shows up in a screen grab.
struct OCRLanguage: Identifiable, Hashable, Sendable {
    let code: String // BCP-47, exactly what Vision expects.
    let displayName: String
    var id: String { code }

    static let polish = OCRLanguage(code: "pl-PL", displayName: "Polski")
    static let english = OCRLanguage(code: "en-US", displayName: "Angielski")

    static let common: [OCRLanguage] = [
        .polish,
        .english,
        OCRLanguage(code: "de-DE", displayName: "Niemiecki"),
        OCRLanguage(code: "fr-FR", displayName: "Francuski"),
        OCRLanguage(code: "es-ES", displayName: "Hiszpański"),
        OCRLanguage(code: "it-IT", displayName: "Włoski"),
        OCRLanguage(code: "uk-UA", displayName: "Ukraiński"),
        OCRLanguage(code: "pt-BR", displayName: "Portugalski"),
    ]

    static func name(for code: String) -> String {
        common.first { $0.code == code }?.displayName ?? code
    }
}

enum OCRError: Error, LocalizedError {
    case noText
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noText: "Nie znalazłem żadnego tekstu w zaznaczonym obszarze."
        case .visionFailed(let reason): "Rozpoznawanie tekstu nie powiodło się: \(reason)"
        }
    }
}

/// One recognized line, kept with its geometry so `TextAssembler` can reconstruct
/// paragraphs instead of gluing every line together with a single, indiscriminate newline.
struct OCRLine: Sendable {
    let text: String
    /// Normalized [0, 1], origin bottom-left — Vision's own convention.
    let boundingBox: CGRect
    let confidence: Float
}

/// Wraps `VNRecognizeTextRequest`.
///
/// The one thing this file exists to get right: **GrabText's actual bug**. Left to its
/// defaults, Vision either auto-detects the language per line or quietly assumes en-US,
/// and either way Polish diacritics (ą ć ę ł ń ó ś ź ż) are exactly the kind of small,
/// easily-confused mark that a mismatched language model drops or swaps for its plain
/// Latin neighbour. Two settings fix it, both mandatory, not defaults to leave alone:
///
/// - `recognitionLanguages` forced to the user's chosen languages, Polish first.
/// - `automaticallyDetectsLanguage = false` — otherwise Vision can override that choice
///   per line whenever it thinks it recognizes something else, which is exactly the
///   silent failure mode being fixed here.
enum OCREngine {
    static func recognize(
        _ image: CGImage,
        languages: [String],
        accurate: Bool
    ) async throws -> [OCRLine] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [OCRLine] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    // macOS hands back decomposed Unicode (NFD) from several text-producing
                    // APIs — Papla hit the identical issue comparing dictated text against
                    // dictionary triggers. A composed ó (U+00F3) and a bare o plus a
                    // combining acute (U+006F U+0301) render identically but compare and
                    // count differently everywhere downstream, so normalize immediately,
                    // per line, before anything else touches this string.
                    let normalized = candidate.string.precomposedStringWithCanonicalMapping
                    return OCRLine(
                        text: normalized,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence
                    )
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = accurate ? .accurate : .fast
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            request.automaticallyDetectsLanguage = false
            request.minimumTextHeight = 0

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.visionFailed(error.localizedDescription))
            }
        }
    }

    /// Reads any QR/2D codes in the image and returns their *decoded* payload — the URL or
    /// text the code actually encodes, not a description of what it looks like. OCR has
    /// nothing useful to say about a QR code (it's a pixel pattern, not glyphs), so a grab
    /// centered on one used to just silently fail with "no text found."
    ///
    /// Tried before the text pass, not after: when a selection is centered on a code, the
    /// decoded payload is unambiguously what the user wants, and it's pointless to also run
    /// the much slower text recognizer over the same pixels.
    static func detectCodes(_ image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNBarcodeObservation]) ?? []
                let values = observations.compactMap { $0.payloadStringValue }
                continuation.resume(returning: values)
            }
            // The 2D symbologies that commonly encode a URL or free text, as opposed to a
            // 1D product barcode (EAN/UPC), which only ever encodes a numeric SKU nobody
            // grabbing text off their screen is after.
            request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.visionFailed(error.localizedDescription))
            }
        }
    }
}
