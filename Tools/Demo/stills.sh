#!/bin/bash
#
# The website's carousel screenshots, cut from the same scripts as its videos.
#
#     Tools/Demo/stills.sh <script>... | all  [--dataset PATH | --no-seed]
#                          [--no-build] [--udid UDID] [--appearance light|dark]
#                          [--out DIR] [--mark NAME]
#
# A take and its screenshot made separately drift apart the moment the data
# behind them changes. Here the script is the storyboard for both:
# `DemoDirector.still()` marks the one frame a screenshot is cut from, and this
# launches the script with GFPC_DEMO_STILL_FILE set, waits for that marker,
# screenshots, and terminates. Nothing is aimed by hand.
#
# Each row of the table below is one launch: a script, the mark it stops at,
# and the carousel file on features.html the frame replaces. Naming a script
# cuts every row it has; `all` cuts every row. Each lands as
# <out>/<site name>.png, by default in ~/GFPCDemoData/stills.
#
# `--mark NAME` stops each named script at its `still("NAME")` instead of its
# rows, for a look at a frame the site does not use, and lands as
# <script>-<NAME>.png.
#
# play.sh --still takes one screenshot of one script, for a look; this is the
# version for the site.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

USAGE="usage: stills.sh <script>... | all [--dataset PATH | --no-seed] [--no-build] [--udid UDID] [--appearance light|dark] [--out DIR] [--mark NAME]"
(( $# )) || { echo "$USAGE" >&2; exit 2; }

DEVICE=booted
DATASET="$ROOT/Tools/Demo/demo-dataset.json"
BUILD=1
APPEARANCE=light
OUT_DIR="${GFPC_DEMO_HOME:-$HOME/GFPCDemoData}/stills"
MARK=""
SCRIPTS=()
ALL=(price-tracking receipt-management reporting-exporting onboarding)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dataset) DATASET="${2/#\~/$HOME}"; shift 2 ;;
        --no-seed) DATASET=""; shift ;;
        --no-build) BUILD=0; shift ;;
        --udid) DEVICE="$2"; shift 2 ;;
        --appearance) APPEARANCE="$2"; shift 2 ;;
        --out) OUT_DIR="${2/#\~/$HOME}"; shift 2 ;;
        --mark) MARK="$2"; shift 2 ;;
        --*) echo "$USAGE" >&2; exit 2 ;;
        all) SCRIPTS+=("${ALL[@]}"); shift ;;
        *) SCRIPTS+=("$1"); shift ;;
    esac
done

(( ${#SCRIPTS[@]} )) || { echo "no scripts given" >&2; exit 2; }
command -v magick >/dev/null || { echo "magick not found (brew install imagemagick)" >&2; exit 2; }

# MARK: - The site's file names
#
# script, mark, and the carousel file the frame replaces. The carousel on
# features.html shows each screenshot whole, at the 1206x2622 a Pro-size iPhone
# takes, so there is nothing to crop. A file is copied over its namesake in the
# site's assets/images/screenshots/ as it stands.
#
# Not here: 01, the launch screen, which a take replaces with a flat curtain,
# and 07, the Capture tab, a JPEG on the site.
STILLS="
price-tracking      tile      screenshot-08-ProductCaptureFlowView
price-tracking      library   screenshot-12-ProductPairListingView
price-tracking      product   screenshot-11-ProductPairDetailView
receipt-management  tile      screenshot-10-ReceiptCaptureView
receipt-management  receipt   screenshot-09-ReceiptDetailView
reporting-exporting tile      screenshot-14-SummaryDashBoardView
reporting-exporting export    screenshot-13-ExportView
onboarding          scanning  screenshot-04-smartscanning-how-it-works
onboarding          camera    screenshot-05-onboarding-camera
onboarding          ready     screenshot-06-onboarding-complete
"

# One launch per line, "script mark file name", in the order asked for
ROWS=()
for SCRIPT_NAME in "${SCRIPTS[@]}"; do
    if [[ -n "$MARK" ]]; then
        ROWS+=("$SCRIPT_NAME $MARK $SCRIPT_NAME-$MARK")
        continue
    fi
    FOUND=0
    while read -r ROW_SCRIPT ROW_MARK ROW_NAME; do
        [[ "$ROW_SCRIPT" == "$SCRIPT_NAME" ]] || continue
        ROWS+=("$ROW_SCRIPT $ROW_MARK $ROW_NAME")
        FOUND=1
    done <<< "$STILLS"
    (( FOUND )) || { echo "no site screenshot for script '$SCRIPT_NAME'" >&2; exit 2; }
done

mkdir -p "$OUT_DIR"
[[ -n "$DATASET" ]] && verify_dataset "$DATASET"

UDID=$(resolve_udid "$DEVICE")
(( BUILD )) && build_and_install "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance "$APPEARANCE"

for ROW in "${ROWS[@]}"; do
    read -r SCRIPT_NAME ROW_MARK ROW_NAME <<< "$ROW"
    STILL_FILE="$OUT_DIR/$SCRIPT_NAME.still"
    DONE_FILE="$OUT_DIR/$SCRIPT_NAME.done"
    RAW="$OUT_DIR/$SCRIPT_NAME.raw.png"
    FINAL="$OUT_DIR/$ROW_NAME.png"
    rm -f "$STILL_FILE" "$DONE_FILE" "$RAW"

    # The same status bar the takes carry, so a still and its video agree on
    # the time of day as well as on the data.
    clean_status_bar "$UDID"

    # Onboarding's Camera page shows the camera permission as it stands, and a
    # Simulator remembers it. Reset, it shows the prompt a new user sees.
    xcrun simctl privacy "$UDID" reset camera "$BUNDLE_ID" 2>/dev/null || true

    EXTRA=(STILL_FILE="$STILL_FILE" STILL_MARK="$ROW_MARK")
    echo "==> $SCRIPT_NAME at $ROW_MARK"
    launch_script "$UDID" "$SCRIPT_NAME" "$DONE_FILE" "$DATASET" "${EXTRA[@]}"

    # The done file is the failure case here: a script that finished without
    # marking a still has no frame to cut.
    if ! wait_for_file "$UDID" "$STILL_FILE" 240 "$DONE_FILE"; then
        xcrun simctl status_bar "$UDID" clear
        exit 1
    fi

    xcrun simctl io "$UDID" screenshot --type png "$RAW" >/dev/null 2>&1
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl status_bar "$UDID" clear
    rm -f "$STILL_FILE" "$DONE_FILE"

    # Quantised to 256 colours: flat-colour UI whose colour count is almost
    # all anti-aliasing, at around half the file. The RMSE printed beside it is
    # the cost; anything past a few hundredths wants a look by eye.
    magick "$RAW" -colors 256 "$FINAL"
    RMSE=$(magick compare -metric RMSE "$RAW" "$FINAL" null: 2>&1 || true)
    rm -f "$RAW"

    echo "Still: $FINAL  $(sips -g pixelWidth -g pixelHeight "$FINAL" | awk '/pixel/ {printf "%s ", $2}') RMSE $RMSE"
done
