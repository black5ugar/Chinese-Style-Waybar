#!/usr/bin/env bash
# wofi Wi-Fi 菜单 — 扫描 → 选择 → （需要时）输入密码 → 连接
# 自动探测后端：NetworkManager (nmcli) 或 iwd (iwctl)
# 用法：绑定到 waybar network 模块的 on-click

WOFI_LIST="wofi --dmenu -i -p Wi-Fi"
WOFI_PASS="wofi --dmenu --password -p 密码"

notify() { command -v notify-send >/dev/null && notify-send -a "Wi-Fi" "$1" "$2"; }
strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b\[?[0-9]*[hl]//g'; }

# 信号强度 → 图标（与 waybar network 模块同一套）
sig_icon() {
    local s=$1
    if   (( s >= 80 )); then printf '󰤨'
    elif (( s >= 60 )); then printf '󰤥'
    elif (( s >= 40 )); then printf '󰤢'
    elif (( s >= 20 )); then printf '󰤟'
    else                     printf '󰤯'
    fi
}

# ---------- 后端探测 ----------
if command -v nmcli >/dev/null 2>&1 && nmcli -t general status >/dev/null 2>&1; then
    BACKEND=nm
elif command -v iwctl >/dev/null 2>&1; then
    BACKEND=iwd
else
    notify "错误" "未找到 nmcli 或 iwctl"
    exit 1
fi

# 并行数组：菜单行 / SSID / 是否加密 / 是否已保存
lines=() ssids=() secured=() known=()

# ---------- NetworkManager ----------
scan_nm() {
    nmcli dev wifi rescan >/dev/null 2>&1
    sleep 1
    local saved
    saved=$(nmcli -t -f NAME con show 2>/dev/null)

    while IFS=: read -r inuse signal security ssid; do
        [ -z "$ssid" ] && continue
        local icon lock mark sec=0 kn=0
        icon=$(sig_icon "$signal")
        lock="  "
        if [ -n "$security" ] && [ "$security" != "--" ]; then
            lock="󰌾 "; sec=1
        fi
        mark="  "
        [ "$inuse" = "*" ] && mark=" "
        grep -Fxq "$ssid" <<< "$saved" && kn=1
        lines+=("$mark$icon $lock$ssid")
        ssids+=("$ssid"); secured+=("$sec"); known+=("$kn")
    done < <(nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list 2>/dev/null \
             | sort -t: -k2,2nr | awk -F: 'length($4) && !seen[$4]++')
}

connect_nm() {
    local ssid=$1 sec=$2 kn=$3 pass
    if [ "$kn" = 1 ]; then
        nmcli con up id "$ssid" >/dev/null 2>&1 && return 0
        # 已保存但连接失败（比如密码改了）→ 走重新输密码流程
        nmcli con delete id "$ssid" >/dev/null 2>&1
    fi
    if [ "$sec" = 1 ]; then
        pass=$($WOFI_PASS </dev/null) || return 1
        [ -z "$pass" ] && return 1
        nmcli dev wifi connect "$ssid" password "$pass" >/dev/null 2>&1
    else
        nmcli dev wifi connect "$ssid" >/dev/null 2>&1
    fi
}

# ---------- iwd ----------
IWDEV=""
scan_iwd() {
    IWDEV=$(iwctl device list | strip_ansi | awk '$1 ~ /^wl/ {print $1; exit}')
    if [ -z "$IWDEV" ]; then
        notify "错误" "未找到无线网卡"
        exit 1
    fi
    iwctl station "$IWDEV" scan >/dev/null 2>&1
    sleep 2
    local saved
    saved=$(iwctl known-networks list 2>/dev/null | strip_ansi | tail -n +5 | sed 's/^ *//; s/ \{2,\}.*//')

    # get-networks 输出：[>] SSID 安全类型 信号(*)，前 4 行是表头
    while IFS= read -r line; do
        [ -z "${line// /}" ] && continue
        local mark="  " sec=1 kn=0 stars sectype ssid icon
        case "$line" in '>'*) mark=" "; line=${line#>}; esac
        line=${line#"${line%%[![:space:]]*}"}          # 去左空白
        stars=$(awk '{print $NF}' <<< "$line")          # 末列：****
        sectype=$(awk '{print $(NF-1)}' <<< "$line")    # 次末列：psk/sae/open
        ssid=$(sed -E 's/[[:space:]]+[^[:space:]]+[[:space:]]+\*+[[:space:]]*$//' <<< "$line")
        [ -z "$ssid" ] && continue
        [ "$sectype" = "open" ] && sec=0
        grep -Fxq "$ssid" <<< "$saved" && kn=1
        icon=$(sig_icon $(( ${#stars} * 25 )))
        local lock="  "; [ "$sec" = 1 ] && lock="󰌾 "
        lines+=("$mark$icon $lock$ssid")
        ssids+=("$ssid"); secured+=("$sec"); known+=("$kn")
    done < <(iwctl station "$IWDEV" get-networks 2>/dev/null | strip_ansi | tail -n +5)
}

connect_iwd() {
    local ssid=$1 sec=$2 kn=$3 pass
    if [ "$kn" = 1 ] || [ "$sec" = 0 ]; then
        iwctl station "$IWDEV" connect "$ssid" >/dev/null 2>&1 && return 0
        [ "$kn" = 1 ] && iwctl known-networks "$ssid" forget >/dev/null 2>&1
    fi
    if [ "$sec" = 1 ]; then
        pass=$($WOFI_PASS </dev/null) || return 1
        [ -z "$pass" ] && return 1
        iwctl --passphrase "$pass" station "$IWDEV" connect "$ssid" >/dev/null 2>&1
    fi
}

# ---------- 主流程 ----------
scan_$BACKEND

if [ ${#lines[@]} -eq 0 ]; then
    notify "Wi-Fi" "未扫描到任何网络"
    exit 0
fi

choice=$(printf '%s\n' "${lines[@]}" | $WOFI_LIST) || exit 0
[ -z "$choice" ] && exit 0

# 用菜单行反查索引，SSID 含空格也不会解析错
idx=-1
for i in "${!lines[@]}"; do
    [ "${lines[$i]}" = "$choice" ] && { idx=$i; break; }
done
[ "$idx" -lt 0 ] && exit 1

ssid=${ssids[$idx]}
if connect_$BACKEND "$ssid" "${secured[$idx]}" "${known[$idx]}"; then
    notify "Wi-Fi 已连接" "$ssid"
    # 让 waybar 的 network 模块立即刷新（interval 3s 内也会自己刷）
    pkill -RTMIN+4 waybar 2>/dev/null || true
else
    notify "连接失败" "$ssid（密码错误或信号问题）"
fi
