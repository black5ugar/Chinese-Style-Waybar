#!/usr/bin/env bash
# 音乐模块 — 固定显示宽度，避免标题变长导致 bar 抖动
# 宽度按显示列计算：汉字算 2 列，ASCII 算 1 列
# MAX_W=10 即 5 个中文字符（或 10 个英文字符）

MAX_W=10

title=$(playerctl metadata title 2>/dev/null || true)
status=$(playerctl status 2>/dev/null || true)

if [ -z "$title" ]; then
    jq -nc '{text: " 暂无播放", tooltip: "没有正在播放的媒体", class: "media-idle"}'
    exit 0
fi

# 单字节(ASCII)算 1 列，多字节(汉字等)算 2 列
cw_of() {
    local LC_ALL=C
    if (( ${#1} > 1 )); then cw=2; else cw=1; fi
}

# 按显示宽度截断（bash 在 UTF-8 locale 下 ${s:0:1} 按字符取）
out=""
w=0
s=$title
while [ -n "$s" ]; do
    ch=${s:0:1}
    s=${s:1}
    cw_of "$ch"
    if (( w + cw > MAX_W )); then
        out+="…"
        break
    fi
    out+=$ch
    (( w += cw )) || true
done

icon=""
[ "$status" = "Paused" ] && icon=""

jq -nc --arg text "$icon $out" --arg tooltip "$title" \
    '{text: $text, tooltip: $tooltip, class: "media"}'
