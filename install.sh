#!/usr/bin/env bash
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/skills"
agents="$HOME/.agents/skills"
claude="$HOME/.claude/skills"
mkdir -p "$agents" "$claude"
for dir in "$src"/*/; do
  name="$(basename "$dir")"
  link="$claude/$name"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "$link existe y no es un enlace: no lo toco" >&2
    exit 1
  fi
  rm -f "$link"
  rm -rf "$agents/$name"
  cp -R "$dir" "$agents/$name"
  ln -s "$agents/$name" "$link"
  echo "instalado: $name"
done
