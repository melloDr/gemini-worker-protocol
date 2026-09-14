# Gemini Worker Protocol

A portable Codex skill package for delegating small, explicitly bounded execution tasks to **Gemini 3.8 Flash High** while the selected Codex Desktop model remains the **Lead Agent**.

This package is designed for a deliberate Lead/worker workflow:

- Codex owns context, planning, architecture, business decisions, user communication, review, and acceptance.
- Gemini is an execution worker only. It is invoked through the user's global `gw` / `gemini-worker.ps1` wrapper.
- Gemini may act only on an explicit Lead brief. It must not invent context, broaden the task, make decisions, or continue through ambiguity.
- A `DONE` response is a worker claim, not acceptance. The Lead reviews the changed files, `git diff`, and tests before accepting it.

## What is included

```text
gemini-worker-protocol/
├── SKILL.md                              # Codex skill entry point
├── INSTALL.md                            # Full Windows setup guide
├── agents/openai.yaml                    # Codex UI metadata
├── scripts/
│   ├── Install-GeminiWorkerSkill.ps1     # Current-user installer
│   ├── gemini-worker.ps1                 # Pinned Gemini worker wrapper
│   └── gemini-worker-session.ps1         # Persistent streaming JSONL bridge
└── references/
    ├── worker-contract.md                # Authority, stop, retry, review rules
    └── AGENTS.md.snippet.md              # Per-project opt-in snippet
```

## Guardrails

The wrapper always pins `gemini-3.8-flash-high` and requests schema-constrained JSON output. It does not silently choose another model or run with `--dangerously-skip-permissions`.

Gemini must stop and return `NEED_LEAD` when instructions are unclear, conflicting, incomplete, or require an architecture, product, security, or permission decision. It reports `DONE`, `NEED_LEAD`, or `FAILED` with files read/changed, commands, tests, assumptions, issues, and the current state.

The protocol covers CLI/script errors, authentication/login failures, permissions, timeouts, model unavailability, quota exhaustion, malformed output, interruptions, partial changes, test failures, and unknown errors. It permits at most one safe retry for a transient failure with no changed files. There is never a silent fallback to another worker, model, or the Lead. The Lead takes over only if the user expressly asks to use the current Codex model.

Gemini cannot commit, push, merge, deploy, publish, change credentials, or alter CI/release configuration unless that exact action is explicitly authorized.

## Quick start (Windows)

1. Install and authenticate the Antigravity CLI, then confirm the required model:

   ```powershell
   agy models
   agy -p "Return exactly AGY_READY." --model gemini-3.8-flash-high --output-format json --print-timeout 1m
   ```

2. From this package directory, install the skill, worker wrapper, and `gw` profile function:

   ```powershell
   Unblock-File -Path .\scripts\*.ps1
   .\scripts\Install-GeminiWorkerSkill.ps1 -InstallWorker -AddGwToProfile -AddScriptsToUserPath
   ```

3. Restart PowerShell and Codex Desktop. Use a precise, bounded brief:

   ```powershell
   gw -Task @'
   Task: Update only src/parser.ts to reject empty identifiers.
   Scope: Read src/parser.ts and its existing parser tests only. Do not modify any other file.
   Constraint: Preserve the current public API and error wording style.
   Test: Run npm test -- parser after the edit.
   Completion: Report DONE only if the stated test passes.
   '@ -WorkingDirectory (Get-Location)
   ```

Read [INSTALL.md](INSTALL.md) before setup. It covers Antigravity installation/login, permissions, global locations, manual setup, project opt-in, portability, and result codes.

## Warm streaming sessions

Use `gws` when the Lead needs a few related Gemini turns in the same feature or bug. Unlike one-shot `gw`, `gws` keeps one `agy --input-format stream-json` process alive, emits progress events immediately, and preserves Gemini's worker context for the next explicit Lead instruction.

```powershell
gws -WorkingDirectory (Get-Location)
```

Then send one JSON line at a time through the same terminal:

```json
{"action":"delegate","task":"Inspect only the failing parser test and return NEED_LEAD if the expected behavior is ambiguous."}
```

Wait for a terminal `worker_result` before sending the next line. End the session with `{"action":"stop"}`. The session is a transport optimization, not autonomous model-to-model chat: the selected Codex model remains Lead and authorizes every turn. It emits compact progress events rather than raw tool output and enforces five related turns by default; then it requires a reset. Use one writer session per worktree and reset after a scope or branch change.

## Project opt-in

For a project-only setup, open PowerShell in the project and run:

```powershell
npx gemini-worker-protocol init --project .
```

It creates `.agents/skills/gemini-worker-protocol`, adds this project's opt-in policy to `AGENTS.md` without overwriting existing instructions, and disables the global copy of this skill. Restart Codex, then open the project. It refuses to replace an existing project copy unless you explicitly append `--force`.

## Expected workflow

```text
User request
    -> Codex Lead scopes the task and makes decisions
    -> gw runs one bounded turn, or gws keeps one bounded worker session warm
    -> Gemini returns DONE / NEED_LEAD / FAILED
    -> Codex Lead inspects diff and tests
    -> Lead accepts, requests a new bounded run, or reports the stop condition
```

For the full authority model, retry limits, failure matrix, and required Lead review, see [references/worker-contract.md](references/worker-contract.md).

## Portability

Copy or zip the entire package folder; it contains no credentials, API keys, cached sessions, or project files. On each new Windows machine, authenticate `agy` locally and rerun the installer. See [INSTALL.md](INSTALL.md#4-move-to-another-windows-machine).

## Upgrading

Run the installer again with `-Force` only when you intentionally want to replace the previously installed package or worker script. Use `-WhatIf` first to preview its filesystem and profile changes.
