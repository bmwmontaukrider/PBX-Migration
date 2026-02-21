# FusionPBX + FreeSWITCH + Kamailio Migration Playbook

**Document Version:** 3.0  
**Date:** February 21, 2026

## 1. Purpose and Outcome

This playbook provides a production-focused method to migrate live SIP traffic from an existing FusionPBX/FreeSWITCH node to a replacement node by using Kamailio as the stable SIP ingress layer. The design goal is to avoid forced call drops, preserve service continuity, and give operations teams explicit checkpoints for decision-making during each migration stage.

The migration strategy is based on a simple operational truth: once a SIP dialog is established on a backend server, that dialog should be allowed to complete naturally on the same server. Instead of moving active calls, this playbook moves only new signaling decisions. Existing calls continue on the old node, while new registrations and new call attempts are gradually directed to the new node through Kamailio dispatcher control.

This model is intentionally conservative. It trades speed for safety by using measurable change gates, fast rollback paths, and scripted execution steps to reduce manual error.

## 2. Architecture Model

In this topology, FusionPBX remains the control plane, FreeSWITCH instances remain the call/media execution layer, and Kamailio becomes the permanent SIP edge. Endpoints and trunks no longer target PBX workers directly; they target Kamailio, which determines the appropriate backend destination.

Operationally, this separation provides two major benefits. First, backend PBX replacement can happen without forcing a full endpoint reconfiguration event at the exact same moment. Second, routing policy can be changed quickly at Kamailio while preserving call stability for in-progress sessions.

The target model is:

- Endpoints and carriers send SIP signaling to Kamailio.
- Kamailio selects backend FreeSWITCH targets through dispatcher sets.
- Active dialogs remain anchored where they were established.
- New dialogs are steered by current dispatcher policy.

## 3. Applicability and Risk Envelope

This playbook is designed for environments where continuity is more important than instant traffic cutover. It works best when operations can allow a drain period for old-node calls and when Kamailio is intended to remain in the design permanently.

This approach is appropriate when:
- Existing calls can complete naturally.
- New server build and restore can be validated before traffic shift.
- Registration migration can happen gradually through normal endpoint refresh behavior.

This approach requires additional design attention when:
- WebRTC clients (WSS/TLS) are in scope and certificate/transport parity must be maintained.
- NAT/media behavior is sensitive and RTP path assumptions must be validated explicitly.
- Trunk providers enforce strict source-IP trust policies.

This approach is not appropriate when:
- You must forcibly migrate in-progress calls.
- The old PBX cannot remain reachable throughout the drain window.
- Media handling assumptions are unknown and cannot be pilot-tested first.

## 4. Pre-Migration Preparation

Before any routing changes are made, define all mandatory variables and operational ownership clearly. The migration fails most often when technical execution is correct but decision ownership and rollback authority are ambiguous. Establish a named incident lead, a rollback approver, and clear communication channels before the window begins.

Required values to capture:

- `OLD_PBX_IP`
- `NEW_PBX_IP`
- `KAMAILIO_IP`
- `SIP_PORT` (usually 5060 for UDP/TCP, 5061 for TLS)
- Endpoint/trunk FQDN values
- Change window start/end and hard rollback time
- Escalation contacts and bridge details

### 4.1 Baseline Collection

Baseline data is your objective reference point during incident decisions. Capture system health and call state from the old PBX before cutover so that any post-change behavior can be compared against known-good values.

Run on old PBX:

```bash
systemctl is-active freeswitch
fs_cli -x "sofia status"
fs_cli -x "show registrations"
fs_cli -x "show channels"
```

Optional scripted capture:

```bash
./scripts/discovery_snapshot.sh --label pre-cutover --output-dir ./artifacts
```

The snapshot output should be stored in a timestamped change record directory. During rollback decisions, this data is often more useful than memory-based troubleshooting.

### 4.2 Data and Service Readiness on New PBX

The new PBX must be functionally ready before any production steering begins. Build/restore first, then prove that basic call processing works under representative scenarios.

1. Create FusionPBX backup from production.
2. Build replacement host with compatible software versions.
3. Restore FusionPBX backup onto new host.
4. Validate FreeSWITCH startup and profile readiness.
5. Execute test call matrix (internal, inbound, outbound, voicemail, transfer).

Recommended health commands on new PBX:

```bash
systemctl is-active freeswitch
fs_cli -x "sofia status"
fs_cli -x "show registrations"
```

If the new PBX cannot pass these checks reliably before migration, do not proceed to Kamailio steering.

## 5. Kamailio Deployment and Validation

Kamailio should be introduced first as a stable ingress point while still routing to the old PBX. This stage is intentionally low impact; its purpose is to validate signaling traversal and routing control without changing backend call ownership behavior yet.

Install Kamailio:

```bash
apt update
apt install -y kamailio kamailio-extra-modules
```

Validate that your Kamailio runtime includes modules and logic for transaction handling, routing, and dialog consistency, including dispatcher and Record-Route behavior. In real deployments, operational stability depends on route block quality as much as package installation.

Generate an initial dispatcher profile in `old` mode:

```bash
./scripts/build_dispatcher_list.sh \
  --mode old \
  --old "sip:${OLD_PBX_IP}:${SIP_PORT}" \
  --new "sip:${NEW_PBX_IP}:${SIP_PORT}" \
  --output ./dispatcher.profile.old.list
```

Apply and reload:

```bash
sudo ./scripts/apply_dispatcher_profile.sh \
  --profile ./dispatcher.profile.old.list \
  --target /etc/kamailio/dispatcher.list
```

