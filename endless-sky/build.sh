#!/usr/bin/env bash
# Build Endless Sky for the browser with Emscripten.
# Output: dist/index.html, index.js, index.wasm, and the data package as index.data.000, .001, ...
# (listed in index.data.json)
#
#   ./build.sh          build (compiles changed sources in parallel into build/, links once)
#   ./build.sh clean    remove build/ and dist/
#
# Written for macOS /bin/bash 3.2 (no associative arrays, no mapfile).
set -euo pipefail
cd "$(dirname "$0")"
SELF="$(pwd)/$(basename "$0")"

ES=endless-sky
TAG=v0.11.2
REPO=https://github.com/endless-sky/endless-sky.git
PATCH=patches/endless-sky-web.patch
OBJ=build
OUT=dist

# Compile flags. gnu++20, not c++20: EM_ASM needs GNU extensions.
CXXFLAGS=(
  -std=gnu++20 -O2 -Wall -Wold-style-cast
  -DES_GLES                                 # OpenGL ES 3 code paths (= WebGL2)
  -Duuid_generate_random=uuid_generate      # Emscripten's libuuid only has uuid_generate
  -sUSE_SDL=2 -sUSE_LIBPNG=1 -sUSE_LIBJPEG=1 -sUSE_ZLIB=1
  -sDISABLE_EXCEPTION_CATCHING=0            # the engine reports load errors with exceptions
)

# One source file -> one object (called by xargs below, several at once).
if [[ "${1:-}" == "--compile-one" ]]; then
  src="$2"
  rel="${src#"$ES"/source/}"
  obj="$OBJ/${rel%.cpp}.o"
  mkdir -p "$(dirname "$obj")"
  echo "  CXX $rel"
  exec em++ "${CXXFLAGS[@]}" -MMD -MP -MF "${obj%.o}.d" -c "$src" -o "$obj"
fi

if [[ "${1:-}" == "clean" ]]; then
  rm -rf "$OBJ" "$OUT"
  echo "Removed $OBJ/ and $OUT/."
  exit 0
fi

# Get the engine if it is missing: pinned upstream tag plus the web patch.
if [[ ! -d "$ES/source" ]]; then
  echo "Cloning Endless Sky $TAG..."
  git clone --depth 1 --branch "$TAG" "$REPO" "$ES"
  git -C "$ES" apply "../$PATCH"
fi

# Link flags.
LDFLAGS=(
  -O2
  -sUSE_SDL=2 -sUSE_LIBPNG=1 -sUSE_LIBJPEG=1 -sUSE_ZLIB=1
  -lopenal                                  # Emscripten's OpenAL on top of Web Audio
  -lidbfs.js                                # IndexedDB filesystem for /persist (mounted by web/pre.js)
  -sDISABLE_EXCEPTION_CATCHING=0
  -sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2
  # The engine runs its own blocking game loop. Asyncify lets SDL_GL_SwapWindow() and
  # FrameTimer::Wait() (emscripten_sleep) hand control back to the browser every frame.
  -sASYNCIFY -sASYNCIFY_STACK_SIZE=1048576
  -sSTACK_SIZE=8388608                      # same order as a desktop main thread
  # Game data stays in JS memory (the preloaded file system); the heap holds game state
  # and decoded images on their way to the GPU.
  -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=268435456 -sMAXIMUM_MEMORY=2147483648
  -sENVIRONMENT=web
  # The page starts the game on the first click or key press, so the browser allows audio.
  -sINVOKE_RUN=0
  -sEXPORTED_RUNTIME_METHODS=callMain,FS
  # Resources at "/" (Files::Init with no arguments uses resources "/" and config "/persist").
  --preload-file "$ES/data@/data"
  --preload-file "$ES/images@/images"
  --preload-file "$ES/sounds@/sounds"
  --exclude-file '*.mp3'                    # music is off in the web build
  --preload-file "$ES/shaders@/shaders"
  --preload-file "$ES/credits.txt@/credits.txt"
  --preload-file "$ES/keys.txt@/keys.txt"
)
if [[ -f web/pre.js ]]; then
  LDFLAGS+=(--pre-js web/pre.js)
