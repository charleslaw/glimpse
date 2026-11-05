#!/bin/bash
# Public mode uploads the signed app to Apple's notary service. It never publishes a release.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
mode="${1:---public}"
if [[ "$#" -gt 1 || ( "$mode" != "--public" && "$mode" != "--local" ) ]]; then
  echo "Usage: scripts/package_release.sh [--public|--local]" >&2
  exit 2
fi
identity="${GLIMPSE_SIGNING_IDENTITY:-}"
profile="${GLIMPSE_NOTARY_PROFILE:-}"
if [[ "$mode" == "--public" ]]; then
  if [[ "$identity" != "Developer ID Application: "* || -z "$profile" ]]; then
    echo "Public releases require GLIMPSE_SIGNING_IDENTITY='Developer ID Application: …' and GLIMPSE_NOTARY_PROFILE. See docs/DISTRIBUTION.md." >&2
    exit 2
  fi
  if ! security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$identity\""; then
    echo "The requested Developer ID Application identity and private key are unavailable in the keychain." >&2
    exit 2
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Public releases require a clean checkout so the included source exactly matches the binary." >&2
    exit 2
  fi
fi
revision="$(git rev-parse HEAD)"
build_number="${GLIMPSE_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
if [[ ! "$build_number" =~ ^[0-9]+$ || "$build_number" == "0" ]]; then
  echo "GLIMPSE_BUILD_NUMBER must be a positive integer." >&2; exit 2
fi
version_args=("CURRENT_PROJECT_VERSION=$build_number")
if [[ -n "${GLIMPSE_VERSION:-}" ]]; then
  if [[ ! "$GLIMPSE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "GLIMPSE_VERSION must have the form 1.2.3." >&2; exit 2
  fi
  version_args+=("MARKETING_VERSION=$GLIMPSE_VERSION")
fi
release_root="${GLIMPSE_RELEASE_DIR:-$repo_root/build/releases}"
mkdir -p "$release_root"
release_root="$(cd "$release_root" && pwd)"
release_dir="$(mktemp -d "$release_root/Glimpse-${revision:0:8}-XXXXXX")"
trap 'echo "Packaging stopped. Review logs in $release_dir." >&2' ERR
payload="$release_dir/package"
mkdir -p "$payload"
echo "Building universal macOS release in $release_dir"
xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$release_dir/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  SWIFT_STRICT_CONCURRENCY=complete SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  "${version_args[@]}" \
  > "$release_dir/build.log" 2>&1
app="$payload/Glimpse.app"
ditto "$release_dir/DerivedData/Build/Products/Release/Glimpse.app" "$app"
lipo "$app/Contents/MacOS/Glimpse" -verify_arch arm64 x86_64
# This app has no embedded executable dependencies. Refuse an incomplete future
# signing workflow instead of silently relying on recursive --deep signing.
if [[ -d "$app/Contents/Frameworks" || -d "$app/Contents/PlugIns" || -d "$app/Contents/XPCServices" ]]; then
  echo "Review and sign embedded code inside-out before packaging this new app layout." >&2
  exit 1
fi
if [[ "$mode" == "--public" ]]; then
  codesign --force --sign "$identity" --options runtime --timestamp \
    --entitlements Glimpse/Glimpse.entitlements "$app"
else
  codesign --force --sign - --options runtime \
    --entitlements Glimpse/Glimpse.entitlements "$app"
  printf '%s\n' 'LOCAL TEST BUILD — ad-hoc signed; not notarized; not for public distribution.' > "$payload/LOCAL-TEST-BUILD.txt"
fi
codesign --verify --deep --strict --verbose=2 "$app"
codesign --display --verbose=4 "$app" 2> "$release_dir/signature.txt"
if [[ "$mode" == "--public" ]]; then
  upload="$release_dir/notarization-upload.zip"
  ditto -c -k --keepParent "$app" "$upload"
  xcrun notarytool submit "$upload" --keychain-profile "$profile" --wait \
    --output-format json > "$release_dir/notarization.json"
  submission="$(python3 - "$release_dir/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print(result['id'])
PY
)"
  xcrun notarytool log "$submission" --keychain-profile "$profile" "$release_dir/notarization-log.json"
  python3 - "$release_dir/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    sys.exit('Notarization was not accepted. Read notarization-log.json; no public archive was produced.')
PY
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
  spctl --assess --type execute --verbose=4 "$app"
fi
cp LICENSE "$payload/LICENSE.txt"
git archive --format=tar.gz --prefix=Glimpse-source/ --output="$payload/Glimpse-source.tar.gz" "$revision"
printf 'Glimpse\n\nDrag Glimpse.app into Applications.\nSource revision: %s\nLicense: GPL-3.0 (included). Matching committed source is included.\n' "$revision" > "$payload/README.txt"
suffix="universal"
if [[ "$mode" == "--local" ]]; then suffix="LOCAL-TEST-universal"; fi
archive="$release_dir/Glimpse-$build_number-$suffix.zip"
ditto -c -k "$payload" "$archive"
(cd "$release_dir" && shasum -a 256 "$(basename "$archive")" > SHA256SUMS)
echo "Package: $archive"
echo "Review the build, signature and notarization logs before distributing."
