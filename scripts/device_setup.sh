#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
#  设备接入脚本 (在手机 Termux 内执行)
#
#  作用：让手机上的 MCP 服务通过 adb 操作目标设备
#  链路：AI 客户端 →(adb forward)→ 手机 Termux MCP →(adb connect)→ 目标设备
#
#  用法：
#    bash ~/device_setup.sh              # 交互式，提示输入设备 IP
#    bash ~/device_setup.sh 192.168.43.1 # 直接指定设备 IP
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

DEV_IP="${1:-}"
ADB_PORT="${DEV_PORT:-5555}"
TARGET="${DEV_IP}:${ADB_PORT}"

cyan()  { echo -e "\033[0;36m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
red()   { echo -e "\033[0;31m$*\033[0m"; }
warn()  { echo -e "\033[1;33m$*\033[0m"; }

banner() {
  echo
  cyan "╔══════════════════════════════════════════╗"
  cyan "║   设备接入 · Termux MCP → ADB → 设备     ║"
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
    echo "    启动命令: adbmcp start"
  fi
  echo
}

# ── 2. 设备 IP ─────────────────────────────────────────────
ask_ip() {
  if [ -z "$DEV_IP" ]; then
    warn "[2/4] 设备 IP 未提供"
    echo
    echo "  请在设备「设置 → 关于 → 网络」查看 IP，或用下面的方法探测："
    echo "    • 设备开启无线调试后，端口号在开发者选项里"
    echo "    • 常见网关: 192.168.43.1 / 192.168.31.1 / 192.168.10.1"
    echo
    printf "  请输入设备 IP (如 192.168.43.1): "
    read -r DEV_IP
    if [ -z "$DEV_IP" ]; then
      red "  ✗ 未输入 IP，退出"
      exit 1
    fi
  fi
  TARGET="${DEV_IP}:${ADB_PORT}"
  cyan "[2/4] 目标设备: $TARGET"
  echo
}

# ── 3. 连接设备 ────────────────────────────────────────────
connect_device() {
  cyan "[3/4] 连接设备"
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
    red "  ✗ 状态 offline —— 设备接受了连接但未授权"
    echo "    设备屏幕上应弹出「允许 USB 调试」授权框，请确认勾选「始终允许」"
    exit 1
  else
    red "  ✗ 连接失败"
    echo "    排查:"
    echo "      1) 设备是否开启「开发者选项 → USB 调试 / 无线调试」"
    echo "      2) 设备 IP 是否正确: $DEV_IP"
    echo "      3) 端口是否为 $ADB_PORT (部分设备用随机端口)"
    echo "      4) 手机与设备是否在同一网络"
    exit 1
  fi
  echo

  # 读取设备信息 (Android 用 getprop, 非 Android 设备会失败属正常)
  green "  设备信息:"
  adb -s "$TARGET" shell "getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk" 2>&1 \
    | sed 's/^/    /'
  adb -s "$TARGET" shell "uname -a" 2>&1 | sed 's/^/    /'
  echo
}

# ── 4. 输出接入指引 ────────────────────────────────────────
show_guide() {
  cyan "[4/4] 完成 —— 接入方式"
  echo
  echo "  【方案 A】手机与 AI 客户端在同一网络 (推荐, 直连)"
  echo "    在 AI 客户端 (Claude Desktop / RikkaHub / WorkBuddy 等) 配置:"
  echo
  echo "    {"
  echo "      \"mcpServers\": {"
  echo "        \"adbmcp\": {"
  echo "          \"type\": \"streamableHttp\","
  echo "          \"url\": \"http://<手机IP>:8081/mcp\""
  echo "        }"
  echo "      }"
  echo "    }"
  echo
  echo "  直接运行 adbmcp 可拿到完整配置 (含 URL 与 Token)。"
  echo
  echo "  【方案 B】通过 USB/TCP 转发 (跨网络, 最稳)"
  echo "    在 AI 客户端所在的电脑上执行:"
  echo "      adb -s <手机IP>:5555 forward tcp:8081 tcp:8081"
  echo "    然后 MCP 地址填: http://127.0.0.1:8081/mcp"
  echo
  green "  ✓ 至此手机侧已就绪。AI 客户端连上后即可通过 MCP 操作设备。"
  echo
}

main() {
  check_env
  ask_ip
  connect_device
  show_guide
}

main
