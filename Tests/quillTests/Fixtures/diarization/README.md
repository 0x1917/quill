# Diarization acceptance-test fixtures

These are the first 12 WAV/RTTM pairs (`ls_real_000` through `ls_real_011`) from
[DimQ1/sortformer-diarization-test-set](https://huggingface.co/datasets/DimQ1/sortformer-diarization-test-set),
pinned to dataset revision `92c3f79cf16148c3420766b7af2e47fb2842ec59`.
See [NOTICE.md](NOTICE.md) for the required LibriSpeech/DimQ1 attribution,
license link, and the exact redistribution statement.

- **License:** CC-BY-4.0 (as declared by the pinned dataset card)
- **Audio:** 16 kHz mono WAV
- **Reference:** RTTM rows, where field 8 is the speaker ID and fields 4–5 are
  the start time and duration.
- **Purpose:** end-to-end quality acceptance tests for Quill's on-device
  `OfflineDiarizerManager` integration. They are not sent to any service.

`DiarizationBenchmarkTests` uses a 250 ms speaker-change collar, optimal
one-to-one anonymous-cluster mapping, and asserts an individual DER <= 35%
plus a speaker-count error <= 1 for all twelve clips. These short,
non-overlapping read-speech clips are an inference smoke corpus, not a
representative meeting-quality benchmark. File hashes are recorded in
`SHA256SUMS` and verified by the portable test suite, so fixture changes are
intentional and reviewable.
