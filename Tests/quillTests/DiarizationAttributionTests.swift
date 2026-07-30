import XCTest
@testable import quillDiarizationSupport

final class DiarizationAttributionTests: XCTestCase {
    func testWordTimingSplitsASRSegmentAtSpeakerHandoff() {
        let turns = DiarizationAttributor.turns(
            words: [word("Hello", 0, 0.4), word("there", 0.45, 0.8), word("yes", 1.05, 1.3)],
            defaultSpeaker: "them",
            ranges: [range("speaker-1", 0, 0.9), range("speaker-2", 1, 1.5)]
        )
        XCTAssertEqual(turns.map(\.text), ["Hello there", "yes"])
        XCTAssertEqual(turns.map(\.attribution.speaker), ["speaker-1", "speaker-2"])
        XCTAssertTrue(turns.allSatisfy { $0.attribution.source == .diarization })
    }

    func testMissingTimelineFallsBackWithoutInventingASpeaker() {
        let attributed = DiarizationAttributor.attribution(
            start: 0, end: 1, defaultSpeaker: "them", ranges: []
        )
        XCTAssertEqual(attributed.speaker, "them")
        XCTAssertEqual(attributed.source, .fallback)
        XCTAssertEqual(attributed.confidence, 0)
    }

    func testLowOverlapFallsBackToThem() {
        let attributed = DiarizationAttributor.attribution(
            start: 0, end: 1, defaultSpeaker: "them", ranges: [range("speaker-1", 0, 0.4)]
        )
        XCTAssertEqual(attributed.speaker, "them")
        XCTAssertEqual(attributed.source, .fallback)
        XCTAssertEqual(attributed.confidence, 0.4, accuracy: 0.001)
    }

    func testEqualOverlapUsesStableTimelineOrder() {
        let attributed = DiarizationAttributor.attribution(
            start: 0, end: 1, defaultSpeaker: "them",
            ranges: [range("speaker-1", 0, 0.8), range("speaker-2", 0.2, 1)]
        )
        XCTAssertEqual(attributed.speaker, "speaker-1")
        XCTAssertEqual(attributed.source, .diarization)
        XCTAssertEqual(attributed.confidence, 0.8, accuracy: 0.001)
        XCTAssertTrue(attributed.overlap)
    }

    func testGapStartsANewTurnEvenForSameSpeaker() {
        let turns = DiarizationAttributor.turns(
            words: [word("first", 0, 0.3), word("second", 2, 2.3)],
            defaultSpeaker: "them", ranges: [range("speaker-1", 0, 3)]
        )
        XCTAssertEqual(turns.map(\.text), ["first", "second"])
    }

    private func word(_ text: String, _ start: Double, _ end: Double) -> TimedTranscriptWord {
        .init(text: text, start: start, end: end)
    }

    private func range(_ speaker: String, _ start: Double, _ end: Double) -> DiarizedSpeakerRange {
        .init(speaker: speaker, start: start, end: end)
    }
}
