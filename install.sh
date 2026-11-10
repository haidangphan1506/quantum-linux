#!/usr/bin/env bash
# Quantum Shell (Caelestia) - trình cài đặt cho Arch Linux.
# Cài gói, font, cấu hình Hyprland (Lua) và liên kết shell vào ~/.config/quickshell/caelestia.
#
#   ./install.sh              cài đặt bình thường
#   ./install.sh --yes        không hỏi xác nhận (pacman --noconfirm)
#   ./install.sh --no-aur     bỏ qua gói AUR (font Material Symbols sẽ phải tự cài)
#   ./install.sh --dry-run    chỉ in ra việc sẽ làm
#   ./install.sh --no-hypr    không đụng tới ~/.config/hypr
#   ./install.sh --no-extras  bỏ qua gói dev (docker, lazygit, bun, opencode...)
#   ./install.sh --no-dotfiles không chép config fish/Thunar/pavucontrol/kitty
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/quantum"
BIN="$HOME/.local/bin"
USER="${USER:-$(id -un)}"
STAMP="$(date +%Y%m%d-%H%M%S)"

YES=0 AUR=1 DRY=0 HYPR=1 EXTRAS=1 DOTS=1
for a in "$@"; do
  case "$a" in
    -y|--yes) YES=1 ;;
    --no-aur) AUR=0 ;;
    --dry-run) DRY=1 ;;
    --no-hypr) HYPR=0 ;;
    --no-extras) EXTRAS=0 ;;
    --no-dotfiles) DOTS=0 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Tuỳ chọn không hợp lệ: $a" >&2; exit 2 ;;
  esac
done

c() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
w() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
run() { if ((DRY)); then printf '  (dry-run) %s\n' "$*"; else "$@"; fi; }

# ---------- kiểm tra môi trường ----------
[[ $EUID -ne 0 ]] || die "Đừng chạy bằng root/sudo. Script sẽ tự gọi sudo khi cần."
[[ -r /etc/arch-release ]] || die "Script này chỉ dành cho Arch Linux (hoặc dẫn xuất có pacman)."
command -v pacman >/dev/null || die "Không tìm thấy pacman."
command -v sudo >/dev/null || die "Cần cài sudo trước (pacman -S sudo)."
[[ -f "$REPO/shell.qml" ]] || die "Không thấy shell.qml trong $REPO - chạy script từ thư mục source."

PAC=(sudo pacman -S --needed); ((YES)) && PAC+=(--noconfirm)

# ---------- gói từ repo chính thức ----------
PKGS=(
  # compositor + shell
  hyprland quickshell xdg-desktop-portal-hyprland xdg-desktop-portal-gtk polkit-kde-agent
  # Qt6 mà các module QML import (Quick3D cho agentviz3d/agentoffice, Multimedia cho wallpaper động)
  qt6-declarative qt6-5compat qt6-multimedia qt6-quick3d qt6-svg qt6-wayland qt6-shadertools
  # âm thanh, mạng, bluetooth, nguồn
  pipewire pipewire-pulse pipewire-alsa wireplumber libpulse
  networkmanager nm-connection-editor bluez bluez-utils blueman
  upower power-profiles-daemon brightnessctl
  # công cụ shell gọi trực tiếp
  kitty cliphist wl-clipboard grim slurp playerctl libnotify jq curl git python
  pacman-contrib fastfetch ffmpeg xdg-utils
  # ứng dụng + font
  fish eza starship zoxide direnv swappy thunar exo xdg-user-dirs
  # thiếu trước đây: XWayland (app X11), ssh-agent (fish dùng), driver GPU/vulkan, Thunar (mount/ảnh thu nhỏ/nén), font có icon cho eza
  xorg-xwayland openssh pciutils mesa gvfs gvfs-mtp tumbler thunar-volman thunar-archive-plugin file-roller
  ttf-jetbrains-mono-nerd ripgrep base-devel less man-db bluez-obex
  nautilus firefox ttf-inter ttf-jetbrains-mono noto-fonts noto-fonts-emoji
)
c "Cài gói từ repo chính thức (${#PKGS[@]} gói)"
run "${PAC[@]}" "${PKGS[@]}"

