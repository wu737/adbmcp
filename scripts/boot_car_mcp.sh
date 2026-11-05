#!/data/data/com.termux/files/usr/bin/bash
# Termux 开机自启入口
# 由 Termux:Boot 或 (rish) 广播触发, 拉起车机 MCP 守护
exec bash "$HOME/mcp-servers/car/car_watchdog.sh" run
