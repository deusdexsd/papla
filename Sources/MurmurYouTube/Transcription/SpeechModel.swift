import FluidAudio
import Foundation

/// The speech-recognition models Papla can run. All of them go through the same on-device
/// FluidAudio pipeline; what differs is which languages they were trained on — and only
/// `v3` covers Polish.
enum SpeechModel: String, CaseIterable, Sendable {
    case v3
    case v2
    case tdtCtc110m
    case tdtJa

    static let defaultsKey = "speechModel"

    /// Read straight from `UserDefaults` so non-main-actor code (the model loader) can ask.
    static var current: SpeechModel {
        SpeechModel(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .v3
    }

    var version: AsrModelVersion {
        switch self {
        case .v3: .v3
        case .v2: .v2
        case .tdtCtc110m: .tdtCtc110m
        case .tdtJa: .tdtJa
        }
    }

    var supportsPolish: Bool { self == .v3 }

    var title: String {
        switch self {
        case .v3: "Parakeet TDT 0.6B v3"
        case .v2: "Parakeet TDT 0.6B v2"
        case .tdtCtc110m: "Parakeet TDT-CTC 110M"
        case .tdtJa: "Parakeet 0.6B JA"
        }
    }

    @MainActor
    var languages: String {
        switch self {
        case .v3: t("25 języków europejskich, w tym polski", "25 European languages, Polish included")
        case .v2: t("tylko angielski", "English only")
        case .tdtCtc110m: t("tylko angielski · mały i szybki", "English only · small and fast")
        case .tdtJa: t("tylko japoński", "Japanese only")
        }
    }

    var approxSize: String? {
        switch self {
        case .v3: "~470 MB"
        case .v2: "~440 MB"
        default: nil
        }
    }

    var huggingFaceRepo: String {
        switch self {
        case .v3: "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        case .v2: "FluidInference/parakeet-tdt-0.6b-v2-coreml"
        case .tdtCtc110m: "FluidInference/parakeet-tdt-ctc-110m-coreml"
        case .tdtJa: "FluidInference/parakeet-0.6b-ja-coreml"
        }
    }

    var folderURL: URL { AsrModels.defaultCacheDirectory(for: version) }

    var isDownloaded: Bool { AsrModels.modelsExist(at: folderURL, version: version) }
}
