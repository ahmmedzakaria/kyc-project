#!/bin/bash

# ======== CONFIG ========
REPO_URL=$1          # e.g. https://github.com/your-org/ideal-api.git
BRANCH_NAME=$2       # e.g. main or dev
TARGET_DIR=$3        # e.g. ./ideal-api
# ========================

# Function: print usage
usage() {
  echo "Usage: $0 <repo_url> <branch_name> <target_dir>"
  echo "Example: ./pull-repo.sh https://github.com/zakaria/ideal-api.git main ./ideal-api"
  exit 1
}

# Check inputs
if [ -z "$REPO_URL" ] || [ -z "$BRANCH_NAME" ] || [ -z "$TARGET_DIR" ]; then
  usage
fi

# If directory does not exist, clone it
if [ ! -d "$TARGET_DIR/.git" ]; then
  echo "🚀 Cloning $REPO_URL (branch: $BRANCH_NAME) into $TARGET_DIR..."
  git clone --branch "$BRANCH_NAME" --single-branch "$REPO_URL" "$TARGET_DIR"
else
  # If already exists, pull latest changes
  echo "🔄 Pulling latest changes for $BRANCH_NAME from $REPO_URL..."
  cd "$TARGET_DIR" || exit
  git fetch origin "$BRANCH_NAME"
  git checkout "$BRANCH_NAME"
  git pull origin "$BRANCH_NAME"
fi

echo "✅ Repository is up to date at $TARGET_DIR (branch: $BRANCH_NAME)"
