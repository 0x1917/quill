# Diarization evaluation and release checklist

Quill's diarizer produces anonymous, session-local labels (`speaker-N`). It
answers *who spoke when*, not a person's identity. Do not present a model label
as a known attendee, and do not build or match voice profiles without explicit,
revocable user consent and a separate privacy/security review.

## What ships and what it does not prove

`Tests/quillTests/Fixtures/diarization` is a pinned 12-clip, non-overlapping
read-speech **smoke corpus**. It detects wiring, timing, fixture, and scoring
regressions. It does not establish quality for actual meetings.

Before enabling or materially changing diarization, evaluate a separate,
consented, access-controlled meeting-style corpus. Do not commit private
meeting recordings to this repository.

## Required corpus coverage

Include at least these slices, with RTTM ground truth and documented consent:

- system-track captures from the supported meeting applications;
- 2, 3, and 4+ remote participants;
- 10–30 minute conversations to measure cluster stability over time;
- overlap/crosstalk and short backchannels;
- silence/no-speech, notification/music contamination, and poor network audio;
- both clean headphone capture and speaker-playback/echo-cancellation paths;
- representative AAC-in-CAF capture, not only 16 kHz PCM WAV.

## Metrics and acceptance decisions

Record, per corpus slice and overall:

1. collar-aware DER (0.25 s collar, document overlap policy);
2. speaker-count error;
3. turn-boundary error and rate of `them` fallback labels;
4. long-session cluster consistency;
5. manual review of the worst-scoring samples.

Pin a baseline by Quill commit, FluidAudio revision, model cache version, and
runner hardware. Treat a statistically/materially worse score versus that
baseline as a release blocker even when an absolute threshold still passes.
The current 35% DER smoke threshold is an integration tripwire, **not** a
meeting-quality target.

## Running the real-model benchmark

Use a provisioned Apple Silicon macOS runner with the offline FluidAudio model
cache already installed. Regular CI deliberately never downloads models.

```sh
QUILL_RUN_DIARIZATION_BENCHMARK=1 swift test
```

Archive the console result with the hardware, macOS version, and model/cache
version. If the cache is absent, the test fails with an actionable message.

## Correctability and safe failure

The transcript JSON exposes `speaker_source`, `speaker_confidence`, and
`overlap`. Consumers should preserve those fields, show anonymous labels as
editable names, support merge/correction workflows, and never convert a low
confidence alignment into a personal identity. Generic `them` is preferable to
a confident but wrong speaker label.
