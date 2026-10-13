#!/bin/zsh
# Package a notarized Shelfy.app into the "Grid paper" disk image.
# Usage: scripts/make-dmg.sh path/to/Shelfy.app [version]
# Writes build/releases/<version>/Shelfy-<version>.dmg, refreshes SHA256SUMS beside it,
# and prints the disk image's path.
#
# The app inside must already be signed, notarized and stapled (scripts/release.sh does that).
# With SHELFY_NOTARY_PROFILE set, the disk image itself is also signed, notarized and stapled.
# Without it the disk image stays unsigned: macOS mounts it normally and checks the stapled app.
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:?Usage: scripts/make-dmg.sh path/to/Shelfy.app [version]}"
app="${app:A}"
[[ -d "$app" ]] || { print -u2 "No app at $app"; exit 1; }
version="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")}"
release_dir="$PWD/build/releases/$version"
dmg="$release_dir/Shelfy-$version.dmg"
mkdir -p "$release_dir"

# dmgbuild writes the Finder layout directly, without scripting Finder.
venv="$PWD/build/dmg-venv"
if [[ ! -x "$venv/bin/dmgbuild" ]]; then
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check 'dmgbuild==1.6.7'
fi

rm -f "$dmg"
"$venv/bin/dmgbuild" -s packaging/dmg/settings.py \
  -D "app=$app" \
  -D "background=$PWD/packaging/dmg/background.png" \
  -D "icon=$app/Contents/Resources/AppIcon.icns" \
  Shelfy "$dmg" > "$release_dir/dmgbuild.log" 2>&1 || { tail -n 30 "$release_dir/dmgbuild.log" >&2; exit 1; }
hdiutil verify -quiet "$dmg"

# Check what a visitor gets: the stapled app and the Applications link.
mount_point="$(mktemp -d "${TMPDIR:-/tmp}/shelfy-dmg.XXXXXX")"
cleanup() { hdiutil detach "$mount_point" -quiet 2>/dev/null || true; rmdir "$mount_point" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountpoint "$mount_point" > /dev/null 2> >(grep -v 'is deprecated' >&2)
[[ -L "$mount_point/Applications" ]] || { print -u2 'The disk image has no Applications link.'; exit 1; }
xcrun stapler validate -q "$mount_point/Shelfy.app"
spctl --assess --type execute "$mount_point/Shelfy.app"
cleanup
trap - EXIT

if [[ -n "${SHELFY_NOTARY_PROFILE:-}" ]]; then
  signing_identity="${SHELFY_SIGNING_IDENTITY:-Developer ID Application: Zazen Technology Group LLC (BZB8682VMH)}"
  codesign --sign "$signing_identity" --timestamp "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile "$SHELFY_NOTARY_PROFILE" \
    --wait --output-format json > "$release_dir/notarization-dmg.json"
  notary_status="$(plutil -extract status raw -o - "$release_dir/notarization-dmg.json")"
  if [[ "$notary_status" != Accepted ]]; then
    print -u2 "Disk image notarization status: $notary_status. See $release_dir/notarization-dmg.json"
    exit 1
  fi
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature "$dmg"
fi

# One checksum file for everything published with this version.
(cd "$release_dir" && shasum -a 256 Shelfy-"$version"-universal.zip(N) "${dmg:t}" > SHA256SUMS)
print "$dmg"