elif [[ -n "${PRE_JS:-}" ]]; then
  LDFLAGS+=(--pre-js "$PRE_JS")             # for testing before web/pre.js exists
else
  echo "warning: web/pre.js missing: saves will not persist." >&2
fi
if [[ -f web/shell.html ]]; then
  LDFLAGS+=(--shell-file web/shell.html)
else
  echo "warning: web/shell.html missing: using Emscripten's default page." >&2
fi

# Sources: everything except Windows code, zip plugins (minizip) and the music decoders
# (libmad/FLAC, which also need a decoding thread).
SOURCES=()
while IFS= read -r f; do
  SOURCES+=("$f")
done < <(find "$ES/source" -name '*.cpp' \
  ! -path "$ES/source/windows/*" \
  ! -name ZipFile.cpp \
  ! -name Mp3Supplier.cpp ! -name FlacSupplier.cpp ! -name AsyncAudioSupplier.cpp | LC_ALL=C sort)

# Rebuild everything when the compile flags or the compiler change.
mkdir -p "$OBJ"
STAMP="$(printf '%s\n' "${CXXFLAGS[@]}" "$(em++ --version | head -1)" | shasum | cut -d' ' -f1)"
if [[ "$(cat "$OBJ/flags.stamp" 2>/dev/null || true)" != "$STAMP" ]]; then
  find "$OBJ" -name '*.o' -delete
  echo "$STAMP" > "$OBJ/flags.stamp"
fi

# An object is up to date if it is newer than its source and every header in its .d file.
up_to_date() {
  local obj="$1"
  local dep="${obj%.o}.d"
  local f
  [[ -f "$obj" && -f "$dep" ]] || return 1
  for f in $(sed -e 's/\\$//' -e 's/^[^:]*://' "$dep"); do
    [[ "$f" == *: ]] && continue
    [[ "$f" -nt "$obj" ]] && return 1
  done
  return 0
}

TODO=()
OBJECTS=()
for src in "${SOURCES[@]}"; do
  rel="${src#"$ES"/source/}"
  obj="$OBJ/${rel%.cpp}.o"
  OBJECTS+=("$obj")
  up_to_date "$obj" || TODO+=("$src")
done

if [[ ${#TODO[@]} -gt 0 ]]; then
  # Fetch and build the ports once, before the parallel compile races to do it.
  embuilder build sdl2 libpng libjpeg zlib > /dev/null
  JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  echo "Compiling ${#TODO[@]} of ${#SOURCES[@]} files ($JOBS jobs)..."
  printf '%s\n' "${TODO[@]}" | xargs -P "$JOBS" -I{} "$SELF" --compile-one {}
else
  echo "All ${#SOURCES[@]} objects up to date."
fi

mkdir -p "$OUT"
echo "Linking..."
em++ "${OBJECTS[@]}" "${LDFLAGS[@]}" -o "$OUT/index.html"

# GitHub rejects files over 100 MB (and warns above 50 MB), and the data package is ~395 MB.
# Split it into parts listed in index.data.json; web/shell.html streams them back into one
# download for Emscripten's loader.
rm -f "$OUT"/index.data.[0-9][0-9][0-9] "$OUT/index.data.json"
split -b 45000000 -a 3 -d "$OUT/index.data" "$OUT/index.data."
DATA_SIZE="$(wc -c < "$OUT/index.data" | tr -d ' ')"
PARTS=""
for f in "$OUT"/index.data.[0-9][0-9][0-9]; do
  PARTS="${PARTS:+$PARTS, }\"$(basename "$f")\""
done
printf '{"size": %s, "parts": [%s]}\n' "$DATA_SIZE" "$PARTS" > "$OUT/index.data.json"
rm "$OUT/index.data"
echo "Built $OUT/. Serve it with: python3 -m http.server 8080 -d $OUT --bind 127.0.0.1"
