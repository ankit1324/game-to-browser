#!/usr/bin/env bash
# Build SDLPoP (Prince of Persia) for the browser with Emscripten.
# Output: dist/index.html, index.js, index.wasm, index.data
set -euo pipefail
cd "$(dirname "$0")"

# Get the engine if it is missing: pinned upstream commit plus the web patch.
SDLPOP_COMMIT=3c5add5fb7f83d4ceb542823ab66d00146c4271b
if [[ ! -d SDLPoP/src ]]; then
  echo "Cloning SDLPoP ${SDLPOP_COMMIT:0:7}..."
  git clone https://github.com/NagyD/SDLPoP.git SDLPoP
  git -C SDLPoP checkout -q "$SDLPOP_COMMIT"
  git -C SDLPoP apply ../patches/sdlpop-web.patch
fi

SRC=SDLPoP/src
OUT=dist
SOURCES=(main data seg000 seg001 seg002 seg003 seg004 seg005 seg006 seg007 seg008 seg009
         seqtbl replay options lighting screenshot menu midi opl3 stb_vorbis)

# Fingerprint of the source code. The game uses it to ignore menu settings saved by a different build.
WEB_BUILD_ID=$(cat "$SRC"/*.c "$SRC"/*.h | cksum | cut -d' ' -f1)

CFLAGS=(-std=gnu99 -O2 -D_GNU_SOURCE=1 -Wall "-DWEB_BUILD_ID=${WEB_BUILD_ID}u")  # gnu99, not c99: EM_ASM needs GNU extensions
PORTS=(-sUSE_SDL=2 -sUSE_SDL_IMAGE=2 '-sSDL2_IMAGE_FORMATS=["png"]')
LDFLAGS=(
  # SDLPoP runs its own blocking game loop; Asyncify lets SDL_Delay() yield to the browser.
  -sASYNCIFY -sASYNCIFY_STACK_SIZE=131072
  -sSTACK_SIZE=1048576
  -sALLOW_MEMORY_GROWTH=1
  -sENVIRONMENT=web
  # The page starts the game on the first click/key press, so the browser allows audio.
  -sINVOKE_RUN=0
  -sEXPORTED_RUNTIME_METHODS=callMain
  -lidbfs.js
  --pre-js web/pre.js
  --preload-file SDLPoP/data@/data
  --preload-file SDLPoP/mods@/mods
  --preload-file SDLPoP/replays@/replays
  --preload-file SDLPoP/SDLPoP.ini@/SDLPoP.ini
)
if [[ -f web/shell.html ]]; then
  LDFLAGS+=(--shell-file web/shell.html)
fi

FILES=()
for f in "${SOURCES[@]}"; do FILES+=("$SRC/$f.c"); done

mkdir -p "$OUT"
emcc "${FILES[@]}" "${CFLAGS[@]}" "${PORTS[@]}" "${LDFLAGS[@]}" -o "$OUT/index.html"
echo "Built $OUT/. Serve it with: python3 -m http.server 8080 -d $OUT"
