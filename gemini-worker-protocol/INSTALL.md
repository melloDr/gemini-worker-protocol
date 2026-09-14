# Install on Windows

## npm one-command installer

After installing Node.js 18+, installing and authenticating Antigravity CLI, run:

```powershell
npx gemini-worker-protocol
```

The npm command calls this package's PowerShell installer for the current Windows user. It installs the global Codex skill, the `gw`/`gws` wrappers, their Scripts directory in User PATH, and the PowerShell profile functions. It does not install `agy` or log in to Gemini. Open a new PowerShell window after it completes.

Use these only when needed:

```powershell
# Preview the command without changing your machine.
npx gemini-worker-protocol --dry-run

# Replace a previous installation of this same protocol.
npx gemini-worker-protocol --force
```

For a machine without npm, use the portable installation below.

This package is portable: copy the entire `gemini-worker-protocol` folder to the new machine before installing. Do not copy only `SKILL.md`; the wrapper, schema, policy reference, and installer are all part of the package.

## 1. Install and authenticate Antigravity CLI

Open PowerShell and use the current official installer:

```powershell
irm https://antigravity.google/cli/install.ps1 | iex
```

Open a new PowerShell window, then start an interactive session once and finish the Google sign-in if prompted:

```powershell
agy
```

Check that the account exposes the required pinned model, then verify non-interactive `-p` mode:

```powershell
agy models
agy -p "Return exactly AGY_READY." --model gemini-3.8-flash-high --output-format json --print-timeout 1m
```

The first command must list `gemini-3.8-flash-high`. Do not replace it with a nearby model name if it is absent, unavailable, or quota-limited: resolve that with the user. The wrapper explicitly passes this model for every run, so it cannot silently select a different one.

`agy -p` uses cached credentials from the interactive sign-in. If the verification returns an authentication error, run `agy` interactively again. For headless execution, configure only the narrow Antigravity permissions appropriate to the repositories and commands you trust; this package intentionally never passes `--dangerously-skip-permissions`.

