#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
#  adbmcp 一行安装 (bootstrap)
#
#  用法:
#    curl -fsSL https://cdn.jsdelivr.net/gh/wu737/adbmcp@main/install/bootstrap.sh | bash
#
#  作用:
#    下载 bundle → 解压 → 执行 install-adbmcp.sh 完成部署
#    与 `pip install adbmcp` 等价, 只是走 shell 路径 (不依赖 Python 包管理)
#
#  镜像: 自动在多个源之间挑选第一个可用的
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

H="$HOME"
APP_DIR="$H/mcp-servers/adbmcp"
BUNDLE_VERSION="${ADBMCP_VERSION:-latest}"

# 候选下载源 (按优先级)
SOURCES=(
  "https://cdn.jsdelivr.net/gh/wu737/adbmcp@${BUNDLE_VERSION}/install/bundle.zip"
  "https://raw.githubusercontent.com/wu737/adbmcp/main/install/bundle.zip"
  "https://github.com/wu737/adbmcp/releases/latest/download/adbmcp-bundle.zip"
)

cyan()  { echo -e "\033[0;36m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
red()   { echo -e "\033[0;31m$*\033[0m"; }
yellow(){ echo -e "\033[1;33m$*\033[0m"; }

echo
cyan "▸ adbmcp bootstrap"
echo

# ── 1. 环境检查 ────────────────────────────────────────────
if [ ! -d "$H/files/usr/bin" ]; then
  red "✗ 这不是 Termux 环境"
  echo "  adbmcp 需要在 Android Termux 中运行"
  exit 1
fi
export PATH="$H/bin:$H/files/usr/bin:$PATH:/system/bin"

for cmd in curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || {
    red "✗ 缺少 $cmd"
    echo "  安装: pkg install ${cmd}"
    exit 1
  }
done
green "  ✓ 环境检查通过"

# ── 2. 下载 bundle ─────────────────────────────────────────
TMP="$H/.adbmcp_bootstrap"
rm -rf "$TMP"
mkdir -p "$TMP"

BUNDLE="$TMP/bundle.zip"
GOT=0
for url in "${SOURCES[@]}"; do
  host=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|')
  printf "  尝试 %-34s" "$host"
  if curl -fsSL --connect-timeout 10 --max-time 180 -o "$BUNDLE" "$url" 2>/dev/null \
     && [ -s "$BUNDLE" ]; then
    green "✓"
    GOT=1
    break
  fi
  echo "失败"
done

if [ "$GOT" -ne 1 ]; then
  echo
  red "✗ 所有下载源都不可用"
  echo "  可手动下载后安装:"
  echo "    https://github.com/wu737/adbmcp/releases"
  echo "  或用 PyPI 方式:"
  echo "    pip install adbmcp"
  rm -rf "$TMP"
  exit 1
fi

# ── 3. 解包 ────────────────────────────────────────────────
cd "$TMP" || exit 1
if ! unzip -oq "$BUNDLE" 2>/dev/null; then
  red "✗ 解包失败 (文件可能不完整)"
  rm -rf "$TMP"
  exit 1
fi
green "  ✓ 已下载并解包 ($(du -h "$BUNDLE" | cut -f1))"

# ── 4. 执行安装 ─────────────────────────────────────────────
# bundle 里结构: scripts/ 与 install/
SCRIPT_SRC=""
if [ -f "$TMP/scripts/adbmcp" ]; then
  SCRIPT_SRC="$TMP/scripts/adbmcp"
elif [ -f "$TMP/install/install-adbmcp.sh" ]; then
  SCRIPT_SRC="$TMP/install/install-adbmcp.sh"
fi

if [ -z "$SCRIPT_SRC" ]; then
  red "✗ bundle 里找不到安装脚本"
  rm -rf "$TMP"
  exit 1
fi

bash "$SCRIPT_SRC"

rm -rf "$TMP"

echo
green "✓ 完成 —— 直接敲 adbmcp 即可启动"
echo
