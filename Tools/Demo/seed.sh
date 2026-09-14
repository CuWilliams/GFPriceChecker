#!/bin/bash
#
# Put a Simulator into a known, populated state from a scrubbed demo dataset.
#
#     Tools/Demo/seed.sh [dataset] [simulator name or UDID]
#
# Defaults to ~/GFPCDemoData/demo-dataset.json on the booted Simulator.
#
# Builds and installs a DEBUG build first, because the seam this drives
# (Dev/DemoSeed.swift) does not exist in a release build. Then it relaunches
# the app with GFPC_DEMO_DATASET naming the dataset, which makes the app wipe
# its store and import that file over it.

set -euo pipefail

DATASET="${1:-$HOME/GFPCDemoData/demo-dataset.json}"
DEVICE="${2:-booted}"
BUNDLE_ID="com.cuwilliams66.GFPriceChecker"
SCHEME="GFPriceChecker"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DATASET="${DATASET/#\~/$HOME}"
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

if [[ "$DEVICE" == "booted" ]]; then
    UDID=$(xcrun simctl list devices booted -j | python3 -c \
        'import json,sys; d=[x for v in json.load(sys.stdin)["devices"].values() for x in v]; print(d[0]["udid"] if d else "")')
    if [[ -z "$UDID" ]]; then
        echo "No booted Simulator. Boot one, or pass a name or UDID as the second argument." >&2
        exit 1
    fi
else
    UDID="$DEVICE"
fi

echo "==> Building and installing a DEBUG build"
DERIVED="$ROOT/build/demo"
xcodebuild build \
    -project "$ROOT/GFPriceChecker.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" \
    -quiet
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/$SCHEME.app"

# Terminate first. A running instance keeps the environment it launched with,
# so relaunching over it silently does nothing new.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

echo "==> Seeding"
SIMCTL_CHILD_GFPC_DEMO_DATASET="$DATASET" xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "Seeded $UDID from $DATASET"
