# RikkaHub 报错「Error while sending message」—— 根因与修复

> 时间：2026-11-05 16:07
> 现象：RikkaHub 的 MCP 列表里 `termux` 显示绿点（已连接），但发消息时报
> `Error while sending message: Streamable HTTP error: {"jsonrpc": "2.0", "id": "...", ...}`

## 结论

**不是配置错误，也不是网络问题。是 `termux-mcp` v0.15.0 的功能缺失。**

服务端没有实现 MCP 规范要求的 `notifications/cancelled` 通知方法，
客户端（这里�� RikkaHub）发送该通知后收到 `-32601 Method not found`，
并把这个错误响应显示成了「发送消息失败」。

已通过补丁修复，实测 `notifications/cancelled` 从崩溃变为 **HTTP 202**。

---

## 排查过程

### 第 1 步：确认服务端活着

```bash
# Termux 内
$ grep -c 'adbmcp-patch' .../termux_mcp/mcp_core.py
0
$ tail -12 ~/mcp-servers/car/mcp.log
11:54:53 [INFO] termux_mcp.mcp_server: Authentication: enabled (length=33)
11:54:53 [INFO] termux_mcp.mcp_server: Termux native MCP (Streamable HTTP) listening on http://0.0.0.0:8081/mcp
...
termux_mcp.mcp_core.RpcError: Method not found: notifications/cancelled
```

关键：日志里唯一的错误就是 `notifications/cancelled`，而且**来自 `192.168.110.4`**（RikkaHub 所在设备）。

### 第 2 步：排除 Accept 头差异

MCP Streamable HTTP 规范要求客户端同时接受 JSON 与 SSE。逐个测：

| Accept 头 | 状态 | Content-Type |
|---|---|---|
| `application/json, text/event-stream` | 200 | `application/json` |
| `application/json` | 200 | `application/json` |
| `text/event-stream` | 200 | `application/json` |
| `*/*` | 200 | `application/json` |

全部正常，**排除 Accept 头因素**。

### 第 3 步：模拟 RikkaHub 的完整调用序列

用 RikkaHub 风格的 32 位 hex request id 走一遍：

| 步骤 | 结果 |
|---|---|
| `initialize` | ✅ 200 `application/json` |
| `notifications/initialized` | ✅ 202 |
| `tools/list` | ✅ 200 `application/json` |
| `tools/call` | ✅ 200 **`text/event-stream`** |
| **`notifications/cancelled`** | ❌ **服务端抛异常，连接中断** |

只有最后一步失败。

### 第 4 步：确认上游缺失

```bash
$ grep -n 'notifications/cancelled' .../termux_mcp/mcp_core.py
(无匹配)
```

`mcp_core.py` 的 `dispatch()` 只处理了 `notifications/initialized`，其它
`notifications/*` 一律 `raise RpcError(METHOD_NOT_FOUND, ...)`。

PyPI 上 `termux-mcp` 最新版就是 **0.15.0**，无修复版本
（源码仓库 https://github.com/termuxgpt/termux-mcp）。

按 JSON-RPC 规范，notification 不应返回响应，更不应报错 —— 这确实是上游 bug。

---

## 修复方案

### 补丁原理

在 `mcp_core.py` 的 `dispatch()` 里，把所有 `notifications/*` 静默成功：

```python
    if method == "notifications/initialized":
        return None
+   # adbmcp-patch: 补齐 MCP 规范的其他通知方法 (notifications/cancelled 等)。
+   # 缺失会让客户端收到 -32601 Method not found 并显示为发送消息失败。
+   if method.startswith("notifications/"):
+       return None
    raise RpcError(METHOD_NOT_FOUND, f"Method not found: {method}")
```

### 补丁脚本

`scripts/patch_cancelled.py` 的特性：

- **幂等** —— 已打过则跳过（靠 `# adbmcp-patch:` 标记识别）
- **自动重打** —— `adbmcp` 每次启动都检查，pip 升级 termux-mcp 后自动修复
- **语法自检** —— 打完 patch 做 `compile()` 校验，失败自动回滚
- **路径自适应** —— 自动定位 `python*/site-packages/termux_mcp/mcp_core.py`

### 集成方式

```bash
# scripts/adbmcp
apply_patches() {
  local patcher="$HOME/bin/patch_cancelled.py"
  [ ! -f "$patcher" ] && patcher="$BASE_DIR/patch_cancelled.py"
  [ -f "$patcher" ] && python3 "$patcher" 2>&1 | grep -q "已为 notifications" \
    && green "  ✓ 已应用上游补丁 (notifications/*)"
}

start_mcp() {
  ...
  apply_patches          # ← 每次启动都检查
  ...
}
```

`install/install-adbmcp.sh` 也会在部署后立即打一次补丁。

---

## 实测验证

```
=== 补丁自动应用 ===
(还原补丁后) grep -c 'adbmcp-patch' mcp_core.py  →  0
(执行 adbmcp restart 后)                          →  1   ← 自动生效

=== 完整流程回归 ===
initialize                 → 200 application/json
notifications/initialized  → 202
tools/list                 → 200 application/json
tools/call                 → 200 text/event-stream
notifications/cancelled    → 202   ← 修复前是连接中断

=== 车机链路 ===
adb -s 192.168.110.39:5555 shell hostname  →  wise
```

---

## 修复过程中踩到的两个坑

### 1. `BIN_DIR` 变量不存在

第一次集成时在 `apply_patches()` 里用了 `$BIN_DIR` / `$CAR_DIR`，
但 `adbmcp` 主脚本里实际只有 `BASE_DIR`（`install-adbmcp.sh` 才有 `BIN_DIR`）。
结果 `patcher` 路径为空，补丁**静默不执行** —— 没有任何报错，只是没效果。

> 教训：加新函数后必须实测，不能只看语法通过。

### 2. CRLF 换行

用 Python 写脚本时默认输出 CRLF，base64 传到手机后：

```
/data/data/com.termux/files/home/mcp-servers/car/install-adbmcp.sh: line 34:
syntax error near unexpected token `$'{\r''
```

`install-adbmcp.sh` 是 CRLF，`adbmcp` 和 `patch_cancelled.py` 却是 LF ——
因为前者是 Python 写文件时生成的，后两者是 Bash heredoc 生成的。

> 教训：部署到 Linux 前统一转 LF。仓库里已有 `.gitattributes` 兜底，
> 但 base64 直传绕过了 git，必须自己转。

---

## 排查方法论

1. **先分层** —— 服务进程 → 握手 → tools/list → tools/call → 特殊通知，
   逐步缩小范围
2. **日志里的客户端 IP 是关键线索** —— `192.168.110.4` 直接指向发起报错的那台设备
3. **模拟客户端而不是猜** —— 用 RikkaHub 风格的 request id 走完整序列，
   一次定位到唯一失败点
4. **上游 bug 要看版本** —— PyPI 最新版就是 0.15.0，说明等更新没用，得自己打补丁
