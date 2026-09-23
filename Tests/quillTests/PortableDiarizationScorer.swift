import Foundation

/// Linux-safe RTTM parser and DER scorer used to validate Quill's acceptance
/// corpus and quality thresholds. It deliberately depends on Foundation only:
/// inference is macOS/Core-ML-only, but corpus/scoring regressions should be
/// caught in any CI environment.
enum PortableDiarizationScorer {
    struct Segment: Hashable {
        let speaker: String
        let start: Double
        let end: Double
    }

    struct Score {
        let der: Double
        let miss: Double
        let falseAlarm: Double
        let confusion: Double
        let referenceSpeech: Double
    }

    enum ParseError: Error, CustomStringConvertible {
        case invalidRTTMLine(String)

        var description: String {
            switch self {
            case .invalidRTTMLine(let line): return "invalid RTTM line: \(line)"
            }
        }
    }

    static func parseRTTM(_ contents: String) throws -> [Segment] {
        try contents.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard !fields.isEmpty else { return nil }
            guard fields.count >= 8, fields[0] == "SPEAKER",
                  let start = Double(fields[3]), let duration = Double(fields[4]),
                  start >= 0, duration > 0
            else { throw ParseError.invalidRTTMLine(String(line)) }
            return Segment(speaker: String(fields[7]), start: start, end: start + duration)
        }
    }

    /// Frame-wise DER, including an optimal one-to-one label mapping. This is
    /// equivalent to normal diarization scoring for our non-overlapping RTTM
    /// fixtures, and works with arbitrary anonymous hypothesis labels.
    static func score(
        reference: [Segment], hypothesis: [Segment],
        frameStep: Double = 0.01, collar: Double = 0.25
    ) -> Score {
        precondition(frameStep > 0 && collar >= 0)
        let referenceLabels = labels(in: reference)
        let hypothesisLabels = labels(in: hypothesis)
        let end = (reference + hypothesis).map(\.end).max() ?? 0
        let frameCount = Int(ceil(end / frameStep))
        guard frameCount > 0 else {
            return Score(der: 0, miss: 0, falseAlarm: 0, confusion: 0, referenceSpeech: 0)
        }

        let referenceFrames = activeLabels(
            reference, labels: referenceLabels, frameCount: frameCount, step: frameStep
        )
        let hypothesisFrames = activeLabels(
            hypothesis, labels: hypothesisLabels, frameCount: frameCount, step: frameStep
        )
        let boundaries = Set(reference.flatMap { [$0.start, $0.end] })
        let halfCollar = collar / 2
        let scorable = (0..<frameCount).map { frame in
            let midpoint = (Double(frame) + 0.5) * frameStep
            return !boundaries.contains(where: { abs(midpoint - $0) < halfCollar })
        }
        // The collar defines the scoring region, so use it for both label
        // assignment and error accumulation. Mapping on excluded frames can
        // otherwise change the score of the retained region.
        let mapping = optimalMapping(
            reference: referenceFrames, hypothesis: hypothesisFrames,
            referenceLabels: referenceLabels, hypothesisLabels: hypothesisLabels,
            scorable: scorable
        )
        var miss = 0, falseAlarm = 0, confusion = 0, referenceSpeech = 0

        for frame in 0..<frameCount where scorable[frame] {
            let ref = referenceFrames[frame]
            let hyp = hypothesisFrames[frame]
            let correct = hyp.filter { label in
                guard let mapped = mapping[label] else { return false }
                return ref.contains(mapped)
            }.count
            miss += max(0, ref.count - hyp.count)
            falseAlarm += max(0, hyp.count - ref.count)
            confusion += min(ref.count, hyp.count) - correct
            referenceSpeech += ref.count
        }

        let scale = frameStep
        let refSeconds = Double(referenceSpeech) * scale
        let missSeconds = Double(miss) * scale
        let falseAlarmSeconds = Double(falseAlarm) * scale
        let confusionSeconds = Double(confusion) * scale
        return Score(
            der: refSeconds == 0 ? 0 : (missSeconds + falseAlarmSeconds + confusionSeconds) / refSeconds,
            miss: missSeconds, falseAlarm: falseAlarmSeconds,
            confusion: confusionSeconds, referenceSpeech: refSeconds
        )
    }

    private static func labels(in segments: [Segment]) -> [String] {
        var seen = Set<String>()
        return segments.compactMap { seen.insert($0.speaker).inserted ? $0.speaker : nil }
    }

    private static func activeLabels(
        _ segments: [Segment], labels: [String], frameCount: Int, step: Double
    ) -> [Set<String>] {
        var frames = Array(repeating: Set<String>(), count: frameCount)
        for segment in segments {
            let start = max(0, Int(ceil(segment.start / step - 0.5)))
            let end = min(frameCount, Int(ceil(segment.end / step - 0.5)))
            guard end > start else { continue }
            for index in start..<end { frames[index].insert(segment.speaker) }
        }
        return frames
    }

    private static func optimalMapping(
        reference: [Set<String>], hypothesis: [Set<String>],
        referenceLabels: [String], hypothesisLabels: [String], scorable: [Bool]
    ) -> [String: String] {
        guard !referenceLabels.isEmpty, !hypothesisLabels.isEmpty else { return [:] }
        var overlap: [String: [String: Int]] = [:]
        for (index, (ref, hyp)) in zip(reference, hypothesis).enumerated() where scorable[index] {
            for h in hyp {
                for r in ref { overlap[h, default: [:]][r, default: 0] += 1 }
            }
        }

        var best: [String: String] = [:]
        var bestTotal = -1
        func search(_ index: Int, used: Set<String>, mapping: [String: String], total: Int) {
            if index == hypothesisLabels.count {
                if total > bestTotal { bestTotal = total; best = mapping }
                return
            }
            let hypothesis = hypothesisLabels[index]
            // An unmatched system speaker is valid; it maps to no reference.
            search(index + 1, used: used, mapping: mapping, total: total)
            for reference in referenceLabels where !used.contains(reference) {
                var next = mapping
                next[hypothesis] = reference
                var nextUsed = used
                nextUsed.insert(reference)
                search(
                    index + 1, used: nextUsed, mapping: next,
                    total: total + (overlap[hypothesis]?[reference] ?? 0)
                )
            }
        }
        search(0, used: [], mapping: [:], total: 0)
        return best
    }
}
