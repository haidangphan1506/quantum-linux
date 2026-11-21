#!/usr/bin/env bash
# Quay man hinh bang gpu-screen-recorder (bam lan nua de dung va luu).
#   screen-record.sh           -> quay toan man hinh dang focus (SUPER+SHIFT+R)
#   screen-record.sh --region  -> keo chon vung roi quay      (SUPER+ALT+R)
# Video luu o ~/Videos/Recordings/YYYYmmdd-HHMMSS.mp4 (co tieng he thong).
dir="$HOME/Videos/Recordings"
state="${XDG_RUNTIME_DIR:-/tmp}/screen-record.file"

# Dang quay -> dung (SIGINT de gpu-screen-recorder ghi not file mp4)
if pgrep -f '^gpu-screen-recorder' >/dev/null; then
  pkill -SIGINT -f '^gpu-screen-recorder'
  for _ in $(seq 1 50); do pgrep -f '^gpu-screen-recorder' >/dev/null || break; sleep 0.1; done
  file=$(cat "$state" 2>/dev/null)
  rm -f "$state"
  if [[ -n $file && -s $file ]]; then
    notify-send -i media-record "Da luu video" "$file"
    printf '%s' "file://$file" | wl-copy -t text/uri-list 2>/dev/null
  else
    notify-send -u critical -i dialog-error "Quay man hinh" "Khong tao duoc file video"
  fi
  exit 0
fi

mkdir -p "$dir"
file="$dir/$(date +%Y%m%d-%H%M%S).mp4"

if [[ ${1:-} == --region ]]; then
  geom=$(slurp -b 00000066 -c ffffffff -w 2 -f '%wx%h+%x+%y') || exit 0   # Esc = huy
  target=(-w region -region "$geom")
else
  mon=$(hyprctl monitors -j | python3 -c 'import json,sys;m=json.load(sys.stdin);f=[x for x in m if x.get("focused")] or m;print(f[0]["name"])' 2>/dev/null)
  target=(-w "${mon:-screen}")
fi

printf '%s' "$file" > "$state"
setsid gpu-screen-recorder "${target[@]}" -f 60 -a default_output -c mp4 -o "$file" >/dev/null 2>&1 &
sleep 0.8
if pgrep -f '^gpu-screen-recorder' >/dev/null; then
  notify-send -t 2500 -i media-record "Dang quay man hinh" "Bam lai phim de dung va luu"
else
  rm -f "$state"
  notify-send -u critical -i dialog-error "Quay man hinh" "gpu-screen-recorder khong khoi dong duoc"
  exit 1
fi
