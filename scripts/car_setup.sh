#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
#  车机接入脚本 (在手机 Termux 内执行)
#
#  作用：让手机上的 MCP 服务通过 adb 操作车机
#  链路：AI 客户端 →(adb forward)→ 手机 Termux MCP →(adb connect)→ 车机
#
#  用法：
#    bash ~/car_setup.sh              # 交互式，提示输入车机 IP
#    bash ~/car_setup.sh 192.168.43.1 # 直接指定车机 IP
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

CAR_IP="${1:-}"
ADB_PORT="${CAR_PORT:-5555}"
TARGET="${CAR_IP}:${ADB_PORT}"

cyan()  { echo -e "\033[0;36m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
red()   { echo -e "\033[0;31m$*\033[0m"; }
warn()  { echo -e "\033[1;33m$*\033[0m"; }

banner() {
  echo
  cyan "╔══════════════════════════════════════════╗"
  cyan "║   车机接入 · Termux MCP → ADB → 车机     ║"
  cyan "╚══════════════════════════════════════════╝"
  echo
}

# ── 1. 环境自检 ────────────────────────────────────────────
check_env() {
  banner
  cyan "[1/4] 环境自检"
  echo

  if command -v adb >/dev/null 2>&1; then
    green "  ✓ adb 已安装: $(adb version 2>/dev/null | head -1)"
  else
    red "  ✗ 未找到 adb"
    echo "    安装命令: pkg install android-tools"
    exit 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    green "  ✓ python3: $(python3 -V 2>&1)"
  else
    warn "  ! 未找到 python3 (MCP 服务可能无法启动)"
  fi

  # 检查 MCP 服务
  if pgrep -f "termux-native-mcp" >/dev/null 2>&1; then
    green "  ✓ termux-native-mcp 正在运行"
  else
    warn "  ! termux-native-mcp 未运行"
    echo "    启动命令: nohup termux-native-mcp --port 8081 --host 127.0.0.1 &"
    echo "    (或执行: bash ~/termux-mcp/start.sh start)"
  fi
  echo
}

# ── 2. 车机 IP ─────────────────────────────────────────────
ask_ip() {
  if [ -z "$CAR_IP" ]; then
    warn "[2/4] 车机 IP 未提供"
    echo
    echo "  请在车机「设置 → 关于 → 网络」查看 IP，或用下面的方法探测："
    echo "    • 车机开启无线调试后，端口号在开发者选项里"
    echo "    • 常见车机网关: 192.168.43.1 / 192.168.31.1 / 192.168.10.1"
    echo
    printf "  请输入车机 IP (如 192.168.43.1): "
    read -r CAR_IP
    if [ -z "$CAR_IP" ]; then
      red "  ✗ 未输入 IP，退出"
      exit 1
    fi
  fi
  TARGET="${CAR_IP}:${ADB_PORT}"
  cyan "[2/4] 目标车机: $TARGET"
  echo
}

# ── 3. 连接车机 ────────────────────────────────────────────
connect_car() {
  cyan "[3/4] 连接车机"
  echo

  # 清理旧连接
  adb disconnect "$TARGET" >/dev/null 2>&1

  echo "  正在执行: adb connect $TARGET"
  OUT=$(adb connect "$TARGET" 2>&1)
  echo "  $OUT"

  sleep 2

  # 验证
  if adb devices | grep -q "^${TARGET}.*device"; then
    green "  ✓ 连接成功，状态: device"
  elif adb devices | grep -q "^${TARGET}.*offline"; then
    red "  ✗ 状态 offline —— 车机接受了连接但未授权"
    echo "    车机屏幕上应弹出「允许 USB 调试」授权框，请确认勾选「始终允许」"
    exit 1
  else
    red "  ✗ 连接失败"
    echo "    排查:"
    echo "      1) 车机是否开启「开发者选项 → USB 调试 / 无线调试」"
    echo "      2) 车机 IP 是否正确: $CAR_IP"
    echo "      3) 端口是否为 $ADB_PORT (部分车机用随机端口)"
    echo "      4) 手机与车机是否在同一热点网络"
    exit 1
  fi
  echo

  # 读取车机信息
  green "  车机信息:"
  adb -s "$TARGET" shell "getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk; wm size" 2>&1 \
    | sed 's/^/    /'
  echo
}

# ── 4. 输出接入指引 ────────────────────────────────────────
show_guide() {
  cyan "[4/4] 完成 —— 接入方式"
  echo
  echo "  【方案 A】手机与 AI 客户端在同一网络 (推荐, 直连)"
  echo "    在 AI 客户端 (Claude Desktop / WorkBuddy 等) 配置:"
  echo
  echo "    {"
  echo "      \"mcpServers\": {"
  echo "        \"car-android\": {"
  echo "          \"type\": \"streamableHttp\","
  echo "          \"url\": \"http://${CAR_IP}:8081/mcp\""
  echo "        }"
  echo "      }"
  echo "    }"
  echo
  echo "  注意: MCP 服务默认只监听 127.0.0.1，需改为 0.0.0.0 才能直连。"
  echo "        重启命令:"
  echo "          pkill -f termux-native-mcp"
  echo "          nohup termux-native-mcp --port 8081 --host 0.0.0.0 &"
  echo
  echo "  【方案 B】通过 USB/TCP 转发 (跨网络, 最稳)"
  echo "    在 AI 客户端所在的电脑上执行:"
  echo "      adb -s ${PHONE_IP:-<手机IP>}:5555 forward tcp:8081 tcp:8081"
  echo "    然后 MCP 地址填: http://127.0.0.1:8081/mcp"
  echo
  green "  ✓ 至此手机侧已就绪。AI 客户端连上后即可通过 MCP 操作车机。"
  echo
}

main() {
  check_env
  ask_ip
  connect_car
  show_guide
}

main
