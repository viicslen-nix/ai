---
allowed-tools: Bash(superset:*)
argument-hint: describe the symptom
description: Diagnose and fix Superset problems such as connection failures, offline hosts, terminals not attaching, auth or update issues. Use when the user reports something broken or misbehaving in Superset itself ("Superset won't connect", "my host shows offline", "terminal won't attach", "the app is stuck"), before filing feedback.
metadata:
    github-path: plugins/superset/skills/doctor
    github-pinned: cli-v1.36.0
    github-ref: refs/tags/cli-v1.36.0
    github-repo: https://github.com/superset-sh/superset
    github-tree-sha: 4f99742abafa25b03940b4ffe68f69263d8519d0
name: doctor
---
# Superset Doctor

Diagnose first, change one thing at a time, verify after each change.

## 1. Snapshot (read-only, run in parallel, tolerate failures)

- `superset status` for host service health
- `superset auth whoami` for auth and the active org
- `superset hosts list` for host reachability
- `superset --version`

## 2. Match known signatures

| Signature | Fix |
| --- | --- |
| `whoami` fails / session expired | `superset auth login` |
| Host shows offline | `superset hosts wake <id>`; confirm the machine is awake and online |
| Host service not running | `superset start` |
| CLI and desktop app version mismatch, or stale CLI | `superset update` |
| App-side misbehavior (macOS) | read the newest entries in `~/Library/Logs/Superset/main.log` for errors |

Propose the matching fix and get the user's go-ahead before running anything that changes state. Never delete data as a "fix".

## 3. Verify

Re-run the originally failing action. If it works, say exactly what was wrong and what fixed it.

## 4. Escalate with evidence

If unresolved, offer to file it with the feedback skill and carry over the collected diagnostics (versions, status output, the relevant log excerpt) so the report arrives pre-triaged. Ask before including any log content; logs can contain paths and project names.
