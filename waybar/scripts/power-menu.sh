#!/usr/bin/env bash
# 水墨电源菜单 — wofi dmenu, English labels
# Esc 取消；回车执行所选项

set -euo pipefail

STYLE="$HOME/.config/wofi/themes/power.css"

chosen=$(printf '󰌾  Lock\n󰍃  Logout\n󰜉  Reboot\n󰐥  Shutdown' | wofi --dmenu \
    --prompt "Power" \
    --style "$STYLE" \
    --width 240 \
    --height 265 \
    --cache-file /dev/null \
    --hide-scroll \
    --insensitive) || exit 0

case "$chosen" in
    *Lock)     "$HOME/.config/sway/scripts/random-lock.sh" ;;
    *Logout)   swaymsg exit ;;
    *Reboot)   systemctl reboot ;;
    *Shutdown) systemctl poweroff ;;
esac
