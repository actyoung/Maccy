#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
dependency_dir=${MACCY_DEPENDENCY_DIR:-"$repo_dir/.swiftpm-local/dependencies"}
archive_dir=${MACCY_ARCHIVE_DIR:-}

mkdir -p "$dependency_dir"

fetch_dependency() {
  local name=$1
  local owner=$2
  local repository=$3
  local revision=$4
  local expected_sha=$5
  local target="$dependency_dir/$name"

  if [[ -f "$target/Package.swift" ]]; then
    return
  fi

  if [[ -e "$target" ]]; then
    print -u2 "Incomplete dependency directory: $target"
    exit 1
  fi

  local temp_dir
  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccy-$name.XXXXXX")
  local archive_path="$temp_dir/source.tar.gz"
  local cached_archive="$archive_dir/$name.tar.gz"

  if [[ -n "$archive_dir" && -f "$cached_archive" ]]; then
    cp "$cached_archive" "$archive_path"
  else
    curl --fail --location --silent --show-error \
      "https://codeload.github.com/$owner/$repository/tar.gz/$revision" \
      --output "$archive_path"
  fi

  local actual_sha
  actual_sha=$(shasum -a 256 "$archive_path" | awk '{print $1}')
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    print -u2 "Checksum mismatch for $name: expected $expected_sha, got $actual_sha"
    exit 1
  fi

  mkdir -p "$target"
  tar -xzf "$archive_path" --strip-components 1 -C "$target"
  print -r -- "$revision  $expected_sha" > "$target/.maccy-source"
  rm -rf "$temp_dir"
}

apply_compatibility_patch() {
  local name=$1
  local patch_path=$2
  local target="$dependency_dir/$name"
  local marker="$target/.maccy-${patch_path:t:r}"

  if [[ -f "$marker" ]]; then
    return
  fi

  patch --directory "$target" --strip 1 --forward < "$patch_path"
  shasum -a 256 "$patch_path" > "$marker"
}

fetch_dependency defaults sindresorhus Defaults \
  38925e3cfacf3fb89a81a35b1cd44fd5a5b7e0fa \
  e5014c1a8c46abe5ddabe68ef51205ede7d8f3b95b5699c3cde3b3f0ba4d0eb8
fetch_dependency fuse-swift krisk fuse-swift \
  26ba868691b2d8b7bf2b1322951eb591be70ccca \
  1a52888163299b88d5c88aee1a5be6bc5909f477a8bffe6ef4451d96a7124bb5
fetch_dependency keyboardshortcuts sindresorhus KeyboardShortcuts \
  e6b60117ec266e1e5d059f7f34815144f9762b36 \
  96eadea236a09c8ee1555b2142b08fde33b40d77cb6df4956f7fd23c6f5d981d
fetch_dependency launchatlogin-modern sindresorhus LaunchAtLogin-Modern \
  a04ec1c363be3627734f6dad757d82f5d4fa8fcc \
  0def8df441f33cd2c3e77be7834a3a77afdb87045e1f72d466d36f53ce2943ee
fetch_dependency sauce Clipy Sauce \
  df657bc1beba23ffd580953f183cd756b5bcd514 \
  58d8c5053d0ee87d61cd0b826dd9e08aa3ced7a1d6db107814458590764bcb83
fetch_dependency settings sindresorhus Settings \
  879ea83a7bbc6dbebf62bed8c547f090146372a6 \
  428b26ba09d3d9cca5c7a15e40a9a548991aa9a42c1972c4e693046cb5873c5d
fetch_dependency swift-log apple swift-log \
  ce592ae52f982c847a4efc0dd881cc9eb32d29f2 \
  fa24758c3725f296e2533c7f77efcf88daffd28efd9ac20d9327006c9796982e
fetch_dependency swifthexcolors thii SwiftHEXColors \
  1f886cb20fedda14a5ac75efd09bc99c95b43a18 \
  70a79379794e638d9a8e4e129a24992a3a7082acb37803403441a531e5bfb821

apply_compatibility_patch settings "$script_dir/patches/settings-command-line-tools.patch"
apply_compatibility_patch keyboardshortcuts "$script_dir/patches/keyboardshortcuts-release.patch"
