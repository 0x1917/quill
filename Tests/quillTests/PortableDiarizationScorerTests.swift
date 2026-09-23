import Foundation
import XCTest
@testable import quillDiarizationTestSupport

final class PortableDiarizationScorerTests: XCTestCase {
    private static let fixtureNames = (0...11).map { String(format: "ls_real_%03d", $0) }
    private static let expectedSpeakerCounts = [
        "ls_real_000": 2, "ls_real_001": 2, "ls_real_002": 2,
        "ls_real_003": 3, "ls_real_004": 2, "ls_real_005": 2,
        "ls_real_006": 3, "ls_real_007": 2, "ls_real_008": 2,
        "ls_real_009": 2, "ls_real_010": 2, "ls_real_011": 3,
    ]

    func testTwelvePinnedRTTMFixturesParseWithExpectedSpeakerCounts() throws {
        let fixtures = try fixtureDirectory()
        for name in Self.fixtureNames {
            let wav = fixtures.appendingPathComponent("\(name).wav")
            XCTAssertTrue(FileManager.default.fileExists(atPath: wav.path), "missing WAV: \(name)")
            XCTAssertGreaterThan(
                (try? wav.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
                1_000,
                "unexpectedly small WAV: \(name)"
            )
            let segments = try PortableDiarizationScorer.parseRTTM(
                String(contentsOf: fixtures.appendingPathComponent("\(name).rttm"), encoding: .utf8)
            )
            XCTAssertFalse(segments.isEmpty, "empty fixture \(name)")
            XCTAssertEqual(
                Set(segments.map(\.speaker)).count,
                try XCTUnwrap(Self.expectedSpeakerCounts[name]),
                "unexpected annotated speaker count in \(name)"
            )
            XCTAssertTrue(segments.allSatisfy { $0.end > $0.start })
        }
    }

    func testFixtureChecksumsMatchManifest() throws {
        let fixtures = try fixtureDirectory()
        let manifest = fixtures.appendingPathComponent("SHA256SUMS")
        let entries = try String(contentsOf: manifest, encoding: .utf8).split(whereSeparator: \.isNewline)
        let fixtureFiles = Set(
            try FileManager.default.contentsOfDirectory(atPath: fixtures.path)
                .filter { $0.hasSuffix(".wav") || $0.hasSuffix(".rttm") }
        )
        XCTAssertEqual(entries.count, fixtureFiles.count)

        var names = Set<String>()
        for entry in entries {
            let parts = entry.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            XCTAssertEqual(parts.count, 2, "malformed checksum entry: \(entry)")
            let name = String(parts[1]).trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(fixtureFiles.contains(name), "manifest names missing fixture: \(name)")
            XCTAssertTrue(names.insert(name).inserted, "duplicate manifest entry: \(name)")
            XCTAssertEqual(try sha256(of: fixtures.appendingPathComponent(name)), String(parts[0]))
        }
        XCTAssertEqual(names, fixtureFiles)
    }

    func testKnownReferenceMatchesItselfExactly() throws {
        let fixtures = try fixtureDirectory()
        for name in Self.fixtureNames {
            let reference = try readRTTM(named: name, in: fixtures)
            let result = PortableDiarizationScorer.score(reference: reference, hypothesis: reference)
            XCTAssertEqual(result.der, 0, accuracy: 0.000_001, "self score failed for \(name)")
        }
    }

    func testAnonymousLabelsAreOptimallyMapped() {
        let reference = [
            segment("alice", 0, 2), segment("bob", 2, 4), segment("alice", 4, 6),
        ]
        let hypothesis = [
            segment("speaker-2", 0, 2), segment("speaker-1", 2, 4), segment("speaker-2", 4, 6),
        ]
        let result = PortableDiarizationScorer.score(reference: reference, hypothesis: hypothesis, collar: 0)
        XCTAssertEqual(result.der, 0, accuracy: 0.000_001)
    }

    func testScorerSeparatesMissFalseAlarmAndConfusion() {
        let reference = [segment("alice", 0, 1), segment("bob", 1, 2)]
        let missed = PortableDiarizationScorer.score(reference: reference, hypothesis: [segment("x", 0, 1)], collar: 0)
        XCTAssertEqual(missed.miss, 1, accuracy: 0.01)
        XCTAssertEqual(missed.der, 0.5, accuracy: 0.01)

        let falseAlarm = PortableDiarizationScorer.score(
            reference: [segment("alice", 0, 1)],
            hypothesis: [segment("x", 0, 2)], collar: 0
        )
        XCTAssertEqual(falseAlarm.falseAlarm, 1, accuracy: 0.01)
        XCTAssertEqual(falseAlarm.der, 1, accuracy: 0.01)

        let confusion = PortableDiarizationScorer.score(
            reference: reference, hypothesis: [segment("x", 0, 2)], collar: 0
        )
        XCTAssertEqual(confusion.confusion, 1, accuracy: 0.01)
        XCTAssertEqual(confusion.der, 0.5, accuracy: 0.01)
    }

    func testCollarExcludesSpeakerChangeBoundaryError() {
        let reference = [segment("alice", 0, 1), segment("bob", 1, 2)]
        let lateBoundary = [segment("x", 0, 1.1), segment("y", 1.1, 2)]
        let withoutCollar = PortableDiarizationScorer.score(
            reference: reference, hypothesis: lateBoundary, collar: 0
        )
        let withStandardCollar = PortableDiarizationScorer.score(
            reference: reference, hypothesis: lateBoundary, collar: 0.25
        )
        XCTAssertGreaterThan(withoutCollar.der, 0)
        XCTAssertEqual(withStandardCollar.der, 0, accuracy: 0.000_001)
    }

    func testCollarDefinesBothMappingAndErrorScoringRegion() {
        // The only overlap that would favour the swapped labels is inside the
        // excluded 250 ms region around 1.0 s. Mapping must ignore it.
        let reference = [segment("alice", 0, 1), segment("bob", 1, 2)]
        let hypothesis = [segment("x", 0, 1.1), segment("y", 1.1, 2)]
        let score = PortableDiarizationScorer.score(
            reference: reference, hypothesis: hypothesis, collar: 0.25
        )
        XCTAssertEqual(score.der, 0, accuracy: 0.000_001)
    }

    private func sha256(of url: URL) throws -> String {
        let command: (String, [String]) = {
            #if os(macOS)
            ("/usr/bin/shasum", ["-a", "256", url.path])
            #else
            ("/usr/bin/sha256sum", [url.path])
            #endif
        }()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.0)
        process.arguments = command.1
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.hashFailed(url) }
        guard let digest = String(
            data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        )?.split(whereSeparator: \.isWhitespace).first else { throw FixtureError.hashFailed(url) }
        return String(digest)
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

    private func readRTTM(named name: String, in directory: URL) throws -> [PortableDiarizationScorer.Segment] {
        try PortableDiarizationScorer.parseRTTM(
            String(contentsOf: directory.appendingPathComponent("\(name).rttm"), encoding: .utf8)
        )
    }

    private func segment(_ speaker: String, _ start: Double, _ end: Double) -> PortableDiarizationScorer.Segment {
        .init(speaker: speaker, start: start, end: end)
    }

    private enum FixtureError: Error { case missing(URL), hashFailed(URL) }
}
