#!/bin/sh

watcher='org.kde.StatusNotifierWatcher'
object_path='/StatusNotifierWatcher'
interface='org.kde.StatusNotifierWatcher'

# QQ Music keeps its StatusNotifierItem bus name after some tray hosts reload,
# but older Electron builds do not always register it with the new watcher.
busctl --user list --no-legend 2>/dev/null \
    | awk '$1 ~ /^org\.kde\.StatusNotifierItem-/ && tolower($3) == "qqmusic" { print $1 }' \
    | while IFS= read -r service; do
        busctl --user call \
            "$watcher" "$object_path" "$interface" \
            RegisterStatusNotifierItem s "$service" \
            >/dev/null 2>&1 || true
    done
