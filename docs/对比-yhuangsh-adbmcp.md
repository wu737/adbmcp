# 与 yhuangsh/adbmcp 的区别

> 对比对象：https://github.com/yhuangsh/adbmcp （npm 包 `@yhuangsh/adbmcp` v0.7.0）
> 对比时间：2026-11-05

## 结论

**同��不同物。** 名字相同纯属巧合，两者解决的是不同问题，可以并存。

| | yhuangsh/adbmcp | wu737/adbmcp（本项目）|
|---|---|---|
| 一句话 | 把 adb 封装成 **37 个 MCP 工具** | 让**手机**变成 MCP 服务端，专门操作**设备** |
| 宿主 | PC / 任意装 Node≥20 的机器 | **手机 Termux**（自带 adb 与 MCP 服务端）|
| 目标设备 | **Android 手机** | **Buildroot Linux 设备** |
| 实现 | TypeScript 1300+ 行自研 | Bash，复用 `termux-mcp` v0.15.0（84 工具）|
| 传输 | stdio 默认，`--http` 可选 | Streamable HTTP（必需）|
| 成熟度 | npm 发布 + vitest 测试 + CI + spec 驱动 | 脚本级，无测试无 CI |
| 特色能力 | Android 深度集成（uiautomator/pm/am/logcat/input/权限管理）| 设备运维（纯 shell）+ 手机即网关 |
| 安全策略 | 设备白名单 + shell 黑名单 + DNS-rebinding 防护 | Bearer token + 服务端危险命令检测 |

---

## 关键实证：对方的 Android 工具在设备上全部失效

我在自己的设备（`192.168.110.39`，Buildroot Linux）上实测了对方项目依赖的命令：

```
getprop ro.product.model      => /bin/sh: getprop: not found
pm list packages              => /bin/sh: pm: not found
dumpsys battery               => /bin/sh: dumpsys: not found
uiautomator dump ...          => /bin/sh: uiautomator: not found
input tap 100 100             => /bin/sh: input: not found
screencap -p                  => /bin/sh: screencap: not found
cmd package list              => /bin/sh: cmd: not found
```

**对方 37 个工具中依赖 Android 运行时的部分（`get_device_info` / `list_packages` /
`dumpsys_query` / `get_ui_hierarchy` / `tap` / `swipe` / `type_text` / `key_event` /
`screenshot` / `logcat_*` / `start_activity` / `force_stop_app` / 权限类工具），
在我的设备上全部无法工作。**

原因：设备是 Buildroot Linux，不带 Android framework。

---

## 能力重叠的部分

对方的 `shell` 工具（`adb shell` 封装）+ `connect` 工具，**确实能操作我的设备** ——
`allowedPrefixes` 默认不限制，`allowedDevices` 默认允许所有设备。

所以单看「用 AI 操作设备」这个需求，两边都能做。区别在**部署形态**：

| | yhuangsh/adbmcp | 本项目 |
|---|---|---|
| 需要 PC 在场 | ✅ 必须（除非在 Termux 里装 Node.js 跑它）| ❌ 不需要 |
| 设备可达性 | PC 必须在设备网段 | 手机连设备热点即可 |
| 现场部署 | 拆笔记本、装 Node、连网、启动进程 | 手机上敲 `adbmcp` |

这也是最初我选手机宿主的核心原因：**设备通常只开热点给手机，不给 PC 接入。**

---

## 各自的独特价值

### yhuangsh/adbmcp 更强的地方
- **Android 深度集成** —— uiautomator 层级树、logcat 流式订阅、dumpsys 查询、
  APK 安装卸载、运行时权限管理、CJK 输入（`ADB_INPUT_B64` 广播绕过 `input text` 的 ASCII 限制）
- **工程质量** —— vitest 测试（约 160 KB 测试代码）、GitHub Actions CI、
  ISSUE_TEMPLATE、CONTRIBUTING、spec-driven 开发流程
- **安全设计** —— 设备白名单、shell 模式黑名单（阻止 `su`/`mkfs`/`rm -rf /`/pipe-to-shell）、
  push 路径根限制、DNS-rebinding 防护、常数时间 token 比对
- **工程化分发** —— npm 包，`npx` 即用
- **协议完整度** —— 同时提供 tools / resources（`adb://devices`）/ prompts

### 本项目更强的地方
- **设备场景** —— 目标就是 Buildroot 设备，实测覆盖
- **手机即宿主** —— 不需要 PC，设备热点直连
- **零 Node 依赖** —— Termux + Python + Bash 即可，Termux:Boot 开机自启
- **通用工具面** —— 84 个工具含 shell / 文件读写 / 截图 / 通知 / 短信 / 电池 等，
  不止 adb
- **固定 Token** —— 跨设备迁移时 AI 客户端配置不用改
- **轻量** —— 整个项目 18 个文件 / 2638 行，克隆即读

---

## 为什么不合并 / 不改名

两者面向不同目标设备，工具集几乎不重叠（实测已验证）。合并会产生一个臃肿且定位模糊的项目。

**建议保留现名。** 两个项目在 GitHub 上无关联，README 里加一段说明即可避免读者误以为是 fork
或竞品。

---

## 互相可借鉴的点（如果未来要增强本项目）

1. **设备白名单** —— 本项目目前 `run` 工具可访问 Termux 内任意路径，
   借鉴 `ADBMCP_ALLOWED_DEVICES` + `ADBMCP_SHELL_ALLOWED_PREFIXES` 能显著收窄攻击面
2. **测试** —— 本项目无自动化测试，可用 `bats` 或 shellcheck 建最小 CI
3. **错误类型化** —— 对方的 `NO_DEVICE` / `DEVICE_OFFLINE` / `MULTIPLE_DEVICES`
   等类型化错误，比裸字符串更利于 AI 判断下一步
4. **shell 黑名单** —— 本项目目前只检测「危险命令」并要求确认，
   可借鉴对方的模式黑名单（阻止 `rm -rf /`、`su`、pipe-to-shell）

---

## 参考

- yhuangsh/adbmcp：https://github.com/yhuangsh/adbmcp
  · npm: `@yhuangsh/adbmcp` · MIT · 作者 Yong Huang
- 本项目：https://github.com/wu737/adbmcp · MIT
