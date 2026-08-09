#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
build_dir="$project_dir/.build/release"
app_dir="$project_dir/dist/SwiftVoice.app"
licenses_dir="$app_dir/Contents/Resources/Licenses"
whisper_bin_dir="$project_dir/vendor/whisper.cpp/build/bin"
whisper_cli="$whisper_bin_dir/whisper-cli"
whisper_server="$whisper_bin_dir/whisper-server"
whisper_libraries=(
  libwhisper.1.dylib
  libggml.0.dylib
  libggml-base.0.dylib
  libggml-cpu.0.dylib
  libggml-blas.0.dylib
  libggml-metal.0.dylib
)

if [[ ! -x "$whisper_cli" ]]; then
  echo "Pinned whisper-cli is not built. Run ./scripts/bootstrap-whisper.sh first." >&2
  exit 2
fi

if [[ ! -x "$whisper_server" ]]; then
  echo "Pinned whisper-server is not built. Run ./scripts/bootstrap-whisper.sh first." >&2
  exit 2
fi

for library in "${whisper_libraries[@]}"; do
  if [[ ! -f "$whisper_bin_dir/$library" ]]; then
    echo "Missing whisper.cpp runtime library: $library" >&2
    exit 2
  fi
done

cd "$project_dir"
swift build -c release

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks" "$licenses_dir"
cp "$build_dir/SwiftVoice" "$app_dir/Contents/MacOS/SwiftVoice"
cp "$whisper_cli" "$app_dir/Contents/MacOS/whisper-cli"
cp "$whisper_server" "$app_dir/Contents/MacOS/whisper-server"
for library in "${whisper_libraries[@]}"; do
  cp -L "$whisper_bin_dir/$library" "$app_dir/Contents/Frameworks/$library"
done
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/SwiftVoiceIcon.icns" "$app_dir/Contents/Resources/SwiftVoiceIcon.icns"
cp "$project_dir/LICENSE" "$licenses_dir/SwiftVoice-LICENSE.txt"
cp "$project_dir/vendor/whisper.cpp/LICENSE" "$licenses_dir/whisper.cpp-LICENSE.txt"

install_name_tool \
  -rpath "$whisper_bin_dir" "@executable_path/../Frameworks" \
  "$app_dir/Contents/MacOS/whisper-cli"

install_name_tool \
  -rpath "$whisper_bin_dir" "@executable_path/../Frameworks" \
  "$app_dir/Contents/MacOS/whisper-server"

for library in "$app_dir"/Contents/Frameworks/*.dylib; do
  codesign --force --sign - "$library"
done
codesign --force --sign - "$app_dir/Contents/MacOS/whisper-cli"
codesign --force --sign - "$app_dir/Contents/MacOS/whisper-server"
codesign --force --sign - "$app_dir/Contents/MacOS/SwiftVoice"
codesign --force --sign - "$app_dir"

codesign --verify --deep --strict "$app_dir"
"$app_dir/Contents/MacOS/whisper-cli" --help >/dev/null 2>&1
"$app_dir/Contents/MacOS/whisper-server" --help >/dev/null 2>&1

echo "$app_dir"
