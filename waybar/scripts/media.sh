#!/usr/bin/env bash
# 音乐模块 — 定宽 + 滚动（marquee）
# 常驻进程模式：waybar 配置里去掉 interval，脚本自己循环输出 JSON
# 宽度按显示列计算：汉字 2 列，ASCII 1 列；MAX_W=10 即 5 个汉字宽

MAX_W=10          # 显示窗口宽度（列）
SEP="  ·  "       # 循环衔接分隔符
TICK=0.5          # 滚动步进间隔（秒）
IDLE_TICK=2       # 无播放时的轮询间隔（秒）

# 单字符显示宽度：多字节（汉字等）算 2 列，ASCII 算 1 列
char_w() {
    local LC_ALL=C
    (( ${#1} > 1 )) && echo 2 || echo 1
}

# 字符串总显示宽度
str_w() {
    local s=$1 w=0 ch
    while [ -n "$s" ]; do
        ch=${s:0:1}; s=${s:1}
        (( w += $(char_w "$ch") ))
    done
    echo "$w"
}

# 从 $1 的第 $2 个字符开始，取不超过 MAX_W 列的窗口；不足则补空格对齐
window_at() {
    local s=$1 start=$2 out="" w=0 ch cw i=0
    # 跳到起始字符
    s=${s:start}
    while [ -n "$s" ]; do
        ch=${s:0:1}; s=${s:1}
        cw=$(char_w "$ch")
        (( w + cw > MAX_W )) && break
        out+=$ch
        (( w += cw ))
    done
    # 汉字边界可能差 1 列，补空格保持定宽
    while (( w < MAX_W )); do out+=" "; (( w++ )); done
    printf '%s' "$out"
}

emit() {
    jq -nc --arg text "$1" --arg tooltip "$2" --arg class "$3" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

prev_title=""
offset=0

while :; do
    title=$(playerctl metadata title 2>/dev/null || true)
    status=$(playerctl status 2>/dev/null || true)

    if [ -z "$title" ]; then
        emit "󰝛 暂无播放" "没有正在播放的媒体" "media-idle"
        prev_title=""
        sleep "$IDLE_TICK"
        continue
    fi

    # 标题变化时重置滚动
    if [ "$title" != "$prev_title" ]; then
        prev_title=$title
        offset=0
    fi

    icon=""
    [ "$status" = "Paused" ] && icon=""

    if (( $(str_w "$title") <= MAX_W )); then
        # 放得下：静态显示，右侧补空格保持定宽
        pad=$title
        w=$(str_w "$pad")
        while (( w < MAX_W )); do pad+=" "; (( w++ )); done
        emit "$icon $pad" "$title" "media"
        sleep "$IDLE_TICK"
        continue
    fi

    # 放不下：循环滚动（标题 + 分隔符 首尾相接）
    loop="${title}${SEP}"
    len=${#loop}                       # 字符数（非列数）
    (( offset >= len )) && offset=0

    # 窗口可能跨越接缝，拼一份双倍字符串再取
    frame=$(window_at "${loop}${loop}" "$offset")
    emit "$icon $frame" "$title" "media"

    if [ "$status" = "Playing" ]; then
        (( offset++ ))
        sleep "$TICK"
    else
        # 暂停时冻结画面，慢速轮询状态
        sleep "$IDLE_TICK"
    fi
done
