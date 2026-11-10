#!/usr/bin/env bash
set -u
ROOT=$1; WORK=$2
. "$ROOT/tests/lib.sh"
TMP_ROOT=$WORK
STANDIN=$(fm_agent_standin "$TMP_ROOT/standin") || { echo "no standin"; exit 1; }
mkdir -p "$TMP_ROOT/agent" "$TMP_ROOT/agent-bin" "$TMP_ROOT/ssh-bin"; cp "$STANDIN" "$TMP_ROOT/agent-bin/opencode"
cat > "$TMP_ROOT/agent/opencode" <<SH
#!/usr/bin/env bash
case "\${1:-}" in --version|--help) exit 0 ;; esac
exec "$TMP_ROOT/agent-bin/opencode" "\$@"
SH
cat > "$TMP_ROOT/ssh-bin/ssh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP_ROOT/ssh.log"; exit 255
SH
chmod +x "$TMP_ROOT/agent/opencode" "$TMP_ROOT/ssh-bin/ssh"; export PATH="$TMP_ROOT/ssh-bin:$TMP_ROOT/agent:$PATH"
command -v tmux >/dev/null && { echo "tmux present; unclassifiable case needs it absent"; }
export FM_HC_BIN=$(command -v hc)
SES=$("$ROOT/bin/fm-hc-lab.sh" name s3move)
"$ROOT/bin/fm-hc-lab.sh" provision "$SES" || { echo provision failed; exit 1; }
SOCK=$("$ROOT/bin/fm-hc-lab.sh" socket "$SES")
LABD=${FM_HC_LAB_DIR:-${TMPDIR:-/tmp}/fm-hc-lab-${UID}}/$SES
echo "LAB_SESSION=$SES"
export HC_SESSION=$SES FM_HC_SOCKET=$SOCK XDG_STATE_HOME="$LABD/env/xdg-state" XDG_CONFIG_HOME="$LABD/env/xdg-config" XDG_DATA_HOME="$LABD/env/xdg-data"
unset HC_TERMINAL_ID HC_TERMINAL_SOCKET HC_SCOPE HC_SOCKET FM_ROOT_OVERRIDE FM_BACKEND TMUX HERDR_ENV FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE XDG_RUNTIME_DIR
PRIMARY=$TMP_ROOT/home
"$ROOT/bin/fm-lab-home.sh" create "$PRIMARY" >/dev/null || { echo "lab home create failed"; exit 1; }
mkdir -p "$TMP_ROOT/user-home"
printf 'opencode\n' > "$PRIMARY/config/secondmate-harness"
mkmate() { local id=$1 m=$TMP_ROOT/$1; mkdir -p "$m/bin" "$m/data" "$m/state" "$m/config" "$m/projects"
  printf '%s\n' "$id" > "$m/.fm-secondmate-home"; printf '# Firstmate\n' > "$m/AGENTS.md"; printf 'charter\n' > "$m/data/charter.md"
  printf '%s\n' 'projects/' 'state/' 'data/' 'config/' > "$m/.gitignore"; git -C "$m" init -q -b main; (cd "$m" && pwd -P); }
export FM_HOME=$PRIMARY HOME=$TMP_ROOT/user-home FM_SPAWN_NO_GUARD=1 FM_SKIP_SECONDMATE_SYNC=1
STATE=$PRIMARY/state
. "$ROOT/bin/fm-backend.sh"; fm_backend_source hc
MV="$ROOT/bin/fm-secondmate-move.sh"
locks() { find "$STATE" -maxdepth 1 -name ".*lock*" | sed "s|$STATE/||" | tr '\n' ' '; }

