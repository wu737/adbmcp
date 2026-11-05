# adbmcp

**Turn your Android phone into a remote control for your car head units** — expose it as an MCP server so Claude, Cursor, RikkaHub, WorkBuddy, or any MCP-capable AI client can operate your vehicle via natural language.

```
You say in RikkaHub: "Which car units are online right now? What OS do they run?"
                    ↓
              AI invokes an MCP tool
                    ↓
        Phone Termux (termux-native-mcp :8081)
                    ↓  adb shell
         Car units .39 / .133 (Buildroot Linux)
```

---

## Why the phone-as-host design

The first attempt ran `mobile-mcp` on the PC (accessibility-tree based Android automation). Testing showed the car head units run **Buildroot Linux** — no `getprop`, no `wm` — so the accessibility approach was **completely non-functional**. Only a pure `adb shell` route works.

| Dimension | Phone Termux host | PC-side mobile-mcp |
|---|---|---|
| Car compatibility | ✅ pure adb shell | ❌ needs accessibility tree; non-Android head units fail |
| Reachability | ✅ phone joins the car's hotspot | ❌ PC must share the car's subnet |
| Field deployment | ✅ phone + car, no PC | ❌ PC required |
| Recovery | ✅ watchdog on both ends | ❌ single point |

---

## Features

- **One-command launch** — type `adbmcp` in Termux; MCP server and car connections come up together
- **LAN direct access** — any AI client connects straight to `http://<phone-IP>:8081/mcp`, no PC relay
- **Fixed token** — AI client configs survive device migrations unchanged
- **Dual-end watchdog** — phone side guards the MCP process and car connections, PC side guards the adb tunnel; both self-heal
- **84 tools** — powered by `termux-mcp` v0.15.0: shell execution, file I/O, screenshot, notifications, and more
- **Dangerous-command gating** — the server flags high-risk commands and requires explicit confirmation

---

## Quick start

### 1. Install Termux on the phone

Use **F-Droid** or GitHub (do **not** use the outdated Play Store build). Let it finish initializing on first launch.

### 2. Deploy

Copy `install/install-adbmcp.sh` and everything under `scripts/` into `~/adbmcp/` on the phone, then:

```bash
cd ~/adbmcp
bash install/install-adbmcp.sh
```

The script installs dependencies (`android-tools` + `termux-mcp`), deploys the scripts, creates the car manifest, starts and self-checks the server, and scans the subnet for adb devices.

### 3. Fill in the car manifest

Edit `~/mcp-servers/car/cars.txt`:

```
192.168.43.1:5555    car hotspot gateway
192.168.110.39:5555  head unit - Buildroot/wise
```

```bash
adbmcp restart
```

### 4. Connect your AI client

`adbmcp config` prints a ready-to-paste config:

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

See [`examples/rikkahub-mcp-import.json`](examples/rikkahub-mcp-import.json) for the RikkaHub-specific format.

### 5. Use it

Just talk to the AI in natural language — it decides when to call tools:

```
Which devices can adb reach right now, and what OS do they run?
What's in the application directory on 192.168.110.39?
Use system_info to check the phone's CPU and memory.
```

---

## Commands

| Command | Purpose |
|---|---|
| `adbmcp` | Start and print connection info (default) |
| `adbmcp status` | MCP / watchdog / adb device status |
| `adbmcp config` | Print a paste-ready client config |
| `adbmcp token` | Show the current fixed token |
| `adbmcp scan [subnet]` | Find every device with port 5555 open |
| `adbmcp lan` / `adbmcp local` | LAN mode (with token) / localhost-only (no auth) |
| `adbmcp restart` / `stop` | Restart / stop |

> **Automatic patch** — `termux-mcp` v0.15.0 does not implement the `notifications/*`
> methods required by the MCP spec, which makes clients (RikkaHub in particular)
> report "Error while sending message". `adbmcp` checks and applies the patch on
> every start (see [`scripts/patch_cancelled.py`](scripts/patch_cancelled.py)),
> including after a `pip upgrade`.

---

## Dependencies

