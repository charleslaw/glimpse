#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
derived_data="${GLIMPSE_DERIVED_DATA:-$repo_root/build/DerivedData}"
scratch="${GLIMPSE_SWIFT_SCRATCH:-$repo_root/build/SwiftTests}"
swift_args=(test --scratch-path "$scratch")
# Disable only the local manifest subprocess sandbox on already-sandboxed hosts.
# This does not change the app or macOS security settings.
if [[ "${GLIMPSE_DISABLE_PACKAGE_SANDBOX:-0}" == "1" ]]; then
  swift_args+=(--disable-sandbox)
fi
if [[ -n "${GLIMPSE_TEST_SANITIZER:-}" ]]; then
  swift_args+=(--sanitize "$GLIMPSE_TEST_SANITIZER")
fi
swift "${swift_args[@]}"
for configuration in Debug Release; do
  xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse \
    -configuration "$configuration" -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    SWIFT_STRICT_CONCURRENCY=complete SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
done
