#!/usr/bin/env python3
"""Interactive wizard for orchestrate_migration_over_ssh.sh."""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

CONFIG_VERSION = 1

DEFAULT_VALUES: dict[str, Any] = {
    "mode": "both",
    "kamailio_host": "",
    "kamailio_user": "root",
    "kamailio_ssh_port": 22,
    "old_pbx_ip": "",
    "new_pbx_ip": "",
    "old_pbx_host": "",
    "old_pbx_user": "root",
    "old_pbx_ssh_port": 22,
    "new_pbx_host": "",
    "new_pbx_user": "root",
    "new_pbx_ssh_port": 22,
    "ssh_key": "",
    "sip_scheme": "sip",
    "sip_port": 5060,
    "set_id": 1,
    "dispatcher_target": "/etc/kamailio/dispatcher.list",
    "reload_cmd": "kamcmd dispatcher.reload",
    "remote_script_dir": "/opt/pbx-migration/scripts",
    "remote_profile_dir": "/tmp/pbx-migration",
    "local_artifacts_dir": "./artifacts/orchestration",
    "capture_snapshots": True,
    "wait_for_drain": False,
    "drain_threshold": 0,
    "drain_interval": 15,
    "drain_timeout": 14400,
    "auto_rollback": True,
}

FIELD_ORDER = [
    "mode",
    "kamailio_host",
    "kamailio_user",
    "kamailio_ssh_port",
    "old_pbx_ip",
    "new_pbx_ip",
    "old_pbx_host",
    "old_pbx_user",
    "old_pbx_ssh_port",
    "new_pbx_host",
    "new_pbx_user",
    "new_pbx_ssh_port",
    "ssh_key",
    "sip_scheme",
    "sip_port",
    "set_id",
    "dispatcher_target",
    "reload_cmd",
    "remote_script_dir",
    "remote_profile_dir",
    "local_artifacts_dir",
    "capture_snapshots",
    "wait_for_drain",
    "drain_threshold",
    "drain_interval",
    "drain_timeout",
    "auto_rollback",
]

