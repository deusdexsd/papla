import AVFoundation
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B, compiled to CoreML and run on the Neural Engine via FluidAudio.
///
/// **Batch, not streaming.** Audio is accumulated while the key is held and transcribed in
/// one pass on release. That's a deliberate trade: at ~100× realtime a 30-second utterance
/// resolves in roughly a third of a second, which is imperceptible for push-to-talk — but
/// it means no live text in the HUD while you speak, unlike Apple's engine.
/// FluidAudio's `SlidingWindowAsrManager` would restore live partials at the cost of a
/// more complex integration; see the note in `docs`.
actor ParakeetEngine: TranscriptionEngine {
    private var samples: [Float] = []
    private var continuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?

    /// Defaults to 16 kHz mono float32 — exactly what Parakeet is trained on.
    private let converter = AudioConverter()

    func preferredInputFormat() async -> AVAudioFormat? {
        // Parakeet is trained on 16 kHz mono; AudioCapture converts to whatever we ask for.
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        samples.removeAll(keepingCapacity: true)

        let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        self.continuation = continuation

        // Force the (possibly very slow) first load to happen here rather than on release,
        // so the user waits before speaking instead of losing an utterance to a timeout.
        _ = try await ParakeetModels.shared.manager()

        return stream
    }

    func feed(_ chunk: AudioChunk) async {
        let buffer = chunk.buffer
        guard buffer.frameLength > 0 else { return }

        // Delegated to FluidAudio's own converter rather than hand-rolled, for one reason
        // that matters more than tidiness: `AsrManager.transcribe(_ samples: [Float])`
        // performs **no resampling and no rate validation**. Feed it the wrong sample rate
        // and it doesn't throw — it silently transcribes garbage.
        //
        // That's a live risk here. In compare mode the capture format is dictated by
        // Apple's analyzer, and `bestAvailableAudioFormat` may legitimately return 8 kHz
        // as well as 16 kHz. `resampleBuffer` normalizes whatever arrives to the 16 kHz
        // mono float32 the model expects, and its Int16→Float path is bit-identical to
        // dividing by 32768, so nothing is lost versus doing it by hand.
        do {
            samples.append(contentsOf: try converter.resampleBuffer(buffer))
        } catch {
            Log.speech.error("Parakeet: audio conversion failed — \(error.localizedDescription)")
        }
    }

    func finish() async {
        defer {
            continuation?.finish()
            continuation = nil
            samples.removeAll(keepingCapacity: true)
        }

        // Parakeet's encoder needs a minimum window; a stray tap of the key isn't speech.
        // Logged rather than silent — an unexpected drop to zero here is how the
        // format bug above disguised itself as a fast, empty result.
        guard samples.count >= 1_600 else {
            Log.speech.info("Parakeet: skipped — only \(self.samples.count) samples captured")
            return
        }

        do {
            let manager = try await ParakeetModels.shared.manager()
            var decoderState = try TdtDecoderState(decoderLayers: SpeechModel.current.version.decoderLayers)
            let started = Date()
            let result = try await manager.transcribe(samples, decoderState: &decoderState)
            let elapsed = Date().timeIntervalSince(started)
            let audioSeconds = Double(samples.count) / 16_000

            Log.speech.info("""
                Parakeet: \(audioSeconds, format: .fixed(precision: 1))s audio in \
                \(elapsed, format: .fixed(precision: 2))s (\(audioSeconds / max(elapsed, 0.0001), format: .fixed(precision: 0))× realtime)
                """)

            continuation?.yield(
                TranscriptionChunk(
                    text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFinal: true
                )
            )
        } catch {
            Log.speech.error("Parakeet failed: \(error.localizedDescription)")
            continuation?.finish(throwing: error)
            continuation = nil
        }
    }

}

/// Process-wide model cache.
///
/// Loading is expensive — ~470 MB downloaded on first ever run, then a few seconds from
/// disk per process — and the models are immutable once loaded, so every dictation shares
/// one instance rather than paying that per utterance. Its own actor because `static var`
/// on `ParakeetEngine` would be unprotected global mutable state under Swift 6.
actor ParakeetModels {
    static let shared = ParakeetModels()

    /// Whether the selected model is already on disk, checked without loading it.
    ///
    /// `nonisolated` and filesystem-based on purpose: the menu needs this synchronously
    /// while drawing, and an in-memory "have I loaded yet" flag would wrongly report
    /// "not downloaded" on every fresh launch.
    nonisolated static var isDownloaded: Bool { SpeechModel.current.isDownloaded }

    /// Total bytes of a model's folder on disk, `nil` when it isn't there.
    nonisolated static func installedSize(of model: SpeechModel) -> Int64? {
        guard let files = FileManager.default.enumerator(
            at: model.folderURL, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
        ) else { return nil }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total > 0 ? total : nil
    }

    /// When the model was downloaded — its folder's own modification date.
    nonisolated static func installedDate(of model: SpeechModel) -> Date? {
        try? model.folderURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The Hugging Face repo the model comes from — its last-modified date says whether
    /// something newer than the local copy exists, and its sibling repos are the other
    /// models published alongside it.
    static func checkRemote(_ model: SpeechModel) async throws -> (lastModified: Date?, others: [String]) {
        async let info = URLSession.shared.data(from: URL(string: "https://huggingface.co/api/models/\(model.huggingFaceRepo)")!)
        async let list = URLSession.shared.data(
            from: URL(string: "https://huggingface.co/api/models?author=FluidInference&search=parakeet&limit=30")!)

        var date: Date?
        if let object = try JSONSerialization.jsonObject(with: try await info.0) as? [String: Any],
           let text = object["lastModified"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = formatter.date(from: text)
        }
        var others: [String] = []
        if let array = try JSONSerialization.jsonObject(with: try await list.0) as? [[String: Any]] {
            others = array.compactMap { $0["id"] as? String }
                .map { $0.replacingOccurrences(of: "FluidInference/", with: "") }
        }
        return (date, others)
    }

    /// Throws the local copy of `model` away and downloads it again — the fix for a corrupted
    /// download.
    func redownload(_ model: SpeechModel) async throws {
        loaded = nil
        loadedModel = nil
        loadTask = nil
        loadTaskModel = nil
        try? FileManager.default.removeItem(at: model.folderURL)
        _ = try await manager()
    }

    private var loaded: AsrManager?
    private var loadedModel: SpeechModel?
    private var loadTask: Task<AsrManager, Error>?
    private var loadTaskModel: SpeechModel?

    var isLoaded: Bool { loaded != nil }

    /// Loads once per model; concurrent callers await the same task rather than racing to
    /// download. Choosing a different model in Ustawienia simply loads that one next time.
    func manager() async throws -> AsrManager {
        let model = SpeechModel.current
        if let loaded, loadedModel == model { return loaded }
        if let loadTask, loadTaskModel == model { return try await loadTask.value }

        let task = Task<AsrManager, Error> {
            let stage = model.isDownloaded ? "loading models from disk" : "downloading models (one time)"
            Log.speech.info("Parakeet \(model.rawValue, privacy: .public): \(stage, privacy: .public)")
            let started = Date()
            let models = try await AsrModels.downloadAndLoad(version: model.version, encoderPrecision: .int8)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            Log.speech.info("Parakeet: ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            return manager
        }
        loadTask = task
        loadTaskModel = model

        do {
            let manager = try await task.value
            loaded = manager
            loadedModel = model
            return manager
        } catch {
            // Don't cache a failed load — a transient download error shouldn't wedge the
            // engine for the rest of the session.
            loadTask = nil
            loadTaskModel = nil
            throw error
        }
    }
}
