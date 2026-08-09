#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/dist/SwiftVoice.app"
release_dir="$project_dir/release"
version=$(plutil -extract CFBundleShortVersionString raw "$project_dir/Resources/Info.plist")
archive_name="SwiftVoice-${version}-macOS-arm64.zip"
archive_path="$release_dir/$archive_name"
checksum_path="$archive_path.sha256"

"$project_dir/scripts/build-app.sh"

for binary in \
  "$app_dir/Contents/MacOS/SwiftVoice" \
  "$app_dir/Contents/MacOS/whisper-cli"; do
  architectures=$(lipo -archs "$binary")
  if [[ "$architectures" != "arm64" ]]; then
    echo "Expected an arm64-only release binary, got '$architectures': $binary" >&2
    exit 3
  fi
done

mkdir -p "$release_dir"
rm -f "$archive_path" "$checksum_path"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive_path"

(
  cd "$release_dir"
  shasum -a 256 "$archive_name" > "$archive_name.sha256"
)

verification_dir=$(mktemp -d /tmp/swiftvoice-release-verify.XXXXXX)
ditto -x -k "$archive_path" "$verification_dir"
verified_app="$verification_dir/SwiftVoice.app"
codesign --verify --deep --strict "$verified_app"
"$verified_app/Contents/MacOS/whisper-cli" --help >/dev/null 2>&1
verified_version=$(plutil -extract CFBundleShortVersionString raw "$verified_app/Contents/Info.plist")
if [[ "$verified_version" != "$version" ]]; then
  echo "Release version mismatch: expected $version, got $verified_version" >&2
  exit 4
fi

echo "$archive_path"
echo "$checksum_path"
