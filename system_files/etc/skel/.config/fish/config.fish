if status is-interactive
    starship init fish | source
    zoxide init fish | source
    atuin init fish | source

    alias ls 'eza --icons'
    alias ll 'eza -la --icons --git'
    alias cat 'bat --paging=never'
end
