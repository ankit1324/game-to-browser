# Endless Sky in the browser

[Endless Sky](https://github.com/endless-sky/endless-sky) v0.11.2 (the 2D space trading and combat
game, C++20 / SDL2 / OpenGL / OpenAL) compiled to WebAssembly with Emscripten. No plugins, no server
code: static files, served by any plain static server.

Play it online: <https://ankit1324.github.io/game-to-browser/endless-sky/dist/> (the first visit
downloads 395 MB).

## Build and run

```sh
brew install emscripten          # once (built and tested with 6.0.12)
./build.sh                       # -> dist/index.html, index.js, index.wasm, index.data.000-008
python3 -m http.server 8080 -d dist --bind 127.0.0.1
```

Then open `http://127.0.0.1:8080/`. `dist/` must be served over HTTP; opening `index.html` from
disk will not work. No special headers are needed (no threads, so no COOP/COEP).

- `./build.sh` compiles the 210 engine sources in parallel into `build/`, recompiles only files whose
  source or headers changed, and links once. Clean build: about 40 s on a 10-core Apple Silicon Mac
  (Emscripten ports already cached); a no-change rebuild just relinks (about 10 s).
- `./build.sh clean` removes `build/` and `dist/`.
- If `endless-sky/` is missing, `build.sh` clones tag `v0.11.2` and applies
  `patches/endless-sky-web.patch`.

