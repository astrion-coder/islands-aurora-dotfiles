# Islands Aurora: zsh + Oh My Zsh + fzf.
# install.sh copies this to ~/.zshrc (re-running it replaces the file; the old one is backed
# up). Put your own aliases and settings in ~/.zshrc.local, which the installer never touches.

# ---------------------------------------------------------------- Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="avit"
plugins=(git)
# extra completions (zsh-completions) are already on the default fpath
source "$ZSH/oh-my-zsh.sh"

export EDITOR=nvim VISUAL=nvim

# ---------------------------------------------------------------- fzf
# Ctrl+T insert files, Ctrl+R search history, Alt+C cd into a directory, `**<Tab>` completion.
# Colours follow the wallpaper: matugen writes them to ~/.config/fzf/colors.
[[ -r "$HOME/.config/fzf/colors" ]] && export FZF_DEFAULT_OPTS_FILE="$HOME/.config/fzf/colors"
export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border=rounded --info=inline-right'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
_fzf_compgen_path() { fd --hidden --follow --exclude .git . "$1"; }
_fzf_compgen_dir()  { fd --type d --hidden --follow --exclude .git . "$1"; }
source <(fzf --zsh)

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
