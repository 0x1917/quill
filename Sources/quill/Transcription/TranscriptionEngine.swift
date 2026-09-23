import Foundation

/// One timed span of recognized speech from a single track, relative to that
/// track's own start.
struct TranscriptSegment: Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    /// Present when the ASR engine exposes word timing. Diarization can then
    /// split a sentence at a speaker handoff instead of assigning it wholesale.
    let words: [TimedTranscriptWord]

    init(start: TimeInterval, end: TimeInterval, text: String, words: [TimedTranscriptWord] = []) {
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }
}

/// A speech-to-text engine quill can run locally. Engines are prepared lazily
/// (model download + load) when the transcription queue has work and released
/// when it drains, so quill never idles holding gigabytes of model weights.
protocol TranscriptionEngine: Sendable {
    /// Short engine identifier recorded as transcript.json provenance.
    var name: String { get }
    /// Concrete model identifier recorded as transcript.json provenance.
    var model: String { get }
    func prepare() async throws
    func transcribe(_ audio: URL) async throws -> [TranscriptSegment]
    func release() async
}
