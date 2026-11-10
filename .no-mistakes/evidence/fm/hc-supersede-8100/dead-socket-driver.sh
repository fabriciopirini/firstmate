#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
W=$ROOT/.test-hc/dead-socket
mkdir -p "$W"
"$ROOT/bin/fm-lab-home.sh" create "$W/home"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE HC_TERMINAL_ID HC_TERMINAL_SOCKET HC_SOCKET HC_SCOPE
export FM_HOME="$W/home" FM_HC_SOCKET=.test-hc/dead.sock HC_SESSION=fm-hclab-unreachable
python3 - <<'PY'
import socket
s=socket.socket(socket.AF_UNIX)
s.bind('.test-hc/dead.sock')
s.close()
PY
trap 'rm -f .test-hc/dead.sock' EXIT
[ -S "$FM_HC_SOCKET" ]
. "$ROOT/bin/fm-backend.sh"
fm_backend_source hc
actual=$(fm_backend_hc_agent_state fm-hclab-unreachable:t123)
printf 'Closed Unix socket still exists; real adapter agent_state=%s\n' "$actual"
[ "$actual" = unreadable ]
actual=$(fm_backend_hc_endpoint_state fm-hclab-unreachable:t123)
printf 'Closed Unix socket endpoint_state=%s\n' "$actual"
[ "$actual" = unreadable ]
python3 - <<'PY'
import socket
s=socket.socket(socket.AF_UNIX)
try:
 s.connect('.test-hc/dead.sock')
except ConnectionRefusedError:
 print('After passive reads, socket still refuses connections: no core was auto-started.')
else:
 raise SystemExit('Unexpected listener after passive reads')
finally:
 s.close()
PY
