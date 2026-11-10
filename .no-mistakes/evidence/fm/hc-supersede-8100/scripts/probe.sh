#!/usr/bin/env bash
# fresh process: <root> <label> <ses> <window> <state> <id>
R=$1 L=$2 SES=$3 W=$4 STATE=$5 ID=$6
. "$R/bin/fm-backend.sh"; fm_backend_source hc
echo "[$L] resolved socket: $(HC_SESSION=$SES fm_backend_detect_hc_core_sock)"
echo "[$L] fm_backend_agent_state hc $W => $(fm_backend_agent_state hc "$W")"
echo "[$L] fm_backend_hc_endpoint_state => $(fm_backend_hc_endpoint_state "$W" 2>/dev/null)"
. "$R/bin/fm-secondmate-liveness-lib.sh"
fm_secondmate_liveness_probe "$STATE/$ID.meta" "$ID" poll
echo "[$L] liveness probe(poll): status=$FM_SM_LIVE_STATUS state=$FM_SM_LIVE_STATE kill=${FM_SM_LIVE_KILL:-} reason=${FM_SM_LIVE_REASON:-}"