FIELD_META: dict[str, dict[str, Any]] = {
    "mode": {
        "label": "Migration mode",
        "desc": "old routes all new traffic to OLD PBX, both enables dual backend, new routes all new traffic to NEW PBX.",
        "type": "choice",
        "choices": ["old", "both", "new"],
    },
    "kamailio_host": {
        "label": "Kamailio host (IP or DNS)",
        "desc": "SSH destination host for Kamailio where dispatcher profile is applied.",
        "type": "text",
        "required": True,
    },
    "kamailio_user": {
        "label": "Kamailio SSH user",
        "desc": "SSH username on Kamailio. Use a user that can run apply script (directly or via sudo).",
        "type": "text",
        "required": True,
    },
    "kamailio_ssh_port": {
        "label": "Kamailio SSH port",
        "desc": "SSH port for Kamailio host.",
        "type": "int",
        "min": 1,
        "max": 65535,
    },
    "old_pbx_ip": {
        "label": "Old PBX signaling IP/FQDN",
        "desc": "Value used in generated SIP URI for the old PBX backend target.",
        "type": "text",
        "required": True,
    },
    "new_pbx_ip": {
        "label": "New PBX signaling IP/FQDN",
        "desc": "Value used in generated SIP URI for the new PBX backend target.",
        "type": "text",
        "required": True,
    },
    "old_pbx_host": {
        "label": "Old PBX SSH host",
        "desc": "SSH destination used for snapshot capture and channel drain checks.",
        "type": "text",
        "required": True,
    },
    "old_pbx_user": {
        "label": "Old PBX SSH user",
        "desc": "SSH username for old PBX operations.",
        "type": "text",
        "required": True,
    },
    "old_pbx_ssh_port": {
        "label": "Old PBX SSH port",
        "desc": "SSH port used to connect to old PBX host.",
        "type": "int",
        "min": 1,
        "max": 65535,
    },
    "new_pbx_host": {
        "label": "New PBX SSH host",
        "desc": "SSH destination for optional new PBX snapshot capture.",
        "type": "text",
        "required": True,
    },
    "new_pbx_user": {
        "label": "New PBX SSH user",
        "desc": "SSH username for new PBX operations.",
        "type": "text",
        "required": True,
    },
    "new_pbx_ssh_port": {
        "label": "New PBX SSH port",
        "desc": "SSH port used to connect to new PBX host.",
        "type": "int",
        "min": 1,
        "max": 65535,
    },
    "ssh_key": {
        "label": "SSH private key path",
        "desc": "Optional private key path used by SSH/SCP. Leave blank to use default SSH agent/keychain.",
        "type": "text",
        "required": False,
    },
    "sip_scheme": {
        "label": "SIP URI scheme",
        "desc": "Scheme used in generated dispatcher URIs.",
        "type": "choice",
        "choices": ["sip", "sips"],
    },
    "sip_port": {
        "label": "SIP port",
        "desc": "Port used in generated dispatcher URIs.",
        "type": "int",
        "min": 1,
        "max": 65535,
    },
    "set_id": {
        "label": "Dispatcher set ID",
        "desc": "Kamailio dispatcher set ID used in generated profile lines.",
        "type": "int",
        "min": 0,
    },
    "dispatcher_target": {
        "label": "Dispatcher target path",
        "desc": "Path to active dispatcher file on Kamailio host.",
        "type": "text",
        "required": True,
    },
    "reload_cmd": {
        "label": "Kamailio reload command",
        "desc": "Command executed on Kamailio after replacing dispatcher file.",
        "type": "text",
        "required": True,
    },
    "remote_script_dir": {
        "label": "Remote script directory on Kamailio",
        "desc": "Directory where apply_dispatcher_profile.sh is expected on Kamailio.",
        "type": "text",
        "required": True,
    },
    "remote_profile_dir": {
        "label": "Remote profile directory on Kamailio",
        "desc": "Directory where generated profile files are uploaded before apply.",
        "type": "text",
        "required": True,
    },
    "local_artifacts_dir": {
        "label": "Local artifacts directory",
        "desc": "Local folder where orchestration run evidence is stored.",
        "type": "text",
        "required": True,
    },
    "capture_snapshots": {
        "label": "Capture pre/post snapshots",
        "desc": "If enabled, collects health snapshots from old/new PBX before and after apply.",
        "type": "bool",
    },
    "wait_for_drain": {
        "label": "Wait for channel drain on old PBX",
        "desc": "Only for mode=new. Waits for old PBX channels to reach threshold.",
        "type": "bool",
    },
    "drain_threshold": {
        "label": "Drain threshold",
        "desc": "Target channel count for drain completion.",
        "type": "int",
        "min": 0,
    },
    "drain_interval": {
        "label": "Drain poll interval (seconds)",
        "desc": "How often to poll channel count while draining.",
        "type": "int",
        "min": 1,
    },
    "drain_timeout": {
        "label": "Drain timeout (seconds)",
        "desc": "Maximum wait duration for channel drain before failure.",
        "type": "int",
        "min": 1,
    },
    "auto_rollback": {
        "label": "Enable auto rollback on failure",
        "desc": "If apply fails after profile upload, attempt rollback to old profile automatically.",
        "type": "bool",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Interactive prompt wrapper for orchestrate_migration_over_ssh.sh. "
            "Supports loading/saving input profiles."
        )
    )
    parser.add_argument(
        "-f",
        "--file",
        dest="input_file",
        help="Load wizard inputs from JSON file.",
    )
    parser.add_argument(
        "-o",
        "--output-input-file",
        dest="output_file",
        help="Write final wizard inputs to JSON file before execution.",
    )
    return parser.parse_args()


def prompt_text(label: str, default: str | None = None, required: bool = False) -> str:
    while True:
        suffix = f" [{default}]" if default is not None else ""
        value = input(f"{label}{suffix}: ").strip()
        if value:
            return value
        if default is not None:
            return default
        if not required:
            return ""
        print("Value is required.")


