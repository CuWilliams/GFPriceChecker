#!/bin/bash
#
# Shared by seed.sh and play.sh. Source it; it defines functions and constants
# and runs nothing.

BUNDLE_ID="com.cuwilliams66.GFPriceChecker"
SCHEME="GFPriceChecker"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The UDID for "booted" or a name/UDID, on stdout. Exits when nothing is booted.
resolve_udid() {
    local device="$1"
    if [[ "$device" != "booted" ]]; then
        echo "$device"
        return
    fi
    local udid
    udid=$(xcrun simctl list devices booted -j | python3 -c \
        'import json,sys; d=[x for v in json.load(sys.stdin)["devices"].values() for x in v]; print(d[0]["udid"] if d else "")')
    if [[ -z "$udid" ]]; then
        echo "No booted Simulator. Boot one, or pass a name or UDID." >&2
        exit 1
    fi
    echo "$udid"
}

# Builds a DEBUG build for $1 and installs it there. DEBUG because every seam
# the demo tooling drives (GFPriceChecker/Dev/) is compiled out of a release.
build_and_install() {
    local udid="$1"
    echo "==> Building and installing a DEBUG build"
    local flags=(
        -project "$ROOT/GFPriceChecker.xcodeproj"
        -scheme "$SCHEME"
        -configuration Debug
        -destination "id=$udid"
        -derivedDataPath "$ROOT/build/demo"
    )
    xcodebuild build "${flags[@]}" -quiet

    # Ask xcodebuild where it put the app rather than assuming -derivedDataPath
    # decided it. Xcode's Build Location preference, if it is set to Custom or to a
    # shared folder, overrides that flag for the products directory and the build
    # still succeeds — so computing the path here produces a build that worked and
    # an install that cannot find it. Same flags as the build, so the answer is the
    # one that build used.
    local products app
    products=$(xcodebuild "${flags[@]}" -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')
    app="$products/$SCHEME.app"
    if [[ ! -d "$app" ]]; then
        echo "Built, but no app at $app" >&2
        exit 1
    fi
    xcrun simctl install "$udid" "$app"
}
