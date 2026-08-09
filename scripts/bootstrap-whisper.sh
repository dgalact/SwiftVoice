#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
vendor_dir="$project_dir/vendor"
whisper_dir="$vendor_dir/whisper.cpp"
whisper_version="v1.9.2"
whisper_commit="306c88f4d1286aec1bf96e544632897886af5501"
whisper_repository="https://github.com/ggml-org/whisper.cpp.git"

mkdir -p "$vendor_dir"

if ! command -v cmake >/dev/null 2>&1; then
  echo "CMake is required to build whisper.cpp." >&2
  echo "Please install CMake and run setup again." >&2
  exit 2
fi

if ! git -C "$whisper_dir" rev-parse --git-dir >/dev/null 2>&1; then
  git clone --branch "$whisper_version" --depth 1 "$whisper_repository" "$whisper_dir"
else
  if [[ -n "$(git -C "$whisper_dir" status --porcelain --untracked-files=no)" ]]; then
    echo "Refusing to change whisper.cpp because it contains local tracked changes." >&2
    exit 3
  fi

  if ! git -C "$whisper_dir" cat-file -e "$whisper_commit^{commit}" 2>/dev/null; then
    git -C "$whisper_dir" fetch --depth 1 origin tag "$whisper_version"
  fi
  git -C "$whisper_dir" checkout --detach "$whisper_commit"
fi

actual_commit=$(git -C "$whisper_dir" rev-parse HEAD)
if [[ "$actual_commit" != "$whisper_commit" ]]; then
  echo "Expected whisper.cpp $whisper_version at $whisper_commit, got $actual_commit." >&2
  exit 4
fi

echo "Using whisper.cpp $whisper_version ($actual_commit)"

rm -rf "$whisper_dir/build"

cmake -S "$whisper_dir" -B "$whisper_dir/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL=ON
cmake --build "$whisper_dir/build" --config Release --target whisper-cli -j

echo "whisper-cli:"
find "$whisper_dir/build" -type f -name whisper-cli -perm -111 -print -quit
