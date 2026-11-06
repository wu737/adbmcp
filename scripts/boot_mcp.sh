#!/data/data/com.termux/files/usr/bin/bash
# Termux 开机自启入口
# 由 Termux:Boot 或 (rish) 广播触发, 拉起 adbmcp 守护
exec bash "$HOME/mcp-servers/adbmcp/device_watchdog.sh" run
