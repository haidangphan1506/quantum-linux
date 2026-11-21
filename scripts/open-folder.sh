#!/bin/sh
# Mở một thư mục bằng trình quản lý file (dùng cho Files / Tải về ở dock).
# xdg-open không đủ: nếu chưa chọn mặc định cho inode/directory, mimeinfo.cache có thể
# chọn kitty-open.desktop (mở terminal thay vì cửa sổ thư mục).
# Dùng:  open-folder.sh <đường dẫn>   |   open-folder.sh --downloads
dir="$1"
if [ "$dir" = "--downloads" ]; then
    dir=$(xdg-user-dir DOWNLOAD 2>/dev/null)
    # xdg-user-dir trả về $HOME khi chưa cấu hình thư mục tải về
    if [ -z "$dir" ] || [ "$dir" = "$HOME" ]; then dir="$HOME/Downloads"; fi
    mkdir -p "$dir"
fi
[ -n "$dir" ] || dir="$HOME"

# Ứng dụng mặc định người dùng đã chọn, nếu đó là trình quản lý file thật (không phải terminal)
def=$(xdg-mime query default inode/directory 2>/dev/null)
case "$def" in
    ""|kitty*|*terminal*|*Terminal*|*alacritty*|*foot*|*wezterm*|*ghostty*) ;;
    *) exec xdg-open "$dir" ;;
esac

for fm in nautilus thunar dolphin nemo caja pcmanfm-qt pcmanfm; do
    if command -v "$fm" >/dev/null 2>&1; then exec "$fm" "$dir"; fi
done
exec xdg-open "$dir"
