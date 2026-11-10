# check status interactive của shell : khi mở kiity/fish => interactive , nhưng khi thực thị script có thể không phải
# check tồn tại file local.config thì reload không thì bỏ qua

if status is-interactive
    # ssh-agent chi khoi dong cho shell tuong tac (truoc day chay ca khi chay script -> sinh agent thua)
    if not set -q SSH_AUTH_SOCK
        eval (ssh-agent -c | string collect) >/dev/null
    end
    if test -f ~/.ssh/id_ed25519_personal
        ssh-add ~/.ssh/id_ed25519_personal 2>/dev/null   # --apple-use-keychain chi co tren macOS
    end

    # nạp tất cả module trong fish/config/ (alias, env, tools, ...)
    for f in $__fish_config_dir/config/*.fish
        source $f
    end

    set -l local_config "$HOME/.config/fish/local.config"

    # Auto load SSH keys
    for key in \
        ~/.ssh/id_ed25519_gitlab \
        ~/.ssh/id_ed25519_github

        if test -f $key
            ssh-add $key 2>/dev/null
        end
    end
end
# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
