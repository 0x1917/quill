import Foundation

/// Platform-independent time-alignment policy shared by Quill's macOS
/// transcription pipeline and its Linux test suite. It deliberately does not
/// identify a person: all speaker names are anonymous diarization clusters.
public struct TimedTranscriptWord: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct DiarizedSpeakerRange: Sendable, Equatable {
    public let speaker: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speaker: String, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

public struct SpeakerAttribution: Sendable, Equatable {
    public enum Source: String, Sendable {
        case diarization
        case fallback
        case microphone
    }

    public let speaker: String
    public let source: Source
    /// Fraction of the word/segment duration that overlaps the chosen range.
    /// It is a time-alignment score, not a model-calibrated identity score.
    public let confidence: Double
    public let overlap: Bool

    public init(speaker: String, source: Source, confidence: Double, overlap: Bool) {
        self.speaker = speaker
        self.source = source
        self.confidence = confidence
        self.overlap = overlap
    }
}

public struct AttributedTranscriptTurn: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let attribution: SpeakerAttribution

    public init(text: String, start: TimeInterval, end: TimeInterval, attribution: SpeakerAttribution) {
        self.text = text
        self.start = start
        self.end = end
        self.attribution = attribution
    }
}

public enum DiarizationAttributor {
    /// Attribute word-timed ASR to anonymous diarization ranges. A word only
    /// receives a diarized speaker when enough of it overlaps that range;
    /// otherwise it safely retains the caller's generic fallback label.
    public static func turns(
        words: [TimedTranscriptWord],
        defaultSpeaker: String,
        ranges: [DiarizedSpeakerRange],
        minimumConfidence: Double = 0.55,
        maximumGap: TimeInterval = 1.0
    ) -> [AttributedTranscriptTurn] {
        guard !words.isEmpty else { return [] }
        let attributed = words.map {
            ($0, attribution(start: $0.start, end: $0.end, defaultSpeaker: defaultSpeaker,
                             ranges: ranges, minimumConfidence: minimumConfidence))
        }
        var turns: [AttributedTranscriptTurn] = []
        var wordsInTurn: [TimedTranscriptWord] = []
        var current: SpeakerAttribution?

        func flush() {
            guard let current, let first = wordsInTurn.first, let last = wordsInTurn.last else { return }
            let confidence = current.confidence
            turns.append(AttributedTranscriptTurn(
                text: wordsInTurn.map(\.text).joined(separator: " "), start: first.start, end: last.end,
                attribution: SpeakerAttribution(
                    speaker: current.speaker, source: current.source, confidence: confidence,
                    overlap: current.overlap
                )
            ))
            wordsInTurn = []
        }

        for (word, next) in attributed {
            if let existing = current, let last = wordsInTurn.last,
               (existing.speaker != next.speaker || existing.source != next.source
                    || word.start - last.end > maximumGap) {
                flush()
                current = next
            } else if current == nil {
                current = next
            }
            wordsInTurn.append(word)
        }
        flush()
        return turns
    }

    /// Attribute an arbitrary span for ASR engines that do not provide word
    /// timing. This is deliberately a fallback; word-level `turns` is more
    /// accurate when a speech segment crosses a diarization boundary.
    public static func attribution(
        start: TimeInterval,
        end: TimeInterval,
        defaultSpeaker: String,
        ranges: [DiarizedSpeakerRange],
        minimumConfidence: Double = 0.55
    ) -> SpeakerAttribution {
        let duration = max(0.001, end - start)
        let matches = ranges.map { range in
            (range, max(0, min(end, range.end) - max(start, range.start)))
        }.filter { $0.1 > 0 }
        guard let best = matches.max(by: { $0.1 < $1.1 }) else {
            return SpeakerAttribution(speaker: defaultSpeaker, source: .fallback, confidence: 0, overlap: false)
        }
        let confidence = min(1, best.1 / duration)
        guard confidence >= minimumConfidence else {
            return SpeakerAttribution(speaker: defaultSpeaker, source: .fallback, confidence: confidence,
                                      overlap: matches.count > 1)
        }
        return SpeakerAttribution(speaker: best.0.speaker, source: .diarization, confidence: confidence,
                                  overlap: matches.count > 1)
    }

    private static func assign(
        _ word: TimedTranscriptWord, attribution: SpeakerAttribution,
        to words: inout [TimedTranscriptWord], current: inout SpeakerAttribution?
    ) {
        current = attribution
        words.append(word)
    }
}
