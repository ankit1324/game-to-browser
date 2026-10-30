# Prince of Persia in the browser

[SDLPoP](https://github.com/NagyD/SDLPoP) (the open-source C/SDL2 port of the 1989 DOS game)
compiled to WebAssembly with Emscripten. No plugins, no server code: four static files.

Play it online: <https://ankit1324.github.io/game-to-browser/prince-of-persia/dist/>

## Build and run

```sh
brew install emscripten          # once
./build.sh                       # clones SDLPoP if missing -> dist/index.html, index.js, index.wasm, index.data
python3 -m http.server 8080 -d dist --bind 127.0.0.1
open http://127.0.0.1:8080
```

`dist/` must be served over HTTP; opening `index.html` from disk will not work.

## How the port works

| Problem | Fix |
|---|---|
| C code | `emcc` compiles SDLPoP's 20 C files to WebAssembly. SDL2 and SDL2_image come from Emscripten's ports (`-sUSE_SDL=2`). |
| SDLPoP runs its own blocking game loop, but a browser tab must yield to stay alive | `-sASYNCIFY` turns every `SDL_Delay()` into a pause that hands control back to the browser. `idle()` got an extra `SDL_Delay(1)`, because some wait loops only call `idle()`. |
| Game files | `data/`, `SDLPoP.ini` etc. are packed into `index.data` and preloaded into Emscripten's in-memory filesystem. |
| Saves must survive a reload | SDLPoP writes saves to `$HOME/.SDLPoP`. `web/pre.js` mounts that folder on IndexedDB; the C code calls `sync_saves()` after each write. |
| Browsers block audio until the user interacts | The page starts the game (`Module.callMain`) on the first click or key press. |
| Space would scroll the page | SDLPoP turns SDL's text input off at startup, so SDL calls `preventDefault()` on every game key. |
| Ctrl+Q would leave a frozen picture | `quit()` tells the page, which shows a "Play again" screen. |
| Menu clicks missed on Retina/HiDPI screens | `read_mouse_state()` converts the mouse position from CSS pixels to canvas pixels. |
| No executable to fingerprint, so old menu settings could load into a new build | `build.sh` passes a hash of the source as `WEB_BUILD_ID`. |

All changes to SDLPoP are in [`patches/sdlpop-web.patch`](patches/sdlpop-web.patch) (42 lines, all behind
`__EMSCRIPTEN__`). Upstream commit: `3c5add5` (2025-12-24).

## Files

- `build.sh`: the whole build, one `emcc` call. Comments explain the flags.
- `web/shell.html`: the page around the game (loading bar, start screen, controls, fullscreen).
- `web/pre.js`: IndexedDB-backed save folder.
- `SDLPoP/`: upstream source with the patch applied (`git -C SDLPoP diff` shows it). It is not in
  the repository: `build.sh` clones commit `3c5add5` and applies the patch.
- `patches/sdlpop-web.patch`: same patch, for reapplying on a newer SDLPoP.

## Controls

Arrows move, Shift picks up / grabs / strikes, Esc opens the menu (quicksave, settings),
F6 / F9 quicksave / quickload, Ctrl+G saves (levels 3-13), Ctrl+L loads (on the title screen).
Full list on the page and in `SDLPoP/README.md`.

If the browser grabs a key before the game sees it (for example F6 in some browsers), use the
Esc menu instead. Replay recording (Ctrl+Tab) is not available: every browser keeps Ctrl+Tab for
switching tabs.

## Legal

SDLPoP's code is GPLv3. The game data (graphics, levels, sound) belongs to Jordan Mechner / Ubisoft.
Running this yourself is fine; hosting it publicly is your decision and carries takedown risk.
