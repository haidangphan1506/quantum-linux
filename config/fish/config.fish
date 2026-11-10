# Chỉ cấu hình cho shell tương tác (mở kitty/fish); script chạy bằng fish bỏ qua phần này.
# Cấu hình riêng từng máy: ~/.config/fish/local.config (nếu có thì được nạp cuối cùng).

if status is-interactive
    # ssh-agent chi khoi dong cho shell tuong tac (truoc day chay ca khi chay script -> sinh agent thua)
    if not set -q SSH_AUTH_SOCK
        eval (ssh-agent -c | string collect) >/dev/null
    end
    # nạp mọi khoá ~/.ssh/id_ed25519* (bỏ .pub); --apple-use-keychain chỉ có trên macOS
    for key in ~/.ssh/id_ed25519*
        string match -q '*.pub' -- $key; and continue
        ssh-add $key 2>/dev/null
    end

    # nạp tất cả module trong fish/config/ (alias, env, tools, ...)
    for f in $__fish_config_dir/config/*.fish
        source $f
    end

    set -l local_config "$HOME/.config/fish/local.config"
    if test -f $local_config
        source $local_config
    end
end

# bun
set --export BUN_INSTALL "$HOME/.bun"
fish_add_path -g $BUN_INSTALL/bin
