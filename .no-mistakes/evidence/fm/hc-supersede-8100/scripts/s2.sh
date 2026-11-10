#!/usr/bin/env bash
# S2: a mate's hc terminal read from an environment that resolves a different (dead/absent) core socket.
set -u
ROOT=$1; BASE=$2; WORK=$3
. "$ROOT/tests/lib.sh"
TMP_ROOT=$WORK
STANDIN=$(fm_agent_standin "$TMP_ROOT/standin") || { echo "no standin"; exit 1; }
mkdir -p "$TMP_ROOT/agent" "$TMP_ROOT/agent-bin"; cp "$STANDIN" "$TMP_ROOT/agent-bin/opencode"
cat > "$TMP_ROOT/agent/opencode" <<SH
#!/usr/bin/env bash
case "\${1:-}" in --version|--help) exit 0 ;; esac
exec "$TMP_ROOT/agent-bin/opencode" "\$@"
SH
chmod +x "$TMP_ROOT/agent/opencode"; export PATH="$TMP_ROOT/agent:$PATH"
export FM_HC_BIN=$(command -v hc)
ID="s2hc$$"
SES=$("$ROOT/bin/fm-hc-lab.sh" name s2dead)
"$ROOT/bin/fm-hc-lab.sh" provision "$SES" || { echo provision failed; exit 1; }
SOCK=$("$ROOT/bin/fm-hc-lab.sh" socket "$SES")
LABD=${FM_HC_LAB_DIR:-${TMPDIR:-/tmp}/fm-hc-lab-${UID}}/$SES
echo "LAB_SESSION=$SES"; echo "LAB_SOCKET=$SOCK"; echo "LAB_DIR=$LABD"
export HC_SESSION=$SES FM_HC_SOCKET=$SOCK XDG_STATE_HOME="$LABD/env/xdg-state" XDG_CONFIG_HOME="$LABD/env/xdg-config" XDG_DATA_HOME="$LABD/env/xdg-data"
unset HC_TERMINAL_ID HC_TERMINAL_SOCKET HC_SCOPE HC_SOCKET FM_ROOT_OVERRIDE FM_BACKEND TMUX HERDR_ENV FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE XDG_RUNTIME_DIR
PRIMARY=$TMP_ROOT/home; MATE=$TMP_ROOT/mate
mkdir -p "$PRIMARY/state" "$PRIMARY/config" "$PRIMARY/data" "$TMP_ROOT/user-home" "$MATE/bin" "$MATE/data" "$MATE/state" "$MATE/config" "$MATE/projects"
printf 'hc\n' > "$PRIMARY/config/backend"; printf 'opencode\n' > "$PRIMARY/config/secondmate-harness"
printf '%s\n' "$ID" > "$MATE/.fm-secondmate-home"; printf '# Firstmate\n' > "$MATE/AGENTS.md"; printf 'charter\n' > "$MATE/data/charter.md"
printf '%s\n' 'projects/' 'state/' 'data/' 'config/' > "$MATE/.gitignore"; git -C "$MATE" init -q -b main
export FM_HOME=$PRIMARY HOME=$TMP_ROOT/user-home FM_SPAWN_NO_GUARD=1 FM_SKIP_SECONDMATE_SYNC=1
STATE=$PRIMARY/state
echo "--- real launch: bin/fm-spawn.sh $ID <mate> --secondmate --backend hc"
"$ROOT/bin/fm-spawn.sh" "$ID" "$MATE" --secondmate --backend hc 2>&1 | grep -E '^(spawned|error)'
. "$ROOT/bin/fm-backend.sh"; fm_backend_source hc
W=$(fm_meta_get "$STATE/$ID.meta" window); echo "record window=$W backend=$(fm_meta_get "$STATE/$ID.meta" backend)"
for i in $(seq 1 100); do [ "$(fm_backend_agent_state hc "$W")" = alive ] && break; sleep 0.1; done
echo "recording env: agent_state=$(fm_backend_agent_state hc "$W")"
PID=$("$ROOT/bin/fm-hc-lab.sh" run "$SES" get "${W#*:}" --json | jq -r '.foreground.pid // empty'); kill "$PID"
for i in $(seq 1 100); do [ "$(fm_backend_agent_state hc "$W")" = dead ] && break; sleep 0.1; done
echo "recording env after agent ended: agent_state=$(fm_backend_agent_state hc "$W")"
# Environment B: no FM_HC_SOCKET, and XDG roots that resolve no running core for $SES.
B=$(mktemp -d /tmp/s2b.XXXX); mkdir -p "$B/run" "$B/state"; chmod 700 "$B/run"
probe_B() {  # <root-to-source> <label>
  env -u FM_HC_SOCKET XDG_RUNTIME_DIR="$B/run" XDG_STATE_HOME="$B/state" bash "$(dirname "$0")/probe.sh" "$1" "$2" "$SES" "$W" "$STATE" "$ID"
  echo "[$2] files under env B after the probe:"; find "$B" -mindepth 1 | sed "s|$B|envB|"
  echo "[$2] processes holding files under env B: $(lsof -t +D "$B" 2>/dev/null | sort -u | tr '\n' ' ')"
}
echo "--- env B probe with THIS change"
probe_B "$ROOT" head
echo "--- env B probe with BASE commit 913bb7a7 (pre-fix adapter), same record"
probe_B "$BASE" base
# stop any stray core the base probe started at env B's socket
env -u FM_HC_SOCKET XDG_RUNTIME_DIR="$B/run" XDG_STATE_HOME="$B/state" HC_SESSION="$SES" "$FM_HC_BIN" server stop </dev/null 2>&1 | sed 's/^/[cleanup] /'
sleep 0.5; for p in $(lsof -t +D "$B" 2>/dev/null | sort -u); do kill "$p"; done; sleep 0.3
echo "processes still holding env B after cleanup: $(lsof -t +D "$B" 2>/dev/null | wc -l | tr -d ' ')"
echo "recording env still reads: agent_state=$(fm_backend_agent_state hc "$W")"
fm_backend_kill hc "$W" '' "fm-$ID" >/dev/null 2>&1
"$ROOT/bin/fm-hc-lab.sh" teardown "$SES"; echo "teardown rc=$?"
echo "SES=$SES"
rm -rf "$B"
