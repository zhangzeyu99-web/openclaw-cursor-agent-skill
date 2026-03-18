---
name: openclaw-cursor-agent-system
description: Build or maintain an OpenClaw -> tmux -> Cursor CLI background task architecture for long-running coding jobs. Use when the user mentions OpenClaw, tmux, Cursor CLI, persistent sessions, background code tasks, spawn-cursor, check-status, attach-session, send-command, or kill-session.
---

# OpenClaw Cursor Agent System

Use this skill when the user wants a persistent coding-task architecture where OpenClaw schedules work, `tmux` provides the real TTY session, and Cursor CLI executes inside that session.

## Quick Start

If the repository does not already contain the toolkit, create this structure:

```text
cursor-agent-system/
├── scripts/
│   ├── common.sh
│   ├── spawn-cursor.sh
│   ├── check-status.sh
│   ├── attach-session.sh
│   ├── send-command.sh
│   └── kill-session.sh
├── templates/
│   └── cursor-task-prompt.md
├── status/
├── tasks/
└── logs/
```

## What To Build

Always include these five executable scripts:

1. `spawn-cursor.sh`
2. `check-status.sh`
3. `attach-session.sh`
4. `send-command.sh`
5. `kill-session.sh`

## Non-Negotiable Requirements

- Use `bash` and `set -euo pipefail`.
- All user-facing errors should be Chinese.
- Cursor CLI must run inside `tmux`, never directly without a TTY.
- Session names must follow `{project}-{task}-{timestamp}`.
- Keep one status JSON, one task Markdown, and one log file per session.
- `spawn-cursor.sh` should support task priority and estimated duration metadata.
- `check-status.sh` should show session existence, PID, recent output, and progress hints.
- `send-command.sh` should support regular instructions plus `/pause`, `/resume`, and `/status`.
- `kill-session.sh` should try graceful shutdown first, then optionally force kill.

## Workflow

1. Read `references/setup.md` before changing the toolkit structure.
2. Reuse existing scripts if present; refactor instead of rewriting blindly.
3. Keep shared logic in `scripts/common.sh`.
4. Add a reusable task prompt template in `templates/cursor-task-prompt.md`.
5. Document usage and examples in the toolkit `README.md`.
6. After edits, run shell syntax validation on all scripts.

## Output Expectations

When implementing or updating this system:

- Explain which script or layer is being changed.
- Preserve existing user data in `status/`, `tasks/`, and `logs/` unless the user asks to purge.
- Prefer status files keyed by session name so other scripts can resolve them reliably.
- Keep the system usable from WSL/macOS shell environments.

## Additional Resources

- For implementation checklist and behavior details, read [references/setup.md](references/setup.md)
- For the task prompt structure used by spawned Cursor runs, read [references/task-prompt.md](references/task-prompt.md)
