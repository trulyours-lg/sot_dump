#!/usr/bin/env bash
# bootstrap-devtools.sh — terminal tooling for vm-trulyours (Debian 13 / trixie)
# Idempotent: safe to re-run.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

BIN="$HOME/.local/bin"
mkdir -p "$BIN"

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

# ---------------------------------------------------------------- apt packages
say "Installing apt packages"
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends \
  tmux \
  neovim \
  ripgrep \
  fd-find \
  bat \
  fzf \
  jq \
  htop \
  tree \
  curl \
  wget \
  git \
  unzip \
  zsh \
  zsh-autosuggestions \
  zsh-syntax-highlighting \
  build-essential \
  pkg-config \
  libssl-dev

# Debian ships these under alternate names to avoid collisions.
say "Linking fd and bat to conventional names"
[[ -x /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind "$BIN/fd"
[[ -x /usr/bin/batcat ]] && ln -sf /usr/bin/batcat "$BIN/bat"

# -------------------------------------------------------------------- lazygit
say "Installing lazygit"
if ! command -v lazygit >/dev/null 2>&1; then
  LG_VER=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
    | jq -r '.tag_name' | tr -d 'v')
  TMP=$(mktemp -d)
  curl -fsSL -o "$TMP/lazygit.tar.gz" \
    "https://github.com/jesseduffield/lazygit/releases/download/v${LG_VER}/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
  tar -xzf "$TMP/lazygit.tar.gz" -C "$TMP" lazygit
  install -m 755 "$TMP/lazygit" "$BIN/lazygit"
  rm -rf "$TMP"
  echo "lazygit ${LG_VER} installed"
else
  echo "lazygit already present: $(lazygit --version | head -1)"
fi

# ----------------------------------------------------------------- PATH + env
say "Ensuring ~/.local/bin is on PATH"
if ! grep -qs 'HOME/.local/bin' "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<'EOF'

# --- dev tooling ---
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nvim
export VISUAL=nvim
alias ll='ls -lah'
alias gs='git status -sb'
alias lg='lazygit'
# fzf-powered file open
fe() { local f; f=$(fzf --preview 'bat --color=always --style=numbers {} 2>/dev/null || cat {}'); [[ -n "$f" ]] && ${EDITOR} "$f"; }
EOF
fi

# fzf keybindings (Ctrl-R history search, Ctrl-T file search)
if ! grep -qs 'fzf/key-bindings' "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<'EOF'
[[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]] && . /usr/share/doc/fzf/examples/key-bindings.bash
[[ -f /usr/share/bash-completion/completions/fzf ]] && . /usr/share/bash-completion/completions/fzf
EOF
fi

say "Done. Run:  source ~/.bashrc"
printf '\nInstalled: %s\n' "$(command -v tmux nvim rg fzf jq lazygit 2>/dev/null | tr '\n' ' ')"
