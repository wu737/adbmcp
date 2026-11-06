"""
CLI 入口 —— ``adbmcp`` 命令。

职责:
1. 首次运行时自动完成部署 (见 installer.setup)
2. 之后把参数原样转发给 ``~/bin/adbmcp`` 这个 shell 主脚本

之所以用 shell 做主实现: adbmcp 的核心是 adb / MCP 进程管理,
shell 在 Termux 上比 Python 更直接 (无需额外依赖, 也便于用户在
``~/bin/adbmcp`` 里自行修改)。
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from . import __version__
from . import installer


def _shell_script() -> Path:
    """已部署的主脚本路径。"""
    return installer.BIN_DIR / installer.MAIN_SCRIPT


def _exec_script(script: Path, args: list[str]) -> int:
    """执行 shell 主脚本。

    POSIX (Termux): 直接执行, 走 shebang, 最快。
    Windows: 无法直接执行 shell 脚本 (WinError 193), 改用 bash 调用。
    """
    if os.name == "posix":
        return subprocess.call([str(script)] + args)

    bash = shutil.which("bash")
    if bash:
        return subprocess.call([bash, str(script)] + args)

    print("✗ 当前环境无法执行 shell 脚本", file=sys.stderr)
    print("  adbmcp 需要在 Android Termux 中运行", file=sys.stderr)
    print(f"  请在 Termux 里执行: pip install adbmcp && adbmcp", file=sys.stderr)
    return 1


def _run_setup_and_exit(args: list[str]) -> int:
    """走一遍部署流程, 然后继续执行原命令。"""
    sys.stdout.flush()   # 保证 setup 的提示先于子进程输出
    if not installer.setup():
        return 1
    # setup 里已部署, 重新解析路径
    script = _shell_script()
    if not script.is_file():
        print("✗ 部署后仍未找到主脚本", file=sys.stderr)
        return 1
    sys.stdout.flush()
    return _exec_script(script, args)


def _version() -> int:
    print(f"adbmcp {__version__}")
    print(f"  包内脚本: {installer.BUNDLED_SCRIPTS}")
    print(f"  部署目录: {installer.APP_DIR}")
    return 0


def _help() -> int:
    script = _shell_script()
    if script.is_file():
        return _exec_script(script, ["--help"])
    print(__doc__)
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    # --version / -V
    if argv and argv[0] in ("--version", "-V"):
        return _version()

    # 显式要求重新部署
    if argv and argv[0] in ("setup", "install"):
        return 0 if installer.setup() else 1

    # 未部署 → 先自动 setup, 再执行原命令
    if not installer.is_installed():
        return _run_setup_and_exit(argv)

    # 已部署 → 转发
    script = _shell_script()
    if not script.is_file():
        return _run_setup_and_exit(argv)

    # 保持交互式终端的信号行为
    try:
        return _exec_script(script, argv)
    except KeyboardInterrupt:
        return 130
    except OSError as exc:
        print(f"✗ 无法执行 {script}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
