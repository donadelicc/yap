#!/bin/bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is required (https://brew.sh). Please install it first." >&2
    exit 1
  fi
  echo "Installing xcodegen via Homebrew..."
  brew install xcodegen
fi

echo "Generating yap.xcodeproj from project.yml..."
xcodegen generate

echo
echo "Done. Open the project with:"
echo "  open yap.xcodeproj"
