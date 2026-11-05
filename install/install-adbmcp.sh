#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
#  adbmcp 一键安装 (新手机部署用)
#
#  用法 (在 Termux 里执行):
#    bash install-adbmcp.sh              # 交互式, 会提示输入车机 IP
#    bash install-adbmcp.sh 192.168.43.1 # 直接指定车机 IP
#
#  完成后:
#    • Termux 里直接敲 adbmcp 即可启动
#    • 输出含可直接粘贴给 AI 客户端 (Claude/Cursor/RikkaHub/WorkBuddy) 的配置
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

H="$HOME"
BIN_DIR="$H/bin"
CAR_DIR="$H/mcp-servers/car"
B="$H/files/usr/bin"
export PATH="$BIN_DIR:$B:/system/bin"

MCP_PORT="${MCP_PORT:-8081}"
MCP_HOST="${MCP_HOST:-0.0.0.0}"
# 固定 token: 换手机时可保持不变, AI 客户端配置就不用改
FIXED_TOKEN="${ADBMCP_TOKEN:-adbmcp-K60Pro-2026-fixed-8f3a9c2e}"
PKG_VERSION="termux-mcp==0.15.0"

cyan()  { echo -e "\033[0;36m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
red()   { echo -e "\033[0;31m$*\033[0m"; }
yellow(){ echo -e "\033[1;33m$*\033[0m"; }
bold()  { echo -e "\033[1m$*\033[0m"; }

banner() {
  echo
  bold "════════════════════════════════════════════════════"
  bold "  adbmcp 一键安装 · Termux MCP + ADB 车机通道"
  bold "════════════════════════════════════════════════════"
  echo
}

# ══ 1. 环境自检与安装 ═════════════════════════════════════
step_deps() {
  cyan "[1/5] 安装依赖"
  echo

  # Termux:API 不是必需, 但部分工具有用
  if ! command -v adb >/dev/null 2>&1; then
    yellow "  → 安装 android-tools (adb)"
    pkg install -y android-tools >/dev/null 2>&1
  fi
  if command -v adb >/dev/null 2>&1; then
    green "  ✓ adb: $(adb version 2>/dev/null | head -1)"
  else
    red "  ✗ adb 安装失败, 请手动执行: pkg install android-tools"
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    yellow "  → 安装 python"
    pkg install -y python >/dev/null 2>&1
  fi
  green "  ✓ python: $(python3 -V 2>&1)"

  # termux-mcp (PyPI) —— 提供 termux-native-mcp 命令
  if command -v termux-native-mcp >/dev/null 2>&1; then
    green "  ✓ termux-native-mcp 已安装"
  else
    yellow "  → pip 安装 $PKG_VERSION"
    pip install --quiet "$PKG_VERSION" >/dev/null 2>&1
    if command -v termux-native-mcp >/dev/null 2>&1; then
      green "  ✓ termux-native-mcp 安装完成"
    else
      red "  ✗ 安装失败, 请手动执行: pip install $PKG_VERSION"
      exit 1
    fi
  fi
  echo
}

# ══ 2. 部署脚本文件 ═══════════════════════════════════════
step_files() {
  cyan "[2/5] 部署脚本"
  echo
  mkdir -p "$BIN_DIR" "$CAR_DIR" "$H/.termux-mcp"
  chmod 700 "$H/.termux-mcp" 2>/dev/null

  # 本脚本同目录下的 adbmcp / car_setup.sh / scan_car.py / car_watchdog.sh / boot_car_mcp.sh
  local src_dir
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local f found=0
  for f in adbmcp car_setup.sh scan_car.py car_watchdog.sh boot_car_mcp.sh patch_cancelled.py; do
    if [ -f "$src_dir/$f" ]; then
      cp "$src_dir/$f" "$CAR_DIR/$f" 2>/dev/null
      [ "$f" = "adbmcp" ] && cp "$src_dir/$f" "$BIN_DIR/adbmcp"
      chmod +x "$CAR_DIR/$f" "$BIN_DIR/adbmcp" 2>/dev/null
      found=$((found+1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    red "  ✗ 未找到脚本文件"
    echo "    请把 adbmcp / car_setup.sh / scan_car.py / car_watchdog.sh / boot_car_mcp.sh"
    echo "    与本脚本放在同一目录"
    exit 1
  fi
  green "  ✓ 已部署 $found 个文件"

  # 立即应用上游补丁 (幂等, 之后每次启动 adbmcp 会自动检查)
  if [ -f "$BIN_DIR/patch_cancelled.py" ]; then
    python3 "$BIN_DIR/patch_cancelled.py" 2>&1 | sed 's/^/  /'
  fi

  # PATH
  if ! grep -q 'HOME/bin' "$H/.bashrc" 2>/dev/null; then
    printf '%s\n' 'export PATH="$HOME/bin:$PATH"' >> "$H/.bashrc"
  fi
  if ! grep -q 'HOME/bin' "$H/.profile" 2>/dev/null; then
    printf '%s\n' 'export PATH="$HOME/bin:$PATH"' >> "$H/.profile"
  fi
  green "  ✓ PATH 已配置 (~/bin)"

  # 开机自启 (需装 Termux:Boot APK 才生效)
  mkdir -p "$H/.termux/boot" 2>/dev/null
  if [ -f "$CAR_DIR/boot_car_mcp.sh" ]; then
    cp "$CAR_DIR/boot_car_mcp.sh" "$H/.termux/boot/" 2>/dev/null
    chmod +x "$H/.termux/boot/boot_car_mcp.sh" 2>/dev/null
    green "  ✓ 开机自启脚本已就位 (需安装 Termux:Boot APK 生效)"
  fi
  echo
}

# ══ 3. 车机清单 ═══════════════════════════════════════════
step_cars() {
  cyan "[3/5] 配置车机"
  echo
  local cars="$CAR_DIR/cars.txt"
  if [ -f "$cars" ]; then
    green "  ✓ 沿用已有清单 $cars"
  else
    cat > "$cars" <<'EOF'
# 车机列表 —— 每行格式:  IP:PORT   备注(可选)
# 空行与以 # 开头的行会被忽略
#
# 格式说明:
#   IP:PORT  adb 无线调试端口。绝大多数车机是 5555；
#            若车机开发者选项显示的是随机端口(如 37099)，填该端口。
EOF
    green "  ✓ 已创建空白清单 $cars"
  fi
  echo "    格式示例: 192.168.43.1:5555    车机热点网关"
  echo "    修改后执行 adbmcp restart 生效"
  echo
}

# ══ 4. 启动并自检 ═════════════════════════════════════════
step_start() {
  cyan "[4/5] 启动并自检"
  echo
  bash "$CAR_DIR/adbmcp" start 2>&1 | tail -25
  echo
}

# ══ 5. 扫描车机 ═══════════════════════════════════════════
step_scan() {
  cyan "[5/5] 扫描局域网内的 adb 设备"
  echo
  local net
  net=$(python3 -c "import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.connect(('10.255.255.255',1));print(s.getsockname()[0])" 2>/dev/null | cut -d. -f1-3)
  if [ -z "$net" ]; then
    yellow "  ! 无法确定本机网段, 跳过"
    echo "    可手动执行: python3 ~/mcp-servers/car/scan_car.py <网段>"
    return 0
  fi
  echo "  扫描网段: ${net}.0/24"
  python3 "$CAR_DIR/scan_car.py" "$net" 2>&1 | head -20
  echo
}

main() {
  banner
  step_deps
  step_files
  step_cars
  step_start
  step_scan

  echo
  bold "════════════════════════════════════════════════════"
  bold "  安装完成"
  bold "════════════════════════════════════════════════════"
  echo
  green "  Termux 里直接敲  adbmcp  即可启动"
  echo
  cyan "  后续操作:"
  echo "    adbmcp status     查看状态"
  echo "    adbmcp config     打印 AI 客户端配置"
  echo "    adbmcp scan       扫描车机"
  echo "    adbmcp restart    重启 (改配置后)"
  echo
  cyan "  AI 客户端配置 (设置 → MCP → 导入):"
  cat "$CAR_DIR/mcp-endpoint.json" 2>/dev/null | sed 's/^/    /'
  echo
  yellow "  注意: AI 客户端需把 URL 里的 IP 换成这台新手机的 IP"
  echo
}

main "$@"
