# quill

A minimal, fully local macOS meeting recorder + transcriber. One menu-bar
click records your mic and all system audio as two separate tracks; when you
stop, quill transcribes both on-device and writes a speaker-tagged transcript.
Nothing ever leaves the machine.

Named for the feather. Sibling of [parrot](https://github.com/digimata/parrot), same skeleton: single
Swift binary, menu-bar tray, no app bundle.

## Install

```sh
cd quill
swift build -c release
sudo cp .build/release/quill /usr/local/bin/quill
quill install --launch-at-login   # optional — runs in the background on login
```

**Requires:** macOS 15+ (Core Audio process taps for system audio — no
virtual device, no kernel extension). Apple Silicon recommended for
transcription speed.

## How to use

1. **Run it** (`quill` in a terminal, or the LaunchAgent).
2. **Click the feather in the menu bar → Start recording.** First use prompts
   for microphone and System Audio Recording permissions. While recording, the
   icon turns red with a running elapsed counter, and macOS shows the purple
   recording indicator.
3. **Click → Stop recording** when the meeting ends. Transcription starts
   automatically (the menu shows progress); a notification fires when the
   transcript is ready.

Each session lands in `~/Recordings/<yyyy.MM.dd-HHmm>/`:

| File | Contents |
|---|---|
| `mic.caf` | your side (default input device, AAC) |
| `system.caf` | everything the Mac played — the other side of the call (AAC) |
| `meta.json` | start/end timestamps, duration, per-track start offsets |
| `transcript.json` | canonical transcript — engine provenance + timed, speaker-tagged segments |
| `transcript.md` | the same transcript rendered for reading |
| `transcribe.log` | transcription progress/errors for this session |

Two tracks on purpose: speech models do better on clean single-source audio.
The mic is labeled `me`; the system track is automatically diarized into
anonymous, session-local `speaker-1`, `speaker-2`, … labels. This resolves
multiple remote participants without trying to identify people or sending
any audio off-device. CAF on purpose: unlike m4a, it needs no finalization
pass — if the process dies mid-meeting, everything already written is still
readable.

## Transcription

Built in, on-device, automatic. The default engine is **Parakeet TDT 0.6B v2**
(English) via [FluidAudio](https://github.com/FluidInference/FluidAudio)'s
Core ML port — roughly 20 seconds per hour of audio on Apple Silicon. Models
(~600 MB) download once on first transcription; `quill doctor` tells you
whether they're already cached so you're never downloading after an important
meeting.

Each track is transcribed separately, shifted by its start offset so both
share one clock, and merged by timestamp. Before transcribing the mixed system
track, quill runs FluidAudio's offline Core ML Community-1/VBx diarizer.
Parakeet word timestamps are aligned one word at a time, so a transcript span
that crosses a turn boundary is split rather than assigned wholesale. A word
must substantially overlap one diarized range before it receives an anonymous
`speaker-N` label; otherwise it remains the safe generic `them` label. The
canonical JSON records the speaker source, time-alignment confidence, and an
overlap flag. If diarization or its model download fails, transcription still
completes with `them`. Jobs run in a serial queue — you can start a new
recording while the last one transcribes. Unfinished jobs resume
on next launch (the filesystem is the queue: a session with `meta.json` but no
`transcript.json` is pending). Failures append to the session's
`transcribe.log` and never block later jobs.

The engine sits behind a small protocol; a Whisper engine (WhisperKit
large-v3-turbo) is planned as the fallback / re-transcription option.

## Config

Optional, at `~/.config/quill/config.json`:

```json
{
  "recordings_dir": "~/Recordings",
  "transcription": { "enabled": true, "engine": "parakeet" },
  "diarization": { "enabled": true, "minimum_confidence": 0.55 },
  "on_stop": "my-hook"
}
```

- `recordings_dir` — where sessions land. Resolution order: `--out` flag >
  config > `~/Recordings`.
- `transcription.enabled` — set `false` to just record.
- `diarization.enabled` — split the mixed system track into anonymous
  `speaker-N` labels (default `true`). Set `false` to retain one `them` label
  for the full system track. The diarization models are downloaded once on
  their first use and run locally thereafter.
- `diarization.minimum_confidence` — the minimum 0–1 fraction of an ASR
  word/span that must overlap a diarization range before Quill labels it
  `speaker-N` (default `0.55`). Lower values label more speech but raise the
  risk of a wrong attribution; unmatched/low-confidence speech remains `them`.
- `mic_voice_processing` — Apple's echo cancellation on the mic (default off).
  Set `true` when recording meetings through the speakers, so playback doesn't
  bleed into the mic track and get transcribed twice as "me". The trade: while
  the voice unit is live, macOS ducks other playback slightly (`.min` ducking
  is configured, but it can't be zeroed). On headphones there's no echo to
  cancel, so raw capture is the better default.
- `on_stop` — shell command spawned with the session directory as its
  argument, **after the transcript is written** (or right after recording if
  transcription is disabled). Wire it to whatever comes next: summarization,
  filing, indexing.

## CLI

```sh
quill                        # run the menu-bar daemon (^C to quit)
quill run --out <dir>        # custom recordings root (default ~/Recordings)
quill doctor                 # check permissions, recordings folder, models
quill install --launch-at-login
quill install --uninstall
```

## Stack

- **Swift** — single SPM executable target
- **Core Audio process tap** (`AudioHardwareCreateProcessTap`, macOS 14.2+) —
  system audio capture via a private aggregate device
- **AVAudioEngine** — mic capture
- **AVAudioFile** — streaming AAC encode into CAF
- **FluidAudio / Parakeet** — on-device Core ML transcription
- **FluidAudio / Community-1 + VBx** — on-device, offline speaker diarization
- **NSStatusItem** — the whole UI

## Diarization acceptance tests

The repository includes 12 short, pinned WAV/RTTM fixtures from the
[DimQ1 Sortformer Diarization Test Set](https://huggingface.co/datasets/DimQ1/sortformer-diarization-test-set)
(CC-BY-4.0). They cover two- and three-speaker turns with known annotations;
see the fixture [attribution notice](Tests/quillTests/Fixtures/diarization/NOTICE.md).
They are a short, non-overlapping read-speech smoke corpus—not a substitute
for consented meeting-style regression fixtures.

- **Any Swift platform (including Linux):** `swift test` runs the
  Foundation-only RTTM parser and DER scorer. It verifies all 12 known
  fixtures, expected speaker counts, anonymous-label matching, the error
  accounting, and the 250 ms speaker-change collar.
- **macOS:** opt into Quill's **actual** offline Core ML diarizer benchmark
  only on a provisioned runner with its model cache preloaded:
  ```sh
  QUILL_RUN_DIARIZATION_BENCHMARK=1 swift test
  ```
  It requires each clip’s DER to be at most 35% and its detected speaker count
  to be within one of the annotation. The test deliberately does not download
  models, so a missing cache produces an actionable failure rather than making
  normal test runs network-dependent. GitHub Actions runs the deterministic
  portable suite on Ubuntu and the normal macOS build/test suite on `macos-15`.
  Run the opt-in Core ML benchmark only from a separately provisioned macOS
  runner that has the FluidAudio model cache.

Cluster IDs are intentionally anonymous, so both suites use optimal
cluster-to-reference matching over the same collar-defined scoring region
before calculating DER. See [evaluation guidance](docs/diarization-evaluation.md)
for the required consent, meeting-style corpus design, and a release benchmark
checklist.

## Gotchas

- A global tap records *everything* the Mac plays — notification dings,
  music, all of it. Don't play Spotify during meetings (or ask for a
  per-process picker if it bothers you).
- If recordings come out silent, check System Settings → Privacy & Security →
  Screen & System Audio Recording.
- Parakeet v2 is English-only. Other languages will come with the Whisper
  engine.
- The binary embeds its Info.plist (`__TEXT,__info_plist`) so TCC can
  attribute permissions to quill itself when running as a LaunchAgent.
