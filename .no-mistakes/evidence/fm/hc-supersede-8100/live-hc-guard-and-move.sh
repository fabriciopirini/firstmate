#!/usr/bin/env bash
# Live validation driver (no-mistakes test phase, run 01M731W04TDEYYADT9RHJHTKVB).
# Drives the REAL hc 0.1.19 binary inside a bin/fm-hc-lab.sh session and the
# real firstmate scripts from the run worktree, against disposable homes.
#   S1 dead/absent socket from a foreign environment reads `unreadable`, starts no core
#   S1b stale socket file (bound, no listener) reads `unreadable`
#   S1c the liveness probe from the foreign env does not mark the live mate relaunchable
#   S1d base commit (913bb7a7) read from the same foreign env -> `missing` + stray core (regression repro)
#   S2 fm-secondmate-move.sh t3code -> hc: T3 env removed from home, mate lands alive on hc
set -u
ROOT=${1:?worktree root}
. "$ROOT/tests/lib.sh"
. "$ROOT/tests/hc-test-safety.sh"
export FM_HC_BIN=$(command -v hc)
TMP_ROOT=$(fm_test_tmproot fm-nm-live)

STANDIN=$(fm_agent_standin "$TMP_ROOT/standin") || fail "no stand-in"
mkdir -p "$TMP_ROOT/agent" "$TMP_ROOT/agent-bin"
cp "$STANDIN" "$TMP_ROOT/agent-bin/opencode"
cat > "$TMP_ROOT/agent/opencode" <<SH
#!/usr/bin/env bash
case "\${1:-}" in --version|--help) exit 0 ;; esac
exec "$TMP_ROOT/agent-bin/opencode" "\$@"
SH
chmod +x "$TMP_ROOT/agent/opencode"
export PATH="$TMP_ROOT/agent:$PATH"

ID="nmA$$"; ID2="nmB$$"
SES=$("$ROOT/bin/fm-hc-lab.sh" name nmlive)
FOREIGN=$(mktemp -d /tmp/fmnm.XXXX)  # short: AF_UNIX path limit
cleanup_lab() {
  local rc=$?
  trap - EXIT
  # stop any stray core the base-commit read started in the foreign env
  env -u FM_HC_SOCKET -u XDG_RUNTIME_DIR XDG_STATE_HOME="$FOREIGN" HC_SESSION="$SES" "$FM_HC_BIN" server stop >/dev/null 2>&1 || true
  hc_test_safe_teardown "$ROOT" "$SES" || echo "note: lab teardown refused (see tripwire output above)"
  fm_test_remove_tree "/tmp/fm-$ID"; fm_test_remove_tree "/tmp/fm-$ID2"
  for d in /tmp/fm-$ID+* /tmp/fm-$ID2+*; do [ -e "$d" ] && fm_test_remove_tree "$d"; done
  rm -rf "$FOREIGN"
  fm_test_cleanup
  exit "$rc"
}
trap cleanup_lab EXIT
"$ROOT/bin/fm-hc-lab.sh" provision "$SES" || fail "lab provision"
SOCK=$("$ROOT/bin/fm-hc-lab.sh" socket "$SES")
hc_test_refuse_if_unsafe "$SES" || fail "lab unsafe"
LABDIR=$(hc_test_lab_dir)/$SES
export HC_SESSION=$SES FM_HC_SOCKET=$SOCK
export XDG_STATE_HOME="$LABDIR/env/xdg-state" XDG_CONFIG_HOME="$LABDIR/env/xdg-config" XDG_DATA_HOME="$LABDIR/env/xdg-data"
unset HC_TERMINAL_ID HC_TERMINAL_SOCKET HC_SCOPE HC_SOCKET FM_ROOT_OVERRIDE FM_BACKEND TMUX HERDR_ENV \
  FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE XDG_RUNTIME_DIR

PRIMARY=$TMP_ROOT/home
mkdir -p "$PRIMARY/state" "$PRIMARY/config" "$PRIMARY/data" "$TMP_ROOT/user-home"
printf 'hc\n' > "$PRIMARY/config/backend"
printf 'opencode\n' > "$PRIMARY/config/secondmate-harness"
seed_mate() {  # <dir> <id>
  mkdir -p "$1/bin" "$1/data" "$1/state" "$1/config" "$1/projects"
  printf '%s\n' "$2" > "$1/.fm-secondmate-home"
  printf '# Firstmate\n' > "$1/AGENTS.md"
  printf 'charter\n' > "$1/data/charter.md"
  printf '%s\n' 'projects/' 'state/' 'data/' 'config/' '.claude/' > "$1/.gitignore"
  git -C "$1" init -q -b main
}
MATE=$TMP_ROOT/mate; seed_mate "$MATE" "$ID"
export FM_HOME=$PRIMARY HOME=$TMP_ROOT/user-home FM_SPAWN_NO_GUARD=1 FM_SKIP_SECONDMATE_SYNC=1
STATE=$PRIMARY/state
. "$ROOT/bin/fm-backend.sh"
fm_backend_source hc || fail "source hc"
wait_for() { local t=$(( $1 * 10 )); shift; while [ $t -gt 0 ]; do "$@" && return 0; t=$((t-1)); sleep 0.1; done; return 1; }
lab() { "$ROOT/bin/fm-hc-lab.sh" run "$SES" "$@"; }
mf() { fm_meta_get "$STATE/$1.meta" "$2"; }
st() { fm_backend_agent_state hc "$(mf "$1" window)"; }
state_is() { [ "$(st "$1")" = "$2" ]; }
foreign() {  # run a command in an env whose hc resolution names no running core
  env -u FM_HC_SOCKET -u XDG_RUNTIME_DIR XDG_STATE_HOME="$FOREIGN" "$@"
}
FSOCK="$FOREIGN/herdr-core/$SES/$SES.sock"

