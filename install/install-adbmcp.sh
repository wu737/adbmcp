#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
#  adbmcp 一键安装 (新手机部署用)
#
#  用法 (在 Termux 里执行):
#    bash install-adbmcp.sh              # 交互式, 会提示输入设备 IP
#    bash install-adbmcp.sh 192.168.43.1 # 直接指定设备 IP
#
#  完成后:
#    • Termux 里直接敲 adbmcp 即可启动
#    • 输出含可直接粘贴给 AI 客户端 (Claude/Cursor/RikkaHub/WorkBuddy) 的配置
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

H="$HOME"
BIN_DIR="$H/bin"
APP_DIR="$H/mcp-servers/adbmcp"
OLD_DIR="$H/mcp-servers/car"          # 旧版目录 (车机时代), 用于迁移
B="$H/files/usr/bin"
# 注意: 必须追加而非覆盖 —— 覆盖会丢掉 Termux 原有的 usr/bin,
# 导致 python3 / pip / adb 全部 command not found
export PATH="$BIN_DIR:$B:$PATH:/system/bin"

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
  bold "  adbmcp 一键安装 · Termux MCP + ADB 设备通道"
  bold "════════════════════════════════════════════════════"
  echo
}

# ══ 0. 迁移旧目录 ═════════════════════════════════════════
step_migrate() {
  [ -d "$OLD_DIR" ] || return 0
  echo
  cyan "[0/5] 迁移旧版数据"
  echo
  mkdir -p "$APP_DIR"

  # 设备清单
  if [ -f "$OLD_DIR/cars.txt" ] && [ ! -f "$APP_DIR/devices.txt" ]; then
    cp "$OLD_DIR/cars.txt" "$APP_DIR/devices.txt"
    green "  ✓ 已迁移 cars.txt → devices.txt"
  fi

  # 模式 / 配置 / 日志
  for f in mode mcp-endpoint.json adbmcp.log watchdog.log mcp.log; do
    if [ -f "$OLD_DIR/$f" ] && [ ! -f "$APP_DIR/$f" ]; then
      cp "$OLD_DIR/$f" "$APP_DIR/$f" 2>/dev/null && green "  ✓ 已迁移 $f"
    fi
  done

  # 旧脚本 (仅保留未改名的新版文件, 旧的 car_*.sh 会被新文件覆盖)
  echo "  · 旧目录保留在 $OLD_DIR (确认无误后可自行删除)"
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
  mkdir -p "$BIN_DIR" "$APP_DIR" "$H/.termux-mcp"
  chmod 700 "$H/.termux-mcp" 2>/dev/null

  # 脚本来源目录: 兼容两种布局
  #   A) 全部平铺在同一目录 (bundle 解压后的形态)
  #   B) install/ 与 scripts/ 分开 (仓库形态)
  local src_dir
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local src_root="$src_dir"
  if [ ! -f "$src_dir/adbmcp" ] && [ -f "$src_dir/../scripts/adbmcp" ]; then
    src_root="$(cd "$src_dir/.." && pwd)"
  fi

  local f found=0
  for f in adbmcp device_setup.sh scan_device.py device_watchdog.sh boot_mcp.sh patch_cancelled.py; do
    local src="$src_root/$f"
    [ -f "$src" ] || src="$src_root/scripts/$f"
    if [ -f "$src" ]; then
      cp "$src" "$APP_DIR/$f" 2>/dev/null
      [ "$f" = "adbmcp" ] && cp "$src" "$BIN_DIR/adbmcp"
      chmod +x "$APP_DIR/$f" "$BIN_DIR/adbmcp" 2>/dev/null
      found=$((found+1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    red "  ✗ 未找到脚本文件"
    echo "    请把 adbmcp / device_setup.sh / scan_device.py / device_watchdog.sh / boot_mcp.sh"
    echo "    放在本脚本同目录, 或放在 scripts/ 子目录中"
    exit 1
  fi

  # 自愈: 统一把脚本转成 LF —— CRLF 在 Termux 下会报 bad interpreter
  local fixed=0
  for f in "$APP_DIR"/*.sh "$APP_DIR"/*.py "$BIN_DIR/adbmcp"; do
    [ -f "$f" ] || continue
    if grep -q $'\r' "$f" 2>/dev/null; then
      sed -i 's/\r$//' "$f" 2>/dev/null && fixed=$((fixed+1))
    fi
  done
  [ "$fixed" -gt 0 ] && yellow "  · 已修正 $fixed 个文件的 CRLF 换行"

  green "  ✓ 已部署 $found 个文件"

  # 清理旧版脚本
  for f in car_setup.sh car_watchdog.sh boot_car_mcp.sh scan_car.py; do
    [ -f "$APP_DIR/$f" ] && rm -f "$APP_DIR/$f" 2>/dev/null
  done

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
  if [ -f "$APP_DIR/boot_mcp.sh" ]; then
    cp "$APP_DIR/boot_mcp.sh" "$H/.termux/boot/" 2>/dev/null
    chmod +x "$H/.termux/boot/boot_mcp.sh" 2>/dev/null
    rm -f "$H/.termux/boot/boot_car_mcp.sh" 2>/dev/null
    green "  ✓ 开机自启脚本已就位 (需安装 Termux:Boot APK 生效)"
  fi
  echo
}

# ══ 3. 设备清单 ═══════════════════════════════════════════
step_devices() {
  cyan "[3/5] 配置设备"
  echo
  local devices="$APP_DIR/devices.txt"
  if [ -f "$devices" ]; then
    green "  ✓ 沿用已有清单 $devices"
  else
    cat > "$devices" <<'EOF'
# 设备列表 —— 每行格式:  IP:PORT   备注(可选)
# 空行与以 # 开头的行会被忽略
#
# 格式说明:
#   IP:PORT  adb 无线调试端口。绝大多数设备是 5555；
#            若设备开发者选项显示的是随机端口(如 37099)，填该端口。
EOF
    green "  ✓ 已创建空白清单 $devices"
  fi
  echo "    格式示例: 192.168.43.1:5555    设备备注(可留空)"
  echo "    修改后执行 adbmcp connect 立即生效, 或 adbmcp restart"
  echo
}

# ══ 4. 启动并自检 ═════════════════════════════════════════
step_start() {
  cyan "[4/5] 启动并自检"
  echo
  bash "$APP_DIR/adbmcp" start 2>&1 | tail -25
  echo
}

# ══ 5. 扫描设备 ═══════════════════════════════════════════
step_scan() {
  cyan "[5/5] 扫描局域网内的 adb 设备"
  echo
  local net
  net=$(python3 -c "import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.connect(('10.255.255.255',1));print(s.getsockname()[0])" 2>/dev/null | cut -d. -f1-3)
  if [ -z "$net" ]; then
    yellow "  ! 无法确定本机网段, 跳过"
    echo "    可手动执行: python3 ~/mcp-servers/adbmcp/scan_device.py <网段>"
    return 0
  fi
  echo "  扫描网段: ${net}.0/24"
  python3 "$APP_DIR/scan_device.py" "$net" 2>&1 | head -20
  echo
}

main() {
  banner
  step_migrate
  step_deps
  step_files
  step_devices
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
  echo "    adbmcp connect    手动连接设备清单"
  echo "    adbmcp scan       扫描网段"
  echo "    adbmcp restart    重启 (改配置后)"
  echo
  cyan "  AI 客户端配置 (设置 → MCP → 导入):"
  cat "$APP_DIR/mcp-endpoint.json" 2>/dev/null | sed 's/^/    /'
  echo
  yellow "  注意: AI 客户端需把 URL 里的 IP 换成这台新手机的 IP"
  echo
}

main "$@"
