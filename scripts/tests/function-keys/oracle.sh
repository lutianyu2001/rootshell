#!/usr/bin/env bash
# Record what tmux sends to a pane for F1-F12 under each modifier prefix into
# tmux-raw.bin, '|'-separated, in the order main.swift expects. The committed
# file was recorded with tmux 3.4.
set -eu
cd "$(dirname "$0")"
out=$PWD/tmux-raw.bin; rm -f "$out"
tmux -L fkt -f /dev/null new-session -d -x 80 -y 24 "stty raw -echo; exec cat > '$out'"
sleep 0.5
for mod in "" S- M- C- S-M- C-S- C-M- C-M-S-; do
  for n in $(seq 1 12); do
    tmux -L fkt send-keys "${mod}F$n"; tmux -L fkt send-keys -l "|"
  done
done
sleep 0.5; tmux -L fkt kill-server