# ---------- gói AUR ----------
# Dùng paru. Material Symbols Rounded: font icon bắt buộc (Theme.iconFont).
# hyprlauncher (Super+R) và hyprshutdown (Super+M) nếu chưa có trong repo chính.
AUR_PKGS=(ttf-material-symbols-variable-git)
aur_helper() { command -v paru >/dev/null && echo paru; }
if ((AUR)); then
  H="$(aur_helper || true)"
  if [[ -z "$H" ]]; then
    c "Chưa có paru - cài paru-bin từ AUR"
    if ((DRY)); then echo "  (dry-run) git clone https://aur.archlinux.org/paru-bin.git && makepkg -si"
    else
      sudo pacman -S --needed --noconfirm base-devel git
      tmp="$(mktemp -d)"; git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
      (cd "$tmp/paru-bin" && makepkg -si --noconfirm); rm -rf "$tmp"; H=paru
    fi
  fi
  c "Cài gói AUR: ${AUR_PKGS[*]}"
  A=("${H:-paru}" -S --needed); ((YES)) && A+=(--noconfirm)
  run "${A[@]}" "${AUR_PKGS[@]}" || w "Cài AUR thất bại - icon trên shell sẽ hiện ô vuông cho tới khi có font 'Material Symbols Rounded'."
else
  w "Bỏ qua AUR: tự cài font 'Material Symbols Rounded' (ttf-material-symbols-variable-git)."
fi

# ---------- dịch vụ systemd ----------
c "Bật dịch vụ: NetworkManager, bluetooth, upower, power-profiles-daemon"
for s in NetworkManager bluetooth upower power-profiles-daemon; do
  run sudo systemctl enable --now "$s.service" || w "Không bật được $s.service"
done
run systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service || true

# ---------- liên kết shell vào quickshell ----------
c "Liên kết shell: $CFG/quickshell/caelestia -> $REPO"
run mkdir -p "$CFG/quickshell" "$STATE" "$BIN" "$CFG/quantum"
link() { # link <đích> <đường dẫn liên kết>
  local target="$1" dest="$2"
  if [[ -L "$dest" ]]; then run ln -sfn "$target" "$dest"
  elif [[ -e "$dest" ]]; then w "Sao lưu $dest -> $dest.bak-$STAMP"; run mv "$dest" "$dest.bak-$STAMP"; run ln -s "$target" "$dest"
  else run ln -s "$target" "$dest"; fi
}
link "$REPO" "$CFG/quickshell/caelestia"
link "$REPO" "$CFG/quickshell/quantum"        # bí danh: một số comment/tài liệu dùng "qs -c quantum"

# launcher cho các app phụ + .desktop (Wm.qml tra icon/tên qua DesktopEntries)
link "$REPO/bin/quantum-taskmgr" "$BIN/quantum-taskmgr"
link "$REPO/apps/agentoffice/claude-agentoffice" "$BIN/claude-agentoffice"
link "$REPO/apps/agentviz3d/claude-agentviz3d" "$BIN/claude-agentviz3d"
run mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/scalable/apps"
for d in quantum-personalize quantum-assistant; do
  run install -Dm644 "$REPO/assets/$d.desktop" "$HOME/.local/share/applications/$d.desktop"
  run install -Dm644 "$REPO/assets/$d.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/$d.svg"
done
run gtk-update-icon-cache -qf "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
case ":$PATH:" in *":$BIN:"*) ;; *) w "$BIN chưa nằm trong PATH - thêm: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac

