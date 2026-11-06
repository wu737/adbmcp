"""
adbmcp —— 把 Android 手机 (Termux) 变成 MCP 服务器

让 Claude / Cursor / RikkaHub / WorkBuddy 等任意 AI 客户端
通过自然语言直接操作 adb 设备。

安装:
    pip install adbmcp

首次运行 `adbmcp` 会自动完成部署 (复制脚本到 ~/bin、安装依赖)。
"""

__version__ = "0.2.0"
__all__ = ["__version__"]
