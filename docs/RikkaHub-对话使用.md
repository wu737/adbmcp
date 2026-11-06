# RikkaHub 对话界面使用 adbmcp —— 实测指南

> 所有结果均为 2026-11-05 在真实设备上实测得出（模拟 RikkaHub 的 MCP 调用链）。

## 前置条件（缺一不可）

| # | 检查项 | 状态 |
|---|---|---|
| 1 | Termux MCP 服务运行中（`adbmcp` 已启动）| ✅ |
| 2 | RikkaHub 设置 → MCP → termux **已连接** | ✅ |
| 3 | 传输类型 = **Streamable HTTP**，URL = `http://192.168.110.13:8081/mcp` | ✅ |
| 4 | headers 含 `Authorization: Bearer adbmcp-K60Pro-2026-fixed-8f3a9c2e` | ✅ |
| 5 | **助手已绑定 termux**（长按助手 → 编辑 → MCP 服务器 → 勾选）| ⚠️ **必须做** |
| 6 | **新建对话**（工具列表在会话创建时注入）| ⚠️ **必须做** |

---

## 怎么用

### 基本形态

在 RikkaHub 对话框里**直接用自然语言说**，AI 会自己判断要不要调工具：

```
现在有几台设备在线？分别是什么系统？
```

AI 会调 `run` → `adb devices` → 拿到设备列表。

### 实测可用的提问示例

#### 设备运维
```
现在 adb 里能连到哪些设备？帮我看看每台的型号和系统版本
设备 192.168.110.39 现在跑了哪些进程？CPU 占用最高的是哪个
列出设备 /customer 目录下都有什么文件
设备的系统版本是什么？内核是什么？
设备运行了多久了？
```

#### 工具选择建议（AI 需要明确点）
```
用 system_info 工具看一下手机的 CPU 和内存
用 battery 工具查一下电量
列出 ~/mcp-servers/adbmcp 目录下的文件
搜索 ~/ 下所有 .txt 文件
```

> 涉及**只读**的工具（`system_info`/`battery`/`ls`/`read`/`search`）直接指定工具名，
> AI 会更准确地调用。

#### 文件操作
```
在 Termux home 下创建一个 test.txt，写入"hello"
读一下 ~/rikka_demo.txt 的内容
把结果写到 /sdcard/Download/output.txt
```

#### 手机自身
```
我现在这台手机的型号和 Android 版本是什么？
```

---

## 实测结果（真实输出）

| 提问意图 | 实际调用 | 返回 |
|---|---|---|
| 有哪些设备在线 | `adb devices` | `.39` / `.133` / `emulator-5554` |
| 设备系统版本 | `adb -s .39 shell cat /etc/os-release` | Buildroot 2021.11-rc2 |
| 设备应用目录 | `adb -s .39 shell ls /customer` | `x4_gui` `run_gui.sh` `voice.mp3` `dui` `htop` ... |
| 设备运行时长 | `adb -s .39 shell cat /proc/uptime` | 941743 秒（约 10.9 天）|
| 手机型号 | `getprop ro.product.model` | 22127RK46C |
| 硬件状态 | `system_info` | CPU 800%、内存 11.2G/7.9G、42°C |

---

## 三个必须知道的机制

### 1. 危险命令会被服务端拦截

```
High-risk command detected (confirmation recommended): rm -rf ...
Re-invoke with `confirmed: true` to proceed, or approve this exact command on the device with the approve tool first.
```

AI 会收到这个提示，然后**重新带确认参数**调用。在 RikkaHub 里，
如果你给工具开了「需要审批」，你会看到**确认弹窗** —— 这是好事，说明防护生效。

### 2. 路径权限边界（实测踩过的坑）

| 路径 | 可写？ | 说明 |
|---|---|---|
| `/data/data/com.termux/files/home/` | ✅ | Termux 工作区，AI 的主要操作区 |
| `/sdcard/Download/` | ✅ | 跨 App 可见，文件管理器能看到 |
| `/data/local/tmp/` | ❌ | `Permission denied` — 属 shell 用户，非 Termux |
| `/data/data/com.tencent.workbuddy.app/` | ❌ | Android 沙箱隔离 |

> 让 AI 在 Termux home 或 `/sdcard` 下工作，别指 `/data/local/tmp`。

### 3. 删除是软删除

`delete` 工具不会真删，会移到 `~/termuxGPT/trash/<时间戳>/`，可恢复。
`write` 覆盖前会在 `~/termuxGPT/snapshots/` 留快照。

---

## 安全配置建议

在 **设置 → MCP → termux → 工具** 给这些开「需要审批」：

| 工具 | 风险 | 建议 |
|---|---|---|
| `run` | 执行任意 shell，**能操作设备、能读写手机文件** | ⚠️ 必开 |
| `write` / `delete` | 改文件 | ⚠️ 建议开 |
| `process_kill` | 杀进程 | ⚠️ 建议开 |
| `sms_send` | 发短信 | ⚠️ 必开 |
| `camera_photo` | 拍照 | ⚠️ 建议开 |
| `read` / `ls` / `search` / `system_info` / `battery` | 只读 | 不用 |

> 84 个工具全开会让上下文膨胀、模型选错工具的概率上升。
> 实际常用的其实只有 `run` + `system_info` + `read`/`ls`/`search`/`write` 几个。

---

## 常见问题

### 报「工具不可用」
→ 助手没绑定 MCP，或当前会话是绑定之前建的。**新建对话**。

### AI 说「我没有 MCP 工具」
→ 同上。工具列表在会话初始化时注入。

### MCP 显示「错误」状态
→ 检查 Termux 里 MCP 是否还活着（`adbmcp status`），
或传输类型是否误选 SSE（必须选 Streamable HTTP）。

### AI 调了 run 但输出为空
→ `run` 对**复合命令**（含 `;`）可能不返回完整输出。
拆成单条命令分别调用更稳。

### 连不上
→ 确认手机与 MCP 服务在同一局域网；IP 变化时用 `adbmcp scan` 重扫并更新 URL。

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
