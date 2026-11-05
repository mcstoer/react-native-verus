#!/usr/bin/env bash
#
# Installs the prebuilt iOS inputs pinned in ios-artifacts.lock into ios/, after
# checking the archive's sha256. Run it before `pod install`: CocoaPods skips
# prepare_command for the :path pods autolinking creates, so nothing else
# produces these files.
#
# Set RNV_IOS_ARTIFACTS to a local .tar.gz to install that file instead of
# downloading. Its checksum is still verified.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$root/ios-artifacts.lock"

if [ -z "${IOS_ARTIFACTS_SHA256:-}" ]; then
  echo "[react-native-verus] ios-artifacts.lock has no checksum yet." >&2
  echo "[react-native-verus] Run the ios-artifacts workflow, or build on a Mac with 'RNV_BUILD_IOS=1 npm run update-sources'." >&2
  exit 1
fi

stamp="$root/ios/.artifacts-sha256"
if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$IOS_ARTIFACTS_SHA256" ] \
  && [ -d "$root/ios/libzcashlc.xcframework" ] \
  && [ -d "$root/ios/ZCashLightClientKit" ] \
  && [ -s "$root/ios/zcashlc.h" ]; then
  echo "[react-native-verus] iOS artifacts already installed."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="$work/ios-artifacts.tar.gz"

if [ -n "${RNV_IOS_ARTIFACTS:-}" ]; then
  cp "$RNV_IOS_ARTIFACTS" "$archive"
else
  echo "[react-native-verus] Downloading $IOS_ARTIFACTS_URL"
  curl -fL --retry 4 --retry-delay 2 -o "$archive" "$IOS_ARTIFACTS_URL"
fi

if command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
else
  actual="$(sha256sum "$archive" | cut -d' ' -f1)"
fi
if [ "$actual" != "$IOS_ARTIFACTS_SHA256" ]; then
  echo "[react-native-verus] Checksum mismatch: expected $IOS_ARTIFACTS_SHA256, got $actual" >&2
  exit 1
fi

# The archive holds exactly these three paths, relative to ios/.
mkdir -p "$work/out"
tar -xzf "$archive" -C "$work/out"
for path in libzcashlc.xcframework ZCashLightClientKit zcashlc.h; do
  if [ ! -e "$work/out/$path" ]; then
    echo "[react-native-verus] Archive is missing $path" >&2
    exit 1
  fi
done

rm -rf "$root/ios/libzcashlc.xcframework" "$root/ios/ZCashLightClientKit" "$root/ios/zcashlc.h"
mv "$work/out/libzcashlc.xcframework" "$work/out/ZCashLightClientKit" "$work/out/zcashlc.h" "$root/ios/"
echo "$IOS_ARTIFACTS_SHA256" > "$stamp"
echo "[react-native-verus] Installed iOS artifacts $IOS_ARTIFACTS_SHA256"
