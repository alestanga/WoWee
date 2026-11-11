#!/usr/bin/env bash
# Build a game-data tree sized for a phone or tablet, rather than a desktop.
#
# A full extraction of a retail client is 19-35 GB, most of which the client
# never reads. This script drops the parts it does not, so what gets copied
# onto a device is smaller.
#
#   tools/ios-lite-extract.sh --mpq-dir <path> --output <path> [options]
#
# What it leaves out, and why:
#
#   sound\      Several GB of .wav files. The client runs without them: the
#               audio coordinator warns that audio is disabled and the game
#               plays on. Music in the client is the project's own soundtrack
#               (assets/Original Music), which is separate from the game's
#               sound effects.
#   movie\      The client acknowledges movie requests without playing them
#               (src/game/game_handler_packets.cpp), so these are never read.
#   dbfilesclient\*.dbc
#               Only the DBCs the client uses are extracted. The full set is
#               ~90 MB and most of it is unused.
#
# What it keeps: the interface (the game's own UI art), terrain, world,
# creature, character and item data - everything the world is drawn from.
#
# Pass --keep-sound to keep the sound effects as well.
#
# The result is still a normal extraction: the same manifest.json, the same
# layout, readable by the desktop client too.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/ios-lite-extract.sh --mpq-dir <path> --output <path> [options]

Required:
  --mpq-dir <path>    Path to the WoW Data directory containing the MPQs
  --output <path>     Where to write the extraction

Options:
  --expansion <id>    classic, turtle, tbc, wotlk, cata (default: auto-detect)
  --locale <id>       enUS, deDE, frFR, ... (default: auto-detect)
  --expansion-subdir  Write into <output>/expansions/<expansion>
  --keep-sound        Keep the sound effects (adds several GB)
  --threads <N>       Extraction threads (default: auto)
  --listfile <path>   External listfile for MPQ enumeration
  -h, --help          This message

Example:
  tools/ios-lite-extract.sh --mpq-dir ~/WoW/Data --output ~/WoWee-Data \\
      --expansion wotlk --expansion-subdir
EOF
}

MPQ_DIR=""
OUTPUT=""
EXTRA=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mpq-dir)    MPQ_DIR="$2"; shift 2 ;;
        --output)     OUTPUT="$2"; shift 2 ;;
        --expansion)  EXTRA+=(--expansion "$2"); shift 2 ;;
        --locale)     EXTRA+=(--locale "$2"); shift 2 ;;
        --threads)    EXTRA+=(--threads "$2"); shift 2 ;;
        --listfile)   EXTRA+=(--listfile "$2"); shift 2 ;;
        --expansion-subdir) EXTRA+=(--expansion-subdir); shift ;;
        --keep-sound)  KEEP_SOUND=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$MPQ_DIR" || -z "$OUTPUT" ]]; then
    echo "Both --mpq-dir and --output are required." >&2
    usage
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTRACT="$REPO_ROOT/build-host/tools/asset_extract/asset_extract"

if [[ ! -x "$EXTRACT" ]]; then
    echo "asset_extract not built at $EXTRACT." >&2
    echo "Build it with:" >&2
    echo "  cmake -S \"$REPO_ROOT\" -B \"$REPO_ROOT/build-host\" -DWOWEE_BUILD_TESTS=OFF" >&2
    echo "  cmake --build \"$REPO_ROOT/build-host\" --target asset_extract" >&2
    exit 1
fi

EXCLUDES=()
if [[ -z "${KEEP_SOUND:-}" ]]; then
    EXCLUDES+=(--exclude 'sound\')
fi
EXCLUDES+=(--exclude 'movie\')

echo "Excluding: ${EXCLUDES[*]:-nothing}"
"$EXTRACT" --mpq-dir "$MPQ_DIR" --output "$OUTPUT" \
    --only-used-dbcs \
    "${EXCLUDES[@]}" \
    "${EXTRA[@]}"

echo
echo "Done. Copy the output directory to the device's WoWee app Documents folder."
du -sh "$OUTPUT" 2>/dev/null || true
