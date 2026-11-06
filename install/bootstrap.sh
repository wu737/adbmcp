#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════
#  adbmcp 一行安装 (bootstrap)
#
#  用法:
#    curl -fsSL https://cdn.jsdelivr.net/gh/wu737/adbmcp@main/install/bootstrap.sh | bash
#
#  作用:
#    从仓库直接拉取脚本文本 → 校验 → 执行 install-adbmcp.sh 完成部署
#    与 `pip install termux-adbmcp` 等价, 只是走纯 shell 路径, 不依赖 Python 包管理
#
#  为什么逐个拉文本文件而不是拉一个 zip:
#    zip 是二进制产物, 不会随代码自动更新; 而仓库里的 .sh 文本永远与 main 同步。
#    实测用户网络下 github.com / raw.githubusercontent.com 常被阻断,
#    jsDelivr 可达 —— 所以做多镜像自动选源。
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

cyan()  { echo -e "\033[0;36m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
red()   { echo -e "\033[0;31m$*\033[0m"; }
yellow(){ echo -e "\033[1;33m$*\033[0m"; }

REF="${ADBMCP_VERSION:-main}"

echo
cyan "▸ adbmcp bootstrap  (ref: $REF)"
echo

# ── 1. 环境检查 (必须先于任何使用 $H 的路径) ──────────────────
# 从 MCP / adb shell / 开机自启触发时, $HOME 可能不是 Termux 的 home,
# 此时显式纠正并传给子进程 (install-adbmcp.sh 也依赖 $HOME)。
H="$HOME"
if [ ! -d "$H/files/usr/bin" ] && [ -d /data/data/com.termux/files/usr/bin ]; then
  H=/data/data/com.termux/files/home
  export HOME="$H"
fi
if [ ! -d "$H/files/usr/bin" ]; then
  red "✗ 这不是 Termux 环境"
  echo "  adbmcp 需要在 Android Termux 中运行"
  exit 1
fi
export PATH="$H/bin:$H/files/usr/bin:$PATH:/system/bin"

for cmd in curl sed; do
  command -v "$cmd" >/dev/null 2>&1 || {
    red "✗ 缺少 $cmd"
    echo "  安装: pkg install ${cmd}"
    exit 1
  }
done
green "  ✓ 环境检查通过"

# ── 2. 下载配置 ────────────────────────────────────────────
TMP="$H/.adbmcp_bootstrap"

# 候选镜像 (按优先级); 会自动记住第一个可用的, 后续文件直接复用
MIRRORS=(
  "https://cdn.jsdelivr.net/gh/wu737/adbmcp@${REF}"
  "https://raw.githubusercontent.com/wu737/adbmcp/${REF}"
  "https://cdn.statically.io/gh/wu737/adbmcp/${REF}"
  "https://ghproxy.net/https://raw.githubusercontent.com/wu737/adbmcp/${REF}"
)
BASE=""

# 需要的文件 —— 与仓库 scripts/ 保持一致
FILES=(
  "scripts/adbmcp"
  "scripts/device_setup.sh"
  "scripts/device_watchdog.sh"
  "scripts/scan_device.py"
  "scripts/boot_mcp.sh"
  "scripts/patch_cancelled.py"
  "install/install-adbmcp.sh"
)

# 校验语法, 并统一 LF (Windows 上编辑过的脚本会带 CRLF, Termux 会报 bad interpreter)
verify() {
  local rel="$1" f="$2"
  sed -i 's/\r$//' "$f" 2>/dev/null
  case "$rel" in
    *.py)
      python3 -c 'import ast,sys; ast.parse(open(sys.argv[1],encoding="utf-8").read())' "$f" 2>/dev/null || return 1
      ;;
    *)
      bash -n "$f" 2>/dev/null || return 1
      ;;
  esac
  return 0
}

# 返回 0 = 成功且 dest 内容有效
fetch() {
  local rel="$1" dest="$2" m url
  local -a candidates

  if [ -n "$BASE" ]; then
    candidates=("$BASE")
  else
    candidates=()
  fi
  for m in "${MIRRORS[@]}"; do
    candidates+=("$m")
  done

  for m in "${candidates[@]}"; do
    url="$m/$rel"
    curl -fsSL --connect-timeout 8 --max-time 60 -o "$dest" "$url" 2>/dev/null || continue
    [ -s "$dest" ] || continue
    # CDN 有时会以 200 返回 HTML 错误页, 挡掉
    if grep -qi '<html\|404: not found\|couldn.t find the requested file' "$dest"; then
      continue
    fi
    BASE="$m"
    verify "$rel" "$dest" || continue
    return 0
  done
  return 1
}

rm -rf "$TMP"
mkdir -p "$TMP/scripts" "$TMP/install" || exit 1

printf "  %-28s" "探测可用镜像"
for rel in "${FILES[@]}"; do
  dest="$TMP/$rel"
  if ! fetch "$rel" "$dest"; then
    echo
    red "✗ 所有镜像都无法取得: $rel"
    echo "  可稍后重试, 或改用 PyPI 方式:"
    echo "    pip install termux-adbmcp"
    rm -rf "$TMP"
    exit 1
  fi
done
printf "%s\n" "$(green "✓ ${#FILES[@]} 个文件")"
yellow "    镜像: $BASE"

# ── 3. 执行安装 ─────────────────────────────────────────────
# install-adbmcp.sh 会从同目录的 ../scripts/ 取脚本, 上面的布局正好匹配
INSTALLER="$TMP/install/install-adbmcp.sh"
if [ ! -f "$INSTALLER" ]; then
  red "✗ 安装脚本缺失"
  rm -rf "$TMP"
  exit 1
fi

bash "$INSTALLER"
rc=$?

rm -rf "$TMP"

echo
if [ "$rc" -eq 0 ]; then
  green "✓ 完成 —— 直接敲 adbmcp 即可启动"
else
  red "✗ 安装脚本返回 $rc"
fi
echo
exit "$rc"
