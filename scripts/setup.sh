#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
whisper_dir="$project_dir/vendor/whisper.cpp"
whisper_cli="$whisper_dir/build/bin/whisper-cli"

for command_name in git cmake swift; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Не найдена команда: $command_name" >&2
    echo "Установи Xcode Command Line Tools и CMake, затем повтори запуск." >&2
    exit 2
  fi
done

"$project_dir/scripts/bootstrap-whisper.sh"
"$project_dir/scripts/build-app.sh"
"$project_dir/scripts/install-app.sh"

defaults write org.swiftvoice.mac whisperExecutablePath "$whisper_cli"

echo
echo "SwiftVoice установлен: /Applications/SwiftVoice.app"
echo "Выбери или скачай модель Whisper прямо в Настройках приложения (Настройки -> Распознавание)."
echo "При первом запуске выдай доступ к микрофону и Accessibility."
echo "Запуск:"
echo "open \"/Applications/SwiftVoice.app\""
