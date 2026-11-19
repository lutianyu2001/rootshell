#!/bin/zsh
# End-to-end test of the number row as F1-F12 (Keyboard Shortcuts > Function
# Keys) with real key presses. See docs/old-xcode-compat.md.
#
# Usage: scripts/old-xcode/function-key-layer-test.sh <APP> <WORK_DIR> <KEY> [<LAYER>] [<PORT>]
#   APP       rootshell.app from build-catalyst.sh
#   WORK_DIR  where the Python environment and the logs go
#   KEY       a program that presses a key by its Mac virtual key code
#             (the compiled tools/key.swift); needs Accessibility
#   LAYER     optionCommand (the default) or command, the FunctionKeyLayer
#             raw values; set in the app's defaults for the run only
# Starts keyecho_sshd.py, launches the app, opens an ssh:// URL to the server,
# presses the layer's chord with 1 through 0, - and =, and compares what the
# server received for each with F1-F12 as Ghostty sends them. Exits 0 when all
# twelve match.
set -u
if [ $# -lt 3 ]; then
  echo "usage: $0 <APP> <WORK_DIR> <KEY> [<LAYER>] [<PORT>]" >&2
  exit 2
fi
HERE=${0:A:h}
APP=${1:A}
WORK=${2:A}
KEY=${3:A}
LAYER=${4:-optionCommand}
PORT=${5:-2223}
case $LAYER in
  optionCommand) MODS=(alt cmd) ;;
  command) MODS=(cmd) ;;
  *) echo "unknown layer $LAYER" >&2; exit 2 ;;
esac
mkdir -p "$WORK"
LOG=$WORK/keyecho.log
rm -f "$LOG" "$WORK/keyecho.err"
PLIST=~/Library/Containers/com.kk2.rootshell/Data/Library/Preferences/com.kk2.rootshell.plist

# Mac virtual key codes of 1-0, - and =, in F-key order.
CODES=(18 19 20 21 23 22 26 28 25 29 27 24)
NAMES=(1 2 3 4 5 6 7 8 9 0 - =)
EXPECT=('^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~')

[ -x "$WORK/venv/bin/python" ] || python3 -m venv "$WORK/venv"
"$WORK/venv/bin/python" -c 'import paramiko' 2>/dev/null || "$WORK/venv/bin/pip" -q install paramiko

"$WORK/venv/bin/python" "$HERE/keyecho_sshd.py" $PORT "$LOG" > "$WORK/keyecho.err" 2>&1 &
SRV=$!
APPPID=
cleanup() {
  kill $SRV 2>/dev/null
  [ -n "$APPPID" ] && kill $APPPID 2>/dev/null
  defaults delete "$PLIST" keybindFunctionKeyLayer 2>/dev/null
}
trap cleanup EXIT
sleep 2

defaults write "$PLIST" keybindFunctionKeyLayer -string $LAYER
open -n --env ROOTSHELL_TEST_TRUST_ALL_HOSTKEYS=1 --env ROOTSHELL_TEST_NO_CLOUDKIT=1 \
  --env ROOTSHELL_TEST_CONNECT_URL=1 "$APP"
sleep 15
APPPID=$(ps -Ao pid=,command= | awk -v a="$APP/Contents/MacOS/rootshell" '$2 == a {print $1; exit}')
echo "app pid ${APPPID:-none}, layer $LAYER (${(j:+:)MODS})"
# A new user each run: a host and user in the connection history open the
# connection sheet instead of connecting.
open -a "$APP" "ssh://tester$RANDOM@127.0.0.1:$PORT"
for i in $(seq 1 60); do
  grep -q 'session opened' "$LOG" 2>/dev/null && break
  sleep 1
done
sleep 5
open -a "$APP"
sleep 1
for code in $CODES; do
  "$KEY" $code $MODS
  sleep 0.5
done
sleep 2

got=("${(@f)$(sed -n "s/.*received '\(.*\)'\$/\1/p" "$LOG")}")
fail=0
for i in {1..12}; do
  g=${got[$i]-<none>}
  if [ "$g" = "${EXPECT[$i]}" ]; then r=ok; else r=FAIL; fail=1; fi
  printf "%-8s F%-3s expected %-8s got %-8s %s\n" "${(j:+:)MODS}+${NAMES[$i]}" $i "${EXPECT[$i]}" "$g" $r
done
if [ ${#got} -gt 12 ]; then
  echo "extra reads: ${got[@]:12}"
  fail=1
fi
exit $fail
