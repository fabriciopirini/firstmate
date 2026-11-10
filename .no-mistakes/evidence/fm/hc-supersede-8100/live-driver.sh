#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
E=~/.no-mistakes/evidence/01M731W04TDEYYADT9RHJHTKVB
W=$ROOT/.test-hc/full
CODE=$ROOT/.test-hc/code
mkdir -p "$W" "$W/user" "$W/codex" "$W/tmp"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_BACKEND FM_GATE_REFUSE_BYPASS HC_TERMINAL_ID HC_TERMINAL_SOCKET HC_SCOPE HC_SOCKET TMUX HERDR_ENV
export HOME="$W/user" CODEX_HOME="$W/codex" TMPDIR="$W/tmp" FM_HC_LAB_DIR="$W/cores" FM_HC_BIN
FM_HC_BIN=$(command -v hc)
export FM_HOME="$W/parent" FM_SPAWN_NO_GUARD=1 FM_SKIP_SECONDMATE_SYNC=1
"$CODE/bin/fm-lab-home.sh" create "$FM_HOME"
MATE=$W/mate
"$CODE/bin/fm-lab-home.sh" create "$MATE"
mkdir -p "$MATE/bin"
cp "$ROOT/AGENTS.md" "$MATE/AGENTS.md"
printf 'gatehc\n' > "$MATE/.fm-secondmate-home"
printf 'Synthetic second-mate lifecycle fixture; no project work.\n' > "$MATE/data/charter.md"
printf 'Preserve this backlog byte for byte.\n' > "$MATE/data/backlog.md"
printf 'codex\n' > "$FM_HOME/config/secondmate-harness"
printf 'hc\n' > "$FM_HOME/config/backend"
printf 'off\n' > "$FM_HOME/config/supervision-host-off"
git -C "$MATE" init -q -b main
SES=$("$CODE/bin/fm-hc-lab.sh" name gate)
lab() { "$CODE/bin/fm-hc-lab.sh" run "$SES" "$@"; }
cleanup() {
 rc=$?; trap - EXIT
 if test -f "$FM_HC_LAB_DIR/$SES/fleet-state.txt"; then
   "$CODE/bin/fm-hc-lab.sh" teardown "$SES" >> "$E/live-hc-cleanup.log" 2>&1 || rc=1
 fi
 rm -rf /tmp/fm-gatehc /tmp/fm-gatemove
 for id in gatehc gatemove; do
   tag=$(printf '%s' "$FM_HOME" | shasum -a 256 | awk '{print $1}')
   rm -rf "/tmp/fm-$id+$tag"
 done
 echo "driver_exit=$rc" >> "$E/live-hc-cleanup.log"
 exit "$rc"
}
trap cleanup EXIT
"$CODE/bin/fm-hc-lab.sh" provision "$SES"
export HC_SESSION=$SES FM_HC_SOCKET
FM_HC_SOCKET=$("$CODE/bin/fm-hc-lab.sh" socket "$SES")
export XDG_STATE_HOME="$FM_HC_LAB_DIR/$SES/env/xdg-state" XDG_CONFIG_HOME="$FM_HC_LAB_DIR/$SES/env/xdg-config" XDG_DATA_HOME="$FM_HC_LAB_DIR/$SES/env/xdg-data"
echo "Real hc version: $($FM_HC_BIN --version); session=$SES"
"$CODE/bin/fm-spawn.sh" gatehc "$MATE" --secondmate --backend hc
cat "$FM_HOME/state/gatehc.meta"
export FM_ROOT=$CODE
STATE=$FM_HOME/state
. "$CODE/bin/fm-secondmate-liveness-lib.sh"
fm_backend_source hc
TARGET=$(fm_backend_target_of_meta "$STATE/gatehc.meta")
lab get "${TARGET#*:}" --json > "$E/live-hc-launch.json"
lab read "${TARGET#*:}" --lines 60 > "$E/live-hc-launch-screen.txt"
echo "launch_agent_state=$(fm_backend_agent_state hc "$TARGET")"
fm_secondmate_liveness_probe "$STATE/gatehc.meta" gatehc full
printf 'launch_probe=%s state=%s reason=%s\n' "$FM_SM_LIVE_STATUS" "$FM_SM_LIVE_STATE" "$FM_SM_LIVE_REASON"
[ "$FM_SM_LIVE_STATUS" = alive ]
labels() {
 local t=$1 out
 out=$(lab get "${t#*:}" --json)
 printf '%s\n' "$out"
 printf '%s' "$out" | jq -e --arg home "$(fm_backend_hometag)" --arg task fm-gatehc '.labels["firstmate.home"]==$home and .labels["firstmate.task"]==$task and (.labels["herdr.space"] | startswith("fm-2ndmate-gatehc-")) and .cols > 0 and .rows > 0' >/dev/null
}
labels "$TARGET"
cp "$STATE/gatehc.meta" "$W/initial.meta"
fm_secondmate_liveness_probe "$STATE/gatehc.meta" gatehc full
cmp "$STATE/gatehc.meta" "$W/initial.meta"
echo 'Alive probe preserved the record and existing terminal.'
# Adversary: same recorded session/terminal, environment resolves an absent socket.
REAL_SOCKET=$FM_HC_SOCKET
export FM_HC_SOCKET=.test-hc/absent-core.sock
for operation in agent endpoint busy; do
 case $operation in
 agent) value=$(fm_backend_hc_agent_state "$TARGET"); [ "$value" = unreadable ] ;;
 endpoint) value=$(fm_backend_hc_endpoint_state "$TARGET"); [ "$value" = unreadable ] ;;
 busy) value=$(fm_backend_hc_busy_state "$TARGET"); [ "$value" = unknown ] ;;
 esac
 echo "absent_socket $operation=$value"