At this point, Kamailio is in the traffic path but production behavior should still match the pre-cutover baseline.

## 6. Controlled Production Migration

Migration is performed in three steering phases to reduce blast radius and keep rollback simple. Each phase should have an explicit pass/fail decision gate before moving forward.

### 6.1 Phase A: Ingress Cutover to Kamailio

Move SIP DNS/FQDN and carrier trunk targeting so inbound signaling reaches Kamailio. Keep backend dispatcher in `old` mode at this stage. This isolates ingress change from backend change and makes troubleshooting clearer.

Expected behavior:
- Endpoints still register successfully.
- Existing and new calls continue to work via old backend.
- Kamailio logs show clean route behavior.

If abnormal failures appear here, rollback is straightforward because backend assignment logic has not changed yet.

### 6.2 Phase B: Dual Backend Observation

Introduce both old and new nodes into dispatcher policy for live observation and controlled traffic exposure.

```bash
./scripts/build_dispatcher_list.sh \
  --mode both \
  --old "sip:${OLD_PBX_IP}:${SIP_PORT}" \
  --new "sip:${NEW_PBX_IP}:${SIP_PORT}" \
  --output ./dispatcher.profile.both.list

sudo ./scripts/apply_dispatcher_profile.sh \
  --profile ./dispatcher.profile.both.list \
  --target /etc/kamailio/dispatcher.list
```

This phase is not meant to be long. Its purpose is to confirm new-node production behavior before full steering.

### 6.3 Phase C: New Traffic Steer to New PBX

Switch dispatcher policy so new dialogs land on NEW-PBX while old dialogs continue draining on OLD-PBX.

```bash
./scripts/build_dispatcher_list.sh \
  --mode new \
  --old "sip:${OLD_PBX_IP}:${SIP_PORT}" \
  --new "sip:${NEW_PBX_IP}:${SIP_PORT}" \
  --output ./dispatcher.profile.new.list

sudo ./scripts/apply_dispatcher_profile.sh \
  --profile ./dispatcher.profile.new.list \
  --target /etc/kamailio/dispatcher.list
```

During this phase, avoid configuration churn unless required for incident response. Unnecessary concurrent changes make root-cause analysis much harder.

## 7. Post-Shift Validation

Validation must include signaling and user-experience outcomes. A migration can appear healthy from a process perspective while still failing in media quality or feature workflows.

Execute the following test matrix:

- Inbound DID to extension
- Outbound PSTN from extension
- Internal extension-to-extension
- Hold/resume and transfer scenarios
- Voicemail deposit/retrieval
- DTMF behavior
- Registration stability during refresh cycles
- TLS/WSS clients where applicable

Capture post-shift evidence:

```bash
./scripts/discovery_snapshot.sh --label post-shift --output-dir ./artifacts
```

Compare pre- and post-shift snapshots for registration count trends, call-state consistency, and service health anomalies.

## 8. Drain Monitoring and Decommission Criteria

After Phase C, old-node calls should naturally decline. Do not decommission based on elapsed time alone; use measured channel state and stability windows.

Monitor channel drain:

```bash
./scripts/wait_for_channel_drain.sh \
  --threshold 0 \
  --interval 15 \
  --timeout 14400
```

Decommission OLD-PBX only when all criteria are met:

- Active channel count is at or below approved threshold.
- No unresolved critical incidents remain.
- Stakeholders approve completion.

Then perform controlled shutdown:

```bash
systemctl stop freeswitch
```

If policy requires, retain the old node in standby state for a defined fallback period before full retirement.

## 9. Rollback Strategy

Rollback should be quick, deterministic, and documented before the window starts. The safest rollback move is to restore dispatcher policy to `old` mode and verify service against baseline indicators.

Rollback triggers can include:
- Sustained registration failures
- Trunk completion degradation
- One-way/no-audio trends with no immediate mitigation

Rollback execution:

```bash
sudo ./scripts/apply_dispatcher_profile.sh \
  --profile ./dispatcher.profile.old.list \
  --target /etc/kamailio/dispatcher.list
```

After rollback, validate service behavior with the same health checks used in pre-cutover baseline and record incident observations for follow-up.

## 10. Script Reference

The following helper scripts are included for operational consistency:

- `scripts/discovery_snapshot.sh` captures timestamped health evidence locally or over SSH.
- `scripts/build_dispatcher_list.sh` generates dispatcher profiles for `old`, `both`, and `new` routing modes.
- `scripts/apply_dispatcher_profile.sh` backs up current dispatcher config, applies a selected profile, and reloads dispatcher.
- `scripts/wait_for_channel_drain.sh` polls FreeSWITCH channel count until drain threshold is reached.
- `scripts/orchestrate_migration_over_ssh.sh` coordinates profile generation, secure upload, remote apply, optional pre/post snapshots, optional drain wait, and optional auto-rollback with explicit required inputs.
- `scripts/orchestrate_migration_wizard.py` provides an interactive prompt-driven wrapper with per-field descriptions, edit/re-enter validation loop, `-f/--file` input loading, and `-o/--output-input-file` JSON export before dry-run/live execution.

Before production use, run each script with `--help` and validate command behavior in a staging environment.

## 11. Operational Notes

This migration method is designed to reduce risk through incremental control rather than rapid switching. Its success depends on strict sequencing, evidence-based gating, and disciplined change management. Teams that treat each phase as a separate decision point typically achieve better outcomes than teams that execute all stages as a single uninterrupted block.

Keep the execution plan simple, measured, and reversible at every step.
