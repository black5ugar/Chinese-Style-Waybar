#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
TOKEN_FILE="$CACHE_DIR/jinrishici_token"
LAST_FILE="$CACHE_DIR/jinrishici_last.json"
CACHE_TTL="${JINRISHICI_CACHE_TTL:-1800}" # 30 分钟

mkdir -p "$CACHE_DIR"

fetch_token() {
    curl -fsSL --connect-timeout 5 --max-time 10 \
        "https://v2.jinrishici.com/token" \
        | jq -r '.data // empty'
}

request_sentence() {
    local token="$1"

    curl -fsSL --connect-timeout 5 --max-time 10 \
        -H "X-User-Token: $token" \
        "https://v2.jinrishici.com/sentence"
}

json_ok() {
    jq -e '.status == "success" and (.data.content // "") != ""' >/dev/null 2>&1
}

format_output() {
    jq -c '
        def clean:
            gsub("[\r\n\t]+"; " ")
            | gsub("  +"; " ");

        # pango 标记下必须转义，否则诗句里出现 & < > 会让整段渲染失败
        def esc:
            gsub("&"; "&amp;")
            | gsub("<"; "&lt;")
            | gsub(">"; "&gt;");

        {
            text: ("<span foreground=\"#b83227\" weight=\"900\">詩</span> "
                + ((.data.content // "") | clean | esc)),
            tooltip: (
                ((.data.origin.dynasty // "") + " "
                + (.data.origin.author // "") + "《"
                + (.data.origin.title // "") + "》")
                + "\n\n"
                + ((.data.origin.content // [])
                    | if type == "array" then join("\n") else tostring end)
                | esc
            ),
            class: "jinrishici"
        }
    '
}

cache_fresh() {
    [[ -s "$LAST_FILE" ]] || return 1

    local now mtime
    now="$(date +%s)"
    mtime="$(stat -c %Y "$LAST_FILE" 2>/dev/null || echo 0)"

    (( now - mtime < CACHE_TTL ))
}

# 缓存未过期且内容有效，则直接使用本地缓存，不再请求接口
if cache_fresh && cat "$LAST_FILE" | json_ok; then
    cat "$LAST_FILE" | format_output
    exit 0
fi

token="$(cat "$TOKEN_FILE" 2>/dev/null || true)"

if [[ -z "$token" ]]; then
    token="$(fetch_token || true)"
    if [[ -n "$token" ]]; then
        printf '%s\n' "$token" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
    fi
fi

resp=""

if [[ -n "$token" ]]; then
    resp="$(request_sentence "$token" || true)"
fi

# 如果 token 失效或返回异常，重新拿一次 token
if ! printf '%s' "$resp" | json_ok; then
    rm -f "$TOKEN_FILE"

    token="$(fetch_token || true)"
    if [[ -n "$token" ]]; then
        printf '%s\n' "$token" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        resp="$(request_sentence "$token" || true)"
    fi
fi

if printf '%s' "$resp" | json_ok; then
    printf '%s\n' "$resp" > "$LAST_FILE"
    printf '%s' "$resp" | format_output
elif [[ -s "$LAST_FILE" ]]; then
    cat "$LAST_FILE" | format_output
else
    jq -nc '{
        text: "诗词加载失败",
        tooltip: "今日诗词请求失败，且没有本地缓存",
        class: "jinrishici-error"
    }'
fi
