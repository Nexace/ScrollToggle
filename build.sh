#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="ScrollToggle.app"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/scrolltoggle-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$app/Contents/MacOS"
xcrun clang -arch arm64 -fobjc-arc -Os -DNDEBUG -Wall -Wextra -Werror \
  -mmacosx-version-min=11.0 -framework AppKit \
  main.m -Wl,-dead_strip -o "$build_dir/arm64"
xcrun clang -arch x86_64 -fobjc-arc -Os -DNDEBUG -Wall -Wextra -Werror \
  -mmacosx-version-min=10.13 -framework AppKit \
  main.m -Wl,-dead_strip -o "$build_dir/x86_64"
xcrun lipo -create "$build_dir/arm64" "$build_dir/x86_64" -output "$app/Contents/MacOS/ScrollToggle"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf 'Built universal app: %s/%s\n' "$PWD" "$app"
