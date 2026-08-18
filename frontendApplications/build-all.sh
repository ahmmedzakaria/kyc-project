#!/usr/bin/env bash
# Builds every active frontend project in this workspace, in dependency order:
#   1. frontend-libs-21/platform  (shared package, no internal deps)
#   2. frontend-libs-21/shared    (depends on platform)
#   3. kyc-frontend-21            (consumes @nexacore/platform + @nexacore/shared)
#   4. system-frontend-21         (consumes @nexacore/platform + @nexacore/shared)
#   5. sentinel-kyc-angular-cld   (standalone app, no dependency on frontend-libs-21)
#
# layout-21 is intentionally skipped — it shares its package name ("sentinel-kyc")
# and scripts with sentinel-kyc-angular-cld, and looks like a superseded snapshot
# rather than an actively maintained app. Pass --with-layout-21 to build it too.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WITH_LAYOUT_21=false

for arg in "$@"; do
    case "$arg" in
        --with-layout-21) WITH_LAYOUT_21=true ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--with-layout-21]" >&2
            exit 1
            ;;
    esac
done

STEP=0
build_project() {
    local label="$1"
    local dir="$2"
    local cmd="$3"

    STEP=$((STEP + 1))
    echo ""
    echo "==> [$STEP] Building $label"
    echo "    dir: $dir"
    echo "    cmd: $cmd"

    ( cd "$dir" && eval "$cmd" )
}

START_TIME=$(date +%s)

build_project "@nexacore/platform" \
    "$SCRIPT_DIR/frontend-libs-21" \
    "npx ng build platform"

build_project "@nexacore/shared" \
    "$SCRIPT_DIR/frontend-libs-21" \
    "npx ng build shared"

# Consuming apps' .angular/cache and node_modules/.vite can keep serving a
# pre-bundled dependency graph that predates the platform/shared rebuild
# above — clear both before building any app against the fresh dist/ output.
echo ""
echo "==> Clearing Angular/Vite caches before app builds"
"$SCRIPT_DIR/clean-cache.sh"

build_project "kyc-frontend-21" \
    "$SCRIPT_DIR/kyc-frontend-21" \
    "npm run build"

build_project "system-frontend-21" \
    "$SCRIPT_DIR/system-frontend-21" \
    "npm run build"

#build_project "sentinel-kyc-angular-cld" \
#    "$SCRIPT_DIR/sentinel-kyc-angular-cld" \
#    "npm run build"

if [ "$WITH_LAYOUT_21" = true ]; then
    build_project "layout-21" \
        "$SCRIPT_DIR/layout-21" \
        "npm run build"
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "==> All builds succeeded in ${ELAPSED}s"
