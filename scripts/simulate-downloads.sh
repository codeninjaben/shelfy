#!/bin/zsh
# Replays the on-disk sequences real downloaders produce, for checking Shelfy by hand.
#
#   scripts/simulate-downloads.sh <scenario> [folder]
#
# Scenarios:
#   chrome       "Unconfirmed N.crdownload" → "name.crdownload" → "name"   (Chrome, Edge, Arc, Brave)
#   firefox      empty "name" placeholder + "name.part", renamed over the placeholder
#   safari       "name.download" bundle; the finished file moves out of it
#   direct       a file written in place over a few seconds (curl -o, wget, apps)
#   multiple     three Chrome-style downloads finishing together
#   interrupted  Chrome, Firefox and Safari downloads abandoned half way (should never appear)
#   cleanup      removes every file this script created
#
# Every file is named "shelfy-sim-…" so cleanup only touches what this script made.
set -euo pipefail

scenario="${1:-}"
folder="${2:-$HOME/Downloads}"
chunk() { head -c "${1:-262144}" /dev/urandom; }

stream_into() { # file chunks pause
    local file="$1" count="${2:-6}" pause="${3:-0.4}"
    for _ in $(seq "$count"); do chunk >> "$file"; sleep "$pause"; done
}

chrome() {
    local name="$1"
    local temp="$folder/Unconfirmed $RANDOM.crdownload"
    : > "$temp"; stream_into "$temp" 3
    mv "$temp" "$folder/$name.crdownload"; stream_into "$folder/$name.crdownload" 3
    mv "$folder/$name.crdownload" "$folder/$name"
}

firefox() {
    local name="$1"
    : > "$folder/$name"
    : > "$folder/$name.part"; stream_into "$folder/$name.part" 6
    mv -f "$folder/$name.part" "$folder/$name"
}

safari() {
    local name="$1" bundle="$folder/$1.download"
    mkdir -p "$bundle"
    : > "$bundle/$name"; stream_into "$bundle/$name" 6
    mv "$bundle/$name" "$folder/$name"
    rm -rf "$bundle"
}

case "$scenario" in
    chrome) chrome "shelfy-sim-chrome-report.pdf" ;;
    firefox) firefox "shelfy-sim-firefox-photo.jpg" ;;
    safari) safari "shelfy-sim-safari-archive.zip" ;;
    direct) : > "$folder/shelfy-sim-direct-data.csv"; stream_into "$folder/shelfy-sim-direct-data.csv" 8 0.3 ;;
    multiple)
        chrome "shelfy-sim-batch-1.png" & chrome "shelfy-sim-batch-2.png" & chrome "shelfy-sim-batch-3.png" &
        wait ;;
    interrupted)
        temp="$folder/Unconfirmed $RANDOM.crdownload"
        : > "$temp"; stream_into "$temp" 2
        mv "$temp" "$folder/shelfy-sim-stalled-video.mp4.crdownload"; stream_into "$folder/shelfy-sim-stalled-video.mp4.crdownload" 2
        : > "$folder/shelfy-sim-stalled-installer.dmg"
        : > "$folder/shelfy-sim-stalled-installer.dmg.part"; stream_into "$folder/shelfy-sim-stalled-installer.dmg.part" 2
        mkdir -p "$folder/shelfy-sim-stalled-dataset.csv.download"
        stream_into "$folder/shelfy-sim-stalled-dataset.csv.download/shelfy-sim-stalled-dataset.csv" 2
        echo "Left three stalled downloads in $folder; none of them should appear in Shelfy." ;;
    cleanup)
        find "$folder" -maxdepth 1 -name 'shelfy-sim-*' -print -exec rm -rf {} + ;;
    *)
        sed -n '2,17p' "$0"; exit 1 ;;
esac
