#!/usr/bin/env bash
# Build plugin hyprbars (thanh tieu de kieu macOS: nut do/vang/xanh, bam dup header)
# cho dung phien ban Hyprland dang cai, roi chep vao ~/.local/lib/hyprland/hyprbars.so
# (titlebar.lua nap file nay). Can: git, g++, make, pkg-config, header Hyprland (goi hyprland).
#
#   ~/.config/hypr/scripts/build-hyprbars.sh          build + cai
#   ~/.config/hypr/scripts/build-hyprbars.sh --reload  build + cai + hyprctl reload
set -euo pipefail

DEST="$HOME/.local/lib/hyprland"
REPO_URL="https://github.com/hyprwm/hyprland-plugins.git"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for c in git g++ make pkg-config; do
  command -v "$c" >/dev/null || { echo "Thieu lenh: $c" >&2; exit 1; }
done
HV="$(pkg-config --modversion hyprland 2>/dev/null)" || {
  echo "Khong tim thay header Hyprland (pkg-config hyprland)." >&2; exit 1; }
echo "==> Hyprland $HV"

git clone -q "$REPO_URL" "$WORK/hyprland-plugins"
cd "$WORK/hyprland-plugins"

# Neu hyprpm.toml co pin cho dung commit Hyprland dang chay thi checkout commit do,
# khong thi dung main (ban moi nhat, khop voi Hyprland moi nhat).
HC="$(hyprctl version -j 2>/dev/null | sed -n 's/.*"commit": *"\([0-9a-f]*\)".*/\1/p' | head -1 || true)"
if [[ -n "$HC" ]]; then
  PIN="$(grep -o "\[\"$HC[0-9a-f]*\", *\"[0-9a-f]*\"\]" hyprpm.toml | sed 's/.*, *"\([0-9a-f]*\)"\]/\1/' | head -1 || true)"
  if [[ -n "$PIN" ]]; then echo "==> Dung pin $PIN"; git checkout -q "$PIN"; fi
fi

echo "==> Build hyprbars"
make -C hyprbars all
mkdir -p "$DEST"
install -m 755 hyprbars/hyprbars.so "$DEST/hyprbars.so"
echo "==> Da cai $DEST/hyprbars.so"

if [[ "${1:-}" == "--reload" ]]; then
  hyprctl reload >/dev/null && echo "==> Da reload Hyprland"
else
  echo "Chay 'hyprctl reload' (hoac dang nhap lai) de hien thanh tieu de."
fi
