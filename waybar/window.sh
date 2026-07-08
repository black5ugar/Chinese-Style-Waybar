#!/usr/bin/env bash

escape() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

print_status() {
    ws=$(swaymsg -t get_workspaces -r | jq -r '.[] | select(.focused).num' | head -n1)

    title=$(swaymsg -t get_tree -r | jq -r '
        .. | objects | select(.focused? == true) | .name // empty
    ' | head -n1)

    if [ -z "$title" ] || [ "$title" = "null" ]; then
        top_line="Desktop"
    else
        top_line="$title"
    fi

    if [ ${#top_line} -gt 20 ]; then
        top_line="${top_line:0:17}..."
    fi

    bottom_line="Workspace ${ws:-?}"

    esc_top=$(printf '%s' "$top_line" | escape)
    esc_bottom=$(printf '%s' "$bottom_line" | escape)

    text="<span size='7500' foreground='#8a8171'>$esc_top</span>
<span size='9000' weight='bold' foreground='#1f1c16'>$esc_bottom</span>"

    jq -nc \
        --arg text "$text" \
        --arg tooltip "$bottom_line" \
        '{text: $text, tooltip: $tooltip}'
}

print_status

swaymsg -t subscribe -m '["workspace","window"]' | while read -r _; do
    print_status
done
