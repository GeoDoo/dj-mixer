# DJM-TOUR1 — macOS DJ Mixer

Native macOS app. 4 channels, 3-band EQ, Beat FX, crossfader, persistent library.

## Quick start

```bash
cd ~/Dev/dj-mixer
swift run
```

The app window appears. Resize it. Stays on top of other windows.

## Load a track

Click **Load** on any channel → pick an audio file (MP3, WAV, M4A, FLAC, AIFF) → waveform appears.

The file is copied to `~/Library/Application Support/dj-mixer/samples/` so it survives restart.

## Channel controls

Per channel from top to bottom:

| Section | What it does |
|---------|-------------|
| **CH label** | Channel number. Hover over it. |
| **Load** | Opens file picker. Also drag-drop not supported yet. |
| **Waveform** | Click anywhere to seek. White line = play position. Green line = cue point. |
| **▶ / ⏹** | Play / Stop. Toggle. |
| **CUE** | First click: marks a green cue line at current position. Second click (while stopped): jumps back to cue and plays. |
| **✕** | Unloads the track from this channel. |
| **HI / MID / LOW** | 3-band EQ. Drag up/down to adjust. Center = flat (0 dB). Up = boost (+6 dB). Down = kill (-∞). Orange arc = boost. Red arc = cut. |
| **Level meter** | 4-segment LED: green/yellow/orange/red. Shows channel output level. |
| **Channel fader** | Slider 0–100%. Default 100%. Drag down to reduce volume. |

## Crossfader

Bottom bar, labeled A–B. Drag to blend between channels assigned to A side vs B side.

**Crossfader assign:** Currently all channels default to THRU (crossfader does nothing). A real DJM mixer has a THRU/A/B switch per channel — I can add this back if you want it.

**CURVE** slider adjusts how abruptly the crossfader transitions (left = smooth, right = sharp).

## Beat FX

Bottom bar, left section. Select an effect type, adjust the parameter, pick a beat division, toggle ON.

| FX Type | What it does | Key parameter |
|---------|-------------|--------------|
| **DELAY** | Synchronized delay repeats | PARAM = feedback amount |
| **ECHO** | Same as delay (warmer) | Same |
| **REVERB** | Spatial reverb (hall) | PARAM = reverb mix |
| **FLANGER** | Sweeping comb filter | PARAM = feedback intensity |
| **PHASER** | Phase-shifting sweep | PARAM = effect mix |
| **FILTER** | Low-pass sweep (closes down) | PARAM = cutoff frequency |
| **CRUSH** | Lo-fi bit/sample rate reduction | PARAM = distortion mix |
| **SPACE** | Huge hall reverb | PARAM = reverb mix |

**BEAT** picker sets the timing: 1/1 = whole note, 1/2 = half, 1/4 = quarter, 1/8 = eighth, 1/16 = sixteenth.

## Master section

Right side of bottom bar:
- **MASTER** level meter + VOL knob — controls overall output
- **BOOTH** volume — controls a separate output bus for monitor speakers

## Library

Click **LIBRARY (N)** in the top bar. Opens a 1200px-wide window.

- **All Tracks** — every file you've ever loaded. Click CH1–CH4 to load instantly.
- **+** to create a playlist. Type a name, hit +.
- **+** menu on each track adds it to a playlist.
- **✕** on a track removes it from library (or from playlist when viewing a playlist).
- Pick a playlist from the dropdown to see only its tracks.
- **✕** next to the playlist picker deletes the playlist.

Library survives app restart. Tracks are stored in `~/Library/Application Support/dj-mixer/samples/`.

## Tips

- **No EQ knob shows active arc?** At exact center (flat), the knob shows a small dot. As you boost, an orange arc grows. As you cut, a red arc grows. The circle stays blue when off-center.
- **CUE button stays lit green** when a cue point is set. Click again while stopped to jump back.
- **Beat FX only processes when ON.** The PARAM knob does nothing when OFF.
- **Want to DJ with someone?** Load tracks on different channels, use channel faders and crossfader to blend.
- **No SoundCloud/Spotify** — load local audio files only. Use `yt-dlp -x --audio-format mp3 <url>` to download from YouTube/SoundCloud first.

## Keyboard shortcuts

None yet. Coming: Space (play/pause focused channel), 1–4 (focus), Q/W (volume), A/S (EQ bands).
