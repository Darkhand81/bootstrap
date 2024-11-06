#!/bin/bash

# ----------------------------------------------------------------
# Darkhand's default tmux console
# Spawns a console split into 4 panels, with htop and bmon running
# ----------------------------------------------------------------

# Give your session a name:
SESSIONNAME="$(hostname)"

# Function to find the first active network interface
get_active_interface() {
  # List all network interfaces that are up, exclude loopback, and select the first one
  ip -o link show up | \
    awk -F': ' '{print $2}' | \
    grep -v '^lo$' | \
    head -n1
}

# Get the first active interface for bmon
INTERFACE=$(get_active_interface)

function has-session {
  tmux has-session -t $SESSIONNAME 2>/dev/null
}

if has-session ; then
    echo "ERROR: Session already exists. Connect with 'tmux attach'."
  else
    # No session found. Create main tmux session:
    tmux new-session -s $SESSIONNAME \; \
      split-window -v \; \
      split-window -h \; \
      select-pane -t 0 \; \
      split-window -h \; \
      send-keys 'htop' C-m \; \
      split-window -v -l 15 \; \
      send-keys "bmon -p $INTERFACE" C-m \; \
      select-pane -t 3
fi
