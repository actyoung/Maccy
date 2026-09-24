#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
app_dir="$repo_dir/build/Maccy.app"
cache_dir="$repo_dir/.swiftpm-local"
icon_source_dir="$repo_dir/Maccy/Assets.xcassets/AppIcon.appiconset"

sdk_path=${SDKROOT:-}
if [[ -z "$sdk_path" ]]; then
  compatible_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
  if [[ -d "$compatible_sdk" ]]; then
    sdk_path="$compatible_sdk"
  else
    sdk_path=$(xcrun --sdk macosx --show-sdk-path)
  fi
fi

if [[ "$app_dir" != "$repo_dir/build/Maccy.app" ]]; then
  print -u2 "Unexpected app output path"
  exit 1
fi

if [[ ! -d "$sdk_path" ]]; then
  print -u2 "macOS SDK not found: $sdk_path"
  exit 1
fi

"$repo_dir/scripts/bootstrap-local-dependencies.sh"

cd "$repo_dir"
mkdir -p "$cache_dir/cache" "$cache_dir/config" "$cache_dir/security" "$cache_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$cache_dir/module-cache"
swift build \
  --disable-sandbox \
  --sdk "$sdk_path" \
  --cache-path "$cache_dir/cache" \
  --config-path "$cache_dir/config" \
  --security-path "$cache_dir/security" \
  --manifest-cache local \
  -debug-info-format none \
  -c release \
  --product Maccy

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$repo_dir/.build/release/Maccy" "$app_dir/Contents/MacOS/Maccy"
cp "$repo_dir/Maccy/Info.plist" "$app_dir/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Maccy" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.p0deje.Maccy.localprivacy" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Maccy Privacy'" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 'Maccy Privacy'" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 2.7.1" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 62" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$app_dir/Contents/Info.plist"

/usr/bin/ruby "$repo_dir/scripts/create-icns.rb" \
  "$icon_source_dir" \
  "$app_dir/Contents/Resources/AppIcon.icns"

for locale_dir in "$repo_dir"/Maccy/*.lproj; do
  locale=${locale_dir:t}
  mkdir -p "$app_dir/Contents/Resources/$locale"
  cp "$locale_dir"/*.strings "$app_dir/Contents/Resources/$locale/" 2>/dev/null || true
done

for locale_dir in "$repo_dir"/Maccy/Settings/*.lproj; do
  locale=${locale_dir:t}
  mkdir -p "$app_dir/Contents/Resources/$locale"
  cp "$locale_dir"/*.strings "$app_dir/Contents/Resources/$locale/" 2>/dev/null || true
done

for locale_dir in "$repo_dir"/Maccy/Views/*.lproj; do
  locale=${locale_dir:t}
  mkdir -p "$app_dir/Contents/Resources/$locale"
  cp "$locale_dir"/*.strings "$app_dir/Contents/Resources/$locale/" 2>/dev/null || true
done

for resource_bundle in "$repo_dir"/.build/release/*.bundle; do
  [[ -e "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$app_dir/Contents/Resources/"
done

codesign --force --deep --sign - --entitlements "$repo_dir/Maccy/Maccy.entitlements" "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
print "$app_dir"
