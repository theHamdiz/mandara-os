# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
	PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Your own additions can go in ~/.bashrc.d/*.
if [ -d ~/.bashrc.d ]; then
	for rc in ~/.bashrc.d/*; do
		if [ -f "$rc" ]; then
			. "$rc"
		fi
	done
fi
unset rc

if [[ $- == *i* ]]; then
	eval "$(starship init bash)"
	eval "$(zoxide init bash)"
	eval "$(atuin init bash)"

	alias ls='eza --icons'
	alias ll='eza -la --icons --git'
	alias cat='bat --paging=never'
fi
