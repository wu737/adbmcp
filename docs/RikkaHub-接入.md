# RikkaHub 接入 adbmcp —— 配置指南

## 结论

RikkaHub 的 MCP 是**两层结构**，你只配了第一层：

| 层 | 位置 | 状态 |
|---|---|---|
| 第一层 · 全局 MCP 服务器列表 | 设置 → MCP → termux | ✅ 已完成（截图 2）|
| **第二层 · 助手绑定** | **长按助手 → 编辑 → MCP 服务器** | ❌ **未勾选 —— 缺口在这里** |

RikkaHub 官方文档原文：

> 将服务器添加到 Rikka 的全局列表**并不会自动将其暴露给你的助手**。你必须为每个助手单独启用。
> 只有在此处勾选的服务器的工具才会出现在助手的工具调用中。

这解释了截图 1 的现象：AI 思考里说「no tools listed」—— 模型确实没收到工具定义，
因为当前助手（Assistant）没有绑定 `termux` 这个 MCP 服务器。

---

## 修复步骤

### 1. 给助手绑定 MCP（关键，必做）

1. 回到 RikkaHub **主屏幕**（助手列表）
2. **长按**你正在用的那个助手 → 或点助手名旁的**编辑（铅笔图标）**
3. 向下滚动到「**MCP 服务器**」区块
4. 找到全局列表里的 `termux`，**把它 toggle 打开**
5. 保存

> 只要当前对话用的助手没绑定，工具就永远不会进入它的工具列表。

### 2. 确认 MCP 服务器配置正确

进入 **设置 → MCP → termux** 编辑，确认：

| 项 | 值 |
|---|---|
| 传输类型 | **Streamable HTTP**（不是 SSE）|
| URL | `http://192.168.110.13:8081/mcp` |
| headers | `Authorization` = `Bearer adbmcp-K60Pro-2026-fixed-8f3a9c2e` |

> ⚠️ 传输类型若选成 SSE，工具列表会拉不到 —— 我们的服务端只有 `/mcp` 端点，
> 实测 `/sse` 返回 401（端点不存在）。

### 3. 新建对话再测

助手配置在会话创建时注入工具列表，**改完请新建一个对话**，当前会话不会自动刷新。

---

## 可选：直接导入 JSON

RikkaHub 支持 **设置 → MCP → 导入图标**，粘贴以下内容：

```json
{
  "type": "streamableHttp",
  "commonOptions": {
    "name": "termux",
    "enable": true,
    "headers": [
      ["Authorization", "Bearer adbmcp-K60Pro-2026-fixed-8f3a9c2e"]
    ]
  },
  "url": "http://192.168.110.13:8081/mcp"
}
```

> 导入后仍需**在助手设置里为该助手单独勾选**这一步。

---

## 安全建议：给写操作加「需要审批」

在 **设置 → MCP → termux → 工具** 里（就是截图 2 那一页），
建议给这些工具开启「**需要审批**」开关：

| 工具 | 风险 |
|---|---|
| `run` | ⚠️ **执行任意 shell** —— 建议开启审批 |
| `write` / `delete` | ⚠️ 改文件 / 删文件 |
| `process_kill` | 杀进程 |
| `sms_send` | 发短信 |
| `camera_photo` | 拍照 |

只读类（`read` / `ls` / `search` / `system_info` / `battery` 等）无需审批。

---

## 服务端实测状态（2026-11-05）

| 项 | 结果 |
|---|---|
| MCP 进程 | ✅ 监听 `0.0.0.0:8081` |
| 握手 `initialize` | ✅ 200 `termux-native-mcp` v0.15.0 |
| `tools/list` | ✅ 84 个工具 |
| `tools/call` → `run` → `adb devices` | ✅ 返回 3 台设备 |
| 设备 `.39` / `.133` | ✅ 均返回 `wise` |
| 鉴权 固定/旧/无 token | ✅ 200 / 401 / 401 |
| `/mcp` 端点 | ✅ 200 |
| `/sse` 端点 | ❌ 401（不存在，故传输类型必须选 Streamable HTTP）|

模型侧也已验证：`deepseek-flash` 直连 API 带 `tools` 参数时返回
`finish_reason: tool_calls`，**模型能力本身没问题**。

## 环境

| 项 | 值 |
|---|---|
| RikkaHub | `me.rerere.rikkahub` v3.1.1 (versionCode 194) |
| 系统 | Android 17 |
| MCP 服务端 | Termux `termux-native-mcp` v0.15.0 |
| Token | `adbmcp-K60Pro-2026-fixed-8f3a9c2e`（固定不变）|

---

## 相关文档

| 文档 | 内容 |
|---|---|
| [快速开始](快速开始.md) | 命令与机制完整说明 |
| [设备接入](设备接入.md) | 设备识别与故障排查 |
| [迁移指南](迁移指南.md) | 换新手机部署 |
| [RikkaHub 接入](RikkaHub-接入.md) | RikkaHub 两层配置 |
| [RikkaHub 对话使用](RikkaHub-对话使用.md) | 实测提问示例 |
| [RikkaHub 工具调用排查](RikkaHub-工具调用排查.md) | 「模型未开启工具调用」根因 |
| [诊断记录](诊断记录-工具不可用.md) | 完整排查过程 |
