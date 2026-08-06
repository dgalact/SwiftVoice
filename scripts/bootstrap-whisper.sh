#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
vendor_dir="$project_dir/vendor"
whisper_dir="$vendor_dir/whisper.cpp"

mkdir -p "$vendor_dir"

if ! command -v cmake >/dev/null 2>&1; then
  echo "CMake is required to build whisper.cpp." >&2
  echo "Please install CMake and run setup again." >&2
  exit 2
fi

if [[ ! -d "$whisper_dir/.git" ]]; then
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$whisper_dir"
fi

rm -rf "$whisper_dir/build"

cmake -S "$whisper_dir" -B "$whisper_dir/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DWHISPER_METAL=ON
cmake --build "$whisper_dir/build" --config Release -j

echo "whisper-cli:"
find "$whisper_dir/build" -type f -name whisper-cli -perm -111 -print -quit
