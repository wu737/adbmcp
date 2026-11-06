# adbmcp

**用手机当 AI 的设备遥控器** —— 把 Android 手机变成 MCP 服务器，让 Claude / Cursor / RikkaHub / WorkBuddy 等任意 AI 客户端通过自然语言直接操作你的设备。

```
你在 RikkaHub 里说：「现在有几台设备在线？分别什么系统？」
                    ↓
              AI 调用 MCP 工具
                    ↓
        手机 Termux (termux-native-mcp :8081)
                    ↓  adb shell
         设备 .39 / .133 (Buildroot Linux)
```

---

## 为什么是手机 Termux 方案

早期方案是让 PC 跑 `mobile-mcp`（基于无障碍树的 Android 自动化）。实测发现设备是 **Buildroot Linux**（无 `getprop`、无 `wm`），无障碍树那套**完全无效**，只有纯 `adb shell` 路线能操作。

| 维度 | 手机 Termux 宿主角 | PC 端 mobile-mcp |
|---|---|---|
| 设备兼容性 | ✅ 纯 adb shell | ❌ 依赖无障碍树，非 Android 设备无效 |
| 设备可达性 | ✅ 手机连设备热点即可 | ❌ PC 必须与设备同网段 |
| 现场部署 | ✅ 手机 + 设备，无需 PC | ❌ 需 PC 参与 |
| 断线恢复 | ✅ 双端守护自动重连 | ❌ 仅单端 |

---

## 特性

- **一键启动** —— Termux 里敲 `adbmcp` 即可，只启动 MCP 并输出接入信息
- **不打扰设备** —— 启动时不会主动连接任何设备；守护等设备接入后才开始工作
- **局域网直连** —— 任意 AI 客户端通过 `http://<手机IP>:8081/mcp` 接入，无需 PC 中转
- **固定 Token** —— 跨设备迁移时 AI 客户端配置无需改动
- **延后守护** —— 后台守护先等待设备接入，检测到设备后才开始维持连接
- **双端守护** —— 手机端守护 MCP 进程与设备连接，PC 端守护 adb 隧道，断线自动自愈
- **84 个工具** —— 基于 `termux-mcp` v0.15.0，含 shell 执行、文件读写、截图、通知等
- **危险命令拦截** —— 服务端识别高危命令并要求显式确认

---

## 快速开始

### 1. 手机装 Termux

从 **F-Droid** 或 GitHub 安装（**不要用 Play 商店的旧版**）。首次打开等它初始化完。

### 2. 部署

把 `install/install-adbmcp.sh` 与 `scripts/` 下的文件传到手机 Termux（`~/adbmcp/`），然后：

```bash
cd ~/adbmcp
bash install/install-adbmcp.sh
```

脚本自动完成：装依赖（`android-tools` + `termux-mcp`）→ 部署脚本 → 建设备清单 → 启动自检 → 扫描网段找可连接设备。

### 3. 填设备清单

编辑 `~/mcp-servers/adbmcp/devices.txt`：

```
192.168.43.1:5555    设备热点网关
192.168.110.39:5555  设备 - Buildroot/wise
```

```bash
adbmcp restart
```

### 4. 接入 AI 客户端

`adbmcp config` 直接打印可粘贴的配置：

