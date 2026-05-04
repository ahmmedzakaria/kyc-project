#!/bin/bash

# =====================================
# sudo apt install jq -y (need jq to parse JSON)
# Script: pull-project-by-version.sh
# Usage: ./pull-project-by-version.sh <version>
# Example: ./pull-project-by-version.sh v3
# =====================================

CONFIG_FILE="project-versions.json"
VERSION=$1

if [ -z "$VERSION" ]; then
  echo "❌ Usage: $0 <version>"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ $CONFIG_FILE not found!"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required. Install it with: sudo apt install jq -y"
  exit 1
fi

if [ "$(jq -r ".versions[\"$VERSION\"] // empty" "$CONFIG_FILE")" == "" ]; then
  echo "❌ Version '$VERSION' not found in $CONFIG_FILE"
  exit 1
fi

is_dirty_repo() {
  local target_dir=$1

  [ -n "$(git -C "$target_dir" status --porcelain)" ]
}

get_origin_url() {
  local target_dir=$1

  git -C "$target_dir" remote get-url origin 2>/dev/null
}

pull_repo() {
  local repo_key=$1
  local repo_url=$2
  local branch=$3
  local target_dir=$4

  if [ -z "$repo_url" ] || [ -z "$branch" ] || [ -z "$target_dir" ]; then
    echo "⚠️  Missing configuration for $repo_key. Skipping."
    return
  fi

  if [ ! -d "$target_dir/.git" ]; then
    echo "🚀 Cloning $repo_key from $repo_url (branch: $branch) into $target_dir..."
    git clone --branch "$branch" --single-branch "$repo_url" "$target_dir"
  else
    local current_origin
    current_origin=$(get_origin_url "$target_dir")

    if [ "$current_origin" != "$repo_url" ]; then
      echo "❌ Remote mismatch for $target_dir"
      echo "   Expected: $repo_url"
      echo "   Actual:   $current_origin"
      exit 1
    fi

    if is_dirty_repo "$target_dir"; then
      echo "❌ $target_dir has uncommitted changes. Commit or stash them before pulling."
      exit 1
    fi

    echo "🔄 Updating $repo_key at $target_dir (branch: $branch)..."
    git -C "$target_dir" fetch origin "$branch"

    if git -C "$target_dir" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$target_dir" checkout "$branch"
    else
      git -C "$target_dir" checkout -b "$branch" --track "origin/$branch"
    fi

    git -C "$target_dir" pull --ff-only origin "$branch"
  fi

  echo "✅ $repo_key ready at $target_dir (branch: $branch)"
}

mkdir -p "$VERSION"

REPO_KEYS=$(jq -r ".core | keys[]" "$CONFIG_FILE")

for repo_key in $REPO_KEYS; do
  repo_url=$(jq -r ".core[\"$repo_key\"].url // empty" "$CONFIG_FILE")
  repo_dir=$(jq -r ".core[\"$repo_key\"].directory // empty" "$CONFIG_FILE")
  repo_branch=$(jq -r ".versions[\"$VERSION\"][\"$repo_key\"].branch // empty" "$CONFIG_FILE")

  if [ -z "$repo_branch" ]; then
    echo "⚠️  No branch configured for $repo_key in $VERSION. Skipping."
    continue
  fi

  pull_repo "$repo_key" "$repo_url" "$repo_branch" "$VERSION/$repo_dir"
done
