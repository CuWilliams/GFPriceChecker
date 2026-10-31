#!/bin/bash
#
# Record one website walkthrough take, unattended.
#
#     Tools/Demo/record.sh <script> [--dataset PATH | --no-seed] [--no-build]
#                                   [--udid UDID] [--appearance light|dark]
#                                   [--out DIR] [--keep] [--recut]
#
# Clean status bar, light appearance, `simctl io recordVideo` around the same
# launch play.sh makes (lib.sh's launch_script), then ffmpeg cuts the launch
# lead-in off and transcodes to the site's spec. The take lands as
# <out>/<script>.mp4, by default in ~/GFPCDemoData/takes; the site name each
# one ships under is the table in Tools/Demo/README.md.
#
# Scripts: price-tracking  receipt-management  reporting-exporting  (and tour)
#
# Light by default, and not only because the site's pages are light: the cut
# is found by looking for the flat white curtain, which dark appearance turns
# black. A dark take needs launch_frame.py's LIGHT test inverted first.
#
# Beside the take goes <script>.captions.json, the captions the storyboard
# showed, timed against the take: what composite.py burns into the site video.
#
# --keep leaves <script>.raw.mov, <script>.timing and <script>.cues.json beside
# the take; --recut re-runs only the cut on those, so the lead-in can be tuned
# without another recording.
#
# Each take ends with a freezedetect report. A scripted hold reads as a freeze
# too, so it is a list to read against the storyboard, not a pass/fail: see
# "Checking a take" in Tools/Demo/README.md.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

USAGE="usage: record.sh <script> [--dataset PATH | --no-seed] [--no-build] [--udid UDID] [--appearance light|dark] [--out DIR] [--keep] [--recut]"
SCRIPT_NAME="${1:?$USAGE}"
shift

DEVICE=booted
DATASET="$ROOT/Tools/Demo/demo-dataset.json"
BUILD=1
APPEARANCE=light
OUT_DIR="${GFPC_DEMO_HOME:-$HOME/GFPCDemoData}/takes"
KEEP_RAW=0
RECUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dataset) DATASET="${2/#\~/$HOME}"; shift 2 ;;
        --no-seed) DATASET=""; shift ;;
        --no-build) BUILD=0; shift ;;
        --udid) DEVICE="$2"; shift 2 ;;
        --appearance) APPEARANCE="$2"; shift 2 ;;
        --out) OUT_DIR="${2/#\~/$HOME}"; shift 2 ;;
        --keep) KEEP_RAW=1; shift ;;
        --recut) RECUT=1; KEEP_RAW=1; shift ;;
        *) echo "$USAGE" >&2; exit 2 ;;
    esac
done

command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 2; }

mkdir -p "$OUT_DIR"
RAW="$OUT_DIR/$SCRIPT_NAME.raw.mov"
TIMING="$OUT_DIR/$SCRIPT_NAME.timing"
DONE_FILE="$OUT_DIR/$SCRIPT_NAME.done"
LOG="$OUT_DIR/$SCRIPT_NAME.log"
CUES="$OUT_DIR/$SCRIPT_NAME.cues.json"
FINAL="$OUT_DIR/$SCRIPT_NAME.mp4"
CAPTIONS="$OUT_DIR/$SCRIPT_NAME.captions.json"

now() { python3 -c 'import time; print(time.time())'; }

