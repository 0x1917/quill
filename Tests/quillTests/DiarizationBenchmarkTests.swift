import Foundation
import XCTest
@testable import quill
@testable import quillDiarizationTestSupport

/// End-to-end acceptance tests for quill's actual diarizer, not a mocked
/// implementation. The fixtures are a pinned, representative 12-clip slice
/// of DimQ1's CC-BY-4.0 Sortformer Diarization Test Set. Each WAV has an RTTM
/// reference with known turn times and speaker identities.
///
/// We score by DER with a 250 ms change-boundary collar, the standard
/// diarization convention. Cluster IDs are anonymous/arbitrary, so
/// the scorer finds the optimal one-to-one cluster-to-reference mapping before
/// it calculates errors. The thresholds are intentionally permissive
/// enough to avoid platform/Core ML numerical flakes while catching a broken
/// model integration, bad sample-rate handling, or loss of speaker clustering.
final class DiarizationBenchmarkTests: XCTestCase {
    private static let fixtureNames = (0...11).map { String(format: "ls_real_%03d", $0) }
    /// A deliberate, reviewable expectation for this pinned corpus slice.
    /// RTTM remains the authority for turn timing; this catches accidental
    /// fixture replacement with a different recording/reference pairing.
    private static let expectedReferenceSpeakerCounts = [
        "ls_real_000": 2, "ls_real_001": 2, "ls_real_002": 2,
        "ls_real_003": 3, "ls_real_004": 2, "ls_real_005": 2,
        "ls_real_006": 3, "ls_real_007": 2, "ls_real_008": 2,
        "ls_real_009": 2, "ls_real_010": 2, "ls_real_011": 3,
    ]

    func testFixtureCorpusIsCompleteAndInternallyConsistent() throws {
        let fixtureDirectory = try fixtureDirectory()
        for name in Self.fixtureNames {
            let wav = fixtureDirectory.appendingPathComponent("\(name).wav")
            let rttm = fixtureDirectory.appendingPathComponent("\(name).rttm")
            XCTAssertTrue(FileManager.default.fileExists(atPath: wav.path), "missing \(wav.lastPathComponent)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: rttm.path), "missing \(rttm.lastPathComponent)")
            let reference = try referenceSegments(from: rttm)
            XCTAssertFalse(reference.isEmpty, "empty RTTM: \(name)")
            XCTAssertEqual(
                Set(reference.map(\.speaker)).count,
                try XCTUnwrap(Self.expectedReferenceSpeakerCounts[name]),
                "unexpected known-speaker count in \(name)"
            )
        }
    }

    func testAutomaticDiarizationMeetsQualityExpectationAcrossTwelveKnownClips() async throws {
        guard ProcessInfo.processInfo.environment["QUILL_RUN_DIARIZATION_BENCHMARK"] == "1" else {
            throw XCTSkip(
                "Set QUILL_RUN_DIARIZATION_BENCHMARK=1 on a provisioned macOS runner to run Core ML inference"
            )
        }
        guard DiarizationEngine.modelsAvailable() else {
            XCTFail(
                "Offline diarizer models are not cached. Prime the FluidAudio cache before enabling this benchmark."
            )
            return
        }
        let fixtureDirectory = try fixtureDirectory()
        let diarizer = DiarizationEngine()
        try await diarizer.prepare()
        defer { Task { await diarizer.release() } }

        var failures: [String] = []
        var totalReferenceSpeech: Double = 0
        var totalError: Double = 0

        for name in Self.fixtureNames {
            let reference = try referenceSegments(
                from: fixtureDirectory.appendingPathComponent("\(name).rttm")
            )
            let actual = try await diarizer.diarize(
                fixtureDirectory.appendingPathComponent("\(name).wav")
            )
            let score = PortableDiarizationScorer.score(
                reference: reference,
                hypothesis: actual.map {
                    .init(speaker: $0.speaker, start: $0.start, end: $0.end)
                },
                collar: DiarizationEngine.evaluationCollar
            )
            let referenceSpeakers = Set(reference.map(\.speaker)).count
            let actualSpeakers = Set(actual.map(\.speaker)).count
            let speakerCountError = abs(referenceSpeakers - actualSpeakers)
            totalReferenceSpeech += score.referenceSpeech
            totalError += score.referenceSpeech * score.der

            if score.der > DiarizationEngine.maximumFixtureDER
                || speakerCountError > DiarizationEngine.maximumFixtureSpeakerCountError {
                failures.append(
                    "\(name): DER \(percent(score.der)); speakers ref=\(referenceSpeakers), actual=\(actualSpeakers)"
                )
            }
        }

        XCTAssertTrue(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
        let corpusDER = totalReferenceSpeech > 0 ? totalError / totalReferenceSpeech : 0
        XCTAssertLessThanOrEqual(
            corpusDER,
            DiarizationEngine.maximumFixtureDER,
            "aggregate DER \(percent(corpusDER)) exceeded \(percent(DiarizationEngine.maximumFixtureDER))"
        )
    }

    private func fixtureDirectory() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diarization", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw FixtureError.missing(source)
        }
        return source
    }

    private func referenceSegments(from url: URL) throws -> [PortableDiarizationScorer.Segment] {
        try PortableDiarizationScorer.parseRTTM(String(contentsOf: url, encoding: .utf8))
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private enum FixtureError: Error, CustomStringConvertible {
        case missing(URL)
        var description: String {
            switch self { case .missing(let url): return "missing fixture directory: \(url.path)" }
        }
    }
}
