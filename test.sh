#!/bin/sh
set -eu
export MallocSpaceEfficient=1
cd "$(dirname "$0")"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/scrolltoggle-check.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -Os -Wall -Wextra -Wno-unused-function \
  -mmacosx-version-min=13.0 -framework AppKit tests.m -o "$test_dir/unit-tests"
"$test_dir/unit-tests"
if [ "${1:-}" = "--live" ]; then
  printf 'Live check: temporarily toggles Natural Scrolling and restores it. Do not interrupt.\n'
  mkdir -p "$test_dir/ScrollVerify.app/Contents/MacOS"
  xcrun clang -fobjc-arc -Os -Wall -Wextra -mmacosx-version-min=13.0 \
    -framework AppKit verify.m -o "$test_dir/ScrollVerify.app/Contents/MacOS/ScrollVerify"
  cp Info.plist "$test_dir/ScrollVerify.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ScrollVerify' "$test_dir/ScrollVerify.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.amogh.ScrollToggle.verify' "$test_dir/ScrollVerify.app/Contents/Info.plist"
  codesign --force --sign - "$test_dir/ScrollVerify.app"
  "$test_dir/ScrollVerify.app/Contents/MacOS/ScrollVerify"
fi
