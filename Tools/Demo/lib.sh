#!/bin/bash
#
# Shared by the scripts here. Source it; it defines functions and constants
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

# Exits unless $1 passes scrub_backup.py --verify. The dataset is the one file
# here that can leak PII, so every launch that seeds checks it first.
verify_dataset() {
    local dataset="$1"
    [[ -f "$dataset" ]] || { echo "No dataset at $dataset" >&2; exit 1; }
    echo "==> Verifying $dataset"
    python3 "$ROOT/Tools/Demo/scrub_backup.py" --verify "$dataset" >/dev/null
}

# The status bar every take and still carries: 9:41, full signal, and a full
# battery with no charging bolt (`discharging` at 100; `charged` adds the bolt).
clean_status_bar() {
    xcrun simctl status_bar "$1" override --time 9:41 --batteryState discharging --batteryLevel 100 \
        --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4
}

# Launches the app on $1 playing script $2, which writes done file $3, seeded
# from dataset $4 unless it is empty. Any further NAME=VALUE arguments reach
# the app as GFPC_DEMO_NAME=VALUE, such as STILL_FILE=… for a stills run.
# Terminates a running instance first: it would keep the environment it
# launched with.
launch_script() {
    local udid="$1" script="$2" done_file="$3" dataset="$4"
    shift 4
    local env=(
        SIMCTL_CHILD_GFPC_DEMO_SCRIPT="$script"
        SIMCTL_CHILD_GFPC_DEMO_DONE_FILE="$done_file"
    )
    [[ -n "$dataset" ]] && env+=(SIMCTL_CHILD_GFPC_DEMO_DATASET="$dataset")
    local pair
    for pair in "$@"; do env+=("SIMCTL_CHILD_GFPC_DEMO_$pair"); done

    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    env "${env[@]}" xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
}

# Whether the app is running on $1. It is a launchd job in the Simulator while
# it runs. Not `| grep -q`: grep quits at the first match, launchctl takes a
# SIGPIPE, and pipefail reports a running app as a dead one.
app_running() {
    [[ "$(xcrun simctl spawn "$1" launchctl list 2>/dev/null)" == *"UIKitApplication:$BUNDLE_ID"* ]]
}

# Waits up to $3 seconds for file $2 while the app on $1 runs. Returns non-zero
# if the deadline passes, the app dies first — a fatalError in the seed, say,
# fails now rather than at the deadline — or file $4, when given, appears
# first (a stills run's done file: the script ended without marking a still).
wait_for_file() {
    local udid="$1" file="$2" timeout="$3" instead="${4:-}"
    local deadline=$(( SECONDS + timeout ))
    until [[ -f "$file" ]]; do
        if [[ -n "$instead" && -f "$instead" ]]; then
            echo "$(head -n 1 "$instead") — it ended before writing $file" >&2
            return 1
        fi
        if (( SECONDS >= deadline )); then
            echo "Timed out waiting for $file" >&2
            return 1
        fi
        if ! app_running "$udid"; then
            # It may have finished between the file check and this one.
            [[ -f "$file" ]] && break
            echo "The app is no longer running. Its log: xcrun simctl spawn $udid log show --last 5m --predicate 'process == \"$SCHEME\"'" >&2
            return 1
        fi
        sleep 0.5
    done
}
