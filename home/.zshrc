# Islands Aurora: zsh + Oh My Zsh + fzf.
# install.sh copies this to ~/.zshrc (re-running it replaces the file; the old one is backed
# up). Put your own aliases and settings in ~/.zshrc.local, which the installer never touches.

# ---------------------------------------------------------------- Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="avit"
# vi keys on the command line: Esc for normal mode, `vv` to edit the command in nvim.
# Beam cursor in insert mode, block in normal mode; Esc switches without a delay.
VI_MODE_SET_CURSOR=true
KEYTIMEOUT=1
plugins=(git vi-mode)
# extra completions (zsh-completions) are already on the default fpath
source "$ZSH/oh-my-zsh.sh"

export EDITOR=nvim VISUAL=nvim

# ---------------------------------------------------------------- fzf
# Ctrl+T insert files, Ctrl+R search history, Alt+C cd into a directory, `**<Tab>` completion.
export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border=rounded --info=inline-right'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
_fzf_compgen_path() { fd --hidden --follow --exclude .git . "$1"; }
_fzf_compgen_dir()  { fd --type d --hidden --follow --exclude .git . "$1"; }
source <(fzf --zsh)

# `pacman -Ss <query>`: browse the repos in fzf with package details on the right; installed
# packages are marked in green. The query matches package names only. Tab marks several,
# Enter installs the selection. Every other pacman command works as usual.
pacman() {
    if [[ "$1" == "-Ss" ]]; then
        shift
        command pacman -Sl \
            | awk '{ printf "%s \033[2m%s\033[0m%s\n", $2, $1, ($4 ~ /^\[installed/ ? "  \033[32minstalled\033[0m" : "") }' \
            | fzf --ansi --multi --nth=1 --query="$*" --preview 'pacman -Si {1}' \
            | awk '{ print $1 }' | xargs -ro sudo pacman -S
    else
        command pacman "$@"
    fi
}

# ---------------------------------------------------------------- your additions
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# ---------------------------------------------------------------- plugins (Arch packages)
# Suggestions are drawn in terminal colour 8, which matugen themes. Syntax highlighting
# has to be loaded last.
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    [[ -r /usr/share/zsh/plugins/$plugin/$plugin.zsh ]] && source /usr/share/zsh/plugins/$plugin/$plugin.zsh
done
unset plugin