done
if fm_backend_hc_capture "$TARGET" 10 fm-gatehc; then echo 'ERROR: capture unexpectedly succeeded'; exit 1; fi
if fm_backend_hc_kill "$TARGET" '' fm-gatehc; then echo 'ERROR: kill unexpectedly succeeded'; exit 1; fi
fm_secondmate_liveness_probe "$STATE/gatehc.meta" gatehc full
printf 'absent_socket probe=%s state=%s reason=%s\n' "$FM_SM_LIVE_STATUS" "$FM_SM_LIVE_STATE" "$FM_SM_LIVE_REASON"
[ "$FM_SM_LIVE_STATUS" = skipped ]
[ "$FM_SM_LIVE_STATE" = unreadable ]
[ ! -e .test-hc/absent-core.sock ]
cmp "$STATE/gatehc.meta" "$W/initial.meta"
[ ! -e "$STATE/.secondmate-relaunch-gatehc" ]
export FM_HC_SOCKET=$REAL_SOCKET
[ "$(fm_backend_hc_agent_state "$TARGET")" = alive ]
echo 'Absent socket started no core, recorded no recovery attempt, and left the original agent alive.'
# Crash the real native process's isolated foreground group, retaining the shell.
latest=$(lab get "${TARGET#*:}" --json)
echo "$latest"
PID=$(printf '%s' "$latest" | jq -r .foreground.pid)
PGID=$(ps -o pgid= -p "$PID" | tr -d ' ')
SELF_PGID=$(ps -o pgid= -p $$ | tr -d ' ')
[ -n "$PGID" ] && [ "$PGID" != "$SELF_PGID" ]
kill -TERM -- "-$PGID"
wait_state() {
 local want=$1 tries=0 got
 while [ "$tries" -lt 60 ]; do
   got=$(fm_backend_hc_agent_state "$TARGET")
   if [ "$got" = "$want" ]; then echo "terminal=$TARGET state=$got"; return 0; fi
   tries=$((tries+1)); sleep .2
 done
 echo "Expected $want, observed $got"; return 1
}
wait_state dead
recover() {
 fm_secondmate_liveness_lock gatehc
 fm_secondmate_liveness_probe "$STATE/gatehc.meta" gatehc full
 printf 'recovery probe=%s state=%s close=%s\n' "$FM_SM_LIVE_STATUS" "$FM_SM_LIVE_STATE" "$FM_SM_LIVE_KILL"
 [ "$FM_SM_LIVE_STATUS" = relaunchable ] && [ "$FM_SM_LIVE_KILL" = 1 ]
 if ! fm_secondmate_liveness_relaunch "$STATE/gatehc.meta" gatehc; then
   printf '%s\n' "$FM_SM_LIVE_OUT"; return 1
 fi
 printf '%s\n' "$FM_SM_LIVE_OUT"
 fm_secondmate_liveness_unlock gatehc
 OLD_TARGET=$TARGET
 TARGET=$(fm_backend_target_of_meta "$STATE/gatehc.meta")
 [ "$TARGET" != "$OLD_TARGET" ]
 rc=0; lab get "${OLD_TARGET#*:}" --json 2>"$W/removed.err" || rc=$?
 [ "$rc" = 3 ]
 echo "old_terminal=$OLD_TARGET removed_exit=$rc replacement=$TARGET"
 wait_state alive
 labels "$TARGET"
}
printf 't3code\n' > "$FM_HOME/config/backend"
recover
[ "$(fm_meta_get "$STATE/gatehc.meta" backend)" = hc ]
echo 'Dead-agent recovery stayed on hc despite config/backend=t3code.'
lab kill "${TARGET#*:}" --json
wait_state missing
lab get "${TARGET#*:}" --json | jq -e '.state=="finished"'
recover
cat "$STATE/.secondmate-relaunch-gatehc"
cp "$MATE/data/backlog.md" "$W/backlog.before"
# Move a synthetic persistent record with no old endpoint onto the real hc core.
MOVE_HOME=$W/move-mate
"$CODE/bin/fm-lab-home.sh" create "$MOVE_HOME"
mkdir -p "$MOVE_HOME/bin"
cp "$ROOT/AGENTS.md" "$MOVE_HOME/AGENTS.md"
printf 'gatemove\n' > "$MOVE_HOME/.fm-secondmate-home"
printf 'Synthetic lifecycle fixture.\n' > "$MOVE_HOME/data/charter.md"
printf 'Keep this backlog through migration.\n' > "$MOVE_HOME/data/backlog.md"
cp "$MOVE_HOME/data/backlog.md" "$W/move-backlog.before"
git -C "$MOVE_HOME" init -q -b main
printf 'kind=secondmate\nharness=codex\nbackend=tmux\nwindow=\nhome=%s\n' "$MOVE_HOME" > "$STATE/gatemove.meta"
"$CODE/bin/fm-secondmate-move.sh" gatemove --backend hc
cmp "$MOVE_HOME/data/backlog.md" "$W/move-backlog.before"
[ "$(fm_meta_get "$STATE/gatemove.meta" backend)" = hc ]
MT=$(fm_backend_target_of_meta "$STATE/gatemove.meta")
echo "moved_agent_state=$(fm_backend_hc_agent_state "$MT")"
[ "$(fm_backend_hc_agent_state "$MT")" = alive ]
lab get "${MT#*:}" --json
# An unsupported destination refuses without touching the now-live mate.
cp "$STATE/gatemove.meta" "$W/moved.meta"
rc=0; "$CODE/bin/fm-secondmate-move.sh" gatemove --backend paseo > "$W/refusal" 2>&1 || rc=$?
cat "$W/refusal"; [ "$rc" = 1 ]
cmp "$STATE/gatemove.meta" "$W/moved.meta"
[ "$(fm_backend_hc_agent_state "$MT")" = alive ]
echo 'Unsupported destination left the live agent and persistent record unchanged.'
# Remote guard must win even over invalid target, invalid configured harness and busy locks.
printf 'kind=secondmate\nharness=codex\nbackend=herdr\nremote_host=fm-test.invalid\nwindow=synthetic:p1\n' > "$STATE/remote.meta"
printf 'invalid-harness\n' > "$FM_HOME/config/secondmate-harness"
mkdir "$STATE/.control-remote.lock" "$STATE/.secondmate-liveness-remote.lock"
printf 'untouched\n' > "$STATE/.control-remote.lock/sentinel"
cp "$STATE/remote.meta" "$W/remote.before"
rc=0; "$CODE/bin/fm-secondmate-move.sh" remote --backend invalid > "$W/remote.refusal" 2>&1 || rc=$?
cat "$W/remote.refusal"; [ "$rc" = 1 ]
grep -q 'on remote host fm-test.invalid' "$W/remote.refusal"
cmp "$STATE/remote.meta" "$W/remote.before"
[ "$(cat "$STATE/.control-remote.lock/sentinel")" = untouched ]
echo 'Remote move refused before target validation or contended locks; records unchanged.'
lab ls --all --json
cmp "$MATE/data/backlog.md" "$W/backlog.before"
echo 'LIVE_SCENARIOS_COMPLETE'
