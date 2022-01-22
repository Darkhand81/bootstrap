#!/bin/bash

# ----------------------------------------------------------------
# Darkhand's default tmux console
# Spawns a console split into 4 panels, with htop and bmon running
# ----------------------------------------------------------------

# Give your session a name:
SESSIONNAME="myserver"

# Internet interface:
INTERFACE="ens18"

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
