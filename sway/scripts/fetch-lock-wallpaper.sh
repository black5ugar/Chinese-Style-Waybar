#!/bin/sh

set -eu

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/sway-lock"
cache_dir="$cache_root/landscapes"

mkdir -p "$cache_dir"

# Older versions stored downloaded files one directory higher.  Move those
# files into the directory consumed by random-lock.sh before fetching a new
# one, so a temporary network failure does not make a valid cache invisible.
find "$cache_root" -maxdepth 1 -type f -name 'wallpaper-*' \
    -exec mv --target-directory="$cache_dir" -- {} +

tmp_file="$(mktemp "$cache_dir/.wallpaper.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

source_name=
extension=

download_image() {
    candidate_source="$1"
    candidate_url="$2"

    if ! curl --fail --silent --show-error --location \
        --connect-timeout 8 --max-time 45 \
        --retry 2 --retry-delay 1 --retry-all-errors \
        --header 'User-Agent: sway-lock-wallpaper/2.0' \
        --output "$tmp_file" \
        "$candidate_url"; then
        printf '%s image download failed; trying the next source.\n' \
            "$candidate_source" >&2
        return 1
    fi

    mime_type="$(file --brief --mime-type "$tmp_file")"
    case "$mime_type" in
        image/jpeg) extension=jpg ;;
        image/png) extension=png ;;
        image/webp) extension=webp ;;
        *)
            printf '%s returned an unsupported file type (%s); trying the next source.\n' \
                "$candidate_source" "$mime_type" >&2
            return 1
            ;;
    esac

    source_name="$candidate_source"
}

fetch_bing_wallpaper() {
    # Rotate through Bing's eight most recent homepage images.  The timer runs
    # every six hours, so this changes the selected image on each run.
    epoch="$(date +%s)"
    bing_index=$((epoch / 21600 % 8))
    bing_api="https://www.bing.com/HPImageArchive.aspx?format=js&idx=$bing_index&n=1&mkt=zh-CN"

    if ! response="$(
        curl --fail --silent --show-error --location \
            --connect-timeout 8 --max-time 30 \
            --retry 1 --retry-delay 1 --retry-all-errors \
            --header 'User-Agent: sway-lock-wallpaper/2.0' \
            "$bing_api"
    )"; then
        printf 'Bing wallpaper metadata request failed; trying the next source.\n' >&2
        return 1
    fi

    if ! image_path="$(printf '%s' "$response" | jq -er '.images[0].url')"; then
        printf 'Bing wallpaper metadata was invalid; trying the next source.\n' >&2
        return 1
    fi

    case "$image_path" in
        http://*|https://*) image_url="$image_path" ;;
        /*) image_url="https://www.bing.com$image_path" ;;
        *)
            printf 'Bing returned an invalid wallpaper URL; trying the next source.\n' >&2
            return 1
            ;;
    esac

    download_image 'Bing Wallpaper' "$image_url"
}

downloaded=false

if fetch_bing_wallpaper; then
    downloaded=true
else
    cache_buster="$(date +%s)"
    if download_image 'LoremFlickr landscape fallback' \
        "https://loremflickr.com/1920/1080/landscape,nature?lock=$cache_buster"; then
        downloaded=true
    elif download_image 'Lorem Picsum fallback' \
        "https://picsum.photos/1920/1080?random=$cache_buster"; then
        downloaded=true
    fi
fi

if [ "$downloaded" != true ]; then
    if find "$cache_dir" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -print -quit | grep -q .; then
        printf 'All remote wallpaper sources failed; keeping the existing cache.\n' >&2
        exit 0
    fi

    printf 'All remote wallpaper sources failed and the cache is empty.\n' >&2
    exit 1
fi

destination="$cache_dir/wallpaper-$(date +%s)-$$.$extension"
mv "$tmp_file" "$destination"
trap - EXIT HUP INT TERM

# Keep the 20 newest cached wallpapers.
find "$cache_dir" -maxdepth 1 -type f -name 'wallpaper-*' -printf '%T@ %p\0' \
    | sort -z -nr \
    | sed -z '1,20d' \
    | cut -z -d ' ' -f 2- \
    | xargs -0r rm -f --

printf 'Downloaded lock-screen wallpaper from %s: %s\n' "$source_name" "$destination"
