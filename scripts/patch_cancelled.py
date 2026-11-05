#!/data/data/com.termux/files/usr/bin/python3
"""
adbmcp 补丁: 为 termux-mcp 补上 MCP 规范要求的 notifications/* 方法。

背景
----
termux-mcp v0.15.0 的 dispatch() 只处理了 "notifications/initialized"，
其它 notifications/* 一律抛 METHOD_NOT_FOUND (-32601)。

而 notifications/cancelled 是 MCP 2025-03-26 规范定义的标准通知 ——
客户端在用户中断生成时会发送它。服务端返回 -32601 会让
RikkaHub / Claude 等客户端把错误显示成:

    Error while sending message: Streamable HTTP error:
    {"jsonrpc": "2.0", "id": "...", "error": {"code": -32601, ...}}

按 JSON-RPC 规范, 通知 (notification) 不应返回响应, 更不应报错。
本补丁让所有 notifications/* 静默成功 (返回 None → HTTP 202)。

幂等: 已打过补丁则跳过。pip 升级 termux-mcp 后补丁会失效,
adbmcp 每次启动会自动重新检查并补上。
"""
import glob
import os
import sys

ANCHOR = '''    if method == "notifications/initialized":
        return None
'''

PATCH = '''    if method == "notifications/initialized":
        return None
    # adbmcp-patch: 补齐 MCP 规范的其他通知方法 (notifications/cancelled 等)。
    # 缺失会让客户端收到 -32601 Method not found 并显示为发送消息失败。
    if method.startswith("notifications/"):
        return None
'''

MARK = "# adbmcp-patch:"


def find_core():
    pats = [
        os.path.expanduser(
            "~/files/usr/lib/python*/site-packages/termux_mcp/mcp_core.py"),
        "/data/data/com.termux/files/usr/lib/python*/site-packages/"
        "termux_mcp/mcp_core.py",
    ]
    for pat in pats:
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[-1]
    return None


def main():
    path = find_core()
    if not path:
        print("[patch] 未找到 termux_mcp/mcp_core.py, 跳过")
        return 0

    with open(path, encoding="utf-8") as f:
        src = f.read()

    if MARK in src:
        print("[patch] 补丁已存在, 跳过")
        return 0

    if ANCHOR not in src:
        print("[patch] 锚点未找到 (上游代码已变更), 跳过")
        return 0

    patched = src.replace(ANCHOR, PATCH, 1)
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(patched)
    except OSError as e:
        print(f"[patch] 写入失败: {e}")
        return 1

    # 语法自检
    try:
        compile(patched, path, "exec")
    except SyntaxError as e:
        # 回滚
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
        print(f"[patch] 补丁语法错误, 已回滚: {e}")
        return 1

    print(f"[patch] 已为 notifications/* 补上处理: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
