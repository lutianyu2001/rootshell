#!/bin/zsh
# End-to-end test of how rootshell resets terminal modes when an SSH
# connection drops. See docs/old-xcode-compat.md.
#
# Usage: scripts/old-xcode/reconnect-test.sh <APP> <WORK_DIR> [<PORT>]
#   APP       rootshell.app from build-catalyst.sh
#   WORK_DIR  where the Python environment and the logs go
# Starts fake_sshd.py, launches the app with the test switches, opens an
# ssh:// URL to the server, which drops the first connection; rootshell
# reconnects and the server asks over DECRQM which modes are still set.
# Exits 0 when all of them were reset, 1 when some are still set, 2 when no
# verdict arrived.
set -u
if [ $# -lt 2 ]; then
  echo "usage: $0 <APP> <WORK_DIR> [<PORT>]" >&2
  exit 2
fi
HERE=${0:A:h}
APP=${1:A}
WORK=${2:A}
PORT=${3:-2222}
mkdir -p "$WORK"
LOG=$WORK/server.log
rm -f "$LOG" "$WORK/server.err" "$WORK/paramiko.log"

[ -x "$WORK/venv/bin/python" ] || python3 -m venv "$WORK/venv"
"$WORK/venv/bin/python" -c 'import paramiko' 2>/dev/null || "$WORK/venv/bin/pip" -q install paramiko

"$WORK/venv/bin/python" "$HERE/fake_sshd.py" $PORT "$LOG" "$WORK/paramiko.log" > "$WORK/server.err" 2>&1 &
SRV=$!
APPPID=
cleanup() {
  kill $SRV 2>/dev/null
  [ -n "$APPPID" ] && kill $APPPID 2>/dev/null
}
trap cleanup EXIT
sleep 2

open -n --env ROOTSHELL_TEST_TRUST_ALL_HOSTKEYS=1 --env ROOTSHELL_TEST_NO_CLOUDKIT=1 \
  --env ROOTSHELL_TEST_CONNECT_URL=1 "$APP"
sleep 15
APPPID=$(ps -Ao pid=,command= | awk -v a="$APP/Contents/MacOS/rootshell" '$2 == a {print $1; exit}')
echo "app pid ${APPPID:-none}"
open -a "$APP" "ssh://tester$RANDOM@127.0.0.1:$PORT"

for i in $(seq 1 90); do
  grep -q RESULT "$LOG" 2>/dev/null && break
  sleep 1
done
cat "$LOG"
grep -q 'RESULT: PASS' "$LOG" && exit 0
grep -q 'RESULT: FAIL' "$LOG" && exit 1
exit 2
