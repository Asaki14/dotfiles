# ~/.config/fish/config.fish

set -g fish_autosuggestion_enabled 1

fish_add_path /usr/local/bin /opt/homebrew/bin $HOME/.npm-global/bin $HOME/.local/bin

# API keys are stored locally in:
#   ~/.config/fish/conf.d/api_keys.local.fish
# Fish loads conf.d/*.fish automatically; the local key file is gitignored.

alias c="clear"
alias mole="/opt/homebrew/opt/mole/bin/mole"
alias agy="agy --dangerously-skip-permissions"

function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if set cwd (command cat -- "$tmp"); and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

function fish_user_key_bindings
    fish_default_key_bindings
end

function proxy
    set -gx http_proxy http://127.0.0.1:7897
    set -gx https_proxy http://127.0.0.1:7897
    set -gx all_proxy http://127.0.0.1:7897
    set -gx HTTP_PROXY http://127.0.0.1:7897
    set -gx HTTPS_PROXY http://127.0.0.1:7897
end

function noproxy
    set -e http_proxy
    set -e https_proxy
    set -e all_proxy
    set -e HTTP_PROXY
    set -e HTTPS_PROXY
end
