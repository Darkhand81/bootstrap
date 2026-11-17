#!/bin/bash

# ----------------------------------------------------------------
# Darkhand's default tmux console (v2)
# Spawns a console split into 4 panels, with htop and bmon running
# ----------------------------------------------------------------

# Short hostname: tmux doesn't allow '.' in session names
SESSIONNAME="$(hostname -s)"

# First interface that is up, excluding loopback.
# Strip any '@peer' suffix (e.g. veth0@if3 -> veth0) so bmon accepts it.
INTERFACE=$(ip -o link show up | awk -F': ' '$2 != "lo" {sub(/@.*/, "", $2); print $2; exit}')

# '=' forces an exact name match instead of a prefix match
if tmux has-session -t "=$SESSIONNAME" 2>/dev/null; then
  echo "ERROR: Session already exists. Connect with 'tmux attach -t $SESSIONNAME'."
  exit 1
fi

# Create detached at the real terminal size so the fixed-height split fits
top_left=$(tmux new-session -d -s "$SESSIONNAME" -x "$(tput cols)" -y "$(tput lines)" -P -F '#{pane_id}')
bottom_left=$(tmux split-window -v -t "$top_left" -P -F '#{pane_id}')
tmux split-window -h -t "$bottom_left"
top_right=$(tmux split-window -h -t "$top_left" -P -F '#{pane_id}')
bmon_pane=$(tmux split-window -v -l 15 -t "$top_right" -P -F '#{pane_id}')

tmux send-keys -t "$top_right" 'htop' C-m
tmux send-keys -t "$bmon_pane" "bmon -p $INTERFACE" C-m

tmux select-pane -t "$bottom_left"
exec tmux attach-session -t "$SESSIONNAME"
