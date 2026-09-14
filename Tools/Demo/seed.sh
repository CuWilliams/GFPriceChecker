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
BUNDLE_ID="com.cuwilliams66.GFPriceChecker"
SCHEME="GFPriceChecker"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Defaults to the dataset committed alongside this script, so a fresh clone
# seeds with nothing to set up first. Pass a path to use a local one — a newer
# scrub sitting in ~/GFPCDemoData/, say.
DATASET="${1:-$ROOT/Tools/Demo/demo-dataset.json}"

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
BUILD_FLAGS=(
    -project "$ROOT/GFPriceChecker.xcodeproj"
    -scheme "$SCHEME"
    -configuration Debug
    -destination "id=$UDID"
    -derivedDataPath "$DERIVED"
)
xcodebuild build "${BUILD_FLAGS[@]}" -quiet

# Ask xcodebuild where it put the app rather than assuming -derivedDataPath
# decided it. Xcode's Build Location preference, if it is set to Custom or to a
# shared folder, overrides that flag for the products directory and the build
# still succeeds — so computing the path here produces a build that worked and
# an install that cannot find it. Same flags as the build, so the answer is the
# one that build used.
PRODUCTS=$(xcodebuild "${BUILD_FLAGS[@]}" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')
APP="$PRODUCTS/$SCHEME.app"
if [[ ! -d "$APP" ]]; then
    echo "Built, but no app at $APP" >&2
    exit 1
fi
xcrun simctl install "$UDID" "$APP"

# Terminate first. A running instance keeps the environment it launched with,
# so relaunching over it silently does nothing new.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

echo "==> Seeding"
SIMCTL_CHILD_GFPC_DEMO_DATASET="$DATASET" xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "Seeded $UDID from $DATASET"
