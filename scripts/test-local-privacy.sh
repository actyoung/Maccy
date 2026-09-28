#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
cache_dir="$repo_dir/.swiftpm-local"
testing_plugin="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

sdk_path=${SDKROOT:-}
if [[ -z "$sdk_path" ]]; then
  compatible_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
  if [[ -d "$compatible_sdk" ]]; then
    sdk_path="$compatible_sdk"
  else
    sdk_path=$(xcrun --sdk macosx --show-sdk-path)
  fi
fi

if [[ ! -d "$sdk_path" ]]; then
  print -u2 "macOS SDK not found: $sdk_path"
  exit 1
fi

if [[ ! -f "$testing_plugin" ]]; then
  print -u2 "Swift Testing macro plugin not found: $testing_plugin"
  exit 1
fi

"$repo_dir/scripts/bootstrap-local-dependencies.sh"

cd "$repo_dir"
mkdir -p "$cache_dir/cache" "$cache_dir/config" "$cache_dir/security" "$cache_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$cache_dir/module-cache"
swift test \
  --disable-sandbox \
  --sdk "$sdk_path" \
  --cache-path "$cache_dir/cache" \
  --config-path "$cache_dir/config" \
  --security-path "$cache_dir/security" \
  --manifest-cache local \
  -Xswiftc -load-plugin-library \
  -Xswiftc "$testing_plugin" \
  -debug-info-format none \
  -c release
