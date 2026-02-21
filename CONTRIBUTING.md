# Contributing

## Branch and PR expectations

1. Keep changes focused and scoped.
2. Update docs when behavior or commands change.
3. Do not commit generated run artifacts.
4. Do not commit private keys, secrets, or environment-specific host inventories.

## Local validation before pushing

Run from repository root:

```bash
cd "<repo-root>"
```

Recommended checks:

1. Mock orchestration smoke:

```bash
bash "./local-lab/run_smoke_test.sh"
```

2. Real-services version preflight:

```bash
bash "./local-lab/real-services/verify_versions.sh"
```

3. Real-services migration smoke:

```bash
bash "./local-lab/real-services/run_real_migration_smoke.sh"
```

4. Shell syntax checks (optional):

```bash
bash -n ./tooling/scripts/*.sh
bash -n ./local-lab/*.sh
bash -n ./local-lab/real-services/*.sh
```

## Security hygiene

- Treat all SSH keys and host/IP details as sensitive.
- If sensitive files are accidentally committed, rotate credentials and remove them from history before publishing.
