#!/bin/sh

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/sway-lock/landscapes"
fallback_image="$HOME/Pictures/Wallpapers/forest.png"

# Do not start a second lock process when a sleep event overlaps the idle timer.
if pgrep -u "$(id -u)" -x swaylock >/dev/null; then
    exit 0
fi

pick_image() {
    find "$1" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        2>/dev/null | shuf -n 1
}

image="$(pick_image "$cache_dir")"
if [ -z "$image" ] && [ -f "$fallback_image" ]; then
    image="$fallback_image"
fi

if [ -n "$image" ]; then
    exec swaylock -f --image "$image" --scaling fill
else
    exec swaylock -f --color 111111
fi
