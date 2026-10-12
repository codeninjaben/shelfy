#!/bin/zsh
# Builds Shelfy.app. Usage: scripts/build.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-Debug}"

# The checked-in project is generated from project.yml; regenerate it when XcodeGen is available.
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --spec project.yml --quiet
fi

mkdir -p build
build_log="build/build-$configuration.log"
if xcodebuild \
    -project Shelfy.xcodeproj \
    -scheme Shelfy \
    -configuration "$configuration" \
    -derivedDataPath build/DerivedData \
    -destination 'platform=macOS' \
    build > "$build_log" 2>&1; then
    awk '/error:|warning:|BUILD (SUCCEEDED|FAILED)/' "$build_log"
else
    tail -n 60 "$build_log" >&2
    exit 1
fi

app="build/DerivedData/Build/Products/$configuration/Shelfy.app"
[[ -d "$app" ]] || { echo "Build failed: $app not found" >&2; exit 1; }
echo "$PWD/$app"
