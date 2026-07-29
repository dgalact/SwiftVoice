#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
whisper_dir="$project_dir/vendor/whisper.cpp"
whisper_cli="$whisper_dir/build/bin/whisper-cli"
model="$whisper_dir/models/ggml-large-v3-turbo.bin"

for command_name in git cmake swift; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Не найдена команда: $command_name" >&2
    echo "Установи Xcode Command Line Tools и CMake, затем повтори запуск." >&2
    exit 2
  fi
done

"$project_dir/scripts/bootstrap-whisper.sh"

if [[ ! -f "$model" ]]; then
  "$whisper_dir/models/download-ggml-model.sh" large-v3-turbo
fi

"$project_dir/scripts/build-app.sh"
"$project_dir/scripts/install-app.sh"

defaults write local.dgalact.jarvis whisperExecutablePath "$whisper_cli"
defaults write local.dgalact.jarvis whisperModelPath "$model"

echo
echo "Jarvis установлен: $HOME/Applications/Jarvis.app"
echo "При первом запуске выдай доступ к микрофону и Accessibility."
echo "Запуск:"
echo "open \"$HOME/Applications/Jarvis.app\""
