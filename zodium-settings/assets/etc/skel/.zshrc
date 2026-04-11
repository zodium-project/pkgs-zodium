# ==============================================================
#  ~/.zshrc — User Zsh configuration
#  Zodium Project : github.com/zodium-project
# ==============================================================

# ── History ───────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=1500
SAVEHIST=1500

# ── Keybindings ───────────────────────────────────────────────
bindkey -e

# ── Directory Navigation ──────────────────────────────────────
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT

# ── Correction ────────────────────────────────────────────────
setopt CORRECT

# ── Completion ────────────────────────────────────────────────
autoload -Uz compinit
compinit -C