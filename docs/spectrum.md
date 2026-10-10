# How the bars are made

Both the macOS and the Windows app follow this, so the bars move the same way on either.
The numbers copy what Web Audio's `AnalyserNode` does, which is what the first prototype
inside the browser used.

## Input

- Only the browser's audio. On macOS a Core Audio process tap on Chrome's processes
  (bundle IDs starting with `com.google.Chrome`); on Windows the WASAPI process loopback of
  `chrome.exe` and its child processes. System sounds and other apps stay out.
- Channels are mixed down to mono.
- Nothing is stored or sent anywhere. The samples go into a ring buffer and are overwritten.

## Analysis

| | |
|---|---|
| FFT size | 2048 samples |
| Window | Blackman |
| Magnitude | `abs(bin) / 2048` |
| Time smoothing | `0.75 × previous + 0.25 × current`, per bin, once per drawn frame |
| Range | -80 dB → 0, -10 dB → 255, clamped |

The default `AnalyserNode` range is -100 to -30 dB. With it, loud and heavily mastered songs
sit at the top all the time, so the range is moved up.

## Bars

- 32 bars from 60 Hz to 16 kHz, spread evenly on a log scale. Bar `i` covers
  `60 × (16000/60)^(i/32)` to `60 × (16000/60)^((i+1)/32)` Hz.
- A bar's height is the loudest bin in its range, after smoothing. Bars narrower than a bin
  take the bin they start in, so the lowest few bars can share one bin.

## Look

- Bars `#39c5bb` (Vocafy's accent) on `#12181b` (Vocafy's dark ground).
- Rounded ends, a gap of 18% of a bar's slot, never shorter than 3 pt.
