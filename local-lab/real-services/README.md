# Real Services Lab (Version-Differentiated)

This lab is the closest local approximation of a real migration topology:

- one ingress SIP proxy (`Kamailio`)
- one old PBX target (`FreeSWITCH old` + `FusionPBX old`)
- one new PBX target (`FreeSWITCH new` + `FusionPBX new`)

Pinned versions in this lab:

- Kamailio: `kamailio/kamailio-ci:latest`
- FreeSWITCH old: `safarov/freeswitch:1.10.3`
- FreeSWITCH new: `safarov/freeswitch:1.10.12`
- FusionPBX old: built from tag `5.3.0`
- FusionPBX new: built from tag `5.5.7`

## Which Script To Run

Use this decision rule:

- Run `verify_versions.sh` when you only want a preflight check that the old/new stacks are truly different and reachable.
- Run `run_real_migration_smoke.sh` when you want to execute an actual staged dispatcher migration (`old -> both -> new`) and verify the final cutover state with artifacts.
- Run `run_call_cutover_sim.sh` when you want live SIP call simulation with pass/fail routing assertions across cutover phases.
- Run `run_call_cutover_dashboard.sh` when you want a live terminal visualization during the simulation.

## Prerequisites

1. Docker Desktop (or Docker Engine) is running.
2. These host ports are available: `15060/udp`, `18080/tcp`, `18081/tcp`.
3. You run commands from the project root:

```bash
cd "<repo-root>"
```

## 1) Preflight Only: Version Verification

Run:

```bash
bash "./local-lab/real-services/verify_versions.sh"
```

What this script does:

1. Starts the real-services containers (with build as needed).
2. Reads runtime versions/tags from old/new FreeSWITCH and FusionPBX containers.
3. Fails if old and new are identical for either stack.
4. Performs basic HTTP status checks on FusionPBX old/new endpoints.

What success means:

- Your lab is alive.
- Old/new version separation is real (not accidental same-image duplication).
- Baseline reachability is good enough to proceed to migration smoke.

What it does not do:

- It does not perform dispatcher cutover.
- It does not change routing from old to new.
- It does not prove migration sequencing, rollback behavior, or final new-only target state.

## 2) Actual Migration Smoke: Staged Dispatcher Cutover

Run:

```bash
bash "./local-lab/real-services/run_real_migration_smoke.sh"
```

What this script does end-to-end:

1. Starts the real-services stack.
2. Waits until `kamcmd` is ready on Kamailio control socket.
3. Re-checks that old/new FreeSWITCH and FusionPBX versions differ.
4. Builds three dispatcher profiles:
   - `old` (all traffic to old target)
   - `both` (dual-target transition state)
   - `new` (all traffic to new target)
5. Applies those profiles in order on Kamailio and runs `dispatcher.reload` after each apply.
6. Captures the applied dispatcher file after each phase (`old`, `both`, `new`).
7. Verifies final state is truly `new` only (new present, old absent).
8. Captures `kamcmd dispatcher.list` output for evidence.

What success means:

- The migration control flow ran in the intended order.
- Dispatcher updates were accepted by Kamailio.
- Final routing state is new-only, matching cutover completion criteria.

What it does not do:

- It does not place SIP calls or validate media/RTP behavior.
- It does not validate production FusionPBX app/database configuration.
- It does not replace staging/UAT call-flow validation.

## 3) SIP Call Cutover Simulation (Live INVITE Traffic)

Run:

```bash
bash "./local-lab/real-services/run_call_cutover_sim.sh"
```

What this script validates:

1. Brings up real-services stack plus SIP simulators (`sipp-uas-old`, `sipp-uas-new`, `sipp-uac`).
2. Applies dispatcher mode `old` and sends call burst; asserts all INVITEs route to old backend.
3. Applies dispatcher mode `both` and sends call burst; asserts traffic reaches both backends.
4. Applies dispatcher mode `new` and sends call burst; asserts all INVITEs route to new backend.
5. Runs in-flight cutover check:
   - starts a long call on old mode
   - cuts over to new mode while call is active
   - sends new calls and verifies post-cutover routing is new-only
6. Writes assertion outputs and SIP message logs into artifacts.

How routing is verified:

