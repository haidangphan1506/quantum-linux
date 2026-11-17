#!/usr/bin/env bash
# Cài theme đăng nhập SDDM kiểu macOS (config/sddm/quantum-macos) và đặt làm mặc định.
#   sudo ./config/sddm/install-sddm-theme.sh [đường_dẫn_ảnh_nền]
# Mặc định lấy ảnh nền ~/Pictures/Wallpapers/quantum-silk-dark.png của người gọi sudo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Cần chạy bằng sudo." >&2
    exit 1
fi

here="$(cd "$(dirname "$0")" && pwd)"
theme="quantum-macos"
dest="/usr/share/sddm/themes/$theme"

# Thư mục home của người dùng gọi sudo (không phải /root)
user="${SUDO_USER:-root}"
home="$(getent passwd "$user" | cut -d: -f6)"
wall="${1:-$home/Pictures/Wallpapers/quantum-silk-dark.png}"

if [[ ! -f "$wall" ]]; then
    echo "Không thấy ảnh nền: $wall" >&2
    echo "Tạo bằng: python3 scripts/gen-macos-wallpaper.py" >&2
    exit 1
fi

install -d "$dest"
install -m644 "$here/$theme/Main.qml" "$here/$theme/metadata.desktop" \
              "$here/$theme/theme.conf" "$dest/"
install -m644 "$wall" "$dest/background.png"

install -d /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-quantum.conf <<CONF
[Theme]
Current=$theme
CONF

echo "Đã cài theme '$theme' vào $dest và đặt làm mặc định."
echo "Xem thử: sddm-greeter-qt6 --test-mode --theme $dest"