if (( ! RECUT )); then
    rm -f "$RAW" "$TIMING" "$DONE_FILE" "$LOG" "$CUES"
    [[ -n "$DATASET" ]] && verify_dataset "$DATASET"

    UDID=$(resolve_udid "$DEVICE")
    (( BUILD )) && build_and_install "$UDID"

    # MARK: - Simulator state

    xcrun simctl bootstatus "$UDID" -b >/dev/null
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl ui "$UDID" appearance "$APPEARANCE"
    clean_status_bar "$UDID"

    # MARK: - Record

    T_SPAWN=$(now)
    xcrun simctl io "$UDID" recordVideo --codec h264 --mask ignored --force "$RAW" >"$LOG" 2>&1 &
    RECORDER=$!
    stop_recorder() {
        kill -INT "$RECORDER" 2>/dev/null || true
        wait "$RECORDER" 2>/dev/null || true
        xcrun simctl status_bar "$UDID" clear
    }
    # The recorder needs a beat before its first frame; launching under it
    # otherwise loses the app's first second.
    sleep 2

    echo "==> Recording $SCRIPT_NAME"
    launch_script "$UDID" "$SCRIPT_NAME" "$DONE_FILE" "$DATASET" "CAPTIONS_FILE=$CUES"

    # A seeded launch restores 78 pairs and their images before the curtain
    # lifts, so this allows more than play.sh's 180 s.
    if ! wait_for_file "$UDID" "$DONE_FILE" 240; then
        stop_recorder
        exit 1
    fi

    T_STOP=$(now)
    stop_recorder
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

    RESULT=$(head -n 1 "$DONE_FILE")
    rm -f "$DONE_FILE"
    if [[ "$RESULT" != done* ]]; then
        # A take that stopped halfway is still a recording, and would otherwise
        # be cut and published as one. The raw file is kept to look at.
        echo "$RESULT" >&2
        echo "Recording kept at $RAW" >&2
        exit 1
    fi

    printf 'T_SPAWN=%s\nT_STOP=%s\n' "$T_SPAWN" "$T_STOP" >"$TIMING"
fi

# MARK: - Trim and transcode

[[ -f "$RAW" && -f "$TIMING" && -f "$CUES" ]] || { echo "Nothing to cut: $RAW, $TIMING or $CUES is missing" >&2; exit 1; }
source "$TIMING"

# The recorder writes a frame only when the screen changes, so its timeline
# is anchored at spawn and the file *ends at the last change*: a closing hold
# on a still screen is not in it. The start is found by looking at the frames
# (launch_frame.py), and the tail is rebuilt by cloning the last frame out to
# when the recorder was stopped.
LEAD_IN="${GFPC_DEMO_LEAD_IN:-0}"
LAUNCH_AT=$(python3 "$ROOT/Tools/Demo/launch_frame.py" "$RAW")
DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAW")
read -r TRIM_START TAIL_PAD <<<"$(python3 -c "
start = $LAUNCH_AT + $LEAD_IN
wall = $T_STOP - $T_SPAWN
print(round(start, 3), round(max(0.0, wall - $DURATION), 3))")"

# 1170 wide, the width TrendFit's site takes ship at; Stage 7 composites
# these portrait takes into the site's landscape frame.
#
# The frame rate is set by the fps filter, not by `-r 60`. The recording
# declares 600 fps over its sparse frames, and `-r` resampled that against the
# declared rate: the receipt take opened on 4 s of white the raw file holds
# for under one. The filter places each frame by its own timestamp.
ffmpeg -v error -y -ss "$TRIM_START" -i "$RAW" \
    -vf "fps=60,tpad=stop_mode=clone:stop_duration=$TAIL_PAD,scale=1170:-2" \
    -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
    -movflags +faststart -an "$FINAL"

# The director timed its captions from the curtain lifting, which is the
# frame the cut lands on unless GFPC_DEMO_LEAD_IN moved it.
python3 - "$CUES" "$CAPTIONS" "$LEAD_IN" <<'PY'
import json, sys
cues_path, captions_path, lead_in = sys.argv[1], sys.argv[2], float(sys.argv[3])
data = json.load(open(cues_path))
for cue in data["cues"]:
    cue["start"] = round(cue["start"] - lead_in, 3)
    cue["end"] = round(cue["end"] - lead_in, 3)
json.dump(data, open(captions_path, "w"), indent=2)
PY

(( KEEP_RAW )) || rm -f "$RAW" "$TIMING" "$LOG" "$CUES"

echo "Take: $FINAL  (launch at ${LAUNCH_AT}s, cut from ${TRIM_START}s, tail +${TAIL_PAD}s)"
echo "Captions: $CAPTIONS"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration -of csv=p=0 "$FINAL"

# MARK: - Freezes

echo "Freezes of 0.2 s or more (start, duration):"
ffmpeg -hide_banner -i "$FINAL" -vf "freezedetect=n=-55dB:d=0.20" -f null - 2>&1 \
    | grep -oE "freeze_(start|duration): [0-9.]+" | awk '{print $2}' | paste - - \
    | awk 'NF == 2 {printf "  %7.2f  %5.2f\n", $1, $2} NF == 1 {printf "  %7.2f  to end\n", $1}' || true
