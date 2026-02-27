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

# wire_gen: cd into $1, run wire, report success
wire_gen() {
  local path=$1
  pushd "$path" >/dev/null || { echo_color "✖ Error: Cannot enter directory $path" red; exit 1; }
  wire ./... && echo_color "✔ Gen $path wire success." green
  popd >/dev/null
}

normalize_mono_target() {
  local raw=$1
  if [[ -z "$raw" || "$raw" == "all" ]]; then
    echo "all"
    return 0
  fi
  if [[ -d "$raw" ]]; then
    echo "$raw"
    return 0
  fi
  if [[ -d "app/$raw" ]]; then
    echo "app/$raw"
    return 0
  fi
  return 1
}

if [[ -d "app" ]]; then
  target=""
  if ! target=$(normalize_mono_target "$selected"); then
    echo_color "✖ Error: App directory '$selected' does not exist (expected app/<name> or full path)" red
    exit 1
  fi

  if [[ "$target" == "all" ]]; then
    found=false
    for path in app/*; do
      [[ -d "$path" ]] || continue
      found=true
      wire_gen "$path"
    done
    if [[ "$found" == false ]]; then
      echo_color "✖ Error: no app directories found under app/" red
      exit 1
    fi
  else
    wire_gen "$target"
  fi
else
  # single-repo mode: default current repo root
  target="."
  if [[ -n "$selected" && "$selected" != "." && "$selected" != "all" ]]; then
    if [[ -d "$selected" ]]; then
      target="$selected"
    else
      echo_color "✖ Error: directory '$selected' does not exist" red
      exit 1
    fi
  fi
  wire_gen "$target"
fi
