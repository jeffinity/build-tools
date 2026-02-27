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

if [[ -x ".kitty/.bin/golangci-lint" ]]; then
  lint_cmd=".kitty/.bin/golangci-lint"
elif command -v golangci-lint &>/dev/null; then
  lint_cmd="golangci-lint"
else
  echo_color "⚠ golangci-lint not found, please execute \`kitty install\` first" yellow
  exit 1
fi

spin_exec "GOOS=linux $lint_cmd run ./..." GOOS=linux $lint_cmd run ./...

echo_color "✔ lint finished." green
