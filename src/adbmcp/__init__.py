"""
adbmcp —— 把 Android 手机 (Termux) 变成 MCP 服务器

让 Claude / Cursor / RikkaHub / WorkBuddy 等任意 AI 客户端
通过自然语言直接操作 adb 设备。

安装:
    pip install termux-adbmcp

首次运行 `adbmcp` 会自动完成部署 (复制脚本到 ~/bin、安装依赖)。
"""

try:
    from importlib.metadata import PackageNotFoundError, version as _pkg_version
    # 唯一真源是已安装包的 dist-info —— 避免源码里硬编码的版本号
    # 与实际发布版本脱节 (publish workflow 会在构建时覆写 pyproject.toml)
    __version__ = _pkg_version("termux-adbmcp")
except (ImportError, PackageNotFoundError):
    # Python < 3.8, 或从源码树直接运行、尚未 pip 安装
    __version__ = "0.0.0+src"

__all__ = ["__version__"]
