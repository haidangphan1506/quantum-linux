# nếu không phải interactive thì skip
if not status is-interactive
    exit
end

# check starshup,direnv, eza,zoxide và init ngay tại fish
if type -q starship
    starship init fish | source
end

if type -q direnv
    direnv hook fish | source
end

if type -q zoxide
    zoxide init fish --cmd z | source
end