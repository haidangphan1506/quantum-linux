#!/bin/sh
# Danh sach phim tat Hyprland doc tu ~/.config/hypr/variable.lua (menu Tro giup -> Phim tat tren bar).
f="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/variable.lua"
grep -E 'key *= ' "$f" | grep -v '^\s*--' |
  sed -E 's/^\s*\{ *key *= *//; s/mainMod *\.\. *"/Super/; s/" *\.\. *key *\.\. *"?/<so>/; s/",? *action *= */\t/; s/ *\},? *(--.*)?$//; s/"//g; s/hl\.dsp\.//' |
  awk -F'\t' '{ printf "  %-28s %s\n", $1, substr($2, 1, 110) }'
