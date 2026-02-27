#!/usr/bin/env bash

set -euo pipefail

if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
  if command -v tput >/dev/null 2>&1; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    RESET="$(tput sgr0)"
  else
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RESET=$'\033[0m'
  fi
else
  RED=; GREEN=; YELLOW=; RESET=
fi

echo_color() {
  local text=$1 color_name=$2 color_code=
  case "$color_name" in
    red)    color_code=$RED   ;;
    green)  color_code=$GREEN ;;
    yellow) color_code=$YELLOW;;
    *)      color_code=       ;;
  esac
  printf "%b%s%b\n" "$color_code" "$text" "$RESET"
}

# 用法
# echo_color "✔ 操作成功" green
# echo_color "⚠ 请确认输入" yellow
# echo_color "✖ 操作失败" red
