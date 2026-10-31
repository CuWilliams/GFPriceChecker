#!/bin/bash
#
# Put a Simulator into a known, populated state from a scrubbed demo dataset.
#
#     Tools/Demo/seed.sh [dataset] [simulator name or UDID]
#
# Defaults to the committed Tools/Demo/demo-dataset.json, on the booted Simulator.
#
# Builds and installs a DEBUG build first, because the seam this drives
# (Dev/DemoSeed.swift) does not exist in a release build. Then it relaunches
# the app with GFPC_DEMO_DATASET naming the dataset, which makes the app wipe
# its store and import that file over it.

set -euo pipefail

DEVICE="${2:-booted}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Defaults to the dataset committed alongside this script, so a fresh clone
# seeds with nothing to set up first. Pass a path to use a local one — a newer
# scrub sitting in ~/GFPCDemoData/, say.
DEFAULT_DATASET="$ROOT/Tools/Demo/demo-dataset.json"
DATASET="${1:-$DEFAULT_DATASET}"

DATASET="${DATASET/#\~/$HOME}"

# Re-scrubbing writes to ~/GFPCDemoData/ by default while this reads the
# committed copy, so a fresh scrub can sit there unnoticed while the Simulator
# keeps getting the old library. Say so rather than seed the stale one quietly.
WORKING="$HOME/GFPCDemoData/demo-dataset.json"
if [[ "$DATASET" == "$DEFAULT_DATASET" && "$WORKING" -nt "$DATASET" ]]; then
    echo "Note: $WORKING is newer than the committed dataset." >&2
    echo "      Seeding the committed one. Pass \"$WORKING\" to use that instead," >&2
    echo "      or copy it over $DATASET and commit it." >&2
fi
if [[ ! -f "$DATASET" ]]; then
    echo "No dataset at $DATASET" >&2
    echo "Build one: python3 Tools/Demo/scrub_backup.py --in ~/GFPCDemoData/backup-raw.json --out $DATASET" >&2
    exit 1
fi

# The dataset is the one artefact in this pipeline that can leak a SIN or a
# real receipt photograph, and it is cheap to re-check. A seed that silently
# loads an unscrubbed export is how one ends up in a published video.
echo "==> Verifying $DATASET"
python3 "$ROOT/Tools/Demo/scrub_backup.py" --verify "$DATASET"

UDID=$(resolve_udid "$DEVICE")
build_and_install "$UDID"

# Terminate first. A running instance keeps the environment it launched with,
# so relaunching over it silently does nothing new.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

echo "==> Seeding"
SIMCTL_CHILD_GFPC_DEMO_DATASET="$DATASET" xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "Seeded $UDID from $DATASET"
