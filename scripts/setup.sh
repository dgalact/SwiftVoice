#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}

for command_name in git cmake swift; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Command not found: $command_name" >&2
    echo "Please install Xcode Command Line Tools and CMake, then run setup again." >&2
    exit 2
  fi
done

"$project_dir/scripts/bootstrap-whisper.sh"
"$project_dir/scripts/build-app.sh"
"$project_dir/scripts/install-app.sh"

echo
echo "SwiftVoice successfully installed: /Applications/SwiftVoice.app"
echo "Select or download your preferred Whisper model directly in Settings -> Recognition."
echo "Grant Microphone and Accessibility permissions when prompted on first launch."
echo "Launch with:"
echo "open \"/Applications/SwiftVoice.app\""
