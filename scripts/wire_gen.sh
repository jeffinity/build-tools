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

selected=${1:-}

# Pre-check: must specify at least one app
if [[ -z "$selected" ]]; then
  echo_color "✖ Error: Please specify at least one app" red
  exit 1
fi

# wire_gen: cd into $1, run wire, report success
wire_gen() {
  local path=$1
  cd "$path" || { echo_color "✖ Error: Cannot enter directory $path" red; exit 1; }
  wire ./... && echo_color "✔ Gen $path wire success." green
  cd -
}

if [[ "$selected" == "all" ]]; then
  # run wire_gen on every sub-dir under app/
  for path in app/*; do
    [[ -d "$path" ]] || continue
    wire_gen "$path"
  done
else
  # Pre-check: the given directory must exist
  if [[ ! -d "$selected" ]]; then
    echo_color "✖ Error: App directory $selected does not exist" red
    exit 1
  fi
  wire_gen "$selected"
fi
