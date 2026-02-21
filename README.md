# PBX Migration Toolkit

This repository provides migration runbooks and automation for moving SIP traffic from an old FusionPBX/FreeSWITCH stack to a new one behind Kamailio.

It includes:

- migration documentation (source, extracted, revised)
- CLI orchestration scripts for dispatcher cutover over SSH
- an interactive wizard for collecting/validating migration inputs
- two local labs:
  - mock SSH lab for orchestration mechanics
  - real-services lab for version-differentiated migration smoke testing

## Repository Structure

- `docs/`
  - `source/` original source document(s)
  - `extracted/` extracted markdown references
  - `revised/` revised migration playbook outputs
- `tooling/`
  - `scripts/` canonical automation scripts
  - `config/` sample input profiles for the wizard
- `local-lab/`
  - mock SSH lab and smoke runner
  - `real-services/` real image lab and staged migration smoke runner
- `artifacts/`
  - generated orchestration artifacts (runtime output)
- `outputs/pbx-migration/`
  - backward-compatibility links to canonical docs/scripts

## Core Scripts

- `tooling/scripts/orchestrate_migration_over_ssh.sh`
  Runs dispatcher profile generation, upload, apply, optional snapshots, optional drain wait, and optional auto-rollback.

- `tooling/scripts/orchestrate_migration_wizard.py`
  Interactive wrapper for collecting inputs with descriptions, validation, review/re-entry, and optional save/load of input JSON (`-o` and `-f`).

- `tooling/scripts/build_dispatcher_list.sh`
  Builds dispatcher list profiles for `old`, `both`, or `new` modes.

- `tooling/scripts/apply_dispatcher_profile.sh`
  Applies a generated dispatcher profile on Kamailio and runs reload command.

## Prerequisites

1. Docker Desktop (or Docker Engine + Compose plugin)
2. `bash`, `ssh`, `scp`, `nc`, `curl`
3. Ports available for local labs:
   - Mock lab SSH: `2221`, `2222`, `2223`
   - Real-services lab: `15060/udp`, `18080/tcp`, `18081/tcp`

## Quick Start

Run from project root:

```bash
cd "<repo-root>"
```

### 1) Mock Lab Smoke Test (Orchestration Mechanics)

```bash
bash "./local-lab/run_smoke_test.sh"
```

This validates SSH execution, dispatcher profile apply flow, and artifact capture using mock hosts.

### 2) Real Lab Preflight (Version Separation Only)

```bash
bash "./local-lab/real-services/verify_versions.sh"
```

This checks that old/new FusionPBX and old/new FreeSWITCH are truly different versions and reachable.

### 3) Real Lab Migration Smoke (Actual Staged Cutover Simulation)

```bash
bash "./local-lab/real-services/run_real_migration_smoke.sh"
```

This runs staged dispatcher cutover `old -> both -> new`, reloads Kamailio each stage, and verifies final new-only state.

Detailed lab guidance is in `local-lab/README.md` and `local-lab/real-services/README.md`.

## Version Check vs Migration Run

- `verify_versions.sh` verifies environment validity only:
  - containers start
  - versions differ between old and new stacks
  - basic HTTP reachability exists

- `run_real_migration_smoke.sh` verifies migration control flow:
  - staged dispatcher transitions are applied in sequence
  - Kamailio reload is invoked after each stage
  - final dispatcher state is verified as new-only
  - run artifacts are recorded for audit/debug

## Wizard Usage

Interactive mode:

```bash
python3 "./tooling/scripts/orchestrate_migration_wizard.py"
```

Load inputs from file and confirm before execution:

```bash
python3 "./tooling/scripts/orchestrate_migration_wizard.py" \
  -f "./tooling/config/lab-inputs.sample.json"
```

Save entered inputs to a JSON file:

```bash
python3 "./tooling/scripts/orchestrate_migration_wizard.py" \
  -o "./tooling/config/my-migration-inputs.json"
```

## Key Handling

- Mock lab (`local-lab/run_smoke_test.sh`): if `local-lab/keys/id_ed25519` is missing, the script auto-generates a local keypair and rebuilds `authorized_keys` before starting containers.
- Real-services lab (`local-lab/real-services/*`): does not use `local-lab/keys/`; it runs via local Docker commands only.
- Real remote orchestration (`tooling/scripts/orchestrate_migration_over_ssh.sh`): requires each operator to use their own SSH identity (pass `--ssh-key <path>` or use your SSH agent/default key).
- Never commit private keys. Keep `local-lab/keys/.gitkeep` only; key material should remain local and ephemeral.

## Artifacts

Generated runtime artifacts are written under:

- `artifacts/orchestration/`
- `local-lab/artifacts/`
- `local-lab/real-services/artifacts/`

These are run outputs and should not be committed.

## Cleanup

Mock lab:

```bash
PATH=/tmp/fakebin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  docker compose -f "./local-lab/docker-compose.yml" down -v
```

Real-services lab:

```bash
PATH=/tmp/fakebin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  docker compose -f "./local-lab/real-services/docker-compose.real.yml" down -v
```

## GitHub Readiness Notes

- `.gitignore` is configured to exclude generated artifacts, local keys, and OS/editor clutter.
- Do not commit private keys, inventory files with secrets, or environment-specific outputs.
- If any sensitive material was ever committed, rotate credentials and purge git history before publishing.

See `CONTRIBUTING.md` for contribution and pre-push checks.

## Publish to GitHub (First Push)

```bash
cd "<repo-root>"

git init
git add .
git status
git commit -m "Initial commit: PBX migration toolkit"
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
```

If you previously committed generated outputs or local keys, untrack them before pushing:

```bash
git rm -r --cached artifacts local-lab/artifacts local-lab/real-services/artifacts
git rm --cached local-lab/keys/id_ed25519 local-lab/keys/authorized_keys || true
git commit -m "Stop tracking local runtime artifacts and keys"
```
