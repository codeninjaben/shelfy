#!/bin/zsh
# Builds Shelfy and (re)launches it. Extra arguments are passed to the app, e.g.
#   scripts/run.sh -ShelfyDebugAppearance dark
#   scripts/run.sh -ShelfyDebugReduceMotion YES -ShelfyDebugReduceTransparency YES
set -euo pipefail
cd "$(dirname "$0")/.."

app="$(scripts/build.sh Debug | tail -n 1)"

if pgrep -x Shelfy >/dev/null; then
    osascript -e 'tell application id "com.benbreslow.Shelfy" to quit' >/dev/null 2>&1 || pkill -x Shelfy || true
    sleep 1
fi

if (( $# > 0 )); then
    open "$app" --args "$@"
else
    open "$app"
fi
echo "Launched $app"
