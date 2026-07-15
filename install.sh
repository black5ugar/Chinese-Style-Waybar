#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: ./install.sh [--start] [--help]

Install the Quickshell topbar into the current user's config directory.

Options:
  --start  Start the installed topbar after copying it
  --help   Show this help message
EOF
}

start_after_install=false

while (($# > 0)); do
    case "$1" in
        --start)
            start_after_install=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir="$script_dir/quickshell/topbar"
config_home=${XDG_CONFIG_HOME:-"${HOME:?HOME is not set}/.config"}
quickshell_root="$config_home/quickshell"
target_dir="$quickshell_root/topbar"

if [[ ! -f "$source_dir/shell.qml" ]]; then
    printf 'Error: topbar source was not found at %s\n' "$source_dir" >&2
    exit 1
fi

if command -v qs >/dev/null 2>&1; then
    quickshell_cmd=qs
elif command -v quickshell >/dev/null 2>&1; then
    quickshell_cmd=quickshell
else
    printf 'Error: Quickshell is not installed (expected qs or quickshell).\n' >&2
    exit 1
fi

if ! command -v swaymsg >/dev/null 2>&1; then
    printf 'Warning: swaymsg was not found; workspace integration will not work.\n' >&2
fi

source_path=$(readlink -f -- "$source_dir")
target_path=$(readlink -m -- "$target_dir")

if [[ "$source_path" == "$target_path" ]]; then
    printf 'Topbar is already located at %s; no files were copied.\n' "$target_dir"
else
    mkdir -p -- "$quickshell_root"

    if [[ -e "$target_dir" ]]; then
        timestamp=$(date '+%Y%m%d-%H%M%S')
        backup_dir="$quickshell_root/topbar.backup-$timestamp"
        if [[ -e "$backup_dir" ]]; then
            backup_dir="$backup_dir-$$"
        fi
        mv -- "$target_dir" "$backup_dir"
        printf 'Existing topbar backed up to %s\n' "$backup_dir"
    fi

    cp -a -- "$source_dir" "$target_dir"
    printf 'Installed topbar to %s\n' "$target_dir"
fi

if [[ "$start_after_install" == true ]]; then
    "$quickshell_cmd" kill -c topbar >/dev/null 2>&1 || true
    "$quickshell_cmd" -c topbar --daemonize
    printf 'Started the topbar with %s.\n' "$quickshell_cmd"
else
    printf '\nStart it with:\n  %s -c topbar\n' "$quickshell_cmd"
fi

printf '\nFor Sway autostart, add:\n  exec_always --no-startup-id %s -c topbar --no-duplicate\n' "$quickshell_cmd"