def prompt_int(label: str, default: int, minimum: int = 0, maximum: int | None = None) -> int:
    while True:
        raw = prompt_text(label, str(default), required=True)
        if not raw.isdigit():
            print("Enter a numeric value.")
            continue
        value = int(raw)
        if value < minimum:
            print(f"Value must be >= {minimum}.")
            continue
        if maximum is not None and value > maximum:
            print(f"Value must be <= {maximum}.")
            continue
        return value


def prompt_choice(label: str, options: list[str], default: str) -> str:
    options_set = {o.lower(): o for o in options}
    while True:
        value = prompt_text(f"{label} ({'/'.join(options)})", default, required=True).lower()
        if value in options_set:
            return options_set[value]
        print(f"Choose one of: {', '.join(options)}")


def prompt_yes_no(label: str, default_yes: bool = True) -> bool:
    default = "y" if default_yes else "n"
    while True:
        value = prompt_text(f"{label} (y/n)", default, required=True).lower()
        if value in {"y", "yes"}:
            return True
        if value in {"n", "no"}:
            return False
        print("Enter y or n.")


def parse_bool_like(value: Any, field: str) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "y", "on"}:
            return True
        if normalized in {"0", "false", "no", "n", "off"}:
            return False
    raise ValueError(f"Invalid boolean for {field}: {value!r}")


def coerce_field_value(key: str, value: Any) -> Any:
    meta = FIELD_META[key]
    field_type = meta["type"]

    if field_type == "text":
        out = str(value).strip()
        if meta.get("required", False) and not out:
            raise ValueError(f"{key} is required and cannot be empty")
        return out

    if field_type == "choice":
        out = str(value).strip().lower()
        if out not in meta["choices"]:
            raise ValueError(f"{key} must be one of {meta['choices']}")
        return out

    if field_type == "int":
        if isinstance(value, bool):
            raise ValueError(f"{key} must be integer")
        if isinstance(value, int):
            out = value
        elif isinstance(value, str) and value.strip().isdigit():
            out = int(value.strip())
        else:
            raise ValueError(f"{key} must be integer")
        min_v = meta.get("min")
        max_v = meta.get("max")
        if min_v is not None and out < min_v:
            raise ValueError(f"{key} must be >= {min_v}")
        if max_v is not None and out > max_v:
            raise ValueError(f"{key} must be <= {max_v}")
        return out

    if field_type == "bool":
        return parse_bool_like(value, key)

    raise ValueError(f"Unsupported field type for {key}: {field_type}")