Official references: [Antigravity installation and auth](https://www.antigravity.google/docs/cli/install/) and [headless mode, models, permissions, and timeouts](https://www.antigravity.google/docs/cli/headless/).

## 2. Install the global Codex skill and worker

From the copied package folder, run:

```powershell
Unblock-File -Path .\scripts\*.ps1
.\scripts\Install-GeminiWorkerSkill.ps1 -InstallWorker -AddGwToProfile -AddScriptsToUserPath
```

For an upgrade from an older package version, add `-Force` so the installer also replaces the worker scripts and updates the existing profile block with the `gws` streaming function.

The installer writes only for the current user:

- the skill to `C:\Users\<USER>\.codex\skills\gemini-worker-protocol` (or `$env:CODEX_HOME\skills\gemini-worker-protocol` when `CODEX_HOME` is set);
- the global wrapper to `C:\Users\<USER>\Scripts\gemini-worker.ps1`;
- the streaming bridge to `C:\Users\<USER>\Scripts\gemini-worker-session.ps1`;
- opt-in `gw` and `gws` PowerShell functions to the current user's all-hosts profile;
- optionally, `C:\Users\<USER>\Scripts` to the user `PATH`.

It refuses to overwrite an existing target. If and only if you want this package to replace the prior version, rerun with `-Force`. To preview filesystem/profile changes without writing them, add `-WhatIf`.

Close and reopen PowerShell (and restart Codex Desktop if it was already open) after installation. Confirm the function and wrapper:

```powershell
Get-Command gw
gw -Task "No work is authorized. Return NEED_LEAD and state why." -WorkingDirectory (Get-Location)
```

The second command is a protocol smoke test. It should return `STATUS: NEED_LEAD`; it must not change files.

### Use a warm streaming session for related turns

Use `gws` only from a persistent PowerShell terminal. It launches one Gemini process using Antigravity's `stream-json` protocol, then reads one JSON object per line from that terminal. Keep the terminal open; the Lead sends the next turn only after the previous `worker_result` arrives. The bridge emits compact progress events rather than raw tool output, and it enforces a five-turn session limit by default.

```powershell
gws -WorkingDirectory (Get-Location)
```

Paste/send this as the first line, then wait for its terminal `worker_result`:

```json
{"action":"delegate","task":"Task: Update only src/parser.ts to reject empty identifiers. Scope: Read src/parser.ts and its existing parser tests only. Test: Run npm test -- parser. Completion: Return DONE only if the test passes."}
```

For an authorized follow-up in the same feature, send another `delegate` line. To end the warm process, send `{"action":"stop"}` or close the terminal stdin. Do not use more than one writer session in a worktree, do not interleave requests, and reset the session after 3–5 turns or any scope/branch change.

### Manual setup (if the installer is not used)

```powershell
$codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$package = (Get-Location).Path
New-Item -ItemType Directory -Force -Path (Join-Path $codexRoot 'skills') | Out-Null
Copy-Item -Recurse $package (Join-Path $codexRoot 'skills\gemini-worker-protocol')
New-Item -ItemType Directory -Force -Path (Join-Path $HOME 'Scripts') | Out-Null
Copy-Item .\scripts\gemini-worker.ps1 (Join-Path $HOME 'Scripts\gemini-worker.ps1')
Copy-Item .\scripts\gemini-worker-session.ps1 (Join-Path $HOME 'Scripts\gemini-worker-session.ps1')
function global:gw { & (Join-Path $HOME 'Scripts\gemini-worker.ps1') @args }
function global:gws { & (Join-Path $HOME 'Scripts\gemini-worker-session.ps1') @args }
```

To persist the final `gw` function, add it to `$PROFILE.CurrentUserAllHosts`, then open a new PowerShell session. Add `$HOME\Scripts` to the user `PATH` only if you also want to call the script by path/name outside `gw`.

## 3. Opt projects in deliberately

The skill is global; each repository remains opt-in. Copy the snippet in [references/AGENTS.md.snippet.md](references/AGENTS.md.snippet.md) into a project's `AGENTS.md` only when the user wants that repository to permit Gemini delegation.

When delegating, the Codex Lead supplies a closed brief that identifies the allowed scope, constraints, tests, and completion condition:

```powershell
gw -Task @'
Task: Update only src/parser.ts to reject empty identifiers.
Scope: Read src/parser.ts and its existing parser tests only. Do not modify any other file.
Constraint: Preserve current public API and error wording style.
Test: Run npm test -- parser after the edit.
Completion: Report a structured DONE result only if the stated test passes.
'@ -WorkingDirectory (Get-Location)
```

The Lead must review the changed files, `git diff`, and tests before accepting `DONE`. `NEED_LEAD`, failed wrapper results, partial work, malformed output, or test failure are all stop-and-review outcomes—not a reason to quietly invoke another model or have the Lead take over without the user's explicit direction.

## 4. Move to another Windows machine

1. Copy or zip the whole `gemini-worker-protocol` package folder.
2. On the target machine, install/login to `agy` and pass the model plus `agy -p` checks in step 1.
3. Unzip/copy the folder, run the installer in step 2, restart PowerShell/Codex, and add only the project opt-ins you intend.

The package contains no credentials, API keys, cached sessions, or project files. Authentication remains local to each Windows user profile.

## Wrapper result codes

| Code | Meaning |
|---:|---|
| 0 | Gemini returned a structured `DONE` report; Lead review is still required. |
| 2 | Gemini returned `NEED_LEAD`; clarify and explicitly authorize another bounded run. |
| 3 | Gemini returned `FAILED`; inspect logs/worktree. |
| 4 | The streaming session reached its turn limit; review and start a new session. |
| 10–12 | Wrapper preflight or wrapper error. |
| 20–23 | `agy` failure, non-success envelope, or malformed output. |

The wrapper assigns this value to PowerShell's `$LASTEXITCODE` and returns rather
than using `exit`, so calling `gw` cannot close the interactive PowerShell
session. Scripts can inspect `$LASTEXITCODE` after the call.
