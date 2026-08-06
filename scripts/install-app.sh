#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
source_app="$project_dir/dist/SwiftVoice.app"
applications_dir="/Applications"
installed_app="$applications_dir/SwiftVoice.app"
user_local_app="$HOME/Applications/SwiftVoice.app"

if [[ ! -d "$source_app" ]]; then
  echo "Сначала собери приложение: ./scripts/build-app.sh" >&2
  exit 1
fi

if [[ -d "$user_local_app" ]]; then
  mkdir -p "$HOME/.Trash"
  backup="$HOME/.Trash/SwiftVoice-user-local-backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$user_local_app" "$backup"
  echo "Удалена устаревшая копия из $HOME/Applications, бекап в: $backup"
fi

if [[ -d "$installed_app" ]]; then
  mkdir -p "$HOME/.Trash"
  backup="$HOME/.Trash/SwiftVoice-before-update-$(date +%Y%m%d-%H%M%S).app"
  mv "$installed_app" "$backup"
  echo "Предыдущая версия перемещена в: $backup"
fi

ditto "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
echo "$installed_app"
