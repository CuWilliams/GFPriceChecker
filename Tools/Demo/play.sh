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
# Nothing here records video. That is record.sh, Stage 6, which wraps this same
# launch in `simctl io recordVideo`.

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

if [[ -n "$DATASET" ]]; then
    [[ -f "$DATASET" ]] || { echo "No dataset at $DATASET" >&2; exit 1; }
    # As in seed.sh: the dataset is the one file here that can leak PII.
    echo "==> Verifying $DATASET"
    python3 "$ROOT/Tools/Demo/scrub_backup.py" --verify "$DATASET" >/dev/null
fi

UDID=$(resolve_udid "$DEVICE")
(( BUILD )) && build_and_install "$UDID"

# A running instance keeps the environment it launched with.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

ENV=(
    SIMCTL_CHILD_GFPC_DEMO_SCRIPT="$SCRIPT_NAME"
    SIMCTL_CHILD_GFPC_DEMO_DONE_FILE="$DONE_FILE"
)
[[ -n "$DATASET" ]] && ENV+=(SIMCTL_CHILD_GFPC_DEMO_DATASET="$DATASET")
if (( STILLS )); then
    ENV+=(SIMCTL_CHILD_GFPC_DEMO_STILL_FILE="$STILL_FILE")
    [[ -n "$STILL_MARK" ]] && ENV+=(SIMCTL_CHILD_GFPC_DEMO_STILL_MARK="$STILL_MARK")
fi

echo "==> Playing $SCRIPT_NAME"
env "${ENV[@]}" xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

# The app is a launchd job in the Simulator while it runs. Checked so that a
# crash — a fatalError in the seed, say — fails now rather than at the deadline.
# Not `| grep -q`: grep quits at the first match, launchctl takes a SIGPIPE,
# and pipefail reports a running app as a dead one.
running() {
    [[ "$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null)" == *"UIKitApplication:$BUNDLE_ID"* ]]
}

WAIT_FOR="$DONE_FILE"
(( STILLS )) && WAIT_FOR="$STILL_FILE"
DEADLINE=$(( SECONDS + 180 ))
until [[ -f "$WAIT_FOR" ]]; do
    if (( SECONDS >= DEADLINE )); then
        echo "Timed out waiting for $WAIT_FOR" >&2
        exit 1
    fi
    if ! running; then
        # It may have finished between the file check and this one.
        [[ -f "$WAIT_FOR" ]] && break
        echo "The app is no longer running. Its log: xcrun simctl spawn $UDID log show --last 5m --predicate 'process == \"$SCHEME\"'" >&2
        exit 1
    fi
    sleep 0.5
done

if (( STILLS )); then
    xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null 2>&1
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    rm -f "$STILL_FILE"
    echo "Still: $SHOT"
    exit 0
fi

RESULT=$(head -n 1 "$DONE_FILE")
rm -f "$DONE_FILE"
echo "$RESULT"
[[ "$RESULT" == done* ]]
