# modes

## shared ui rules
- Large, readable values; dark theme default.
- Confidence bar; color-blind friendly palette.
- Haptics on stable lock.
- Small info bar: active preset, last f0/f1.

## pitch mode
- Show **Hz**, **note**, and **cents**.
- States: "listening" -> "coarse" -> "refined".
- History: short median over last N stable readings.
- **History window**: use median of the last **5** stable readings to display Hz/note/cents.

## lug/edge mode
- Lug map (4/6/8/10 lugs). Select a reference lug.
- Display delta Hz vs reference (delta = lug f1 - ref f1). Show small +/- cents as secondary.
- "Tighten/loosen" copy with tiers based on |delta|:
  - <= **0.10 Hz** -> **in tune** (no action)
  - **0.10-0.30 Hz** -> **slightly** (minor tweak)
  - **0.30-0.80 Hz** -> **medium** (noticeable turn)
  - **> 0.80 Hz** -> **strong** (larger turn)
- Copy rule: if delta > 0 -> **loosen lug X <tier>**; if delta < 0 -> **tighten lug X <tier>**.
- **Hysteresis**: 0.05 Hz to prevent oscillating messages near boundaries.
- **Mini-history**: store last **6** passes per lug; render six small ticks around each lug dot (older -> newer, fade older). Color: green for loosen, blue for tighten, gray for in-tune.

## resonant mode
- Display `rtf = f1 / f0` prominently.
- Text hints:
  - rtf < 1.40 -> "raise resonant"
  - rtf > 1.65 -> "lower resonant"
- **In-range and sweet spot**
  - In-range when **1.50 <= rtf <= 1.62** -> show badge: "Resonant ratio in range"
  - Sweet spot when **1.54-1.58** -> show badge: "Sweet spot"
  - Outside ranges keep existing guidance (<1.40 raise / >1.65 lower). Between 1.40-1.50 or 1.62-1.65 show "close - fine adjust".

## spectrum mode
- 20-500+ Hz magnitude plot; peak markers.
- Waveform inset (optional); zoom/hold controls.
- Export **PNG** of current spectrum.
- **Waveform inset**
  - Position: top-right overlay, **100dp** height, width auto (maintain ~3:1 scope aspect).
  - Behavior: long-press to freeze; double-tap to reset zoom; drag on main chart to zoom X.
- **PNG export**
  - Resolution: export at **2x logical size**, capped to **2560 px** on the long edge. Background matches theme; include axes and peak labels.
