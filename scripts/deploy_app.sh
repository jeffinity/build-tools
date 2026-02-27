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

OS=${1:-}; ARCH=${2:-}; APP_RAW=${3:-}; RHOSTS=${4:-};
APP=${APP_RAW##*/}

if [[ -z $APP || -z $OS || -z $ARCH || -z $RHOSTS ]]; then
  echo_color "Usage: $0 <os> <arch> <app> <rhost(s)>" red
  exit 1
fi

IFS=',' read -r -a HOST_ARRAY <<< "$RHOSTS"
BUILD_DIR="target/${APP}/${OS}/${ARCH}"
[[ ! -d $BUILD_DIR ]] && { echo_color "Build dir not found: $BUILD_DIR" red; exit 1; }

REMOTE_DIR="/opt/${APP}"      # 安装目录
REMOTE_TMP="/tmp"             # SFTP 可写目录
SSH_OPT=(
  -q                           # 静默模式：抑制 motd / banner 类输出
  -o LogLevel=ERROR            # 只保留 error
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
)

short_hash(){                 # 取 8 位文件 hash
  if command -v md5sum &>/dev/null; then
    md5sum "$1" | cut -c1-8
  elif command -v md5 &>/dev/null; then
    md5 "$1"  | awk '{print $4}' | cut -c1-8
  else
    sha256sum "$1" | cut -c1-8
  fi
}

remote_finalize_cmd(){        # 返回资产机执行的 shell
  local tmp_path="$1" exe="$2" fn="$3"
  cat <<EOF
set -e
sudo install -d -m 755 ${REMOTE_DIR}
if [[ ! -f ${REMOTE_DIR}/${exe} ]]; then
  sudo mv ${tmp_path} ${REMOTE_DIR}/${exe}
fi
sudo chmod +x ${REMOTE_DIR}/${exe}
sudo ln -f -s ${REMOTE_DIR}/${exe} ${REMOTE_DIR}/${fn}
find ${REMOTE_DIR} -type f -name '${fn}.bk.*' | sort | head -n -10 | xargs --no-run-if-empty sudo rm -f
EOF
}

deploy_single_host(){
  local host="$1"
  local ds=$(date +%Y%m%d%H%M)

  local uploaded=false

  for file in "$BUILD_DIR"/*; do
    [[ -f $file ]] || continue
    local fn=$(basename "$file")
    local hs=$(short_hash "$file")
    local exe_name="${fn}.bk.${ds}_${hs}"
    local tmp_path="${REMOTE_TMP}/${exe_name}"
    local match_name="${fn}.bk.*_${hs}"

    exists=$(ssh "${SSH_OPT[@]}" "$host" \
      "if [ -f ${REMOTE_DIR}/${exe_name} ]; then echo yes; else echo no; fi")
    if [[ "$exists" == "yes" ]]; then
      echo_color "[EXIST] ${exe_name} already on ${host}, skip upload" yellow
      continue
    fi

    echo_color "[PUT]   $file → ${host}:${tmp_path}" green
     # ---- 上传方式选择 ----
     if [[ "$host" == op* || "$host" == *-jump ]]; then
       sftp -q -b - "$host" <<EOF
put $file ${exe_name}
quit
EOF
     else
       echo scp "${SSH_OPT[@]}" "$file" "${host}:${tmp_path}"
       scp "${SSH_OPT[@]}" "$file" "${host}:${tmp_path}"
     fi

    ssh "${SSH_OPT[@]}" "$host" "$(remote_finalize_cmd "${tmp_path}" "${exe_name}" "${fn}")" >/dev/null
    uploaded=true
  done

  # 自动重启服务
  if [[ $uploaded == true && ${AUTO_RESTART:-false} == true ]]; then
    echo_color "[RST]   attempt restart ${APP} on ${host}" cyan
    ssh "${SSH_OPT[@]}" "$host" "sudo systemctl restart ${APP} || true" >/dev/null
  fi
}

for host in "${HOST_ARRAY[@]}"; do
  echo_color "==== Deploy to ${host} ====" magenta
  deploy_single_host "$host"
done
echo_color "**** All done ****" green