echo "== launch hc second mate $ID (real fm-spawn, real hc $("$FM_HC_BIN" --version))"
OUT=$("$ROOT/bin/fm-spawn.sh" "$ID" "$MATE" --secondmate --backend hc 2>"$TMP_ROOT/spawn.err") || { cat "$TMP_ROOT/spawn.err"; fail "spawn"; }
echo "$OUT" | grep '^spawned'
wait_for 20 state_is "$ID" alive || fail "never alive"
echo "recording env: agent_state=$(st "$ID")  resolved socket=$(fm_backend_detect_hc_core_sock)"
WIN=$(mf "$ID" window)

echo; echo "== S1: same target read from a foreign env (XDG_STATE_HOME=$FOREIGN, no FM_HC_SOCKET)"
mkdir -p "$FOREIGN"
echo "foreign resolved socket: $(foreign bash -c ". '$ROOT/bin/fm-backend.sh'; HC_SESSION=$SES fm_backend_detect_hc_core_sock")"
FS=$(foreign bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_source hc; fm_backend_agent_state hc '$WIN'")
FE=$(foreign bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_source hc; fm_backend_endpoint_state hc '$WIN'; echo rc=\$?" 2>&1 | tr '\n' ' ')
echo "foreign agent_state=$FS endpoint_state=$FE"
[ "$FS" = unreadable ] || fail "S1 foreign env must read unreadable, got $FS"
[ ! -e "$FSOCK" ] || fail "S1 a core socket appeared at $FSOCK"
pgrep -f "$FOREIGN" >/dev/null && fail "S1 a process references the foreign root"
echo "foreign socket exists? $( [ -e "$FSOCK" ] && echo yes || echo no )"
pass "S1 absent socket in a foreign env reads unreadable and starts no core"

echo; echo "== S1b: stale socket file at the foreign path (bound, listener gone)"
mkdir -p "$(dirname "$FSOCK")"
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$FSOCK"
[ -S "$FSOCK" ] || fail "could not create stale socket"
FS=$(foreign bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_source hc; fm_backend_agent_state hc '$WIN'")
echo "foreign agent_state with stale socket=$FS"
[ "$FS" = unreadable ] || fail "S1b stale socket must read unreadable, got $FS"
foreign bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_unix_sock_live '$FSOCK'" && fail "S1b stale socket must not read live"
pass "S1b stale socket file reads unreadable"
rm -f "$FSOCK"

echo; echo "== S1c: liveness probe from the foreign env on a DEAD mate must not be relaunchable"
PID=$(lab get "$(mf "$ID" hc_terminal)" --json | jq -r '.foreground.pid // empty')
kill "$PID"; wait_for 20 state_is "$ID" dead || fail "agent never read dead"
echo "recording env now reads: $(st "$ID")"
BEFORE=$(cat "$STATE/$ID.meta")
PROBE=$(foreign bash -c ". '$ROOT/bin/fm-secondmate-liveness-lib.sh'; fm_secondmate_liveness_probe '$STATE/$ID.meta' '$ID' poll; echo \"status=\$FM_SM_LIVE_STATUS state=\$FM_SM_LIVE_STATE kill=\${FM_SM_LIVE_KILL:-} reason=\${FM_SM_LIVE_REASON:-}\"")
echo "foreign probe: $PROBE"
case "$PROBE" in *status=relaunchable*) fail "S1c foreign probe must not be relaunchable" ;; esac
case "$PROBE" in *state=unreadable*) : ;; *) fail "S1c expected state=unreadable" ;; esac
[ "$(cat "$STATE/$ID.meta")" = "$BEFORE" ] || fail "S1c record changed"
[ ! -e "$FSOCK" ] || fail "S1c core started"
LIVE_TERMS=$(lab ls --json | jq -r '[.[]? // .terminals[]?] | length' 2>/dev/null || echo '?')
echo "lab core terminal count: $LIVE_TERMS"
pass "S1c foreign-env liveness probe leaves the mate alone (unreadable, no respawn, no core)"

