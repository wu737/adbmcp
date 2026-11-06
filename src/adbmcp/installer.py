"""
部署逻辑: 把打包进来的 shell 脚本安装到用户级目录。

设计原则
--------
* 安装到 ``~/bin`` 与 ``~/mcp-servers/adbmcp/`` —— 不污染 Termux 的 ``$PREFIX``,
  用户随时可以 ``rm -rf`` 清干净。
* 幂等: 重复运行只覆盖脚本, 不动用户数据 (``devices.txt`` / 日志 / 配置)。
* 自愈: 落地时统一把 CRLF 转成 LF —— Termux 下 CRLF 会报
  ``bad interpreter: /bin/bash^M``。
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

# 打包进来的脚本 (由 pyproject 的 force-include 提供)
BUNDLED_SCRIPTS = Path(__file__).parent / "scripts"

# 部署目标
BIN_DIR = Path.home() / "bin"
APP_DIR = Path.home() / "mcp-servers" / "adbmcp"

# 主脚本 (放到 PATH 里的那个)
MAIN_SCRIPT = "adbmcp"

# 需要复制过去的文件
DEPLOY_FILES = [
    "adbmcp",
    "device_setup.sh",
    "device_watchdog.sh",
    "boot_mcp.sh",
    "scan_device.py",
    "patch_cancelled.py",
]

# 可执行权限的文件
EXECUTABLE = {"adbmcp", "device_setup.sh", "device_watchdog.sh", "boot_mcp.sh"}

# 设备清单模板
DEVICES_TEMPLATE = """\
# 设备列表 —— 每行格式:  IP:PORT   备注(可选)
# 空行与以 # 开头的行会被忽略
#
# 格式说明:
#   IP:PORT  adb 无线调试端口。绝大多数设备是 5555；
#            若设备开发者选项显示的是随机端口(如 37099)，填该端口。
"""


def _flush() -> None:
    """确保部署提示先于子进程输出 (Python stdout 有缓冲)。"""
    try:
        sys.stdout.flush()
    except (AttributeError, ValueError):
        pass


def _cyan(msg: str) -> None:
    print(f"\033[0;36m{msg}\033[0m")
    _flush()


def _green(msg: str) -> None:
    print(f"\033[0;32m{msg}\033[0m")
    _flush()


def _yellow(msg: str) -> None:
    print(f"\033[1;33m{msg}\033[0m")
    _flush()


def _red(msg: str) -> None:
    print(f"\033[0;31m{msg}\033[0m")
    _flush()


def _read_text(path: Path) -> str:
    """读文件并统一为 LF。"""
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")


def _write_text(path: Path, text: str, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # newline="\n" 保证不引入 CRLF
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    if executable:
        mode = path.stat().st_mode
        path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def is_installed() -> bool:
    """主脚本是否已经部署到位。"""
    return (BIN_DIR / MAIN_SCRIPT).is_file()


def deploy() -> bool:
    """把脚本复制到 ~/bin 与 ~/mcp-servers/adbmcp/。返回是否成功。"""
    if not BUNDLED_SCRIPTS.is_dir():
        _red(f"✗ 包内缺少 scripts 目录: {BUNDLED_SCRIPTS}")
        return False

    BIN_DIR.mkdir(parents=True, exist_ok=True)
    APP_DIR.mkdir(parents=True, exist_ok=True)

    copied = 0
    for name in DEPLOY_FILES:
        src = BUNDLED_SCRIPTS / name
        if not src.is_file():
            continue
        text = _read_text(src)
        is_exec = name in EXECUTABLE

        # 主脚本同时放两份: ~/bin (PATH) 与 APP_DIR (便于调用同目录脚本)
        _write_text(APP_DIR / name, text, is_exec)
        if name == MAIN_SCRIPT:
            _write_text(BIN_DIR / MAIN_SCRIPT, text, is_exec)
        copied += 1

    if copied == 0:
        _red("✗ 没有可部署的脚本")
        return False

    # 设备清单: 已存在则保留用户的
    devices = APP_DIR / "devices.txt"
    if not devices.exists():
        _write_text(devices, DEVICES_TEMPLATE)

    # PATH: 确保 ~/bin 在 PATH 里
    _ensure_path()

    _green(f"✓ 已部署 {copied} 个脚本 → {APP_DIR}")
    return True


def _ensure_path() -> None:
    """把 ~/bin 写进 shell 启动文件 (若尚未包含)。"""
    for rc in (Path.home() / ".bashrc", Path.home() / ".profile"):
        try:
            existing = rc.read_text(encoding="utf-8") if rc.exists() else ""
        except OSError:
            continue
        if "HOME/bin" in existing:
            continue
        try:
            with open(rc, "a", encoding="utf-8", newline="\n") as fh:
                fh.write('\nexport PATH="$HOME/bin:$PATH"\n')
            _green(f"✓ PATH 已配置 ({rc.name})")
        except OSError:
            pass


def _termux() -> bool:
    """是否运行在 Termux 环境。"""
    return "com.termux" in os.environ.get("PREFIX", "")


def ensure_dependencies() -> bool:
    """检查并安装运行依赖 (adb / termux-mcp)。返回是否全部就绪。"""
    if not _termux():
        # 非 Termux 环境 (例如在 PC 上 pip install) —— 不处理依赖
        return True

    ok = True

    # adb
    if shutil.which("adb") is None:
        _yellow("→ 安装 android-tools (adb)")
        subprocess.run(["pkg", "install", "-y", "android-tools"],
                       capture_output=True, timeout=600)
    if shutil.which("adb"):
        _green("✓ adb 就绪")
    else:
        _red("✗ adb 不可用 (pkg install android-tools)")
        ok = False

    # termux-native-mcp
    if shutil.which("termux-native-mcp") is None:
        _yellow("→ pip 安装 termux-mcp")
        subprocess.run([sys.executable, "-m", "pip", "install", "--quiet",
                        "termux-mcp==0.15.0"], capture_output=True, timeout=900)
    if shutil.which("termux-native-mcp"):
        _green("✓ termux-native-mcp 就绪")
    else:
        _red("✗ termux-native-mcp 不可用 (pip install termux-mcp)")
        ok = False

    return ok


def apply_patch() -> None:
    """给 termux-mcp 打上游补丁 (补齐 notifications/* 方法)。"""
    patcher = BIN_DIR / "patch_cancelled.py"
    if not patcher.is_file():
        patcher = APP_DIR / "patch_cancelled.py"
    if not patcher.is_file():
        return
    try:
        out = subprocess.run([sys.executable, str(patcher)],
                             capture_output=True, text=True, timeout=60)
        if "已为 notifications" in (out.stdout or ""):
            _green("✓ 已应用上游补丁 (notifications/*)")
    except (OSError, subprocess.SubprocessError):
        pass


def setup(quiet: bool = False) -> bool:
    """完整部署流程。"""
    if not quiet:
        _cyan("▸ 首次部署 adbmcp ...")
        print()
    if not deploy():
        return False
    ensure_dependencies()
    apply_patch()
    if not quiet:
        print()
        _green("✓ 部署完成, 接下来直接敲 adbmcp 即可")
    return True


def ensure_ready() -> bool:
    """确保已部署; 未部署则自动 setup。"""
    if is_installed():
        return True
    return setup()
