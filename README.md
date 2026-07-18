# DJ Mixer

A two-deck digital DJ mixer that runs in your browser. Load audio files, adjust EQ, crossfade between tracks. No install, no sign-up, no servers.

---

## Quick start

```bash
# Open the mixer
open index.html

# Or serve it (if dragging files from a browser tab)
python3 -m http.server 8080
# then open http://localhost:8080
```

## How to mix

### 1. Load a song onto each deck

- **File picker:** Click "Load Track" on a deck, pick an MP3/WAV/FLAC/MP4/M4A from your computer.
- **Drag & drop:** Drag an audio file onto a deck.
- **From SoundCloud/Bandcamp/YouTube:**

```bash
# Install once
brew install yt-dlp ffmpeg

# Download a track (use the share URL from the site)
yt-dlp -x --audio-format mp3 'https://soundcloud.com/artist/track-name'

# Drag the resulting .mp3 onto a deck
```

### 2. Play and adjust

| Control | How |
|---------|-----|
| Play/Pause | Click ▶ or press **Space** |
| Stop & reset | Click ■ |
| Jump in track | Click anywhere on the waveform |
| Set cue point | Click **Cue** — a green marker appears. Jump back by clicking Cue again. |
| Loop | Click **⟳** — track repeats until you click it again |

### 3. EQ (tone controls)

Each deck has 4 knobs: **Vol, Hi, Mid, Lo.**

- **Drag up/down** on a knob to adjust
- Center = flat (12 o'clock)
- Up = boost, Down = cut
- Full down = complete kill (silence that frequency band)
- **Double-click** a knob to toggle between 0% and 100%

Hi controls treble (~7kHz), Mid controls mids (~1.2kHz), Lo controls bass (~200Hz).

### 4. Crossfader

The vertical slider between the decks blends from Deck A (top) to Deck B (bottom). Center = equal mix.

### 5. Volume

Each deck has its own Vol knob. The crossfader blends between them.

---

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| `1` | Focus Deck A |
| `2` | Focus Deck B |
| `Space` | Play/Pause focused deck |
| `←` `→` | Crossfader left/right |
| `Q` `W` | Deck A volume down/up |
| `I` `O` | Deck B volume down/up |
| **Deck A EQ** | |
| `A` `Z` | Hi cut/boost |
| `S` `X` | Mid cut/boost |
| `D` `C` | Lo cut/boost |
| **Deck B EQ** | |
| `J` `U` | Hi cut/boost |
| `K` `Y` | Mid cut/boost |
| `L` `H` | Lo cut/boost |

---

## What each part does

```
┌─────────────┐     ┌─────────────┐
│   Deck A    │     │   Deck B    │
│             │     │             │
│ [Waveform]  │     │ [Waveform]  │  ← Click to seek
│ ▶ ■ Cue ⟳  │     │ ▶ ■ Cue ⟳  │  ← Transport controls
│ Vol Hi Mid  │     │ Vol Hi Mid  │  ← Knobs: drag up/down
│ Lo          │     │ Lo          │
│  ← A  [fader] B → │             │  ← Crossfader blends decks
└─────────────┘     └─────────────┘
```

### Signal chain (what happens to the sound)

```
Song file → EQ (Lo → Mid → Hi) → Volume → Crossfader → Master → Speakers
```

Each deck's audio goes through its own EQ and volume BEFORE the crossfader. This is how professional DJ mixers work — you can shape the sound of each track independently before blending.

### EQ frequencies

| Band | Frequency | Effect |
|------|-----------|--------|
| Lo (Low) | 200Hz shelf | Bass drum, bass guitar, sub-bass |
| Mid | 1.2kHz peaking | Vocals, snare, guitar, piano |
| Hi (High) | 7kHz shelf | Cymbals, hi-hat, air, brightness |

### Full kill

When you turn an EQ knob all the way down, that frequency band is completely removed (not just quiet). This is the "kill switch" style used in DJ mixers — pull Lo on one track while pushing it on the other for smooth bass swaps.

---

## Getting songs

**Legal free downloads:**

| Site | How |
|------|-----|
| **Bandcamp** | Many artists offer "Name your price" — set to $0 for free download. Download the MP3/WAV/FLAC and drag it in. |
| **SoundCloud** | Tracks with "Free DL" in the title allow downloads. Use `yt-dlp` (above) to grab the full quality file. |
| **Your own CDs/vinyl** | Rip to MP3 with any audio software. |

yt-dlp (`brew install yt-dlp ffmpeg`) works on any streaming site that plays audio — it extracts the actual media URL the browser plays and saves it as a local file.

---

## File format support

MP3, WAV, FLAC, OGG, AAC, M4A, MP4 (audio tracks from video files).

Drag onto a deck or use the file picker.

---

## What's NOT here (yet)

- **BPM detection** — no automatic tempo detection
- **Beat sync** — no sync button to match tempos
- **Pitch/tempo** — no keylock or speed slider
- **Effects** — no reverb, delay, echo, filter sweeps
- **Recording** — no way to record your mix
- **Headphone cue** — no pre-fader listen separate from master

Add them when you need them.
