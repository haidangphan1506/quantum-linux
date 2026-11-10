if not status is-interactive
    exit
end

# Files
alias ls "eza --icons --group-directories-first -1"
alias ll "eza --icons --group-directories-first -lah"
alias la "eza --icons --group-directories-first -a"
alias lla "eza --icons --group-directories-first -la"

# Git
alias gs 'git status'
alias gd 'git diff'
alias ga 'git add .'
alias gc 'git commit'
alias gl 'git log'
alias gp 'git push'
alias gpl 'git pull'
alias gpd 'git pull origin develop'
alias gst 'git stash'
alias gsp 'git stash pop'
alias gw 'git switch'
alias gwt 'git switch main'
alias gb 'git branch'
alias gbd 'git branch -d'

# Docker
alias d docker
alias dcu "docker compose up -d"
alias dd "docker compose down"
alias dps "docker ps"   # (bo alias ps->podman: de len lenh ps he thong)
alias lg lazygit
alias lzd lazydocker
# System
alias c clear
alias cls clear
alias bs 'bun start:dev'

# Caelestia Themes
alias ctheme '~/.config/scripts/caelestia-themes.sh'
alias ctheme-light '~/.config/scripts/caelestia-themes.sh light'
alias ctheme-dark '~/.config/scripts/caelestia-themes.sh dark'
alias ctheme-toggle '~/.config/scripts/caelestia-themes.sh toggle'
alias ctheme-status '~/.config/scripts/caelestia-themes.sh status'
