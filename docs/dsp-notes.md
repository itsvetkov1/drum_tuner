# dsp-notes

## overview
Single-path **FFT-only** analysis with two passes: quick coarse, then refined. Designed for drum strikes (transients). No long-term pitch tracking; per-strike stabilization and short history.

## capture & pre-processing
- Sample rate: 44.1 or 48 kHz; mono float.
- DC removal, Hann or Hamming window.
- Optional pre-emphasis for low frequencies when targeting <60 Hz.
- Strike detection: envelope follower + threshold + hysteresis + short lockout; collect analysis window post-attack.

## analysis passes
### coarse pass
- Window ≈ 150 ms (e.g., 4096 @ 44.1k). 0–2× zero-pad.
- Find dominant region; parabolic interpolation for peak bin → f0 guess.
- Push immediate UI reading with lower confidence.

### refine pass
- Window ≈ 500 ms (700–800 ms for <70 Hz targets).
- Larger FFT (e.g., 16384 @ 44.1k), 2–4× zero-padding allowed.
- Quadratic/parabolic sub-bin interpolation; Quinn/Macleod variant if needed.
- Stabilize value with short median over last N strikes.

## peaks & labeling
- Keep top N peaks within 20–500+ Hz.
- **f0 selection**: highest-energy low-frequency candidate with harmonic support.
- **f1 selection (lug/edge)**: search a higher band; bias around prior f1 when a target filter is active.
- Reject peaks with low SNR or unstable neighborhood.

## rtf (resonant tuning factor)
- `rtf = f1 / f0` when both present.
- UI hints: if rtf < 1.40 → raise resonant; if > 1.65 → lower resonant.

## confidence metric
- Based on SNR near chosen peaks, agreement between coarse and refine, and window energy.
- Widen target filter when confidence is low.

## outputs
- Populate `AnalysisResult` fields; `null` when not found.
- Optional spectral array for Spectrum mode (downsampled for UI).

## tests
- C++ gtests with synthetic tones and two-peak cases.
- Golden comparisons using qa-fixtures WAVs with annotated f0/f1 JSON.
