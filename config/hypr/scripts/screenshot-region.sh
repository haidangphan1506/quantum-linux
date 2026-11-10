#!/usr/bin/env bash
# Chup vung man hinh. Neu shell Caelestia co picker -> dung picker (co freeze).
# Neu khong (vd profile dev) -> fallback grim + slurp, copy clipboard, luu file, mo swappy khi bam thong bao.
if qs -c caelestia ipc show 2>/dev/null | grep -q '^target picker'; then
  exec qs -c caelestia ipc call picker openFreeze
fi

geom=$(slurp) || exit 0          # Esc = huy
dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"
file="$dir/$(date +%Y%m%d-%H%M%S).png"
grim -g "$geom" "$file" || exit 1
wl-copy < "$file"
action=$(notify-send -i "$file" --action=edit=Edit "Screenshot" "Da luu $file va copy vao clipboard")
[[ $action == edit ]] && swappy -f "$file"
