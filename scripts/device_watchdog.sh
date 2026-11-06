#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
#  adbmcp 守护 (Termux Native MCP + ADB 设备连接维护)
#
#  职责:
#    1. 保持 termux-native-mcp (HTTP :8081) 存活
#    2. 保持与设备清单的 adb 连接存活 (掉线自动重连)
#    3. 周期性记录健康状态
#
#  用法:
#    bash ~/device_watchdog.sh start    启动守护 (后台)
#    bash ~/device_watchdog.sh stop     停止
#    bash ~/device_watchdog.sh status   查看状态
#    bash ~/device_watchdog.sh run      前台运行 (调试)
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

BASE_DIR="$HOME/mcp-servers/adbmcp"
PID_FILE="$BASE_DIR/watchdog.pid"
LOG_FILE="$BASE_DIR/watchdog.log"
MCP_PORT="${MCP_PORT:-8081}"
MCP_HOST="${MCP_HOST:-127.0.0.1}"
CHECK_INTERVAL="${CHECK_INTERVAL:-20}"

# 设备列表: 每行 "IP:PORT  标签"  (标签可留空, 仅作备注)
DEVICES_FILE="$BASE_DIR/devices.txt"

mkdir -p "$BASE_DIR"

cyan()  { echo -e "\033[0;36m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
red()   { echo -e "\033[0;31m$*\033[0m"; }
warn()  { echo -e "\033[1;33m$*\033[0m"; }

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
  # 日志超过 1MB 轮转
  if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt 1048576 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
  fi
}

# ── MCP 存活检测 ───────────────────────────────────────────
mcp_alive() {
  # 端口探测最可靠
  if timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$MCP_PORT" 2>/dev/null; then
    return 0
  fi
  # pgrep 兜底
  pgrep -f "termux-native-mcp" >/dev/null 2>&1 && return 0
  return 1
}

# ── 启动 MCP ───────────────────────────────────────────────
start_mcp() {
  if mcp_alive; then
    return 0
  fi
  log "MCP 未运行，拉起..."
  # 先清理可能残留的端口占用
  pkill -f "termux-native-mcp" 2>/dev/null
  sleep 1
  nohup termux-native-mcp --port "$MCP_PORT" --host "$MCP_HOST" \
    >> "$BASE_DIR/mcp.log" 2>&1 &
  echo $! > "$BASE_DIR/mcp.pid"
  # 等待端口就绪
  for i in $(seq 1 15); do
    sleep 1
    if mcp_alive; then
      log "MCP 已就绪 (pid $(cat "$BASE_DIR/mcp.pid" 2>/dev/null), ${i}s)"
      return 0
    fi
  done
  log "✗ MCP 启动超时，详见 $BASE_DIR/mcp.log"
  return 1
}

# ── 设备连接维护 ───────────────────────────────────────────
read_targets() {
  [[ -f "$DEVICES_FILE" ]] || return 0
  # 去掉注释与空行
  grep -v '^\s*#' "$DEVICES_FILE" 2>/dev/null | grep -v '^\s*$'
}

reconnect_devices() {
  if ! command -v adb >/dev/null 2>&1; then
    log "adb 未安装，跳过设备连接"
    return 0
  fi

  local connected_any=0
  local target state

  while read -r target _rest; do
    [[ -z "$target" ]] && continue
    state=$(adb devices 2>/dev/null | awk -v t="$target" '$1==t{print $2; exit}')
    if [[ "$state" == "device" ]]; then
      continue
    fi
    # 掉线或未连接 → 重连
    log "重连设备 $target (当前状态: ${state:-none})"
    adb connect "$target" >> "$LOG_FILE" 2>&1
    sleep 1
    state=$(adb devices 2>/dev/null | awk -v t="$target" '$1==t{print $2; exit}')
    if [[ "$state" == "device" ]]; then
      log "✓ 设备 $target 已连接"
      connected_any=1
    else
      log "✗ 设备 $target 连接失败 (状态: ${state:-none})"
    fi
  done < <(read_targets)
}

# ── 状态输出 ───────────────────────────────────────────────
show_status() {
  echo
  cyan "══ adbmcp 守护状态 ══"
  echo

  if mcp_alive; then
    local mpid
    mpid=$(pgrep -f "termux-native-mcp" | head -1)
    green "  ✓ MCP 运行中  pid=$mpid  监听 127.0.0.1:$MCP_PORT"
  else
    red "  ✗ MCP 未运行"
  fi

  local wpid=""
  [[ -f "$PID_FILE" ]] && wpid=$(cat "$PID_FILE" 2>/dev/null)
  if [[ -n "$wpid" ]] && kill -0 "$wpid" 2>/dev/null; then
    green "  ✓ watchdog 运行中  pid=$wpid"
  else
    red "  ✗ watchdog 未运行"
  fi

  echo
  cyan "  ── adb 设备 ──"
  if command -v adb >/dev/null 2>&1; then
    adb devices 2>/dev/null | sed 's/^/    /'
  else
    echo "    adb 未安装"
  fi

  echo
  cyan "  ── 已配置设备 ──"
  if [[ -s "$DEVICES_FILE" ]]; then
    read_targets | while read -r t rest; do
      [[ -z "$t" ]] && continue
      st=$(adb devices 2>/dev/null | awk -v x="$t" '$1==x{print $2; exit}')
      if [[ "$st" == "device" ]]; then
        green "    ✓ $t  ${rest}"
      else
        warn "    ✗ $t  ${rest}  (${st:-未连接})"
      fi
    done
  else
    echo "    (无配置，编辑 $DEVICES_FILE 每行一个 IP:PORT)"
  fi
  echo
}

# ── 主循环 ─────────────────────────────────────────────────
run_loop() {
  echo $$ > "$PID_FILE"
  log "watchdog 启动 (pid $$, interval ${CHECK_INTERVAL}s)"
  trap 'log "watchdog 退出"; rm -f "$PID_FILE"; exit 0' TERM INT

  while true; do
    start_mcp
    reconnect_devices
    sleep "$CHECK_INTERVAL"
  done
}

# ── 入口 ───────────────────────────────────────────────────
case "${1:-start}" in
  start)
    if [[ -f "$PID_FILE" ]]; then
      oldpid=$(cat "$PID_FILE" 2>/dev/null)
      if kill -0 "$oldpid" 2>/dev/null; then
        warn "watchdog 已在运行 (pid $oldpid)"
        exit 0
      fi
    fi
    nohup bash "$0" run >> "$LOG_FILE" 2>&1 &
    sleep 2
    show_status
    ;;
  stop)
    if [[ -f "$PID_FILE" ]]; then
      pid=$(cat "$PID_FILE" 2>/dev/null)
      kill "$pid" 2>/dev/null && green "✓ watchdog 已停止 (pid $pid)" || warn "watchdog 未在运行"
      rm -f "$PID_FILE"
    else
      warn "无 PID 文件"
    fi
    ;;
  restart)
    bash "$0" stop; sleep 1; bash "$0" start
    ;;
  status)
    show_status
    ;;
  run)
    run_loop
    ;;
  *)
    echo "用法: bash $0 {start|stop|restart|status|run}"
    exit 1
    ;;
esac
