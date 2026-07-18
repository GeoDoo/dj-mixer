# Plan: macOS Desktop App for DJ Mixer

## Goal

Package the current web-based DJ mixer (Python backend + HTML/CSS/JS frontend) as a proper macOS desktop application — dock icon, menu bar, no terminal, audio that survives sleep/wake.

## Current state

- Backend: `backend.py` — Python stdlib http.server + sqlite3, serves API + static files
- Frontend: `index.html` + `styles.css` with inline JS, Web Audio API for mixing
- Tests: 13 tests (pytest + Playwright), run via `python3 -m pytest tests/`
- Start: `python3 backend.py` in terminal, open http://localhost:8765

## Options (cheapest to most expensive)

### Option A: Nativefier / PWA wrapper (1 hour)

Wrap the web app in Electron via `nativefier`. Produces a .app. Pros: 1 command. Cons: Electron is 200MB+ per app, no audio integration, electron itself is a resource hog. Skip.

### Option B: macOS WKWebView wrapper + bundled Python (~2 hours)

A Swift/Xcode project that bundles the backend + static files and wraps the frontend in WKWebView. Actually the laziest: a `macapp/` directory with:

- `macapp/Info.plist` — app metadata
- `macapp/main.swift` — 30 lines: start Python subprocess, open WKWebView
- Bundled Python runtime via `python3` (macOS ships it)

**Build with one `swiftc` command, no Xcode needed.**

| Pro | Con |
|-----|-----|
| ~30 lines Swift | Requires Xcode Command Line Tools (already installed) |
| Actual dock icon, app menu, Cmd+Q | Python subprocess means ~30MB runtime total |
| WKWebView uses Safari's engine (fast, modern) | Web Audio API works but latency may differ from Chrome |
| Backend lifecycle tied to app | Need to handle app quit → kill backend |
| .app bundle is self-contained | Sharing requires codesigning or "right click → open" |

### Option C: Swift native (SwiftUI + AVFoundation) (weeks)

Rewrite the entire mixer as a native macOS app with AVFoundation audio processing. Full native controls, AudioKit for effects. Maximum quality. But it's a full rewrite of all 1000+ lines of JS + Python. Not YAGNI unless the web path proves insufficient.

### Option D: Tauri (Rust backend + web frontend) (~1 week)

Replace the Python backend with Rust (Tauri), keep the existing HTML/CSS/JS frontend. Pros: cross-platform, smaller binary than Electron, proper OS integration. Cons: need to rewrite backend in Rust, learn Tauri's IPC model. Same web tech for the frontend.

## Recommendation

**Option B: macOS WKWebView wrapper.** It's the minimum viable "proper macOS app" — actual .app icon, no terminal, all existing code preserved. If audio latency or backend overhead becomes a problem, Option D (Tauri) is the next step without throwing away the frontend.

## Proposed approach

1. Create `macapp/` directory in the repo root
2. Write `main.swift` — launches backend as subprocess, creates WKWebView window, handles app lifecycle
3. Write `Info.plist` — bundle identifier, icons, minimum macOS version
4. Generate a simple app icon (or use a placeholder)
5. Build the .app with a shell script (`build-mac.sh`)
6. Test: app launches, backend starts, mixer loads, controls work
7. Update `samples/` path to be inside `~/Library/Application Support/dj-mixer/` instead of alongside the app

## Files likely to change

- `macapp/main.swift` (new)
- `macapp/Info.plist` (new)
- `macapp/build-mac.sh` (new)
- `backend.py` — update SAMPLES path to use `~/Library/Application Support/dj-mixer/` when running as bundled app
- `README.md` — add build/run instructions

## Tests / validation

- `python3 -m pytest tests/` — all 13 existing tests must still pass
- Manual: launch .app, verify library panel renders, upload a track, play it
- Manual: Cmd+Q quits, backend process terminates

## Risks, tradeoffs, open questions

- **Audio** — WKWebView's Web Audio API may have different latency/permissions than Chrome. Test before committing to Option B.
- **Bundled Python** — macOS ships Python 3.9. If the user upgrades macOS and Python changes, the `dj.db` and `samples/` survive but the app needs recompiling.
- **Distribution** — sharing the .app requires removing the quarantine attribute or codesigning. Notarization is possible but complex. For personal use, `xattr -dr com.apple.quarantine /Applications/dj-mixer.app` is enough.
- **Auto-start backend** — WKWebView loads `http://localhost:8765`. If the backend crashes, the app shows a connection error. Should add a health-check retry.
- **Samples path** — currently `samples/` in the project dir. A proper macOS app stores user data in `~/Library/Application Support/<bundle-id>/`. The backend should detect if it's running bundled and switch paths.

## Open question for the user

> Option B gives you a real .app icon, dock, menu bar, no terminal — in ~30 lines of Swift. The mixer code doesn't change at all. Want me to build this, or do you have a different bar for "proper"?