```json
{
  "mcpServers": {
    "adbmcp": {
      "type": "streamableHttp",
      "url": "http://192.168.110.13:8081/mcp",
      "timeout": 120000,
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

RikkaHub 专用格式见 [`examples/rikkahub-mcp-import.json`](examples/rikkahub-mcp-import.json)。

### 5. 用起来

在 AI 对话框里直接说人话，AI 会自己判断要不要调工具：

```
现在 adb 里能连到哪些设备？分别是什么系统？
设备 192.168.110.39 上有哪些应用目录？
用 system_info 看一下手机 CPU 和内存
```

---

## 命令一览

| 命令 | 作用 |
|---|---|
| `adbmcp` | 启动 + 打印接入信息（默认） |
| `adbmcp status` | 查看 MCP / 守护 / adb 设备状态 |
| `adbmcp config` | 打印可粘贴的 AI 客户端配置 |
| `adbmcp connect` | 手动连接设备清单里的设备 |
| `adbmcp token` | 显示当前固定 token |
| `adbmcp scan [网段]` | 扫描网段找出所有开 5555 的设备 |
| `adbmcp lan` / `adbmcp local` | 切换局域网模式（+token）/ 仅本机模式（免鉴权） |
| `adbmcp restart` / `stop` | 重启 / 停止 |

> **自动打补丁** —— `termux-mcp` v0.15.0 未实现 MCP 规范要求的 `notifications/*`
> 通知方法，客户端（尤其 RikkaHub）会因此报「Error while sending message」。
> `adbmcp` 每次启动都会自动检查并打上补丁（见
> [`scripts/patch_cancelled.py`](scripts/patch_cancelled.py)），pip 升级后同样自动重打。

---

## 依赖

| 依赖 | 版本 | 安装方式 |
|---|---|---|
| Termux | ≥ 0.118 | F-Droid / GitHub |
| android-tools (adb) | 37.0.0 | `pkg install android-tools` |
| python | 3.14.x | `pkg install python` |
| [termux-mcp](https://pypi.org/project/termux-mcp/) | 0.15.0 | `pip install termux-mcp==0.15.0` |
| Termux:Boot | — | 单独 APK（可选，用于开机自启） |

---

## 目录结构

```
install/install-adbmcp.sh   一键安装
scripts/
  adbmcp                    主脚本（PATH 内，直接敲 adbmcp）
  device_watchdog.sh        守护：MCP 进程 + 设备连接
  device_setup.sh           手动连接设备
  scan_device.py            网段扫描
  boot_mcp.sh               开机自启入口
  patch_cancelled.py        上游补丁（补齐 notifications/* 方法）
docs/                       详细文档
examples/                   各客户端配置示例
```

部署到手机后：

```
~/bin/adbmcp                   ← 主脚本
~/mcp-servers/adbmcp/           ← 设备清单、日志、配置
~/.termux/boot/boot_mcp.sh     ← 开机自启
```

---

## 文档

| 文档 | 内容 |
|---|---|
| [快速开始](docs/快速开始.md) | 完整命令与机制说明 |
| [设备接入](docs/设备接入.md) | 设备识别、协议限制、故障排查 |
| [RikkaHub 接入](docs/RikkaHub-接入.md) | RikkaHub 两层配置（全局 MCP + 助手绑定）|
| [RikkaHub 对话使用](docs/RikkaHub-对话使用.md) | 实测可用的提问示例、路径权限边界 |
| [RikkaHub 工具调用排查](docs/RikkaHub-工具调用排查.md) | 「当前模型未开启工具调用」根因（源码级）|
| [迁移指南](docs/迁移指南.md) | 换新手机部署 |
| [诊断记录](docs/诊断记录-工具不可用.md) | 完整排查过程留档 |
| [对比 yhuangsh/adbmcp](docs/对比-yhuangsh-adbmcp.md) | 同名项目的区别（宿主位置 / 目标设备不同）|
| [排障 notifications/cancelled](docs/排障-notifications-cancelled.md) | RikkaHub 报「Error while sending message」的根因 |

---

## 关于同名项目

有一个也叫 `adbmcp` 的项目：[yhuangsh/adbmcp](https://github.com/yhuangsh/adbmcp)（npm 包 `@yhuangsh/adbmcp`）。
**两者不是同一个东西，名字相同纯属巧合**，可以并存：

| | yhuangsh/adbmcp | 本项目 |
|---|---|---|
| 宿主 | PC / 任意装 Node≥20 的机器 | **手机 Termux** |
| 目标设备 | **Android 手机** | **Buildroot Linux 设备** |
| 实现 | TypeScript 1300+ 行自研，37 工具 | Bash 复用 `termux-mcp`，84 工具 |
| 特色 | Android 深度集成（uiautomator/logcat/pm/input）、npm 分发、完整测试与 CI | 设备运维、手机即网关、零 Node 依赖、Token 固定 |

实测证据：对方的 Android 专属工具在设备上全部 `not found`（设备是 Buildroot，无 Android framework）。
详见 [对比文档](docs/对比-yhuangsh-adbmcp.md)。

---

## 安全须知

> ⚠️ **本项目默认使用固定 Token，且仓库中公开了默认值。**

- 服务绑定 `0.0.0.0` 时，**服务端强制要求 Token**（`termux-native-mcp` 的 `_check_startup_guards` 逻辑），无 Token 会直接拒绝启动
- 完全免鉴权只能绑 `127.0.0.1`（`adbmcp local`），那样局域网无法直连
- **默认 Token 是公开的**。若你的网络环境不完全可信，请改用随机值：
  ```bash
  export ADBMCP_TOKEN=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
  adbmcp restart
  ```
  然后同步更新所有 AI 客户端配置

建议在 **RikkaHub / Claude 等客户端侧**给高危工具开启「需要审批」：

| 工具 | 风险 |
|---|---|
| `run` | ⚠️ 执行任意 shell —— 能操作设备、读写手机文件 |
| `write` / `delete` | 改 / 删文件（软删除，落在 `~/termuxGPT/trash/`）|
| `process_kill` | 杀进程 |
| `sms_send` | 发短信 |
| `camera_photo` | 拍照 |

只读类（`read` / `ls` / `search` / `system_info` / `battery`）无需审批。

---

## 已知限制

- **Termux 被杀 → MCP 进程消失。** 守护能扛住「Termux 存活但 MCP 挂掉」，Termux 整体被杀需重开 App（装 Termux:Boot 可自动拉起）
- **无线调试会因息屏断开。** 实测手机多次转 `offline`。对策：`termux-wake-lock`、关闭电池优化、或改用 USB
- **Termux 无 `ip` 命令权限**，`/proc/net/fib_trie` 也被 Android 11+ 收紧 → IP 探测改用 Python socket
- **Termux 版 adb 无 `adb mdns`** → 设备 IP 靠手填或 `adbmcp scan` 扫描
- **`run` 对含 `;` 的复合命令可能返回空** → 拆成单条分别调用

---

## License

MIT
