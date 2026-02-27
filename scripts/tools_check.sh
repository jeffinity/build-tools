#!/usr/bin/env bash

set -eu

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P -- "$(dirname -- "$SOURCE")" >/dev/null 2>&1 && pwd)"
  TARGET="$(readlink -- "$SOURCE")"
  [[ "$TARGET" != /* ]] && SOURCE="$DIR/$TARGET" || SOURCE="$TARGET"
done
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SOURCE")" >/dev/null 2>&1 && pwd)"

. "$SCRIPT_DIR/common.sh"

declare -A packages
packages=(
    [protoc-gen-go]="google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.6"
    [protoc-gen-go-grpc]="google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.5.1"
    [protoc-gen-validate]="github.com/envoyproxy/protoc-gen-validate@v1.2.1"
    [protoc-gen-openapi]="github.com/google/gnostic/cmd/protoc-gen-openapi@latest"
    [protoc-gen-openapiv2]="github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@latest"
    [protoc-gen-gotag]="github.com/srikrsna/protoc-gen-gotag@v1.0.2"
    [buf]="github.com/bufbuild/buf/cmd/buf@latest"
    [gum]="github.com/charmbracelet/gum@latest"
    [wire]="github.com/google/wire/cmd/wire@latest"
    [gci]="github.com/daixiang0/gci@v0.13.7"
    [golangci-lint]="github.com/golangci/golangci-lint/cmd/golangci-lint@v1.64.4"
    [golines]="github.com/segmentio/golines@v0.13.0"
)

if [[ "${OS:-}" == "Windows_NT" ]]; then
  if [[ -n "${BUILD_ROOT:-}" ]]; then
    if [[ "$BUILD_ROOT" =~ ^([A-Za-z]:\\|\\\\) ]]; then
      ROOT_WIN="$BUILD_ROOT"
    else
      ROOT_WIN="$(cygpath -aw "$BUILD_ROOT")"
    fi
  else
    ROOT_WIN="$(cygpath -aw "$(pwd -P)")"
  fi

  export GOBIN="${ROOT_WIN}\\\.build\\.bin"
  GOBIN_POSIX="$(cygpath -au "$GOBIN")"
  mkdir -p "$GOBIN_POSIX"

  export PATH="$GOBIN_POSIX:$PATH"
  EXE_EXT=".exe"
else
  ROOT_POSIX="${BUILD_ROOT:-$(pwd -P)}"
  export GOBIN="$ROOT_POSIX/.build/.bin"
  mkdir -p "$GOBIN"

  export PATH="$GOBIN:$PATH"
  EXE_EXT=""
fi

mkdir -p "$GOBIN"

check_binary() {
  local binary=$1
  if [[ -f "$GOBIN/$binary$EXE_EXT" || -f "$GOBIN/$binary" ]]; then
    return 0
  fi
  return 1       # 两个都没找到 → 缺失
}

install_package() {
    local package_path=$1
    go install "$package_path"
}

for binary in "${!packages[@]}"; do
    if ! check_binary "$binary"; then
        echo_color "⇊ $binary does not exist, installing..." yellow
        install_package "${packages[$binary]}"
    fi
done

if ! check_binary "protoc"; then

    echo_color "⇊ protoc does not exist, installing..." yellow

    OS=$(go env GOOS)
    ARCH=$(go env GOARCH)
    TMP_DIR="/tmp/protoc"
    rm -rf "$TMP_DIR"
    mkdir -p $TMP_DIR

    case "$OS" in
        linux)
            URL="https://github.com/protocolbuffers/protobuf/releases/download/v31.0/protoc-31.0-linux-x86_64.zip"
            ;;
        darwin)
            case "$ARCH" in
                amd64)
                    URL="https://github.com/protocolbuffers/protobuf/releases/download/v31.0/protoc-31.0-osx-x86_64.zip"
                    ;;
                arm64)
                    URL="https://github.com/protocolbuffers/protobuf/releases/download/v31.0/protoc-31.0-osx-aarch_64.zip"
                    ;;
                *)
                    echo "Unsupported architecture: $OS:$ARCH, Please try to manually install protoc to the .build/.bin"
                    exit 1
            esac
            ;;
        windows)
            URL="https://github.com/protocolbuffers/protobuf/releases/download/v31.0/protoc-31.0-win64.zip"
            ;;
    esac

    echo "download protoc from $URL to $TMP_DIR/protoc.zip"
    curl -L "$URL" -o "$TMP_DIR/protoc.zip"
    unzip -q "$TMP_DIR/protoc.zip" -d "$TMP_DIR"

    if [[ "$OS" == "windows" ]]; then
        mv "$TMP_DIR/bin/protoc.exe" "$GOBIN/protoc.exe"
    else
        mv "$TMP_DIR/bin/protoc"     "$GOBIN/protoc"
    fi

    rm -rf "$TMP_DIR"
fi

echo_color "✔ All checks and installations are done." green