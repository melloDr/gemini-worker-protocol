---
name: gemini-worker-protocol
description: Delegate a tightly bounded implementation task to Gemini 3.8 Flash High through the user's gw/gemini-worker.ps1 wrapper, while Codex remains the planning and review lead. Use only for explicit worker delegation, not ordinary coding or model selection.
---

# Gemini Worker Protocol

Use this skill when the user asks to delegate a bounded task to their Gemini worker. The currently selected Codex Desktop model is always the **Lead Agent**: it owns context, planning, architecture, business decisions, user communication, acceptance, and any fallback decision. Gemini 3.8 Flash High is only an execution worker invoked through the user's global `gw` / `gemini-worker.ps1` mechanism.

Before a delegation, read [the worker contract](references/worker-contract.md). Confirm the project opted in (see [the AGENTS.md snippet](references/AGENTS.md.snippet.md)); if it did not, ask the user before changing that project. Do not install or configure the worker unless the user asks.

## Delegate only a closed task

Give Gemini a small, explicit task with its goal, allowed files/areas, concrete constraints, required tests, and a clear completion condition. Supply only the context it actually needs. The Lead must retain decisions and resolve ambiguity; never ask Gemini to infer product intent, choose architecture, expand scope, or continue from an unclear instruction.

Invoke the global wrapper from the intended repository directory, for example:

```powershell
gw -Task "Implement only the accepted change described below..." -WorkingDirectory (Get-Location)
```

The wrapper pins `gemini-3.8-flash-high`, uses bounded headless execution, and requires structured output. Do not substitute a direct `agy` call, another worker/model, or a different execution mechanism unless the user explicitly changes this protocol.

For two or more tightly related turns in one bounded feature or bug, use `gws` (`gemini-worker-session.ps1`) from a persistent terminal. It keeps one `agy --input-format stream-json` process warm and exchanges JSONL requests/results. Send exactly one Lead brief, wait for its terminal `worker_result`, then let the Lead decide whether to send an explicit follow-up. End the session after 3–5 turns, when the feature/branch changes, on any failure, or after a terminal `DONE` that needs no follow-up. Do not use it to let Gemini and the Lead chat freely or to run concurrent writers in the same worktree.

## Lead control loop

1. Inspect the worker report and any logs. `NEED_LEAD`, malformed output, a partial result, or any failure is not success.
2. For `NEED_LEAD`, answer the exact question/options and delegate again only after a new explicit authorization. Never tell it merely to "use best judgment."
3. For `DONE`, independently inspect `git diff`/changed files, run or review the relevant tests, and compare the result with the original task before accepting, requesting rework, or rejecting it.
4. On a failure, classify and report it to the user/Lead. Do not silently fall back to another worker or to the Lead model. The Lead may take over only after the user expressly says to use the current Codex model/Lead.

Use the retry policy and failure handling in the worker contract. Never retry indefinitely. Never commit, push, merge, deploy, alter credentials, or make other external/release actions unless the user explicitly authorizes that action.

## Installation and portability

For a new Windows machine, use [INSTALL.md](INSTALL.md). It covers Antigravity CLI installation and login, `agy -p` verification, the pinned model, the global wrapper and `gw` profile function, global Codex skill installation, and copying this package.