Sizes: the data package 395 MB (the game's images, sounds and data, in 9 parts of up to 45 MB),
`index.wasm` 7.1 MB (2.0 MB
gzipped), `index.js` 0.9 MB.

## How the port works

| Problem | Fix |
|---|---|
| C++ engine | `em++` compiles everything in `source/` except Windows code, zip plugins (`ZipFile.cpp`) and the music decoders. SDL2, libpng, libjpeg and zlib come from Emscripten's ports; OpenAL is Emscripten's (`-lopenal`, on Web Audio). |
| The engine runs a blocking game loop, but a browser tab must yield to stay alive | `-sASYNCIFY`: `SDL_GL_SwapWindow()` yields once per frame, and `FrameTimer::Wait()` sleeps with `emscripten_sleep()` instead of busy-waiting in `sleep_until()`. |
| Threads would need COOP/COEP headers that a plain static server can't send | No pthreads. `TaskQueue` runs its "async" tasks on the main thread: they wait in one queue and run about 10 ms per 16 ms frame from `ProcessSyncTasks()`, so the loading screen animates while ~6,900 images decode. `Wait()` runs the waiting queue's own tasks right away. Sounds load one per task the same way. |
| OpenGL | WebGL 2 only (`-sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2`), through the engine's existing OpenGL ES 3 code path (`-DES_GLES`). |
| Game files | `data/`, `images/`, `sounds/` (without the MP3 music), `shaders/`, `credits.txt` and `keys.txt` are packed into `index.data` and preloaded at `/`. With no arguments the engine uses resources `/` and config `/persist`. |
| GitHub rejects files over 100 MB, and the data package is 395 MB | `build.sh` splits it into parts of 45 MB (`index.data.000`, `.001`, ...) listed in `index.data.json`. `web/shell.html` streams the parts to Emscripten's loader as one download, so its progress bar works unchanged. |
| Pilots and preferences must survive a reload | `web/pre.js` mounts `/persist` on IndexedDB and holds startup until it is loaded. `Files.cpp` calls `Module.syncSaves()` after every write, delete, move or copy. Preferences are also saved when the Preferences panel closes, because browser players close the tab instead of quitting. |
| Storing makes IndexedDB an exact copy of `/persist`, so storing after a failed load would erase the saves that didn't load | `web/pre.js` stores nothing until the load has finished, and nothing at all in a session whose load failed. The page then says that saving is off. |
| Emscripten's libjpeg is IJG libjpeg 9, not libjpeg-turbo | `ReadJPG()` decodes RGB and widens each row to RGBA. |
| Browsers block audio until the user interacts | `-sINVOKE_RUN=0`; the page calls `Module.callMain([])` on the first click or key press. |
| Space and Tab would scroll the page or move focus | `SDL_StopTextInput()` after the window is created, so SDL calls `preventDefault()` on game keys. Text fields turn text input on when needed. |
| Window size | The window takes the canvas's CSS size and follows resizes (SDL's resizable-window handling). Saved fullscreen/maximized states are ignored at startup: browsers allow fullscreen only from a user gesture (use the page's Fullscreen button). |
| A browser window is often smaller than the desktop minimum (1024x768). At 100% the planet panel (680 px tall) lost its Spaceport and Depart buttons | `Screen::SetZoom()` lets the UI go below 100%, in steps of 5 down to 50%, until the main menu and the planet panel fit: 85% for the 1228x597 canvas of a 1280x720 window. |
| The F3 performance display reads `/proc/self/statm` | In the browser it shows the WebAssembly heap size instead. |
| The runtime stays alive after `main()` returns | `main()` calls `Module.onExit(code)`, and the page shows its "Game closed" screen. |

All engine changes are in [`patches/endless-sky-web.patch`](patches/endless-sky-web.patch), each
behind `#ifdef __EMSCRIPTEN__` and commented (`git -C endless-sky diff` shows them).

## Engine choice and credits

- Engine: upstream Endless Sky **v0.11.2** (latest stable release, commit `3b92d79`), pinned.
- The web changes start from **[endless-web](https://github.com/thomasballinger/endless-web)** by
  **Thomas Ballinger** and **Michał Janiszewski** (branch `endless-web`, `a5f7246`): the
  single-threaded `TaskQueue`, no zip/AVIF/music, and the build flags. This port replaces their
  synchronous task execution with time-sliced execution, uses `/persist` on IndexedDB for all user
  files, uses Emscripten's libjpeg port instead of building libjpeg-turbo with cmake, and drops the
  development flags (`ASSERTIONS=2`, `GL_ASSERTIONS`, source maps, `--emrun`).

## Files

- `build.sh`: the whole build. Comments explain the flags.
- `web/shell.html`: the page around the game (loading bar, start screen, controls, fullscreen).
- `web/pre.js`: IndexedDB-backed `/persist`.
- `endless-sky/`: upstream source at v0.11.2 with the patch applied. It is not in the repository:
  `build.sh` clones it.
- `patches/endless-sky-web.patch`: the same changes, for reapplying.

## Known limits

- **No music.** The MP3/FLAC decoders need a decoding thread; sound effects work.
- **No zip plugins**, no AVIF images, no "open folder" buttons (there is no file manager).
- **Loading:** about 12 s from click to main menu (headless Chrome, M-series Mac). Most frames
  of the loading screen are short, but single huge images can't be split: decoding one 4800x4800
  or 4096x4096 JPEG (`star/smoke ring`, `ui/milky way`) blocks the tab for up to about 1 s.
- **First visit downloads 395 MB.** The browser's HTTP cache may keep it; nothing else caches it.
- **Play in one tab at a time.** Each tab stores its whole copy of `/persist`, so a second tab
  can delete a pilot that the first one saved.
- **Small windows get a smaller UI.** Below about 1000x680 CSS pixels the UI is drawn under 100%,
  so text gets smaller. The Fullscreen button gives the largest canvas.
- Memory: the heap grows to about 400-500 MB while playing (maximum 2 GB).
- F11 and Esc belong to the browser in fullscreen: enter with the page's Fullscreen button, leave
  with Esc.

## Verification

Headless Chrome 156 (ANGLE on Metal, muted) at 1280x720, served by plain `python3 -m http.server`:
start page; animated loading screen; main menu; new pilot through the intro to landing on New
Boston; take-off; thrust and turning, with both real and synthetic key events; 60 fps in flight
(16.7 ms per frame); after a reload, the pilot and a changed preference are still there; game keys
never scroll the page; no console errors. A second run gave the game a silent
`OfflineAudioContext` so the sound code runs: audio initialized and 50 sounds played without errors.
A third test makes the IndexedDB load fail or hang and checks that saved pilots survive. Screenshots
are in [`docs/screenshots/`](docs/screenshots/).

## Legal

Endless Sky's code is GPLv3+ (Michael Zahniser and contributors). The art and sounds are licensed
per file, as listed in [`copyright`](https://github.com/endless-sky/endless-sky/blob/v0.11.2/copyright): CC-BY-SA-4.0, CC0, public
domain (including photographs from morguefile.com), CC-BY-SA-3.0, CC-BY-4.0, CC-BY-3.0 and the
Unsplash license. Hosting it publicly is allowed if you offer the source with it (upstream v0.11.2
plus `patches/endless-sky-web.patch`) and keep the credits.
