#!/bin/bash
#
# Regenerate the website's walkthrough videos, unattended.
#
#     Tools/Demo/site.sh [all | <script>...] [--no-build] [--udid UDID]
#                                            [--composite-only]
#
# Records each take (record.sh), then composites it into the site's frame
# with its captions (composite.py). The videos and their .vtt files land in
# ${GFPC_DEMO_HOME:-~/GFPCDemoData}/site, named as the site serves them from
# assets/video/; copying them across is the website's step.
#
# Builds once, for the first take, and reuses that build for the rest.
# --composite-only skips recording and re-composites the takes already there.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

USAGE="usage: site.sh [all | <script>...] [--no-build] [--udid UDID] [--composite-only]"
ALL=(price-tracking receipt-management reporting-exporting)

SCRIPTS=()
RECORD_FLAGS=()
BUILD=1
RECORD=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        all) SCRIPTS+=("${ALL[@]}"); shift ;;
        --no-build) BUILD=0; shift ;;
        --udid) RECORD_FLAGS+=(--udid "$2"); shift 2 ;;
        --composite-only) RECORD=0; shift ;;
        -*) echo "$USAGE" >&2; exit 2 ;;
        *) SCRIPTS+=("$1"); shift ;;
    esac
done
(( ${#SCRIPTS[@]} )) || SCRIPTS=("${ALL[@]}")

if (( RECORD )); then
    for script in "${SCRIPTS[@]}"; do
        flags=("${RECORD_FLAGS[@]+"${RECORD_FLAGS[@]}"}")
        (( BUILD )) || flags+=(--no-build)
        "$ROOT/Tools/Demo/record.sh" "$script" "${flags[@]+"${flags[@]}"}"
        BUILD=0
    done
fi

echo "==> Compositing"
python3 "$ROOT/Tools/Demo/composite.py" "${SCRIPTS[@]}"
