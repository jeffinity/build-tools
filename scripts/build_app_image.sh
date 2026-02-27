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

usage() {
  cat <<EOF
Usage: $0 <app_path> <version> [-p|--push] [-o|--os <os>] [-a|--arch <arch>]
  <app_path>           your app directory, e.g. app/probe_center
  <version>            image tag, e.g. v1.2.3
  -p, --push           push after build
  -o, --os <os>        target OS (default linux)
  -a, --arch <arch>    target arch (default amd64)
EOF
  exit 1
}

# split into positional and option args
POSITIONAL=()
OPTIONS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--push|-o|--os|-a|--arch)
      OPTIONS+=("$1")
      shift
      if [[ "$1" && "$1" != -* ]]; then
        OPTIONS+=("$1")
        shift
      fi
      ;;
    *)
      if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
        POSITIONAL+=("$1")
        shift
      else
        OPTIONS+=("$1")
        shift
      fi
      ;;
  esac
done

# handle missing positional args with specific error
if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
  echo_color "Error: app_path is missing." red
  usage
elif [[ ${#POSITIONAL[@]} -eq 1 ]]; then
  APP_PATH=${POSITIONAL[0]}
  echo_color "Error: version is missing for app_path '${APP_PATH}'." red
  usage
fi

# restore positional
APP_PATH=${POSITIONAL[0]}
VERSION=${POSITIONAL[1]}
# restore options for parsing
set -- "${OPTIONS[@]}"

PUSH=false
TARGETOS=linux
TARGETARCH=amd64

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--push)
      PUSH=true
      shift
      ;;
    -o|--os)
      if [[ "$TARGETOS" == "linux" ]]; then TARGETOS=$2; fi
      shift 2
      ;;
    -a|--arch)
      if [[ "$TARGETARCH" == "amd64" ]]; then TARGETARCH=$2; fi
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ ! -d "$APP_PATH" ]]; then
  echo_color "Error: directory '$APP_PATH' does not exist." red
  exit 1
fi

APP_NAME=${APP_PATH##*/}
IMAGE="harbor.gainetics.io/waf/images/${APP_NAME}:${VERSION}"

echo_color "Building image ${IMAGE} for ${TARGETOS}/${TARGETARCH}..." cyan

go mod tidy
GOWORK=off go mod vendor

DOCKER_BUILDKIT=1 docker build \
  --platform "${TARGETOS}/${TARGETARCH}" \
  -f deploy/app.dockerfile \
  --build-arg APP="$APP_PATH" \
  --build-arg APP_NAME="$APP_NAME" \
  --build-arg VERSION="$VERSION" \
  --build-arg TARGETOS="$TARGETOS" \
  --build-arg TARGETARCH="$TARGETARCH" \
  -t "$IMAGE" \
  .

rm -rf vendor

if [[ "$PUSH" == true ]]; then
  docker push "$IMAGE"
fi

echo_color " ✅ Build succeeded: ${IMAGE}" green
if [[ "$PUSH" == false ]]; then
  echo_color "To push the image, run:" yellow
  echo_color "  docker push ${IMAGE}" yellow
fi