def load_input_file(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"Input file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"Input file is not valid JSON: {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise ValueError("Input file root must be a JSON object")

    out = DEFAULT_VALUES.copy()
    raw_values = data.get("values", data)
    if not isinstance(raw_values, dict):
        raise ValueError("Input JSON must contain an object at root or in 'values'")

    for key in FIELD_ORDER:
        if key in raw_values:
            out[key] = coerce_field_value(key, raw_values[key])

    return enforce_rules(out)


def save_input_file(path: Path, values: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "config_version": CONFIG_VERSION,
        "values": {k: values[k] for k in FIELD_ORDER},
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def enforce_rules(values: dict[str, Any]) -> dict[str, Any]:
    if not values["old_pbx_host"]:
        values["old_pbx_host"] = values["old_pbx_ip"]
    if not values["new_pbx_host"]:
        values["new_pbx_host"] = values["new_pbx_ip"]

    if values["mode"] != "new":
        values["wait_for_drain"] = False
        values["drain_threshold"] = 0
        values["drain_interval"] = 15
        values["drain_timeout"] = 14400

    if values["mode"] == "old":
        values["auto_rollback"] = False

    return values


def should_prompt_field(key: str, values: dict[str, Any]) -> bool:
    if key in {"drain_threshold", "drain_interval", "drain_timeout"}:
        return values["mode"] == "new" and values["wait_for_drain"]
    if key == "wait_for_drain":
        return values["mode"] == "new"
    if key == "auto_rollback":
        return values["mode"] != "old"
    return True


def prompt_field(key: str, values: dict[str, Any]) -> None:
    if not should_prompt_field(key, values):
        return

    meta = FIELD_META[key]
    current = values[key]
    print(f"\n{meta['label']}")
    print(f"  {meta['desc']}")

    field_type = meta["type"]
    if field_type == "text":
        values[key] = prompt_text(meta["label"], str(current), required=meta.get("required", False))
        return
    if field_type == "choice":
        values[key] = prompt_choice(meta["label"], list(meta["choices"]), str(current))
        return
    if field_type == "int":
        values[key] = prompt_int(meta["label"], int(current), minimum=meta.get("min", 0), maximum=meta.get("max"))
        return
    if field_type == "bool":
        values[key] = prompt_yes_no(meta["label"], default_yes=bool(current))
        return
    raise ValueError(f"Unsupported field type for {key}: {field_type}")


def guided_prompt(values: dict[str, Any]) -> dict[str, Any]:
    for key in FIELD_ORDER:
        prompt_field(key, values)
        enforce_rules(values)
    return values


def editable_fields(values: dict[str, Any]) -> list[str]:
    return [key for key in FIELD_ORDER if should_prompt_field(key, values)]


def print_summary(values: dict[str, Any], include_index: bool = False) -> list[str]:
    fields = editable_fields(values)
    print("\nSummary")
    print("-------")
    for idx, key in enumerate(fields, start=1):
        label = FIELD_META[key]["label"]
        value = values[key]
        prefix = f"{idx}. " if include_index else "- "
        print(f"{prefix}{label}: {value}")
    return fields


def review_and_edit(values: dict[str, Any]) -> dict[str, Any]:
    while True:
        fields = print_summary(values, include_index=True)
        print("\nOptions: number=edit field, r=re-enter all prompts, c=continue, q=quit")
        action = prompt_text("Choose option", "c", required=True).strip().lower()

        if action in {"c", "continue"}:
            errors = validate_values(values)
            if errors:
                print("\nValidation errors:")
                for err in errors:
                    print(f"- {err}")
                print("Please edit the fields above or re-enter all prompts.")
                continue
            return values
        if action in {"q", "quit", "a", "abort"}:
            raise KeyboardInterrupt
        if action in {"r", "reenter", "re-enter"}:
            guided_prompt(values)
            enforce_rules(values)
            continue
        if action.isdigit():
            index = int(action)
            if index < 1 or index > len(fields):
                print("Invalid field number.")
                continue
            prompt_field(fields[index - 1], values)
            enforce_rules(values)
            continue
        print("Invalid option.")


def validate_values(values: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    tmp = enforce_rules(values.copy())
    for key in FIELD_ORDER:
        if not should_prompt_field(key, tmp):
            continue
        try:
            coerce_field_value(key, tmp[key])
        except ValueError as exc:
            errors.append(str(exc))
    return errors


def build_base_command(orchestrator_path: Path, values: dict[str, Any]) -> list[str]:
    cmd = [
        str(orchestrator_path),
        "--mode",
        str(values["mode"]),
        "--kamailio-host",
        str(values["kamailio_host"]),
        "--kamailio-user",
        str(values["kamailio_user"]),
        "--kamailio-ssh-port",
        str(values["kamailio_ssh_port"]),
        "--old-pbx-ip",
        str(values["old_pbx_ip"]),
        "--new-pbx-ip",
        str(values["new_pbx_ip"]),
        "--old-pbx-host",
        str(values["old_pbx_host"]),
        "--old-pbx-user",
        str(values["old_pbx_user"]),
        "--old-pbx-ssh-port",
        str(values["old_pbx_ssh_port"]),
        "--new-pbx-host",
        str(values["new_pbx_host"]),
        "--new-pbx-user",
        str(values["new_pbx_user"]),
        "--new-pbx-ssh-port",
        str(values["new_pbx_ssh_port"]),
        "--sip-port",
        str(values["sip_port"]),
        "--sip-scheme",
        str(values["sip_scheme"]),
        "--set-id",
        str(values["set_id"]),
        "--dispatcher-target",
        str(values["dispatcher_target"]),
        "--reload-cmd",
        str(values["reload_cmd"]),
        "--remote-script-dir",
        str(values["remote_script_dir"]),
        "--remote-profile-dir",
        str(values["remote_profile_dir"]),
        "--local-artifacts-dir",
        str(values["local_artifacts_dir"]),
    ]

    if str(values["ssh_key"]).strip():
        cmd.extend(["--ssh-key", str(values["ssh_key"]).strip()])

    if values["capture_snapshots"]:
        cmd.append("--capture-snapshots")
    if values["wait_for_drain"]:
        cmd.extend(
            [
                "--wait-for-drain",
                "--drain-threshold",
                str(values["drain_threshold"]),
                "--drain-interval",
                str(values["drain_interval"]),
                "--drain-timeout",
                str(values["drain_timeout"]),
            ]
        )
    if values["auto_rollback"]:
        cmd.append("--auto-rollback")
    return cmd


def run_command(cmd: list[str]) -> int:
    print("\nExecuting:\n")
    print(shlex.join(cmd))
    print()
    proc = subprocess.run(cmd, check=False)
    return proc.returncode


def main() -> int:
    args = parse_args()

    script_dir = Path(__file__).resolve().parent
    orchestrator = script_dir / "orchestrate_migration_over_ssh.sh"

    if not orchestrator.exists() or not orchestrator.is_file():
        print(f"Missing orchestrator script: {orchestrator}", file=sys.stderr)
        return 1

    print("PBX Migration SSH Wizard")
    print("------------------------")

    input_file_default = args.input_file if args.input_file else None
    output_file_default = args.output_file if args.output_file else None

    print("\nConfig file options")
    print("-------------------")
    print("You can load prior inputs from a JSON file and/or save current inputs to a JSON file.")
    input_file_text = prompt_text("Input file path to load (-f, optional)", input_file_default, required=False).strip()
    output_file_text = prompt_text(
        "Output file path to save entered inputs (-o, optional)",
        output_file_default,
        required=False,
    ).strip()

    values = DEFAULT_VALUES.copy()
    input_path: Path | None = None
    if input_file_text:
        input_path = Path(input_file_text).expanduser().resolve()
        try:
            values = load_input_file(input_path)
        except ValueError as exc:
            print(f"Failed to load input file: {exc}", file=sys.stderr)
            return 1
        print(f"\nLoaded defaults from: {input_path}")

    if input_path:
        if prompt_yes_no("Run step-by-step prompts for every field", False):
            values = guided_prompt(values)
    else:
        values = guided_prompt(values)

    values = enforce_rules(values)
    values = review_and_edit(values)

    if output_file_text:
        output_path = Path(output_file_text).expanduser().resolve()
        save_input_file(output_path, values)
        print(f"\nSaved input file: {output_path}")

    base_cmd = build_base_command(orchestrator, values)

    if not prompt_yes_no("Run DRY-RUN first", True):
        print("Aborted by user.")
        return 0

    dry_run_cmd = [*base_cmd, "--dry-run"]
    dry_rc = run_command(dry_run_cmd)
    if dry_rc != 0:
        print(f"Dry-run failed with exit code {dry_rc}. Fix inputs and retry.", file=sys.stderr)
        return dry_rc

    if not prompt_yes_no("Dry-run succeeded. Execute live run now", False):
        print("Done. No live changes were applied.")
        return 0

    live_cmd = [*base_cmd, "--confirm"]
    live_rc = run_command(live_cmd)
    if live_rc != 0:
        print(f"Live run failed with exit code {live_rc}.", file=sys.stderr)
    return live_rc


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nInterrupted.")
        raise SystemExit(130)
    except EOFError:
        print("\nInput stream ended. Exiting.")
        raise SystemExit(130)
