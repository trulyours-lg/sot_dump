#!/usr/bin/env bash
# sot-session.sh — build the SOT working layout in one command.
# Usage:  ./sot-session.sh      (creates or reattaches to session "sot")
set -euo pipefail

SESSION="sot"
ROOT="${SOT_ROOT:-$HOME/sot}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach -t "$SESSION"
fi

# Window 1: code — editor left, shell right
tmux new-session  -d -s "$SESSION" -n code -c "$ROOT"
tmux split-window -h -t "$SESSION:code" -c "$ROOT"
tmux select-pane  -t "$SESSION:code.1"

# Window 2: server — cargo run top, logs bottom
tmux new-window   -t "$SESSION" -n server -c "$ROOT"
tmux split-window -v -t "$SESSION:server" -c "$ROOT"
tmux send-keys    -t "$SESSION:server.2" 'journalctl -f -u caddy' C-m

# Window 3: db — psql
tmux new-window   -t "$SESSION" -n db -c "$ROOT"
tmux send-keys    -t "$SESSION:db" 'psql -d sot_research_2026' C-m

# Window 4: git
tmux new-window   -t "$SESSION" -n git -c "$ROOT"
tmux send-keys    -t "$SESSION:git" 'lazygit' C-m

# Window 5: agent
tmux new-window   -t "$SESSION" -n agent -c "$ROOT"

tmux select-window -t "$SESSION:code"
exec tmux attach -t "$SESSION"