| Dependency | Version | Install |
|---|---|---|
| Termux | ≥ 0.118 | F-Droid / GitHub |
| android-tools (adb) | 37.0.0 | `pkg install android-tools` |
| python | 3.14.x | `pkg install python` |
| [termux-mcp](https://pypi.org/project/termux-mcp/) | 0.15.0 | `pip install termux-mcp==0.15.0` |
| Termux:Boot | — | separate APK (optional, enables boot autostart) |

---

## Layout

```
install/install-adbmcp.sh   one-shot installer
scripts/
  adbmcp                    main script (on PATH, just type `adbmcp`)
  patch_cancelled.py        upstream patch (adds notifications/* handling)
  car_watchdog.sh           watchdog: MCP process + car connections
  boot_car_mcp.sh           boot autostart entry
  car_setup.sh              manual car connection helper
  scan_car.py               subnet scanner
docs/                       detailed documentation
examples/                   client config samples
```

After deployment on the phone:

```
~/bin/adbmcp                      ← main script
~/mcp-servers/car/               ← manifest, logs, generated config
~/.termux/boot/boot_car_mcp.sh    ← boot autostart
```

---

## Documentation

| Doc | Contents |
|---|---|
| [快速开始 (Chinese)](docs/快速开始.md) | Full command and mechanism reference |
| [车机接入 (Chinese)](docs/车机接入.md) | Car identification, protocol limits, troubleshooting |
| [迁移指南 (Chinese)](docs/迁移指南.md) | Deploying on a new phone |
| [RikkaHub 接入](docs/RikkaHub-接入.md) | RikkaHub's two-layer config (global MCP + assistant binding) |
| [RikkaHub 对话使用](docs/RikkaHub-对话使用.md) | Verified prompt examples, path permission boundaries |
| [RikkaHub 工具调用排查](docs/RikkaHub-工具调用排查.md) | Root cause of "model does not support tool calling" (source-level) |
| [诊断记录](docs/诊断记录-工具不可用.md) | Full troubleshooting log |
| [对比 yhuangsh/adbmcp](docs/对比-yhuangsh-adbmcp.md) | Differences from the same-named project |
| [Troubleshooting: notifications/cancelled](docs/排障-notifications-cancelled.md) | Root cause of RikkaHub's "Error while sending message" |

---

## About the same-named project

There is another project also called `adbmcp`: [yhuangsh/adbmcp](https://github.com/yhuangsh/adbmcp)
(npm package `@yhuangsh/adbmcp`). **These are different projects** — the shared name is a
coincidence, and they coexist fine:

| | yhuangsh/adbmcp | this project |
|---|---|---|
| Host | PC / any machine with Node ≥20 | **phone running Termux** |
| Target device | **Android phones** | **Buildroot Linux car head units** |
| Implementation | 1300+ lines of hand-written TypeScript, 37 tools | Bash on top of `termux-mcp`, 84 tools |
| Highlights | deep Android integration (uiautomator/logcat/pm/input), npm distribution, full test suite and CI | car-unit operations, phone-as-gateway, zero Node dependency, fixed token |

Measured evidence: the Android-specific tools on the other project all fail with `not found`
on a car head unit (Buildroot has no Android framework).
See the [comparison doc](docs/对比-yhuangsh-adbmcp.md).

---

## Security

> ⚠️ **This project ships a fixed default token, and that default is public in this repo.**

- When bound to `0.0.0.0`, the server **requires** a token — `termux-native-mcp`'s `_check_startup_guards` refuses to start without one
- A fully auth-free mode requires binding `127.0.0.1` (`adbmcp local`), which makes LAN access impossible
- **The default token is public.** If your network isn't fully trusted, generate a random one:
  ```bash
  export ADBMCP_TOKEN=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
  adbmcp restart
  ```
  Then update the token in every AI client config.

On the client side (RikkaHub / Claude / …), enable "requires approval" for high-risk tools:

| Tool | Risk |
|---|---|
| `run` | ⚠️ executes arbitrary shell — can operate car units and read/write phone files |
| `write` / `delete` | modify / remove files (soft delete into `~/termuxGPT/trash/`) |
| `process_kill` | kill processes |
| `sms_send` | send SMS |
| `camera_photo` | take photos |

Read-only tools (`read` / `ls` / `search` / `system_info` / `battery`) need no approval.

---

## Known limitations

- **Killing Termux kills the MCP process.** The watchdog handles "Termux alive but MCP dead"; a fully killed Termux needs the app reopened (Termux:Boot automates this).
- **Wireless debugging drops when the screen sleeps.** The phone was observed flipping to `offline` repeatedly. Workarounds: `termux-wake-lock`, disable battery optimization, or use USB.
- **No `ip` command permission in Termux**, and `/proc/net/fib_trie` is restricted on Android 11+ → IP detection falls back to a Python socket.
- **The Termux adb build has no `adb mdns`** → car IPs must be entered manually or found via `adbmcp scan`.
- **`run` may return empty output for compound commands containing `;`** → issue them separately.

---

## License

MIT
