#!/usr/bin/env bash
# wofi Wi-Fi 菜单（水墨版）— 扫描 → 选择 → 确认/输密码 → 连接
# 后端自动探测：NetworkManager (nmcli) 或 iwd (iwctl)

STYLE="$HOME/.config/wofi/wifi-menu.css"

# 基础 wofi 参数：统一样式、禁用历史排序
wofi_base() {
    wofi --dmenu -i --style "$STYLE" --cache-file /dev/null \
         --width 380 "$@"
}
wofi_list()    { wofi_base --height 400 -p "Wi-Fi"; }
wofi_confirm() { wofi_base --height 150 -p "连接到 $1"; }
wofi_pass()    { wofi_base --height 120 --password -p "连接到 $1 · 输入密码" </dev/null; }

notify() { command -v notify-send >/dev/null && notify-send -a "Wi-Fi" "$1" "$2"; }
strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b\[?[0-9]*[hl]//g'; }

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
        nmcli con delete id "$ssid" >/dev/null 2>&1
    fi
    if [ "$sec" = 1 ]; then
        pass=$(wofi_pass "$ssid") || return 1
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

    while IFS= read -r line; do
        [ -z "${line// /}" ] && continue
        local mark="  " sec=1 kn=0 stars sectype ssid icon
        case "$line" in '>'*) mark=" "; line=${line#>}; esac
        line=${line#"${line%%[![:space:]]*}"}
        stars=$(awk '{print $NF}' <<< "$line")
        sectype=$(awk '{print $(NF-1)}' <<< "$line")
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
        pass=$(wofi_pass "$ssid") || return 1
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

choice=$(printf '%s\n' "${lines[@]}" | wofi_list) || exit 0
[ -z "$choice" ] && exit 0

idx=-1
for i in "${!lines[@]}"; do
    [ "${lines[$i]}" = "$choice" ] && { idx=$i; break; }
done
[ "$idx" -lt 0 ] && exit 1

ssid=${ssids[$idx]}
sec=${secured[$idx]}
kn=${known[$idx]}

# 已保存 / 开放网络：弹出确认框，回车即连
# 新的加密网络：密码框本身就是确认（输入密码回车 = 确认连接）
if [ "$kn" = 1 ] || [ "$sec" = 0 ]; then
    ans=$(printf '󰸞 连接\n󰜺 取消\n' | wofi_confirm "$ssid") || exit 0
    [ "$ans" = "󰸞 连接" ] || exit 0
fi

if connect_$BACKEND "$ssid" "$sec" "$kn"; then
    notify "Wi-Fi 已连接" "$ssid"
    pkill -RTMIN+4 waybar 2>/dev/null || true
else
    notify "连接失败" "$ssid（密码错误或信号问题）"
fi
