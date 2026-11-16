#!/usr/bin/env bash
# Chup man hinh: SUPER+S / Shift+Print = chon vung; Print = toan man hinh (--full).
# Luu file, copy clipboard, roi hien popup xem truoc o goc man hinh (Quantum Shell) voi cac nut
# Danh dau (ve tron/mui ten/highlight/ghi chu), Copy, Thu muc. Neu shell khong chay thi
# dung thong bao voi nut Edit mo swappy.
mode=region; [[ ${1:-} == --full ]] && mode=full

dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"
file="$dir/$(date +%Y%m%d-%H%M%S).png"

if [[ $mode == full ]]; then
  out=$(hyprctl monitors -j | python3 -c 'import json,sys;m=[x for x in json.load(sys.stdin) if x.get("focused")] or json.load(sys.stdin);print(m[0]["name"])' 2>/dev/null)
  grim ${out:+-o "$out"} "$file" || exit 1
else
  geom=$(slurp -b 00000066 -c ffffffff -w 2) || exit 0      # Esc = huy
  grim -g "$geom" "$file" || exit 1
fi
wl-copy < "$file"

for cfg in caelestia quantum; do
  if qs -c "$cfg" ipc call screenshot popup "$file" >/dev/null 2>&1; then exit 0; fi
done
action=$(notify-send -i "$file" --action=edit=Edit "Screenshot" "Da luu $file va copy vao clipboard")
[[ $action == edit ]] && swappy -f "$file"
