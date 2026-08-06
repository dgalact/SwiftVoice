#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
source_app="$project_dir/dist/SwiftVoice.app"
applications_dir="/Applications"
installed_app="$applications_dir/SwiftVoice.app"
user_local_app="$HOME/Applications/SwiftVoice.app"

if [[ ! -d "$source_app" ]]; then
  echo "Build the application first: ./scripts/build-app.sh" >&2
  exit 1
fi

if [[ -d "$user_local_app" ]]; then
  mkdir -p "$HOME/.Trash"
  backup="$HOME/.Trash/SwiftVoice-user-local-backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$user_local_app" "$backup"
  echo "Removed legacy copy from $HOME/Applications, backed up to: $backup"
fi

if [[ -d "$installed_app" ]]; then
  mkdir -p "$HOME/.Trash"
  backup="$HOME/.Trash/SwiftVoice-before-update-$(date +%Y%m%d-%H%M%S).app"
  mv "$installed_app" "$backup"
  echo "Previous version moved to: $backup"
fi

ditto "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
echo "$installed_app"
