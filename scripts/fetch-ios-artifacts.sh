#!/usr/bin/env bash
#
# Installs the prebuilt iOS inputs pinned in ios-artifacts.lock into ios/, after
# checking the archive's sha256. The podspec runs this when they are missing,
# since CocoaPods skips prepare_command for the :path pods autolinking creates.
#
# RNV_IOS_ARTIFACTS=<file.tar.gz> installs a local archive instead of
# downloading it; its checksum is still verified.
# RNV_FORCE_FETCH=1 replaces a set built locally by `npm run update-sources`.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
lock="$root/ios-artifacts.lock"

# Parsed, never sourced, so the lock file cannot run code.
read_lock() {
  sed -n "s/^$1=//p" "$lock" | tail -n 1 | tr -d '[:space:]'
}
url="$(read_lock IOS_ARTIFACTS_URL)"
sha="$(read_lock IOS_ARTIFACTS_SHA256)"

if [ -z "$sha" ]; then
  echo "[react-native-verus] ios-artifacts.lock has no checksum yet." >&2
  echo "[react-native-verus] Run the 'iOS artifacts' workflow, or build on a Mac with 'RNV_BUILD_IOS=1 npm run update-sources'." >&2
  exit 1
fi
if ! [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
  echo "[react-native-verus] IOS_ARTIFACTS_SHA256 is not 64 lowercase hex characters." >&2
  exit 1
fi
if [ -z "${RNV_IOS_ARTIFACTS:-}" ] && ! [[ "$url" =~ ^https://[^[:space:]]+$ ]]; then
  echo "[react-native-verus] IOS_ARTIFACTS_URL must be an https URL." >&2
  exit 1
fi

has_artifacts() {
  [ -d "$root/ios/libzcashlc.xcframework" ] \
    && [ -d "$root/ios/ZCashLightClientKit" ] \
    && [ -s "$root/ios/zcashlc.h" ]
}

stamp="$root/ios/.artifacts-sha256"
if has_artifacts; then
  if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sha" ]; then
    echo "[react-native-verus] iOS artifacts already installed."
    exit 0
  fi
  if [ ! -f "$stamp" ] && [ -f "$root/ios/.prepack-stamp" ] && [ "${RNV_FORCE_FETCH:-}" != "1" ]; then
    echo "[react-native-verus] Keeping the locally built iOS artifacts; set RNV_FORCE_FETCH=1 to replace them."
    exit 0
  fi
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="$work/ios-artifacts.tar.gz"

if [ -n "${RNV_IOS_ARTIFACTS:-}" ]; then
  cp "$RNV_IOS_ARTIFACTS" "$archive"
else
  echo "[react-native-verus] Downloading $url"
  curl -fL --proto '=https' --retry 4 --retry-delay 2 -o "$archive" "$url"
fi

if command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
else
  actual="$(sha256sum "$archive" | cut -d' ' -f1)"
fi
if [ "$actual" != "$sha" ]; then
  echo "[react-native-verus] Checksum mismatch: expected $sha, got $actual" >&2
  exit 1
fi

# The checksum pins the archive, so its contents are trusted; still refuse
# absolute or parent-relative paths before extracting.
if tar -tzf "$archive" | grep -Eq '^/|(^|/)\.\.(/|$)'; then
  echo "[react-native-verus] Archive contains unsafe paths." >&2
  exit 1
fi
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
echo "$sha" > "$stamp"
echo "[react-native-verus] Installed iOS artifacts $sha"
