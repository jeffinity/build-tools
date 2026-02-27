#!/usr/bin/env bash
set -euo pipefail

# --------- resolve script dir (follows symlinks) ----------
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P -- "$(dirname -- "$SOURCE")" >/dev/null 2>&1 && pwd)"
  TARGET="$(readlink -- "$SOURCE")"
  [[ "$TARGET" != /* ]] && SOURCE="$DIR/$TARGET" || SOURCE="$TARGET"
done
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SOURCE")" >/dev/null 2>&1 && pwd)"

. "$SCRIPT_DIR/gum_helper.sh"

# --------- config (overridable by env) ----------
REPO_URL="${APP_LAYOUT_REPO_URL:-https://github.com/jeffinity/app-layout.git}"
REPO_BRANCH="${APP_LAYOUT_BRANCH:-main}"
TMP_CLONE_DIR="/tmp/app-layout"
SRC_SUBPATH="app/app_layout"
TEMPLATE_MODULE="github.com/jeffinity/app-layout"

# --------- usage & args ----------
usage() {
  echo_color "Usage: task newapp -- <new-module-path> <your-app-name> [other args...]" red
  echo_color "Example: task newapp -- github.com/jeffinity/app-layout foo-api" red
}

# need: module path + app name
if [ $# -lt 2 ]; then
  usage
  exit 1
fi

NEW_MODULE_PATH="$1"; shift   # 新的包名（模块路径）
CLI_ARGS="$*"                 # 其余参数整体右移一位（保持原有功能）
name="${1:-}"                 # your-app-name 现在位于新的 $1
if [[ -z "$name" ]]; then
  usage
  exit 1
fi

# 不允许 app 名里有空格
if [[ "${name}" =~ [[:space:]] ]]; then
  usage
  exit 1
fi

echo_color "Creating new application: ${name}" cyan

# --------- pre checks ----------
if [ -d "app/${name}" ]; then
  echo_color "Directory ${name} exists in app/ & please reconfirm this name" red
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo_color "Error: git is required but not installed" red
  exit 1
fi

mkdir -p app

# --------- fetch template to /tmp ----------
echo_color "Fetching template from ${REPO_URL}@${REPO_BRANCH} ..." cyan
rm -rf "${TMP_CLONE_DIR}"
git -c advice.detachedHead=false clone --depth=1 --branch "${REPO_BRANCH}" \
  "${REPO_URL}" "${TMP_CLONE_DIR}" >/dev/null 2>&1 || {
  echo_color "Error: git clone failed from ${REPO_URL}@${REPO_BRANCH}" red
  exit 1
}

SRC_DIR="${TMP_CLONE_DIR}/${SRC_SUBPATH}"
if [ ! -d "${SRC_DIR}" ]; then
  echo_color "Error: template path '${SRC_DIR}' not found in repo" red
  exit 1
fi

# --------- copy template ----------
cp -a "${SRC_DIR}" "app/${name}"

# --------- do replacements ----------
safe_name="${name//-/_}"

# 1) *.proto: app_layout -> safe_name （go_package 等需要下划线）
find "app/${name}" -type f -name '*.proto' -exec sed -i.bak "s/app_layout/${safe_name}/g" {} +

# 2) 所有文件：app_layout -> name（文件夹/包名等）
find "app/${name}" -type f -exec sed -i.bak "s/app_layout/${name}/g" {} +

# 3) 仅在 *.go 中：模板模块路径 -> 新模块路径
#    使用可移植的转义，兼容 GNU/BSD sed
_sed_esc() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'; }
OLD_ESC="$(_sed_esc "${TEMPLATE_MODULE}")"
NEW_ESC="$(_sed_esc "${NEW_MODULE_PATH}")"

# 遍历 *.go 文件替换 import 前缀
while IFS= read -r -d '' f; do
  sed -i.bak "s|${OLD_ESC}|${NEW_ESC}|g" "$f"
done < <(find "app/${name}" -type f -name '*.go' -print0)

# 4) 清理备份
find "app/${name}" -type f -name '*.bak' -delete

# 可选：保留 /tmp 模板以便排查，默认清理
rm -rf "${TMP_CLONE_DIR}"

# --------- generate conf & wire ----------
task conf -- "app/${name}"
task wire -- "app/${name}"

echo_color "New application '${name}' created successfully & enjoy it!" green
