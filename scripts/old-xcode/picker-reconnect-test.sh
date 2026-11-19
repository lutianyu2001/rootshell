#!/bin/zsh
# End-to-end test of what rootshell reconnects to after a zmx session was
# attached from its session picker. See docs/old-xcode-compat.md.
#
# Usage: scripts/old-xcode/picker-reconnect-test.sh <APP> <WORK_DIR> <ZMX> <KEY> [<PORT>]
#   APP       rootshell.app from build-catalyst.sh
#   WORK_DIR  where the Python environment, zmx's sockets and the logs go
#   ZMX       a zmx binary for this Mac
#   KEY       a program that presses a key by its Mac virtual key code
#             (the compiled tools/key.swift); needs Accessibility
# Starts zmx_reconnect_sshd.py, which runs real processes, with a zmx session
# named 1 already running; launches the app with the test switches and opens
# an ssh:// URL to the server. When the picker has listed the session, it
# presses 1, which attaches it. The server drops that connection; rootshell
# reconnects, and the server reports what the new connection's terminal runs.
# Exits 0 when it reattached the session, 1 when it came back to a shell, 2
# when no verdict arrived. Leaves a screenshot of the reconnected pane in
# WORK_DIR.
set -u
if [ $# -lt 4 ]; then
  echo "usage: $0 <APP> <WORK_DIR> <ZMX> <KEY> [<PORT>]" >&2
  exit 2
fi
HERE=${0:A:h}
APP=${1:A}
WORK=${2:A}
ZMX=${3:A}
KEY=${4:A}
PORT=${5:-2223}
SESSION=1
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/zmx"
LOG=$WORK/server.log
rm -f "$LOG" "$WORK/server.err" "$WORK/after-reconnect.png"
cp "$ZMX" "$WORK/bin/zmx"

[ -x "$WORK/venv/bin/python" ] || python3 -m venv "$WORK/venv"
"$WORK/venv/bin/python" -c 'import paramiko' 2>/dev/null || "$WORK/venv/bin/pip" -q install paramiko

# zmx's sockets go to the work directory, apart from the user's own sessions.
ENVFILE=$WORK/env
cat > "$ENVFILE" <<EOF
PATH=$WORK/bin:/usr/bin:/bin:/usr/sbin:/sbin
HOME=$WORK/home
SHELL=/bin/sh
ZMX_DIR=$WORK/zmx
EOF
zmx_env=(env -i $(cat "$ENVFILE"))
$zmx_env zmx kill $SESSION >/dev/null 2>&1
# A session standing in for Claude Code: a screen that only it shows.
$zmx_env zmx run $SESSION -d sh -c 'printf "\033[2J\033[HSTAND-IN FOR CLAUDE CODE IN ZMX SESSION 1\n"; exec sleep 100000' \
  > "$WORK/zmx-run.log" 2>&1
sleep 1
echo "zmx sessions before:"; $zmx_env zmx list

"$WORK/venv/bin/python" "$HERE/zmx_reconnect_sshd.py" $PORT "$LOG" $SESSION "$ENVFILE" > "$WORK/server.err" 2>&1 &
SRV=$!
APPPID=
cleanup() {
  kill $SRV 2>/dev/null
  [ -n "$APPPID" ] && kill $APPPID 2>/dev/null
  $zmx_env zmx kill $SESSION >/dev/null 2>&1
}
trap cleanup EXIT
sleep 2

open -n --env ROOTSHELL_TEST_TRUST_ALL_HOSTKEYS=1 --env ROOTSHELL_TEST_NO_CLOUDKIT=1 \
  --env ROOTSHELL_TEST_CONNECT_URL=1 "$APP"
sleep 15
APPPID=$(ps -Ao pid=,command= | awk -v a="$APP/Contents/MacOS/rootshell" '$2 == a {print $1; exit}')
echo "app pid ${APPPID:-none}"
# A new user each run: a host and user in the connection history open the
# connection sheet instead of connecting.
open -a "$APP" "ssh://tester$RANDOM@127.0.0.1:$PORT"

# Session discovery runs `zmx list` over an exec channel; the picker shows
# shortly after it returns.
for i in $(seq 1 60); do
  grep -q 'conn 1: session discovery done' "$LOG" 2>/dev/null && break
  sleep 1
done
sleep 3
open -a "$APP"
sleep 1
"$KEY" 18   # the 1 key: the picker attaches the session named 1

for i in $(seq 1 120); do
  grep -q RESULT "$LOG" 2>/dev/null && break
  sleep 1
done
sleep 3
screencapture -x "$WORK/after-reconnect.png" 2>/dev/null
cat "$LOG"
grep -q 'RESULT: PASS' "$LOG" && exit 0
grep -q 'RESULT: FAIL' "$LOG" && exit 1
exit 2
