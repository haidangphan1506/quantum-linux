# Lời chào + thông tin hệ thống khi mở terminal fish (chỉ shell tương tác).
# Tắt: set -U quantum_no_greeting 1   |   Bật lại: set -e quantum_no_greeting
function fish_greeting
    set -q quantum_no_greeting; and return
    status is-interactive; or return
    test -t 1; or return   # không hiện khi chạy trong pipe/script

    # lời chào + icon theo giờ
    set -l h (date +%H | string replace -r '^0' '')
    set -l hello "Chào buổi sáng" icon "󰖜"
    if test $h -ge 22 -o $h -lt 5
        set hello "Khuya rồi, nghỉ sớm nhé"; set icon "󰖔"
    else if test $h -ge 18
        set hello "Chào buổi tối"; set icon "󰖔"
    else if test $h -ge 12
        set hello "Chào buổi chiều"; set icon "󰖙"
    end

    set -l accent 50fa7b
    set -l dim 6272a4
    set -l line1 "$icon  $hello, $USER!"
    set -l line2 "󰃭  "(date '+%A, %d/%m/%Y')"   "(date '+%H:%M')"   󰌢  "$hostname
    set -l w (math (string length --visible -- $line1 $line2 | sort -n | tail -1) + 4)
    set -l bar (string repeat -n $w ─)

    # khung chào
    set_color $dim; printf '╭%s╮\n' $bar
    printf '│'; set_color -o $accent; printf '  %s' $line1; set_color $dim
    printf '%*s│\n' (math $w - 2 - (string length --visible -- $line1)) ''
    printf '│'; set_color normal; set_color $dim; printf '  %s' $line2
    printf '%*s│\n' (math $w - 2 - (string length --visible -- $line2)) ''
    printf '╰%s╯\n' $bar; set_color normal

    # thông tin hệ thống: icon nerd font + thanh phần trăm
    if type -q fastfetch
        fastfetch --logo none --pipe false --key-type icon --percent-type 3 \
            --color-keys "38;2;80;250;123" --color-title "38;2;189;147;249" \
            --structure OS:Kernel:Uptime:Packages:Shell:WM:CPU:GPU:Memory:Disk:Battery:LocalIp 2>/dev/null
    else
        printf 'OS: %s\nKernel: %s\nUptime: %s\n' (uname -n) (uname -r) (uptime -p)
    end

    # dải màu palette
    printf ' '
    for c in ff5555 ffb86c f1fa8c 50fa7b 8be9fd bd93f9 ff79c6
        set_color $c; printf '██▌ '
    end
    set_color normal; printf '\n\n'
end
