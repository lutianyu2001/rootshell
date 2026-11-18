#!/bin/zsh
# End-to-end test of what the keyboard toolbar's keys send, for builds that
# cannot show or tap the toolbar (the Mac Catalyst app on an Intel Mac). See
# docs/old-xcode-compat.md.
#
# Usage: scripts/old-xcode/toolbar-key-test.sh <APP> <WORK_DIR> [<PORT>]
#   APP       rootshell.app from build-catalyst.sh
#   WORK_DIR  where the Python environment and the logs go
# Starts keyecho_sshd.py, launches the app with ROOTSHELL_TEST_TOOLBAR_KEYS,
# opens an ssh:// URL to the server, and compares what the server received for
# each key with the sequence it should send. Exits 0 when every key matches.
set -u
if [ $# -lt 2 ]; then
  echo "usage: $0 <APP> <WORK_DIR> [<PORT>]" >&2
  exit 2
fi
HERE=${0:A:h}
APP=${1:A}
WORK=${2:A}
PORT=${3:-2223}
mkdir -p "$WORK"
LOG=$WORK/keyecho.log
APPLOG=~/Library/Containers/com.kk2.rootshell/Data/tmp/toolbar-key-test.log
rm -f "$LOG" "$WORK/keyecho.err" "$APPLOG"

# Ghostty encodes the function keys; it writes a modified F3 as CSI 13;<mods> ~
# rather than xterm's CSI 1;<mods> R, which reads like a cursor position report.
KEYS=(esc tab arrowUp arrowDown arrowRight arrowLeft f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12
      shift+f1 ctrl+f5 alt+f12 ctrl+shift+f3 ctrl+alt+f9)
EXPECT=('^[' '^I' '^[[A' '^[[B' '^[[C' '^[[D' '^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' '^[[17~' '^[[18~' '^[[19~'
        '^[[20~' '^[[21~' '^[[23~' '^[[24~' '^[[1;2P' '^[[15;5~' '^[[24;3~' '^[[13;6~' '^[[20;7~')

[ -x "$WORK/venv/bin/python" ] || python3 -m venv "$WORK/venv"
"$WORK/venv/bin/python" -c 'import paramiko' 2>/dev/null || "$WORK/venv/bin/pip" -q install paramiko

"$WORK/venv/bin/python" "$HERE/keyecho_sshd.py" $PORT "$LOG" > "$WORK/keyecho.err" 2>&1 &
SRV=$!
APPPID=
cleanup() {
  kill $SRV 2>/dev/null
  [ -n "$APPPID" ] && kill $APPPID 2>/dev/null
}
trap cleanup EXIT
sleep 2

open -n --env ROOTSHELL_TEST_TRUST_ALL_HOSTKEYS=1 --env ROOTSHELL_TEST_NO_CLOUDKIT=1 \
  --env ROOTSHELL_TEST_CONNECT_URL=1 --env ROOTSHELL_TEST_TOOLBAR_KEYS=${(j:,:)KEYS} "$APP"
sleep 5
APPPID=$(ps -Ao pid=,command= | awk -v a="$APP/Contents/MacOS/rootshell" '$2 == a {print $1; exit}')
echo "app pid ${APPPID:-none}"
open -a "$APP" "ssh://tester$RANDOM@127.0.0.1:$PORT"
# The app waits 15 s after the URL's tab appears, then sends a key every 0.5 s.
sleep $(( 25 + ${#KEYS} ))

got=("${(@f)$(sed -n "s/.*received '\(.*\)'\$/\1/p" "$LOG")}")
fail=0
for i in {1..${#KEYS}}; do
  g=${got[$i]-<none>}
  if [ "$g" = "${EXPECT[$i]}" ]; then r=ok; else r=FAIL; fail=1; fi
  printf "%-14s expected %-10s got %-10s %s\n" ${KEYS[$i]} "${EXPECT[$i]}" "$g" $r
done
if [ ${#got} -gt ${#KEYS} ]; then
  echo "extra reads: ${got[@]:${#KEYS}}"
  fail=1
fi
[ $fail = 0 ] || { echo "--- app log ($APPLOG)"; cat "$APPLOG" 2>/dev/null; }
exit $fail
