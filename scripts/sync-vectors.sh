#!/bin/sh
# Keeps GFCore's vendored copy of the cross-platform test vectors identical to their
# source in shared-docs (gfpricechecker/vectors/). See claude.md, "Testing Strategy".
#
#   scripts/sync-vectors.sh          copy shared-docs' vectors over the vendored copy
#   scripts/sync-vectors.sh --check  exit 1 if the two differ; changes nothing
#
# shared-docs is looked for next to this repo; set SHARED_DOCS to use another checkout.
# Exit status: 0 in step, 1 drifted, 2 shared-docs not found or bad arguments.

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
shared_docs=${SHARED_DOCS:-"$repo/../shared-docs"}
source="$shared_docs/gfpricechecker/vectors"
vendored="$repo/Packages/GFCore/Tests/GFCoreTests/Vectors"

if [ ! -d "$source" ]; then
    echo "sync-vectors: no vectors at $source" >&2
    echo "sync-vectors: clone CuWilliams/shared-docs next to this repo, or set SHARED_DOCS" >&2
    exit 2
fi

describe() {
    branch=$(git -C "$shared_docs" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    commit=$(git -C "$shared_docs" rev-parse --short HEAD 2>/dev/null || echo "?")
    dirty=$(git -C "$shared_docs" status --porcelain -- gfpricechecker/vectors 2>/dev/null)
    echo "shared-docs $branch @ $commit${dirty:+, with uncommitted vector changes}"
}

case "${1:-}" in
    --check)
        if diff -r "$source" "$vendored" >/dev/null 2>&1; then
            echo "sync-vectors: vendored vectors match $(describe)"
        else
            echo "sync-vectors: vendored vectors differ from $(describe):" >&2
            diff -rq "$source" "$vendored" >&2 || true
            echo "sync-vectors: run scripts/sync-vectors.sh to update the vendored copy" >&2
            exit 1
        fi
        ;;
    "")
        mkdir -p "$vendored"
        rsync -a --delete "$source/" "$vendored/"
        echo "sync-vectors: copied vectors from $(describe)"
        ;;
    *)
        echo "usage: $0 [--check]" >&2
        exit 2
        ;;
esac
