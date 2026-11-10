# Second mates on hc: local validation

Target: `59c943564a118bcaf72e704c9a582397229f4a42`.

The independent oracle was the supplied intent: second mates keep their homes/backlogs, hc recovery removes the old terminal before creating one replacement, missing/dead sockets are unreadable rather than missing, remote moves refuse before locks/probes, and moving off T3 removes only the T3-owned environment after archival.

## Live product evidence

`live-hc-full.log` records real Firstmate scripts against hc 0.1.19 in an owned fm-hclab session, with actual Codex processes and synthetic second-mate homes. It covers launch labels; alive no-op; absent-socket refusal with the original process still alive; crashed-agent recovery; finished-terminal cleanup and replacement; recorded-backend recovery despite a changed default; moving a legacy record with no endpoint onto hc; unsupported-destination refusal; remote refusal ahead of invalid target/harness and contended locks. Recovery replaced t1 with t2, then t2 with t3; the independent moved mate occupied t4. Nonzero terminal dimensions were verified (200 columns, 120 rows).

The Codex processes reached the native sign-in screen under an isolated CODEX_HOME. No account was signed in and no model turn was claimed. This proves the local process/runtime lifecycle, not authenticated supervisor execution.

`dead-socket.log` additionally checks a real closed Unix socket: passive product reads return unreadable and the socket continues to refuse connections afterward.

`t3-local-cleanup.log` executes the actual cleanup owner on synthetic Claude and Codex configurations. It removes the stale supervisor environment and credential link while preserving unrelated settings, source token bytes and backlog. It does not prove the full T3 archive-to-replacement ordering. The focused mocked-server regression passes that ordering, but is not live evidence. `t3` is absent from PATH, and the real client in the disposable home exits 4/no_credential. A locally installed server would still require an operator-issued full-access MCP credential, which this run is forbidden to mint or borrow from production. Provide a disposable authorized T3 server and credential to complete this scenario.

No desktop presentation was opened: the live runtime was a headless isolated hc core. The terminal screen capture and core-side label JSON are retained; no screenshot or Herdr.app visual grouping proof is claimed.

## Focused automated checks (supplemental; not live scenarios)

- `tests/fm-backend-hc.test.sh`: final exit 0.
- `tests/fm-secondmate-liveness.test.sh`: final exit 0.
- `FM_TEST_ONLY=test_failed_t3_secondmate_move_archives_before_respawn_on_target tests/fm-backend-t3code.test.sh`: exit 0, mocked T3/spawn boundary.

Initial tests with TMPDIR inside the original code root refused nested second-mate fixture homes. An unchanged `git archive` of the target was unpacked under `.test-hc/code`, making fixtures siblings of that disposable code root while keeping all data within the run worktree. The first copied liveness run then refused the remote fixture's untracked command; initializing the disposable Git index with the two invoked remote commands fixed that setup condition. The final run passed. No product source was changed.

The exploratory Herdr lab helper prepare succeeded; the unprovisioned session was cleaned up through its guarded teardown. Both real hc labs completed guarded teardown successfully (see `live-hc-cleanup.log`). All required command exit statuses were observed before reporting. No full suite, linter, formatter, push, PR or CI phase was run.
