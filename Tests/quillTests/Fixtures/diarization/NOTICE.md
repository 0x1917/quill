# Fixture attribution and license notice

This directory redistributes the unmodified first 12 WAV/RTTM pairs
(`ls_real_000` through `ls_real_011`) selected from
[`DimQ1/sortformer-diarization-test-set`](https://huggingface.co/datasets/DimQ1/sortformer-diarization-test-set)
at revision [`92c3f79cf16148c3420766b7af2e47fb2842ec59`](https://huggingface.co/datasets/DimQ1/sortformer-diarization-test-set/tree/92c3f79cf16148c3420766b7af2e47fb2842ec59).
The upstream dataset card identifies these samples as derived from the
[LibriSpeech ASR corpus](https://www.openslr.org/12), **test-clean** subset.

- **Audio and annotations:** LibriSpeech / Vassil Panayotov with Daniel Povey,
  Gautham Chen, Sanjeev Khudanpur, and Vijayaditya Khudanpur; “LibriSpeech:
  an ASR corpus based on public domain audio books.”
- **Dataset packaging:** DimQ1, *Sortformer Diarization Test Set*.
- **License:** [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

This repository only selected these files as test fixtures and normalized RTTM
line endings from CRLF to LF. The audio and annotation content was otherwise
not modified. See `README.md` for use and hash details.