- SIPp UAS containers (`old` and `new`) record raw SIP messages.
- The script counts backend-observed `INVITE` totals per phase and asserts deltas:
  - `old`: old delta >= expected calls, new delta == 0
  - `both`: old delta >= 1 and new delta >= 1
  - `new`: old delta == 0, new delta >= expected calls
- In-flight check uses:
  - old-mode precheck call to old backend
  - long call completion confirmation
  - post-cutover assertion that only new backend receives fresh calls

Tuning knobs (optional env vars):

- `CALLS_PER_PHASE` (default `10`)
- `CALL_RATE` (default `5`)
- `CALL_DURATION_MS` (default `1200`)
- `LONG_CALL_MS` (default `25000`)
- `POST_CUTOVER_CALLS` (default `8`)
- `PHASE_GAP_SECONDS` (default `35`, used to avoid transaction-id reuse artifacts between phases)

What this still does not prove:

- RTP/media quality and one-way audio edge cases.
- Full production dialplan or FusionPBX app logic.
- Carrier/interconnect behavior.

## 4) Live Visualization Dashboard (Real-Time)

Run:

```bash
bash "./local-lab/real-services/run_call_cutover_dashboard.sh"
```

What this does:

1. Starts `run_call_cutover_sim.sh` in the background.
2. Continuously samples backend INVITE totals from:
   - `real-sipp-uas-old` (`/tmp/old_messages.log`)
   - `real-sipp-uas-new` (`/tmp/new_messages.log`)
3. Displays a live dashboard with:
   - current phase (`old`, `both`, `new`, `inflight`, etc.)
   - inferred dispatcher mode (`old`, `both`, `new`)
   - total INVITEs handled by old/new backends
   - per-interval deltas (`OLD +x`, `NEW +y`)
4. Writes a time-series CSV (`live-metrics.csv`) in the run artifact folder.

Useful env vars:

- `DASH_INTERVAL_SECONDS` (default `1`)
- `DASH_NO_CLEAR=1` (disable screen clears for log capture)
- Simulation vars still apply (`CALLS_PER_PHASE`, `PHASE_GAP_SECONDS`, etc.)

## Evidence and Verification Artifacts

Each migration smoke run writes a timestamped folder:

`./local-lab/real-services/artifacts/run-YYYYmmdd_HHMMSS/`

Key files and why they matter:

- `dispatcher.old.list`: generated profile for old-only routing.
- `dispatcher.both.list`: generated profile for transition routing.
- `dispatcher.new.list`: generated profile for new-only routing.
- `applied-old.list`: dispatcher file after old profile apply.
- `applied-both.list`: dispatcher file after both profile apply.
- `applied-new.list`: dispatcher file after final new profile apply (primary cutover proof).
- `kamcmd-dispatcher.list.txt`: Kamailio runtime dispatcher listing after migration.

Call-cutover simulation artifacts are written under:

`./local-lab/real-services/artifacts/call-cutover-YYYYmmdd_HHMMSS/`

Key files:

- `old.assertions.txt`, `both.assertions.txt`, `new.assertions.txt`
- `old.uas-old.messages.log`, `old.uas-new.messages.log`
- `both.uas-old.messages.log`, `both.uas-new.messages.log`
- `new.uas-old.messages.log`, `new.uas-new.messages.log`
- `inflight.assertions.txt`
- `inflight-precutover.uac.log`
- `inflight-long.uac.log`
- `inflight-post-cutover.uac.log`
- `current_phase.txt`
- `status.txt`
- `simulation.stdout.log`
- `live-metrics.csv`

Manual validation commands:

```bash
docker compose -f "./local-lab/real-services/docker-compose.real.yml" ps
docker exec real-kamailio /bin/sh -c "kamcmd -s unix:/run/kamailio/kamailio_ctl dispatcher.list"
bash "./local-lab/real-services/verify_versions.sh"
```

## Stop Lab

```bash
PATH=/tmp/fakebin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin docker compose -f "./local-lab/real-services/docker-compose.real.yml" down -v
```

If you used call simulation, stop with both files:

```bash
PATH=/tmp/fakebin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin docker compose -f "./local-lab/real-services/docker-compose.real.yml" -f "./local-lab/real-services/docker-compose.calls.yml" down -v
```
