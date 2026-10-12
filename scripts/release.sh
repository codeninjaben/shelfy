#!/bin/zsh
# Create a universal Developer ID-signed, notarized, and stapled Shelfy ZIP.
# Usage: scripts/release.sh [version]
# Optional: SHELFY_NOTARY_PROFILE=profile-name to use notarytool instead of Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

release_version="${1:-1.0.0}"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { print -u2 'Use a version such as 1.0.0'; exit 2; }
signing_team="${SHELFY_SIGNING_TEAM:-BZB8682VMH}"
signing_identity="${SHELFY_SIGNING_IDENTITY:-Developer ID Application: Zazen Technology Group LLC (BZB8682VMH)}"
release_dir="$PWD/build/releases/$release_version"
archive="$release_dir/Shelfy.xcarchive"
app="$archive/Products/Applications/Shelfy.app"
submission_zip="$release_dir/Shelfy-$release_version-notarization.zip"
download_zip="$release_dir/Shelfy-$release_version-universal.zip"
mkdir -p "$release_dir"

xcodebuild archive \
  -project Shelfy.xcodeproj -scheme Shelfy -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" -derivedDataPath build/ReleaseDerivedData \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$signing_identity" \
  "DEVELOPMENT_TEAM=$signing_team" ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS=--timestamp "MARKETING_VERSION=$release_version" \
  > "$release_dir/archive.log" 2>&1

codesign --verify --deep --strict --verbose=2 "$app"
[[ "$(lipo -archs "$app/Contents/MacOS/Shelfy")" == *arm64* && "$(lipo -archs "$app/Contents/MacOS/Shelfy")" == *x86_64* ]] || { print -u2 'The archive is not universal.'; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$app" "$submission_zip"

# Credentials stay in the Keychain or Xcode; never put secrets in this script.
if [[ -n "${SHELFY_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$submission_zip" \
    --keychain-profile "$SHELFY_NOTARY_PROFILE" \
    --wait --output-format json > "$release_dir/notarization.json"
  notary_status="$(plutil -extract status raw -o - "$release_dir/notarization.json")"
  submission_id="$(plutil -extract id raw -o - "$release_dir/notarization.json")"
  if [[ "$notary_status" != Accepted ]]; then
    xcrun notarytool log "$submission_id" --keychain-profile "$SHELFY_NOTARY_PROFILE" "$release_dir/notarization-log.json"
    print -u2 "Notarization status: $notary_status. See $release_dir/notarization-log.json"
    exit 1
  fi
else
  # Xcode's signed-in Apple account can submit Developer ID archives directly.
  export_options="$release_dir/export-upload.plist"
  rm -f "$export_options"
  plutil -create xml1 "$export_options"
  plutil -insert method -string developer-id "$export_options"
  plutil -insert destination -string upload "$export_options"
  plutil -insert teamID -string "$signing_team" "$export_options"
  plutil -insert signingStyle -string manual "$export_options"
  plutil -insert signingCertificate -string "$signing_identity" "$export_options"
  xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$export_options" -exportPath "$release_dir/xcode-export" \
    > "$release_dir/export-upload.log" 2>&1
  exported=false
  for attempt in {1..60}; do
    if xcodebuild -exportNotarizedApp -archivePath "$archive" \
      -exportPath "$release_dir/notarized" > "$release_dir/export-notarized.log" 2>&1; then
      exported=true
      break
    fi
    print "Waiting for Apple's notarization result ($attempt/60)…"
    sleep 10
  done
  if [[ "$exported" != true ]]; then
    print -u2 "The notarized app could not be exported. See $release_dir/export-notarized.log"
    exit 1
  fi
  app="$release_dir/notarized/Shelfy.app"
fi

xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"

# Repackage after stapling so the downloaded app carries Apple's ticket offline.
ditto -c -k --sequesterRsrc --keepParent "$app" "$download_zip"
(cd "$release_dir" && shasum -a 256 "${download_zip:t}" > SHA256SUMS)
print "$download_zip"
print "$release_dir/SHA256SUMS"