echo; echo "=== A. move a tmux-recorded mate with no endpoint onto the real hc core"
M1=$(mkmate s3a)
printf 'kind=secondmate\nharness=opencode\nhome=%s\nworktree=%s\nproject=%s\nendpoint_task_id=s3a\nmode=secondmate\nyolo=off\nprojects=\n' "$M1" "$M1" "$M1" > "$STATE/s3a.meta"
echo "--- record before:"; cat "$STATE/s3a.meta"
echo "\$ bin/fm-secondmate-move.sh s3a --backend hc"; "$MV" s3a --backend hc; echo "exit=$?"
echo "--- record after:"; cat "$STATE/s3a.meta"
W=$(fm_meta_get "$STATE/s3a.meta" window)
for i in $(seq 1 100); do [ "$(fm_backend_agent_state hc "$W")" = alive ] && break; sleep 0.1; done
echo "agent_state on hc: $(fm_backend_agent_state hc "$W")"
echo "terminal labels: $("$ROOT/bin/fm-hc-lab.sh" run "$SES" get "${W#*:}" --json | jq -c '{space:.labels["herdr.space"],tab:.labels["herdr.tab"],task:.labels["firstmate.task"],home:.labels["firstmate.home"]}')"
echo "expected space: fm-$(FM_HOME="$M1" FM_ROOT="$M1" fm_backend_hometag)  expected home label: $(fm_backend_hometag)"
echo "relaunch ledger: $(cat "$STATE/.secondmate-relaunch-s3a" 2>/dev/null | tr '\n' ' ')"
echo "locks left behind: [$(locks)]"

echo; echo "=== A2. adversarial: move it to hc again (same backend) -> early refusal, agent untouched"
B4=$(cat "$STATE/s3a.meta")
"$MV" s3a --backend hc; echo "exit=$?"
[ "$(cat "$STATE/s3a.meta")" = "$B4" ] && echo "record unchanged: yes" || echo "record unchanged: NO"
echo "agent_state on hc: $(fm_backend_agent_state hc "$W")"

echo; echo "=== B. adversarial: remote mate refused before any lock or host probe"
M2=$(mkmate s3b)
printf 'kind=secondmate\nharness=opencode\nhome=%s\nworktree=%s\nendpoint_task_id=s3b\nmode=secondmate\nremote_host=lab-host\nremote_backend=herdr\nremote_herdr_session=fm-remote\nremote_target=fm-remote:w1:p1\nwindow=fm-remote:w1:p1\nbackend=herdr\n' "$M2" "$M2" > "$STATE/s3b.meta"
B4=$(cat "$STATE/s3b.meta"); : > "$TMP_ROOT/ssh.log"
# watch for lock dirs while the move runs
( for i in $(seq 1 60); do find "$STATE" -maxdepth 1 -name ".*s3b*" ; sleep 0.05; done ) > "$TMP_ROOT/b-watch" 2>/dev/null &
WP=$!
"$MV" s3b --backend hc; echo "exit=$?"
wait $WP
[ "$(cat "$STATE/s3b.meta")" = "$B4" ] && echo "record unchanged: yes" || echo "record unchanged: NO"
echo "ssh invocations: $(wc -l < "$TMP_ROOT/ssh.log" | tr -d ' ')"
echo "s3b lock/ledger files ever seen during the move: [$(sort -u "$TMP_ROOT/b-watch" | sed "s|$STATE/||" | tr '\n' ' ')]"
echo "hc terminals on the lab core (no launch for s3b): $("$ROOT/bin/fm-hc-lab.sh" run "$SES" ls --json | jq -c '[.[]?.labels["firstmate.task"]? // empty] // .' 2>/dev/null)"

echo; echo "=== C. adversarial: tmux-recorded mate whose endpoint cannot be read (no tmux on this host) -> refused"
M3=$(mkmate s3c)
printf 'kind=secondmate\nharness=opencode\nhome=%s\nworktree=%s\nproject=%s\nendpoint_task_id=s3c\nmode=secondmate\nyolo=off\nprojects=\nwindow=firstmate:fm-s3c\n' "$M3" "$M3" "$M3" > "$STATE/s3c.meta"
B4=$(cat "$STATE/s3c.meta")
"$MV" s3c --backend hc; echo "exit=$?"
[ "$(cat "$STATE/s3c.meta")" = "$B4" ] && echo "record unchanged: yes" || echo "record unchanged: NO"
[ -e "$STATE/.secondmate-relaunch-s3c" ] && echo "relaunch attempt recorded: YES" || echo "relaunch attempt recorded: no"
echo "locks left behind: [$(locks)]"

fm_backend_kill hc "$W" '' "fm-s3a" >/dev/null 2>&1; echo "closed s3a terminal: rc=$?"
"$ROOT/bin/fm-hc-lab.sh" teardown "$SES"; echo "teardown rc=$?"
echo "SES=$SES"