echo; echo "== S1d: base commit 913bb7a7 from the same foreign env (regression reproduction)"
BASE=$TMP_ROOT/base; mkdir -p "$BASE"
git -C "$ROOT" archive 913bb7a7 bin | tar -x -C "$BASE"
BS=$(foreign bash -c ". '$BASE/bin/fm-backend.sh'; fm_backend_source hc; fm_backend_agent_state hc '$WIN'")
echo "base foreign agent_state=$BS ; core socket now exists at foreign path? $( [ -S "$FSOCK" ] && echo yes || echo no )"
foreign env HC_SESSION="$SES" "$FM_HC_BIN" server stop >/dev/null 2>&1 || true
sleep 0.5
echo "after stopping the stray core: foreign socket live? $(bash -c ". '$ROOT/bin/fm-backend.sh'; fm_backend_unix_sock_live '$FSOCK' && echo yes || echo no")"
pass "S1d base commit reads '$BS' from the foreign env (pre-fix behavior recorded)"

echo; echo "== S2: move a t3code-recorded mate (no endpoint, T3 env in home) onto hc"
fm_backend_kill hc "$(mf "$ID" window)" '' "fm-$ID" >/dev/null 2>&1 || true
MATE2=$TMP_ROOT/mate2; seed_mate "$MATE2" "$ID2"
OUT=$("$ROOT/bin/fm-spawn.sh" "$ID2" "$MATE2" --secondmate --backend hc 2>"$TMP_ROOT/spawn2.err") || { cat "$TMP_ROOT/spawn2.err"; fail "spawn2"; }
wait_for 20 state_is "$ID2" alive || fail "mate2 never alive"
fm_backend_kill hc "$(mf "$ID2" window)" '' "fm-$ID2" >/dev/null 2>&1 || fail "close mate2"
# Rewrite the record as a t3code mate with no recorded endpoint.
grep -v -E '^(backend|window|hc_session|hc_terminal)=' "$STATE/$ID2.meta" > "$STATE/$ID2.meta.t"
printf 'backend=t3code\n' >> "$STATE/$ID2.meta.t"; mv "$STATE/$ID2.meta.t" "$STATE/$ID2.meta"
mkdir -p "$MATE2/.claude"
cat > "$MATE2/.claude/settings.local.json" <<'JSON'
{"permissions":{"allow":["Bash(ls)"]},"env":{"KEEP_ME":"1","FM_SUPERVISOR_BACKEND":"t3code","FM_SUPERVISOR_TARGET":"thread-archived-123","FM_T3CODE_ENV_KEYS":"FM_SUPERVISOR_BACKEND,FM_SUPERVISOR_TARGET"}}
JSON
printf 'tok\n' > "$TMP_ROOT/primary-token"; ln -s "$TMP_ROOT/primary-token" "$MATE2/config/t3code-token"
echo "-- record before:"; sed -n '/^backend=/p;/^kind=/p;/^window=/p' "$STATE/$ID2.meta"
echo "-- settings.local.json before:"; cat "$MATE2/.claude/settings.local.json"
echo "-- t3code-token link before: $(ls -l "$MATE2/config/t3code-token" | awk '{print $9,$10,$11}')"
set +e
MOUT=$("$ROOT/bin/fm-secondmate-move.sh" "$ID2" --backend hc 2>&1); MRC=$?
echo "-- fm-secondmate-move.sh $ID2 --backend hc  (exit $MRC)"; echo "$MOUT"
[ "$MRC" -eq 0 ] || fail "S2 move failed"
echo "-- record after:"; sed -n '/^backend=/p;/^kind=/p;/^window=/p' "$STATE/$ID2.meta"
echo "-- settings.local.json after:"; cat "$MATE2/.claude/settings.local.json"
echo "-- t3code-token link after: $( [ -e "$MATE2/config/t3code-token" ] || [ -L "$MATE2/config/t3code-token" ] && echo present || echo absent)"
[ "$(mf "$ID2" backend)" = hc ] || fail "S2 record must name hc"
node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1]));const e=d.env||{};if("FM_SUPERVISOR_BACKEND" in e||"FM_SUPERVISOR_TARGET" in e||"FM_T3CODE_ENV_KEYS" in e)process.exit(1);if(e.KEEP_ME!=="1"||!d.permissions)process.exit(2)' "$MATE2/.claude/settings.local.json" || fail "S2 T3 env not removed or user keys lost"
[ ! -L "$MATE2/config/t3code-token" ] || fail "S2 token link remains"
wait_for 20 state_is "$ID2" alive || fail "S2 moved mate never alive on hc"
echo "moved mate agent_state on hc: $(st "$ID2")"
lab get "$(mf "$ID2" hc_terminal)" --json | jq -c '{state, labels: {space: .labels["herdr.space"], task: .labels["firstmate.task"]}}'
grep -h . "$STATE/.secondmate-relaunch-$ID2" 2>/dev/null | tail -2
pass "S2 move off t3code removes the T3 env from the home and lands the mate alive on hc"
fm_backend_kill hc "$(mf "$ID2" window)" '' "fm-$ID2" >/dev/null 2>&1 || true
echo LIVE_DRIVER_COMPLETE
