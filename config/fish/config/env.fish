fish_add_path "$HOME/.local/bin"
fish_add_path "$HOME/bin"

set -gx BROWSER brave
set -gx TERMINAL kitty   # terminal emulator (shell mac dinh la fish)

# đẩy màu scheme hiện tại (caelestia) vào palette của terminal (color16-18, ...)
# thiếu dòng này thì các dòng dùng $2/$3/$4 trong fastfetch sẽ ra màu đen mặc định -> chữ vô hình
cat ~/.local/state/caelestia/sequences.txt 2>/dev/null