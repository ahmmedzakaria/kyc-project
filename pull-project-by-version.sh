#!/bin/bash

# =====================================
# sudo apt install jq -y (need jq to parse JSON)
# Script: pull-version.sh
# Usage: ./pull-version.sh <version>
# Example: ./pull-version.sh v1
# =====================================



CONFIG_FILE="project-versions.json"
VERSION=$1

if [ -z "$VERSION" ]; then
  echo "❌ Usage: $0 <version>"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ config.json not found!"
  exit 1
fi

# Extract info using jq
FRONTEND_URL=$(jq -r ".core.frontend.url" $CONFIG_FILE)
FRONTEND_DIR=$(jq -r ".core.frontend.directory" $CONFIG_FILE)
FRONTEND_BRANCH=$(jq -r ".versions[\"$VERSION\"].frontend.branch" $CONFIG_FILE)

BACKEND_URL=$(jq -r ".core.backend.url" $CONFIG_FILE)
BACKEND_DIR=$(jq -r ".core.backend.directory" $CONFIG_FILE)
BACKEND_BRANCH=$(jq -r ".versions[\"$VERSION\"].backend.branch" $CONFIG_FILE)

# Helper function to clone or update a repo
pull_repo() {
  local repo_url=$1
  local branch=$2
  local target_dir=$3

  if [ "$repo_url" == "null" ] || [ "$branch" == "null" ] || [ "$target_dir" == "null" ]; then
    echo "⚠️  Missing configuration for $target_dir. Skipping."
    return
  fi

  if [ ! -d "$target_dir/.git" ]; then
    echo "🚀 Cloning $repo_url (branch: $branch) into $target_dir..."
    git clone --branch "$branch" --single-branch "$repo_url" "$target_dir"
  else
    echo "🔄 Updating $target_dir (branch: $branch)..."
    cd "$target_dir" || exit
    git fetch origin "$branch"
    git checkout "$branch"
    git pull origin "$branch"
    cd - >/dev/null || exit
  fi

  echo "✅ $target_dir ready (branch: $branch)"
}

# Pull frontend and backend
pull_repo "$FRONTEND_URL" "$FRONTEND_BRANCH" "$VERSION/$FRONTEND_DIR"
pull_repo "$BACKEND_URL" "$BACKEND_BRANCH" "$VERSION/$BACKEND_DIR"