# ---------- gói bổ sung (chỉ cài cái còn thiếu) ----------
# Dùng `pacman -S --needed` nên gói đã có sẽ bị bỏ qua; gói không có trong repo thì thử AUR.
have() { pacman -Qq "$1" >/dev/null 2>&1; }
in_repo() { pacman -Si "$1" >/dev/null 2>&1; }
cmd_or_pkg() { command -v "$1" >/dev/null 2>&1 || have "$2"; }
EXTRA_PKGS=(
  blueman                                  # bluetooth GUI (đã nằm trong gói chính, giữ để chắc chắn)
  fcitx5-im fcitx5-unikey                  # nhóm fcitx5 (fcitx5, configtool, gtk, qt) + bộ gõ Telex/VNI
  htop btop pavucontrol networkmanager unzip
  docker docker-compose                    # nmcli nằm trong networkmanager
  lazygit lazydocker
  hyprlauncher hyprshutdown                # Super+R / Super+M trong config (repo hoặc AUR)
)
install_extras() {
  local missing=() aur=() p
  for p in "${EXTRA_PKGS[@]}"; do
    # nhóm gói (fcitx5-im) -> pacman -Sg; còn lại kiểm tra đã cài chưa
    if pacman -Sg "$p" >/dev/null 2>&1; then missing+=("$p"); continue; fi
    have "$p" && continue
    if in_repo "$p"; then missing+=("$p"); else aur+=("$p"); fi
  done
  ((${#missing[@]})) && { c "Cài thêm: ${missing[*]}"; run "${PAC[@]}" "${missing[@]}"; } || c "Gói bổ sung (repo): đã đủ"
  if ((${#aur[@]})); then
    if ((AUR)) && [[ -n "$(aur_helper || true)" ]]; then
      local H2; H2="$(aur_helper)"; local A2=("$H2" -S --needed); ((YES)) && A2+=(--noconfirm)
      c "Không có trong repo chính, cài từ AUR: ${aur[*]}"; run "${A2[@]}" "${aur[@]}" || w "AUR thất bại: ${aur[*]}"
    else w "Không cài được (không có trong repo, AUR bị tắt/không có helper): ${aur[*]}"; fi
  fi

  # bun: repo -> AUR (bun-bin) -> script chính thức
  if ! cmd_or_pkg bun bun && ! command -v "$HOME/.bun/bin/bun" >/dev/null; then
    c "Cài bun"
    if in_repo bun; then run "${PAC[@]}" bun
    elif ((AUR)) && [[ -n "$(aur_helper || true)" ]]; then run "$(aur_helper)" -S --needed ${YES:+--noconfirm} bun-bin
    else run bash -c 'curl -fsSL https://bun.sh/install | bash' || w "Cài bun thất bại"; fi
  fi
  # opencode-ai (npm package) qua bun
  local B; B="$(command -v bun || echo "$HOME/.bun/bin/bun")"
  if command -v opencode >/dev/null || [[ -x "$HOME/.bun/bin/opencode" ]]; then c "opencode-ai: đã có"
  elif ((DRY)) || [[ -x "$B" ]]; then c "Cài opencode-ai (bun)"; run "$B" install -g opencode-ai || w "Cài opencode-ai thất bại"
  else w "Bỏ qua opencode-ai vì chưa có bun"; fi

  # docker: bật dịch vụ + thêm user vào nhóm docker (cần đăng nhập lại)
  if have docker || ((DRY)); then
    run sudo systemctl enable --now docker.service || w "Không bật được docker.service"
    id -nG "$USER" | tr ' ' '\n' | grep -qx docker || { run sudo usermod -aG docker "$USER"; w "Đã thêm $USER vào nhóm docker - đăng xuất/đăng nhập lại để dùng docker không cần sudo."; }
  fi
}
((EXTRAS)) && install_extras

# ---------- driver GPU (phát hiện bằng lspci) ----------
gpu_drivers() {
  command -v lspci >/dev/null || return 0
  local g; g="$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display')"; local d=()
  grep -qi 'intel'  <<<"$g" && d+=(vulkan-intel intel-media-driver)
  grep -qiE 'amd|ati|radeon' <<<"$g" && d+=(vulkan-radeon libva-mesa-driver)
  grep -qi 'nvidia' <<<"$g" && d+=(nvidia-open-dkms nvidia-utils linux-headers) && w "NVIDIA: cần thêm 'nvidia_drm.modeset=1' vào kernel cmdline và env LIBVA_DRIVER_NAME/GBM_BACKEND theo wiki Hyprland."
  ((${#d[@]})) && { c "Driver GPU: ${d[*]}"; run "${PAC[@]}" "${d[@]}" || w "Cài driver GPU thất bại"; }
  return 0
}
gpu_drivers

# ---------- chép cấu hình vào hệ thống ----------
# Chép (không symlink) để bạn sửa tự do; bản cũ được sao lưu thành <tên>.bak-<ngày>.
put() { # put <nguồn> <đích>  (file hoặc thư mục)
  local src="$1" dst="$2"
  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ -d "$src" && -d "$dst" ]] && diff -rq "$src" "$dst" >/dev/null 2>&1; then return; fi
    if [[ -f "$src" && -f "$dst" ]] && cmp -s "$src" "$dst"; then return; fi
    w "Sao lưu $dst -> $dst.bak-$STAMP"; run mv "$dst" "$dst.bak-$STAMP"
  fi
  run mkdir -p "$(dirname "$dst")"; run cp -a "$src" "$dst"
}
if ((HYPR)); then
  c "Cấu hình Hyprland (Lua, cần Hyprland >= 0.55): $CFG/hypr"
  put "$REPO/config/hypr" "$CFG/hypr"
  run chmod +x "$CFG/hypr/scripts/"*.sh 2>/dev/null || true
fi
if ((DOTS)); then
  c "Cấu hình fish, Thunar, pavucontrol, kitty"
  put "$REPO/config/fish"    "$CFG/fish"
  put "$REPO/config/Thunar"  "$CFG/Thunar"
  put "$REPO/config/pavucontrol.ini" "$CFG/pavucontrol.ini"
  # kitty chạy fish; Thunar "Open Terminal Here" (exo-open) dùng kitty
  if [[ ! -e "$CFG/kitty/kitty.conf" ]]; then
    run mkdir -p "$CFG/kitty"; ((DRY)) || printf 'shell /usr/bin/fish\nconfirm_os_window_close 0\n' > "$CFG/kitty/kitty.conf"
  else grep -q '^shell ' "$CFG/kitty/kitty.conf" || { ((DRY)) || printf '\nshell /usr/bin/fish\n' >> "$CFG/kitty/kitty.conf"; }; fi
  if [[ ! -e "$CFG/xfce4/helpers.rc" ]]; then
    run mkdir -p "$CFG/xfce4"; ((DRY)) || printf 'TerminalEmulator=kitty\n' > "$CFG/xfce4/helpers.rc"
  fi
  # fish là shell đăng nhập mặc định
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != */fish ]]; then
    c "Đặt fish làm shell mặc định"
    run sudo chsh -s /usr/bin/fish "$USER" || w "chsh thất bại - chạy tay: chsh -s /usr/bin/fish"
  fi
fi

# ---------- kiểm tra cuối ----------
if ! ((DRY)); then
  c "Kiểm tra"
  v="$(Hyprland --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | tr -d v || true)"
  if [[ -n "$v" ]]; then
    echo "  Hyprland $v"
    [[ "$(printf '%s\n0.55\n' "$v" | sort -V | head -1)" == "0.55" ]] || w "Hyprland < 0.55 không đọc được cấu hình Lua / lệnh 'hyprctl eval' mà shell dùng. Hãy cập nhật (pacman -Syu)."
  fi
  command -v qs >/dev/null && echo "  quickshell: $(qs --version 2>/dev/null | head -1)" || w "Không thấy lệnh qs"
  fc-list | grep -qi 'Material Symbols' && echo "  font Material Symbols: OK" || w "Thiếu font Material Symbols Rounded"
  python3 -B -c 'import ast,glob,sys; [ast.parse(open(f).read()) for f in glob.glob(sys.argv[1]+"/scripts/*.py")]' "$REPO" && echo "  scripts python: OK"
fi

cat <<MSG

Hoàn tất. Cách chạy:
  • Từ TTY (đăng nhập bằng user thường):   Hyprland
  • Đang trong một phiên Hyprland:          qs -c caelestia      (xem log: qs -c caelestia log)
  • Phím tắt mặc định: Super+Space (launcher), Super+A (control center), Super+Tab (overview),
    Super+L (khoá), Super+I (Personalize), Super+Enter hoặc Ctrl+Alt+T (terminal kitty + fish).
    Xem config/hypr/variable.lua. Bộ gõ Việt: chạy fcitx5-configtool để thêm Unikey.
MSG
