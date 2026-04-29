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
ROOT_DIR=$(pwd -P)

usage() {
  if [[ -d "$ROOT_DIR/app" ]]; then
    echo_color "Usage: $0 <os> <arch> <app> <rhost(s)> [-f|--force]" red
  else
    echo_color "Usage: $0 <os> <arch> <rhost(s)> [-f|--force]" red
  fi
}

if [[ -z "$OS" || -z "$ARCH" ]]; then
  usage
  exit 1
fi

shift 2

POSITIONAL=()
BUILD_OPTS=()

for arg in "$@"; do
  case "$arg" in
    -f|--force)
      BUILD_OPTS+=("-f")
      ;;
    -*)
      echo_color "Unknown option: $arg" red
      usage
      exit 1
      ;;
    *)
      POSITIONAL+=("$arg")
      ;;
  esac
done

BUILD_ARGS=("$OS" "$ARCH" "")
DEPLOY_ARGS=("$OS" "$ARCH")

if [[ -d "$ROOT_DIR/app" ]]; then
  if [[ ${#POSITIONAL[@]} -ne 2 ]]; then
    usage
    exit 1
  fi

  APP=${POSITIONAL[0]:-}
  RHOSTS=${POSITIONAL[1]:-}

  BUILD_ARGS+=("$APP")
  DEPLOY_ARGS+=("$APP" "$RHOSTS")
else
  if [[ ${#POSITIONAL[@]} -ne 1 ]]; then
    usage
    exit 1
  fi

  RHOSTS=${POSITIONAL[0]:-}

  DEPLOY_ARGS+=("$RHOSTS")
fi

BUILD_ARGS+=("${BUILD_OPTS[@]}")

bash "$SCRIPT_DIR/build_app.sh" "${BUILD_ARGS[@]}"
bash "$SCRIPT_DIR/deploy_app.sh" "${DEPLOY_ARGS[@]}"
