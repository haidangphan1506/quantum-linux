#!/usr/bin/env bash
# Tối ưu mạng cho Quantum Linux. Chạy: sudo scripts/net-optimize.sh [--aspm]
#   --aspm  tắt ASPM L1/L1.1 của card Realtek rtw89 (bớt giật/rớt wifi, tốn pin hơn chút; cần reboot)
# Chạy lại nhiều lần không sao (idempotent).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Chạy bằng sudo" >&2; exit 1; }
c() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

c "TCP: BBR + bộ đệm lớn hơn"
echo tcp_bbr > /etc/modules-load.d/quantum-bbr.conf
modprobe tcp_bbr
cat > /etc/sysctl.d/90-quantum-net.conf <<'EOF'
# BBR chịu mất gói trên wifi tốt hơn cubic nhiều; fq lo pacing cho các card không bị netprio shape
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# bộ đệm TCP tới 16 MiB (mặc định gửi chỉ 4 MiB)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
# không reset cửa sổ sau khi kết nối nghỉ (keep-alive HTTP/2, SSH, websocket)
net.ipv4.tcp_slow_start_after_idle = 0
# tự dò MTU khi gặp “lỗ đen” ICMP (hay gặp ở wifi công cộng / VPN)
net.ipv4.tcp_mtu_probing = 1
# TCP Fast Open cả chiều client lẫn server
net.ipv4.tcp_fastopen = 3
net.core.netdev_max_backlog = 4096
EOF
sysctl -q --system

c "Wifi: tắt power-save"
cat > /etc/NetworkManager/conf.d/90-quantum-wifi.conf <<'EOF'
[connection]
# 2 = tắt. Power-save làm ping giật và tốc độ dao động trên rtw89
wifi.powersave=2
EOF

c "Bỏ trình quản lý mạng trùng lặp (NetworkManager lo hết) — có hiệu lực sau reboot"
# iwd + wpa_supplicant cùng chạy → giành nhau wlan0 ("is another supplicant running?").
# systemd-networkd cũng chạy DHCP trên wlan0 → 2 IP, 2 default route.
# KHÔNG dừng chúng ngay: iwd khi thoát sẽ hạ wlan0 → wifi rớt và NetworkManager
# coi wlan0 là "unmanaged", không tự kết nối lại. Chỉ disable + mask (để D-Bus/socket
# không bật lại), lần khởi động sau chỉ còn NetworkManager + wpa_supplicant.
systemctl disable -q iwd.service 2>/dev/null || true
systemctl mask -q iwd.service
systemctl disable -q systemd-networkd.socket systemd-networkd.service \
  systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask -q systemd-networkd.socket systemd-networkd.service systemd-networkd-wait-online.service

if [ "${1:-}" = "--aspm" ]; then
  c "rtw89: tắt ASPM L1 (áp dụng sau reboot)"
  echo "options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y" > /etc/modprobe.d/quantum-rtw89.conf
fi

# Đọc lại cấu hình (powersave) mà không ngắt kết nối hiện tại
systemctl reload NetworkManager

# netprio (nếu có): cài bản mới (đo tốc độ bằng 4 luồng song song)
U=${SUDO_USER:-}
NP="$(getent passwd "$U" 2>/dev/null | cut -d: -f6)/.local/share/netprio/install.sh"
if [ -n "$U" ] && [ -x "$NP" ]; then
  c "Cập nhật netprio"
  "$NP" || true
fi

c "Kết quả"
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
echo
echo "Khởi động lại máy để tắt hẳn iwd/systemd-networkd (bỏ IP + route trùng)."
echo "Hoàn tác: sudo systemctl unmask iwd systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service"
