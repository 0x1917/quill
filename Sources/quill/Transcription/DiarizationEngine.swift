@preconcurrency import FluidAudio
import Foundation

/// Offline, on-device speaker diarization for the mixed system-audio track.
/// FluidAudio's Community-1 Core ML pipeline returns anonymous, stable speaker
/// IDs (S1, S2, …) and their time ranges; it never identifies a person or
/// sends recording data off-device.
actor DiarizationEngine {
    struct Segment: Sendable {
        let speaker: String
        let start: TimeInterval
        let end: TimeInterval
    }

    nonisolated let name = "pyannote-community-1-coreml-vbx"

    /// Community-1's practical default for meetings. A 0.25 s collar is
    /// standard when assessing diarization: it excludes inherently ambiguous
    /// change boundaries from a reference comparison.
    static let evaluationCollar: TimeInterval = 0.25
    static let maximumFixtureDER = 0.35
    static let maximumFixtureSpeakerCountError = 1

    private var manager: OfflineDiarizerManager?
    private var displayNames: [String: String] = [:]

    func prepare() async throws {
        guard manager == nil else { return }
        let manager = OfflineDiarizerManager()
        try await manager.prepareModels()
        self.manager = manager
    }

    /// Run an audio file through the same configured pipeline used by quill.
    /// `internal` so the benchmark target can test the integration boundary.
    func diarize(_ audio: URL) async throws -> [Segment] {
        guard let manager else { throw EngineError.notPrepared }
        let result = try await manager.process(audio)
        return result.segments.map {
            Segment(
                speaker: displayName(for: $0.speakerId),
                start: TimeInterval($0.startTimeSeconds),
                end: TimeInterval($0.endTimeSeconds)
            )
        }
    }

    func release() async {
        // OfflineDiarizerManager has no explicit cleanup API. Releasing our
        // reference lets Core ML reclaim its model resources between jobs.
        manager = nil
        displayNames = [:]
    }

    private func displayName(for id: String) -> String {
        if let name = displayNames[id] { return name }
        // FluidAudio currently emits S1, S2, …, but preserve one-to-one
        // labeling if a future dependency revision changes that convention.
        let name = "speaker-\(displayNames.count + 1)"
        displayNames[id] = name
        return name
    }

    static func modelsAvailable() -> Bool {
        let root = OfflineDiarizerModels.defaultModelsDirectory()
        let required = [
            "Segmentation.mlmodelc", "FBank.mlmodelc", "Embedding.mlmodelc",
            "PldaRho.mlmodelc", "plda-parameters.json",
        ]
        let candidateRoots = [
            root,
            root.appendingPathComponent("speaker-diarization", isDirectory: true),
            root.appendingPathComponent("speaker-diarization-coreml", isDirectory: true),
            root.appendingPathComponent("speaker-diarization-offline", isDirectory: true),
        ]
        return candidateRoots.contains { directory in
            required.allSatisfy {
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
            }
        }
    }

    enum EngineError: Error, CustomStringConvertible {
        case notPrepared

        var description: String { "diarization engine used before prepare()" }
    }
}
