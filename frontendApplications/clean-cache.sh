#!/usr/bin/env bash
# Clears Angular/Vite build caches across this workspace's apps:
#   .angular/cache   — Angular CLI's persistent build cache
#   node_modules/.vite — Vite's pre-bundled dependency-graph cache
#
# Needed after rebuilding frontend-libs-21's dist/platform or dist/shared —
# the dev server's Vite pre-bundle can otherwise keep serving a stale
# dependency graph that predates a package's new/changed exports, surfacing
# as "SyntaxError: The requested module '...' does not provide an export
# named 'X'" in the browser even though the actual build is correct.
#
# Safe to run any time: both directories are pure build artifacts, rebuilt
# automatically on next `ng serve`/`ng build`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APPS=(
    kyc-frontend-21
    system-frontend-21
    log-frontend-21
    sentinel-kyc-angular-cld
    layout-21
)

echo "==> Clearing Angular/Vite caches"

for app in "${APPS[@]}"; do
    dir="$SCRIPT_DIR/$app"
    [ -d "$dir" ] || continue

    removed=false
    if [ -d "$dir/.angular/cache" ]; then
        rm -rf "$dir/.angular/cache"
        removed=true
    fi
    if [ -d "$dir/node_modules/.vite" ]; then
        rm -rf "$dir/node_modules/.vite"
        removed=true
    fi

    if [ "$removed" = true ]; then
        echo "    cleared: $app"
    else
        echo "    skipped: $app (nothing cached)"
    fi
done

echo "==> Done. Restart any running dev server(s) to pick up fresh caches."
