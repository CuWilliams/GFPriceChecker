#!/bin/bash
#
# Play one scripted take in the Simulator, unattended, and wait for it to end.
#
#     Tools/Demo/play.sh <script> [--still [mark]] [--dataset PATH | --no-seed]
#                                 [--no-build] [--udid UDID]
#
# Builds and installs a DEBUG build, then launches the app with GFPC_DEMO_SCRIPT
# naming the script and GFPC_DEMO_DATASET naming the committed dataset, so every
# take starts from the same library. The director writes a done file when the
# script ends; this waits for it and exits non-zero if the script failed, the
# app died, or nothing arrived in time.
#
# --still runs the script in stills mode: it waits for DemoDirector.still() to
# mark the frame (at `tile`, or the mark given), screenshots it, and terminates.
#
# Nothing here records video. That is record.sh, which wraps the same launch
# (lib.sh's launch_script) in `simctl io recordVideo`.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

USAGE="usage: play.sh <script> [--still [mark]] [--dataset PATH | --no-seed] [--no-build] [--udid UDID]"
SCRIPT_NAME="${1:?$USAGE}"
shift

DEVICE=booted
DATASET="$ROOT/Tools/Demo/demo-dataset.json"
BUILD=1
STILL_MARK=""
STILLS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --still)
            STILLS=1
            if [[ $# -gt 1 && "$2" != --* ]]; then STILL_MARK="$2"; shift; fi
            shift ;;
        --dataset) DATASET="${2/#\~/$HOME}"; shift 2 ;;
        --no-seed) DATASET=""; shift ;;
        --no-build) BUILD=0; shift ;;
        --udid) DEVICE="$2"; shift 2 ;;
        *) echo "$USAGE" >&2; exit 2 ;;
    esac
done

OUT_DIR="${GFPC_DEMO_HOME:-$HOME/GFPCDemoData}/takes"
mkdir -p "$OUT_DIR"
DONE_FILE="$OUT_DIR/$SCRIPT_NAME.done"
STILL_FILE="$OUT_DIR/$SCRIPT_NAME.still"
SHOT="$OUT_DIR/$SCRIPT_NAME${STILL_MARK:+-$STILL_MARK}.png"
rm -f "$DONE_FILE" "$STILL_FILE"

[[ -n "$DATASET" ]] && verify_dataset "$DATASET"

UDID=$(resolve_udid "$DEVICE")
(( BUILD )) && build_and_install "$UDID"

EXTRA=()
if (( STILLS )); then
    EXTRA+=(STILL_FILE="$STILL_FILE")
    [[ -n "$STILL_MARK" ]] && EXTRA+=(STILL_MARK="$STILL_MARK")
fi

echo "==> Playing $SCRIPT_NAME"
launch_script "$UDID" "$SCRIPT_NAME" "$DONE_FILE" "$DATASET" ${EXTRA[@]+"${EXTRA[@]}"}

if (( STILLS )); then
    wait_for_file "$UDID" "$STILL_FILE" 180 "$DONE_FILE"
    xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null 2>&1
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    rm -f "$STILL_FILE" "$DONE_FILE"
    echo "Still: $SHOT"
    exit 0
fi

wait_for_file "$UDID" "$DONE_FILE" 180
RESULT=$(head -n 1 "$DONE_FILE")
rm -f "$DONE_FILE"
echo "$RESULT"
[[ "$RESULT" == done* ]]
