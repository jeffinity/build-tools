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

echo 'Args:' "$@"

CHECKSUM_FILE='.build_checksum'
root_dir=$(pwd)

# Build metadata
BUILD_TIME=$(date '+%F %T')
GIT_COMMIT=$(git rev-parse --short HEAD)
MODULE_PATH=$(go list -m | head -n 1)
BUILD_USER=$(id -un)
GO_VERSION=$(go version | awk '{print $3}')

# CLI args
os=$1
arch=$2
version=$3
selected=$4
opts=("${@:5}")

if [ -z "$version" ]; then
  version=$(git describe --abbrev=0 --tags 2>/dev/null || echo "v0.0.1")
fi

# Common ldflags, injecting into pkg/buildinfo
LDFLAGS="-s -w \
  -X 'github.com/jeffinity/singularity/buildinfo.BuildTime=${BUILD_TIME}' \
  -X 'github.com/jeffinity/singularity/buildinfo.CommitID=${GIT_COMMIT}' \
  -X 'github.com/jeffinity/singularity/buildinfo.Version=${version}' \
  -X 'github.com/jeffinity/singularity/buildinfo.BuildOS=${os}' \
  -X 'github.com/jeffinity/singularity/buildinfo.BuildUser=${BUILD_USER}' \
  -X 'github.com/jeffinity/singularity/buildinfo.GoVersion=${GO_VERSION}' \
  -X 'github.com/jeffinity/singularity/buildinfo.GoArch=${arch}'"


checksum_cmd() {
  if command -v md5sum >/dev/null 2>&1; then
    echo "md5sum"
  elif command -v md5 >/dev/null 2>&1; then
    echo "md5"
  else
    echo "No suitable checksum command found" >&2
    exit 1
  fi
}

calculate_checksum() {
  local dir=$1
  local sum_cmd=$(checksum_cmd)

  find "$dir" -name "*.go" -exec $sum_cmd {} \; | $sum_cmd | cut -d ' ' -f 1
}

should_build() {
  local app_dir=$1
  local pkg_dir=$root_dir/pkg
  local checksum_file="${app_dir}/${CHECKSUM_FILE}"
  local sum_cmd=$(checksum_cmd)

  # 计算当前校验和
  local current_checksum=$(calculate_checksum "$app_dir")
  current_checksum+=$(calculate_checksum "$pkg_dir")

  if [ -f "$root_dir/go.mod" ]; then
    current_checksum+=$($sum_cmd "$root_dir/go.mod" | cut -d ' ' -f 1)
  fi

  if [ -f "$root_dir/go.work" ]; then
    current_checksum+=$($sum_cmd "$root_dir/go.work" | cut -d ' ' -f 1)
  fi

  local final_checksum=$(echo "$current_checksum" | $sum_cmd | cut -d ' ' -f 1)

  # 读取上次的校验和
  local last_checksum=$(cat "$checksum_file" 2>/dev/null || echo "")

  # 返回上次和当前的校验和
  echo "$final_checksum $last_checksum"
}

build_app() {
  local app=$1
  local app_name=$(basename "$app")
  local out_dir=$root_dir/target/"$app_name"/"$os"/"$arch"
  local ext=""
  [[ "$os" == "windows" ]] && ext=".exe"

  local out_file="$out_dir/$app_name$ext"

  echo_color "Building $app → $out_dir" yellow

  [[ -d "$app/cmd" ]] || {
    echo_color "Error: nothing to build in $app" red
    exit 1
  }

  mkdir -p "$out_dir"
  pushd "$app/cmd" >/dev/null

  local build_cmd="GOOS=${os} CGO_ENABLED=0 GOARCH=${arch} go build -buildvcs=false -ldflags \"${LDFLAGS}\" -o ${out_file}"
  echo_color "Command: $build_cmd" grey

  spin_exec "Building ${app_name}..." GOOS=${os} CGO_ENABLED=0 GOARCH=${arch} go build -buildvcs=false -ldflags "${LDFLAGS}" -o ${out_file}

  popd >/dev/null

  echo_color "✔ Build ${app_name} complete:" green
  ls -lh "$out_dir"
  echo_color "---------" green
}

checksum_build() {
  local app=$1
  local out_dir=$root_dir/target/$(basename "$app")/$os
  read -r current last <<< "$(should_build "$app")"

  if [[ ! -d $out_dir || -z $(ls -A "$out_dir") || $current != "$last" ]]; then
    build_app "$app"
    echo "$current" > "$app/$CHECKSUM_FILE"
  else
    echo_color "Skipping $app, no changes detected (use -f to force)" yellow
  fi
}

# Dispatch: build one or all
if [[ "$selected" == "all" ]]; then
  for dir in app/*; do
    [[ -d $dir ]] || continue
    if [[ " ${opts[*]} " == *" -f "* ]]; then
      echo_color "Force build mode" yellow
      build_app "$dir"
    else
      checksum_build "$dir"
    fi
  done
else
  if [[ " ${opts[*]} " == *" -f "* ]]; then
    echo_color "Force build mode" yellow
    build_app "$selected"
  else
    checksum_build "$selected"
  fi
fi
