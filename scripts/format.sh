#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P -- "$(dirname -- "$SOURCE")" >/dev/null 2>&1 && pwd)"
  TARGET="$(readlink -- "$SOURCE")"
  [[ "$TARGET" != /* ]] && SOURCE="$DIR/$TARGET" || SOURCE="$TARGET"
done
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SOURCE")" >/dev/null 2>&1 && pwd)"

. "$SCRIPT_DIR/gum_helper.sh"

# -----------------------------------------------------------------------------
# Function: find_tool
# Purpose : Locate a given tool by first checking .kitty/.bin/<tool>,
#           then falling back to system PATH. Returns the executable path or
#           empty string if not found.
# Usage   : TOOL_CMD=$(find_tool "gci")
# -----------------------------------------------------------------------------
find_tool() {
  local name="$1"
  local local_bin=".kitty/.bin/$name"
  if [[ -x "$local_bin" ]]; then
    echo "$local_bin"
  elif command -v "$name" &>/dev/null; then
    echo "$name"
  else
    echo ""
  fi
}

if [ $# -lt 1 ]; then
  echo_color "✖ No target specified. Please provide a directory or 'all'." red
  echo_color "Usage: bash format.sh <directory or 'all'>" yellow
  exit 1
fi

SELECTED_APP="$1"

if ! MODULE_NAME=$(go list -m | head -n 1 2>/dev/null); then
  echo_color "✖ Unable to retrieve module name. Run this at the root of a Go module." red
  exit 1
fi

SEARCH_ROOT="$SELECTED_APP"
if [ "$SELECTED_APP" == "all" ]; then
  SEARCH_ROOT="."
fi

GO_FIND_CMD=(
  find "$SEARCH_ROOT" \
    \( -path "*/vendor/*" -o -path "*/third_party/*" -o -path "*/proto_gen/*" \) -prune -o \
    -type f -name '*.go' ! -name '*.pb.go' \
    -print0
)

# -----------------------------------------------------------------------------
# Run gofmt
# -----------------------------------------------------------------------------
GOFMT_CMD=$(find_tool "gofmt")
if [ -z "$GOFMT_CMD" ]; then
  echo_color "✖ gofmt not found, please execute \`kitty install\` first" yellow
  exit 1
fi

spin_exec "gofmt" sleep 1; "${GO_FIND_CMD[@]}" | xargs -0 "$GOFMT_CMD" -s -w
echo_color "✔ gofmt completed" green

# -----------------------------------------------------------------------------
# Run gci
# -----------------------------------------------------------------------------

GCI_CMD=$(find_tool "gci")
if [ -z "$GCI_CMD" ]; then
  echo_color "✖ gci not found, please execute \`kitty install\` first" yellow
  exit 1
fi

spin_exec "gci sorting" sleep 1; "${GO_FIND_CMD[@]}" | xargs -0 "$GCI_CMD" write --skip-generated -s Standard -s Default -s "Prefix(${MODULE_NAME})" -s Blank -s Dot
echo_color "✔ gci sorting completed" green

# -----------------------------------------------------------------------------
# Run golines
# -----------------------------------------------------------------------------

GOLINES_CMD=$(find_tool "golines")
if [ -z "$GOLINES_CMD" ]; then
  echo_color "✖ golines not found, please execute \`kitty install\` first" yellow
  exit 1
fi

spin_exec "golines formatting" sleep 1; "${GO_FIND_CMD[@]}" | xargs -0 "$GOLINES_CMD" -w \
  --base-formatter=gofmt \
  --max-len=180 \
  --reformat-tags \
  --shorten-comments \
  --ignore-generated
echo_color "✔ golines formatting completed" green

go mod edit -fmt

echo_color "🎉 All format tasks have been completed" green
