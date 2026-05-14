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
ARG3=${3:-}
ARG4=${4:-}
MAX_PARALLEL=5

APP_RAW=""
RHOSTS=""

if [[ -z "$OS" || -z "$ARCH" ]]; then
  echo_color "Usage: $0 <os> <arch> [app] <rhost(s)>" red
  exit 1
fi

if [[ -n "$ARG4" ]]; then
  # mono-repo style: deploy_app.sh <os> <arch> <app> <hosts>
  APP_RAW="$ARG3"
  RHOSTS="$ARG4"
else
  # single-repo style: deploy_app.sh <os> <arch> <hosts>
  RHOSTS="$ARG3"
  APP_RAW="$(basename "$(pwd -P)")"
fi

APP=${APP_RAW##*/}

if [[ -z "$APP" || -z "$RHOSTS" ]]; then
  echo_color "Usage: $0 <os> <arch> [app] <rhost(s)>" red
  exit 1
fi

BUILD_DIR="target/${APP}/${OS}/${ARCH}"

REMOTE_DIR="/opt/${APP}"      # 安装目录
REMOTE_TMP="/tmp"             # SFTP 可写目录
SSH_OPT=(
  -q                           # 静默模式：抑制 motd / banner 类输出
  -o LogLevel=ERROR            # 只保留 error
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
)

SCP_OPT=(
  -o LogLevel=ERROR
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
)

trim_space(){
  local text="$1"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  printf '%s' "$text"
}

contains_wildcard(){
  local text="$1"
  [[ "$text" == *'*'* || "$text" == *'?'* || "$text" == *'['* ]]
}

expand_tilde(){
  local path="$1"
  if [[ "$path" == "~" ]]; then
    printf '%s' "$HOME"
    return
  fi
  if [[ "$path" == "~/"* ]]; then
    printf '%s/%s' "$HOME" "${path#\~/}"
    return
  fi
  printf '%s' "$path"
}

declare -a SSH_ALIASES=()
declare -A SEEN_ALIAS=()
declare -A SEEN_CFG_FILE=()
SSH_ALIAS_LOADED=false

scan_ssh_alias(){
  local cfg_file="$1"
  cfg_file=$(expand_tilde "$cfg_file")
  [[ -f "$cfg_file" ]] || return 0
  [[ -n ${SEEN_CFG_FILE["$cfg_file"]+x} ]] && return 0
  SEEN_CFG_FILE["$cfg_file"]=1

  local cfg_dir
  cfg_dir="$(cd -P -- "$(dirname -- "$cfg_file")" >/dev/null 2>&1 && pwd)"

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    local line key rest
    line="${raw_line%%#*}"
    line="$(trim_space "$line")"
    [[ -z "$line" ]] && continue

    read -r key rest <<< "$line"
    key="${key,,}"

    if [[ "$key" == "include" ]]; then
      local inc_pattern
      for inc_pattern in $rest; do
        local abs_pattern
        abs_pattern="$(expand_tilde "$inc_pattern")"
        if [[ "$abs_pattern" != /* ]]; then
          abs_pattern="${cfg_dir}/${abs_pattern}"
        fi

        local matches=()
        shopt -s nullglob
        matches=( $abs_pattern )
        shopt -u nullglob
        local inc_file
        for inc_file in "${matches[@]}"; do
          scan_ssh_alias "$inc_file"
        done
      done
      continue
    fi

    if [[ "$key" == "host" ]]; then
      local alias
      for alias in $rest; do
        [[ "$alias" == !* ]] && continue
        contains_wildcard "$alias" && continue
        [[ -n ${SEEN_ALIAS["$alias"]+x} ]] && continue
        SEEN_ALIAS["$alias"]=1
        SSH_ALIASES+=("$alias")
      done
    fi
  done < "$cfg_file"
}

load_ssh_alias(){
  [[ "$SSH_ALIAS_LOADED" == true ]] && return
  SSH_ALIAS_LOADED=true
  scan_ssh_alias "$HOME/.ssh/config"
}

declare -a HOST_ARRAY=()

resolve_hosts(){
  local raw_hosts="$1"
  local token
  local need_alias=false
  local parsed=()
  IFS=',' read -r -a parsed <<< "$raw_hosts"

  for token in "${parsed[@]}"; do
    token="$(trim_space "$token")"
    [[ -z "$token" ]] && continue
    contains_wildcard "$token" && need_alias=true
  done

  if [[ "$need_alias" == true ]]; then
    load_ssh_alias
  fi

  local -A seen_host=()
  HOST_ARRAY=()
  for token in "${parsed[@]}"; do
    token="$(trim_space "$token")"
    [[ -z "$token" ]] && continue

    if contains_wildcard "$token"; then
      local matches=()
      local alias
      for alias in "${SSH_ALIASES[@]}"; do
        [[ "$alias" == $token ]] && matches+=("$alias")
      done
      if [[ ${#matches[@]} -eq 0 ]]; then
        echo_color "[ERR] No ssh host matched pattern: ${token}" red
        exit 1
      fi

      local match_text
      match_text=$(IFS=','; printf '%s' "${matches[*]}")
      echo_color "[MATCH] ${token} => ${#matches[@]} host(s): ${match_text}" cyan

      local host
      for host in "${matches[@]}"; do
        [[ -n ${seen_host["$host"]+x} ]] && continue
        seen_host["$host"]=1
        HOST_ARRAY+=("$host")
      done
      continue
    fi

    [[ -n ${seen_host["$token"]+x} ]] && continue
    seen_host["$token"]=1
    HOST_ARRAY+=("$token")
  done

  if [[ ${#HOST_ARRAY[@]} -eq 0 ]]; then
    echo_color "[ERR] No deploy host resolved from input: ${raw_hosts}" red
    exit 1
  fi
}

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
       scp "${SCP_OPT[@]}" "$file" "${host}:${tmp_path}"
     fi

    ssh "${SSH_OPT[@]}" "$host" "$(remote_finalize_cmd "${tmp_path}" "${exe_name}" "${fn}")" >/dev/null
    uploaded=true
  done

  # 自动重启服务
  if [[ $uploaded == true && ${AUTO_RESTART:-false} == true ]]; then
    echo_color "[RST]   attempt restart ${APP} on ${host}" cyan
    ssh "${SSH_OPT[@]}" "$host" "sudo systemctl restart ${APP} >/dev/null 2>&1 || true" >/dev/null
  fi
}

run_parallel_deploy(){
  local -a active_pids=()
  local -a failed_hosts=()
  local -A pid_host_map=()
  local host pid

  reap_jobs(){
    local remaining=()
    local p h
    for p in "${active_pids[@]}"; do
      if kill -0 "$p" 2>/dev/null; then
        remaining+=("$p")
        continue
      fi

      h="${pid_host_map["$p"]:-unknown}"
      if wait "$p"; then
        echo_color "[OK]   ${h}" green
      else
        echo_color "[FAIL] ${h}" red
        failed_hosts+=("$h")
      fi
    done
    active_pids=("${remaining[@]}")
  }

  for host in "${HOST_ARRAY[@]}"; do
    while (( ${#active_pids[@]} >= MAX_PARALLEL )); do
      reap_jobs
      (( ${#active_pids[@]} < MAX_PARALLEL )) && break
      sleep 0.2
    done

    (
      echo_color "==== Deploy to ${host} ====" magenta
      deploy_single_host "$host"
    ) &
    pid=$!
    active_pids+=("$pid")
    pid_host_map["$pid"]="$host"
  done

  while (( ${#active_pids[@]} > 0 )); do
    reap_jobs
    (( ${#active_pids[@]} == 0 )) && break
    sleep 0.2
  done

  if (( ${#failed_hosts[@]} > 0 )); then
    echo_color "**** Deploy completed with failures (${#failed_hosts[@]}) ****" red
    printf '%s\n' "${failed_hosts[@]}"
    return 1
  fi
  return 0
}

safe_name(){
  local text="$1"
  text="${text//[^a-zA-Z0-9._-]/_}"
  printf '%s' "$text"
}

yaml_quote(){
  local text="$1"
  text="${text//\'/\'\'}"
  printf "'%s'" "$text"
}

declare -a UPLOAD_HOSTS=()
declare -a UPLOAD_FNS=()
declare -a UPLOAD_EXE_NAMES=()
declare -a UPLOAD_TMP_PATHS=()
declare -a UPLOAD_STATUS_FILES=()
declare -a UPLOAD_TASK_SCRIPTS=()
declare -a UPLOAD_TASK_NAMES=()
declare -A HOST_UPLOAD_COUNT=()

LOG_ROOT="/tmp/deploy_${APP}_$(date +%Y%m%d%H%M%S)_$$"
STATUS_DIR="${LOG_ROOT}/status"
TASK_DIR="${LOG_ROOT}/tasks"
mkdir -p "$STATUS_DIR" "$TASK_DIR"

queue_upload_task(){
  local host="$1"
  local file="$2"
  local fn="$3"
  local exe_name="$4"
  local tmp_path="$5"
  local idx sid_host sid_fn status_file task_script task_name
  local scp_line status_q

  idx=${#UPLOAD_HOSTS[@]}
  sid_host="$(safe_name "$host")"
  sid_fn="$(safe_name "$fn")"
  status_file="${STATUS_DIR}/${idx}_${sid_host}_${sid_fn}.status"
  task_script="${TASK_DIR}/${idx}_${sid_host}_${sid_fn}.sh"
  task_name="${host}:${fn}"

  printf -v scp_line '%q ' scp "${SCP_OPT[@]}" "$file" "${host}:${tmp_path}"
  scp_line="${scp_line% }"
  printf -v status_q '%q' "$status_file"
  cat > "$task_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
set +e
${scp_line}
rc=\$?
set -e
echo "\$rc" > ${status_q}
exit "\$rc"
EOF
  chmod +x "$task_script"

  UPLOAD_HOSTS+=("$host")
  UPLOAD_FNS+=("$fn")
  UPLOAD_EXE_NAMES+=("$exe_name")
  UPLOAD_TMP_PATHS+=("$tmp_path")
  UPLOAD_STATUS_FILES+=("$status_file")
  UPLOAD_TASK_SCRIPTS+=("$task_script")
  UPLOAD_TASK_NAMES+=("$task_name")
  HOST_UPLOAD_COUNT["$host"]=$(( ${HOST_UPLOAD_COUNT["$host"]:-0} + 1 ))
}

plan_upload_tasks(){
  local deploy_ts host file fn hs exe_name tmp_path exists check_rc
  deploy_ts=$(date +%Y%m%d%H%M)
  for host in "${HOST_ARRAY[@]}"; do
    for file in "$BUILD_DIR"/*; do
      [[ -f $file ]] || continue
      fn=$(basename "$file")
      hs=$(short_hash "$file")
      exe_name="${fn}.bk.${deploy_ts}_${hs}"
      tmp_path="${REMOTE_TMP}/${exe_name}"

      set +e
      exists=$(ssh "${SSH_OPT[@]}" "$host" "if [ -f ${REMOTE_DIR}/${exe_name} ]; then echo yes; else echo no; fi")
      check_rc=$?
      set -e
      if (( check_rc == 0 )) && [[ "$exists" == "yes" ]]; then
        echo_color "[EXIST] ${exe_name} already on ${host}, skip upload" yellow
        continue
      fi
      if (( check_rc != 0 )); then
        echo_color "[WARN] pre-check failed on ${host}, will still queue upload task" yellow
      fi

      echo_color "[QUEUE] ${host}:${fn} -> ${tmp_path}" cyan
      queue_upload_task "$host" "$file" "$fn" "$exe_name" "$tmp_path"
    done
  done
}

write_mprocs_config(){
  local cfg="$1"
  local start_idx="$2"
  local end_idx="$3"
  local idx task_name task_script
  {
    echo "hide_keymap_window: true"
    echo "procs:"
    for (( idx=start_idx; idx<=end_idx; idx++ )); do
      task_name="${UPLOAD_TASK_NAMES[$idx]}"
      task_script="${UPLOAD_TASK_SCRIPTS[$idx]}"
      printf "  %s:\n" "$(yaml_quote "$task_name")"
      echo "    cmd:"
      printf "      - %s\n" "$(yaml_quote "bash")"
      printf "      - %s\n" "$(yaml_quote "$task_script")"
    done
  } > "$cfg"
}

run_uploads_with_mprocs(){
  local total start_idx end_idx batch_no cfg
  total=${#UPLOAD_STATUS_FILES[@]}
  start_idx=0
  batch_no=1
  while (( start_idx < total )); do
    end_idx=$(( start_idx + MAX_PARALLEL - 1 ))
    (( end_idx >= total )) && end_idx=$(( total - 1 ))
    cfg="${LOG_ROOT}/mprocs_batch_${batch_no}.yaml"
    write_mprocs_config "$cfg" "$start_idx" "$end_idx"
    "$MPROCS_BIN" --config "$cfg" --on-all-finished '{c: quit}' || true
    start_idx=$(( end_idx + 1 ))
    batch_no=$(( batch_no + 1 ))
  done
}

collect_failed_hosts(){
  local idx host status_file rc
  local -A failed_set=()
  for idx in "${!UPLOAD_STATUS_FILES[@]}"; do
    host="${UPLOAD_HOSTS[$idx]}"
    status_file="${UPLOAD_STATUS_FILES[$idx]}"
    rc=99
    [[ -f "$status_file" ]] && rc=$(tr -d '[:space:]' < "$status_file")
    [[ -z "$rc" ]] && rc=99
    [[ "$rc" != "0" ]] && failed_set["$host"]=1
  done
  for host in "${HOST_ARRAY[@]}"; do
    if [[ -n ${failed_set["$host"]+x} ]]; then
      echo_color "[FAIL] ${host}" red
      return 1
    fi
  done
  return 0
}

finalize_uploaded_hosts_serial(){
  local host idx uploaded
  for host in "${HOST_ARRAY[@]}"; do
    (( ${HOST_UPLOAD_COUNT["$host"]:-0} == 0 )) && continue
    echo_color "==== Finalize ${host} ====" magenta
    uploaded=false
    for idx in "${!UPLOAD_HOSTS[@]}"; do
      [[ "${UPLOAD_HOSTS[$idx]}" == "$host" ]] || continue
      ssh "${SSH_OPT[@]}" "$host" "$(remote_finalize_cmd "${UPLOAD_TMP_PATHS[$idx]}" "${UPLOAD_EXE_NAMES[$idx]}" "${UPLOAD_FNS[$idx]}")" >/dev/null
      uploaded=true
    done
    if [[ "$uploaded" == true && ${AUTO_RESTART:-false} == true ]]; then
      echo_color "[RST]   attempt restart ${APP} on ${host}" cyan
      ssh "${SSH_OPT[@]}" "$host" "sudo systemctl restart ${APP} >/dev/null 2>&1 || true" >/dev/null
    fi
  done
}

run_mprocs_deploy(){
  plan_upload_tasks
  if (( ${#UPLOAD_HOSTS[@]} == 0 )); then
    echo_color "No files need upload, skip finalize and restart." yellow
    return 0
  fi
  run_uploads_with_mprocs
  collect_failed_hosts || return 1
  finalize_uploaded_hosts_serial
}

resolve_hosts "$RHOSTS"
echo_color "==== Final deploy targets ====" magenta
printf '%s\n' "${HOST_ARRAY[@]}"
[[ ! -d $BUILD_DIR ]] && { echo_color "Build dir not found: $BUILD_DIR" red; exit 1; }

MPROCS_BIN="${GOBIN}/mprocs${EXE_EXT:-}"
if [[ ! -x "$MPROCS_BIN" ]] && command -v mprocs >/dev/null 2>&1; then
  MPROCS_BIN="$(command -v mprocs)"
fi

if [[ -t 1 && ${#HOST_ARRAY[@]} -gt 1 && -x "$MPROCS_BIN" ]]; then
  echo_color "==== Upload mode: mprocs ====" magenta
  run_mprocs_deploy
else
  if [[ -t 1 && ${#HOST_ARRAY[@]} -gt 1 && ! -x "$MPROCS_BIN" ]]; then
    echo_color "[WARN] mprocs not found, fallback to non-TUI parallel deploy" yellow
  fi
  run_parallel_deploy
fi

echo_color "**** All done ****" green
