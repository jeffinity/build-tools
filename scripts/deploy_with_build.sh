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

OS=${1:-}
ARCH=${2:-}

if [[ -z "$OS" || -z "$ARCH" ]]; then
  echo_color "Usage: $0 <os> <arch> [app] <rhost(s)>" red
  exit 1
fi

shift 2

ROOT_DIR=$(pwd -P)
BUILD_ARGS=("$OS" "$ARCH" "")
DEPLOY_ARGS=("$OS" "$ARCH")

if [[ -d "$ROOT_DIR/app" ]]; then
  if [[ $# -ne 2 ]]; then
    echo_color "Usage: $0 <os> <arch> <app> <rhost(s)>" red
    exit 1
  fi

  APP=${1:-}
  RHOSTS=${2:-}

  BUILD_ARGS+=("$APP")
  DEPLOY_ARGS+=("$APP" "$RHOSTS")
else
  if [[ $# -ne 1 ]]; then
    echo_color "Usage: $0 <os> <arch> <rhost(s)>" red
    exit 1
  fi

  RHOSTS=${1:-}

  DEPLOY_ARGS+=("$RHOSTS")
fi

bash "$SCRIPT_DIR/build_app.sh" "${BUILD_ARGS[@]}"
bash "$SCRIPT_DIR/deploy_app.sh" "${DEPLOY_ARGS[@]}"
