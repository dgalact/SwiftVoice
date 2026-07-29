#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
source_app="$project_dir/dist/Jarvis.app"
applications_dir="$HOME/Applications"
installed_app="$applications_dir/Jarvis.app"

if [[ ! -d "$source_app" ]]; then
  echo "Сначала собери приложение: ./scripts/build-app.sh" >&2
  exit 1
fi

mkdir -p "$applications_dir"

if [[ -d "$installed_app" ]]; then
  mkdir -p "$HOME/.Trash"
  backup="$HOME/.Trash/Jarvis-before-update-$(date +%Y%m%d-%H%M%S).app"
  mv "$installed_app" "$backup"
  echo "Предыдущая версия перемещена в: $backup"
fi

ditto "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
echo "$installed_app"
