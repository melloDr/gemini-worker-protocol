## External execution worker

This project may use the `gemini-worker-protocol` skill.

The currently selected Codex Desktop model is the Lead Agent and owns planning,
decisions, review, and acceptance. Gemini 3.8 Flash High is an execution worker
only, invoked exclusively through the user's global `gw` / `gemini-worker.ps1`
mechanism. Gemini may act only on an explicit, bounded Lead brief.

Gemini must stop with `NEED_LEAD` when scope or context is unclear/conflicting or
a decision is required. It must never silently fall back to another model or the
Lead. The Lead reviews the diff and tests before accepting any `DONE` report.
No commit, push, merge, deploy, or other external/release action is allowed
without the user's explicit authorization.
