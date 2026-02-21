# Local Lab Guide

This folder contains the local test environments used to validate the migration tooling before touching real infrastructure.

There are two labs:

1. `mock SSH lab` (root `local-lab/`)
2. `real services lab` (`local-lab/real-services/`)

The two labs serve different purposes and should be used together.

## Why this lab exists

The migration scripts are operational automation for production cutovers. The main risk is not syntax; it is orchestration behavior over SSH, file transfer correctness, dispatcher updates, and rollback safety under realistic sequencing.

This lab gives you a safe, repeatable environment to verify:

- command generation and argument handling
- SSH connectivity assumptions (user/key/port)
- remote profile copy and apply behavior
- snapshot capture and artifact structure
- control-flow safety (`--dry-run`, `--confirm`, rollback path)

## Lab components

### 1) Mock SSH Lab

Path:

- `local-lab/docker-compose.yml`
- `local-lab/run_smoke_test.sh`

Services:

- `kamailio` (mock host with SSH and dispatcher file target)
- `old-pbx` (mock host with simulated `fs_cli` / FreeSWITCH responses)
- `new-pbx` (mock host with simulated `fs_cli` / FreeSWITCH responses)

What is simulated:

- remote SSH execution
- dispatcher file update and reload command path
- pre/post snapshot collection
- generated artifacts and run directories

What is not simulated:

- real SIP dialogs
- RTP/media behavior
- carrier interoperability
- real FusionPBX database/application state

This lab is intended to validate script mechanics end-to-end, not telephony quality.

### 2) Real Services Lab

Path:

- `local-lab/real-services/docker-compose.real.yml`
- `local-lab/real-services/verify_versions.sh`
- `local-lab/real-services/run_real_migration_smoke.sh`

Services:

- Kamailio image (real)
- FreeSWITCH old and new (real, different pinned tags)
- FusionPBX old and new (real source tags, built into separate images)

Version differentiation enforced:

- FreeSWITCH old: `safarov/freeswitch:1.10.3`
- FreeSWITCH new: `safarov/freeswitch:1.10.12`
- FusionPBX old: tag `5.3.0`
- FusionPBX new: tag `5.5.7`

`verify_versions.sh` fails if old/new versions are identical.

What this verifies:

- real image startup
- pinned-version separation between old and new stacks
- basic service reachability checks
- staged dispatcher migration flow when running the migration smoke script

What this does not verify:

- full production FusionPBX setup (DB/provisioning/trunks)
- SIP routing logic through real dialplans
- live call migration behavior

## How this simulates an actual migration environment

The labs mirror the production topology shape:

- a stable SIP ingress role (Kamailio)
- an old PBX target
- a new PBX target
- migration automation running from an operator node

The mock lab simulates the **operational flow**:

- generate dispatcher profile
- upload to ingress
- apply and reload
- observe and collect evidence

The real-services lab simulates the **versioning and service reality**:

- two different FreeSWITCH versions
- two different FusionPBX versions
- containerized lifecycle management similar to infra change windows

Combined, this gives strong pre-flight confidence for automation behavior, while keeping telephony-specific acceptance testing in a dedicated staging or pilot environment.

## Runbook

### A) Mock lab smoke test

```bash
cd "<repo-root>"
bash "./local-lab/run_smoke_test.sh"
```

Expected output highlights:

- dispatcher profile files created under `local-lab/artifacts/run-*`
- snapshots captured for old/new pre/post
- remote apply completes and reload command succeeds

### B) Real-services version verification

```bash
cd "<repo-root>"
bash "./local-lab/real-services/verify_versions.sh"
```

Expected output highlights:

- FreeSWITCH old and new versions printed and different
- FusionPBX old/new tags and commits printed and different
- script exits successfully only if version separation is confirmed

This step is a preflight only check. It confirms the environment is valid for migration testing, but it does not execute the migration sequence.

### C) Real-services migration smoke (actual staged cutover simulation)

```bash
cd "<repo-root>"
bash "./local-lab/real-services/run_real_migration_smoke.sh"
```

What this run does:

- starts/validates real services
- performs the staged dispatcher transition: `old -> both -> new`
- reloads dispatcher after each profile apply
- verifies final state is new-only
- writes proof artifacts under `local-lab/real-services/artifacts/run-*`

This is the step that validates migration control-flow behavior. It is the closest local equivalent to an actual cutover runbook without placing live SIP calls.

## Artifacts produced

- Mock lab orchestration artifacts:
  - `local-lab/artifacts/`
- Optional top-level orchestration artifacts:
  - `artifacts/`

These artifacts contain dispatcher profiles and snapshot command outputs used for audit/debug.

## Key Handling

- Mock SSH lab (`local-lab/run_smoke_test.sh`) auto-generates `local-lab/keys/id_ed25519` when missing and refreshes `authorized_keys` before starting containers.
- Real-services lab (`local-lab/real-services/*`) does not use `local-lab/keys/`; it runs with local Docker commands (`docker compose`, `docker exec`).
- For real remote migrations, use your own operator SSH identity with `tooling/scripts/orchestrate_migration_over_ssh.sh` (`--ssh-key <path>` or SSH agent).
- Do not commit private keys; keep only `local-lab/keys/.gitkeep` tracked.

## Cleanup

Mock lab:

```bash
PATH=/tmp/fakebin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin docker compose -f "./local-lab/docker-compose.yml" down -v
```

Real-services lab:

```bash
PATH=/tmp/fakebin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin docker compose -f "./local-lab/real-services/docker-compose.real.yml" down -v
```

## Notes and limitations

- Docker Desktop credential-helper behavior is handled via a local helper shim in the run scripts.
- Some images are `amd64`; on Apple Silicon, emulation may increase startup time.
- Real-services HTTP checks validate container/runtime presence, not full FusionPBX app configuration health.
