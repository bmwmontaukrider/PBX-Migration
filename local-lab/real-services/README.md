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
