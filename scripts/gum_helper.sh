#!/usr/bin/env bash

set -eu

ROOT_INPUT="${BUILD_ROOT:-}"
if [[ -z "$ROOT_INPUT" ]]; then
  ROOT_INPUT="$(pwd -P)"
fi

if [[ "${OS:-}" == "Windows_NT" ]]; then
  if [[ "$ROOT_INPUT" =~ ^([A-Za-z]:\\|\\\\) ]]; then
    ROOT_WIN="$ROOT_INPUT"
  else
    ROOT_WIN="$(cygpath -aw "$ROOT_INPUT")"
  fi

  GOBIN="${ROOT_WIN}\\\.build\\.bin"
  GOBIN_POSIX="$(cygpath -au "$GOBIN")"
  mkdir -p "$GOBIN_POSIX"

  PATH="$GOBIN_POSIX:$PATH"
  EXE_EXT=".exe"
  export GOBIN PATH EXE_EXT
else
  GOBIN="$ROOT_INPUT/.build/.bin"
  mkdir -p "$GOBIN"

  PATH="$GOBIN:$PATH"
  EXE_EXT=""
  export GOBIN PATH EXE_EXT
fi

spin_exec() {
  local title="$1"; shift

  local full_cmd
  printf -v full_cmd '%q ' "$@"

  gum spin --spinner dot --title "$title" \
           --show-stderr --show-error -- \
           bash -c "$full_cmd"
}

# 如果输出到终端并且 TERM 不是 dumb，就使用 gum 进行彩色渲染
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
  USE_GUM=true
else
  USE_GUM=false
fi

echo_color() {
  local text="$1"
  local color_name="${2:-white}"
  local gum_args=()

  # 根据 color_name 选择对应的 ANSI 颜色代码（gum style 接收数字或 16 进制）
  case "$color_name" in
    red)     gum_args=(--foreground 1)   ;;
    green)   gum_args=(--foreground 2)   ;;
    yellow)  gum_args=(--foreground 3)   ;;
    blue)    gum_args=(--foreground 4)   ;;
    magenta) gum_args=(--foreground 5)   ;;
    cyan)    gum_args=(--foreground 6)   ;;
    white)   gum_args=(--foreground 250)   ;;
    grey)    gum_args=(--foreground 7)   ;;
    bold)    gum_args=(--bold)           ;;
    italic)  gum_args=(--italic)         ;;
    *)       gum_args=(--foreground 7)   ;;
  esac

  if [ "$USE_GUM" = true ]; then
    gum style "${gum_args[@]}" -- "$text"
  else
    printf "%s\n" "$text"
  fi
}

# 示例用法
# echo_color "✔ 操作成功" green
# echo_color "⚠ 请确认输入" yellow
# echo_color "✖ 操作失败" red