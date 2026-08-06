#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
build_dir="$project_dir/.build/release"
app_dir="$project_dir/dist/SwiftVoice.app"

cd "$project_dir"
swift build -c release

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/SwiftVoice" "$app_dir/Contents/MacOS/SwiftVoice"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/SwiftVoiceIcon.icns" "$app_dir/Contents/Resources/SwiftVoiceIcon.icns"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
