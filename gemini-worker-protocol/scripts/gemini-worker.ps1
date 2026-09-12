<#
Runs one bounded Gemini execution-worker task. Install this file as
%USERPROFILE%\Scripts\gemini-worker.ps1; call it through the `gw` function.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Task,

    [string]$WorkingDirectory = (Get-Location).Path,

    [ValidateRange(1, 60)]
    [int]$TimeoutMinutes = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$model = 'gemini-3.8-flash-high'

function Write-WorkerFailure {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$LogDirectory
    )

    Write-Output 'STATUS: FAILED'
    Write-Output "FAILURE_KIND: $Kind"
    Write-Output "MESSAGE: $Message"
    Write-Output "LOG_DIRECTORY: $LogDirectory"
    Write-Output 'NEXT_ACTION: Stop. Inspect the logs and worktree; do not silently fall back.'
}

function Get-FailureKind {
    param([string]$Text)

    if ($Text -match '(?i)quota|rate limit|resource exhausted|too many requests') { return 'QUOTA_EXHAUSTED' }
    if ($Text -match '(?i)authentication required|not authenticated|login|sign[ -]?in|credential') { return 'AUTH_LOGIN_FAILURE' }
    if ($Text -match '(?i)permission denied|access denied|not allowed|approval') { return 'PERMISSION_DENIED' }
    if ($Text -match '(?i)invalid model|model .*unavailable|model .*not recognized|model .*not found') { return 'MODEL_UNAVAILABLE' }
    if ($Text -match '(?i)timeout|timed out|deadline exceeded') { return 'TIMEOUT' }
    if ($Text -match '(?i)cancelled|canceled|interrupted') { return 'INTERRUPTED' }
    return 'CLI_ERROR'
}

if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
    $logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'gemini-worker-no-workspace'
    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
    Write-WorkerFailure -Kind 'INVALID_WORKING_DIRECTORY' -Message "Directory does not exist: $WorkingDirectory" -LogDirectory $logDirectory
    $global:LASTEXITCODE = 10
    return
}

if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
    $logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'gemini-worker-missing-agy'
    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
    Write-WorkerFailure -Kind 'MISSING_COMMAND' -Message 'The Antigravity CLI command `agy` was not found on PATH.' -LogDirectory $logDirectory
    $global:LASTEXITCODE = 11
    return
}

$runId = "gemini-worker-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))-$PID"
$logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) $runId
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$schemaPath = Join-Path $logDirectory 'report-schema.json'
$stdoutPath = Join-Path $logDirectory 'stdout.json'
$stderrPath = Join-Path $logDirectory 'stderr.log'

$schema = @'
{
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "status": { "type": "string", "enum": ["DONE", "NEED_LEAD", "FAILED"] },
    "task_completed": { "type": "string" },
    "files_read": { "type": "array", "items": { "type": "string" } },
    "files_changed": { "type": "array", "items": { "type": "string" } },
    "commands_run": { "type": "array", "items": { "type": "string" } },
    "test_results": { "type": "array", "items": { "type": "string" } },
    "assumptions": { "type": "array", "items": { "type": "string" } },
    "remaining_issues": { "type": "array", "items": { "type": "string" } },
    "question": { "type": "string" },
    "options": { "type": "array", "items": { "type": "string" } },
    "current_state": { "type": "string" }
  },
  "required": ["status", "task_completed", "files_read", "files_changed", "commands_run", "test_results", "assumptions", "remaining_issues", "question", "options", "current_state"]
}
'@
Set-Content -LiteralPath $schemaPath -Value $schema -Encoding utf8

$workerPrompt = @"
You are Gemini 3.8 Flash High, an execution worker. The currently selected Codex Desktop model is the Lead Agent and is the only planner, decision-maker, reviewer, and user-facing agent.

Carry out only the bounded Lead brief below, within the supplied working directory. Do not invent context, infer missing requirements, broaden scope, clean up unrelated code, make architecture/business/security decisions, select another worker/model, or claim to be the Lead. Do not commit, push, merge, deploy, publish, change credentials, or modify CI/release configuration unless this exact brief explicitly authorizes it.

If the brief is unclear or conflicting, repository facts need a decision, required context is missing, a permission boundary blocks you, or the work would exceed scope: stop immediately. Do not make further changes. Return status NEED_LEAD with one precise question, concrete safe options, and the current state.

If you complete the task, return status DONE. If execution cannot continue, return FAILED. Always fill every field required by the JSON schema truthfully. Include all files read/changed, commands run, test results (or "Not run" with a reason), assumptions, and remaining issues. The Lead will independently review the diff and tests; completion is not acceptance.

Lead brief begins:
$Task
Lead brief ends.
"@

try {
    Push-Location -LiteralPath $WorkingDirectory
    try {
        # No --dangerously-skip-permissions: respect the user's scoped agy permissions.
        $stdout = & agy -p $workerPrompt --model $model --output-format json --json-schema $schemaPath --print-timeout "$TimeoutMinutes`m" 2> $stderrPath
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
}
catch {
    $_ | Out-String | Set-Content -LiteralPath $stderrPath -Encoding utf8
    Write-WorkerFailure -Kind 'WRAPPER_ERROR' -Message $_.Exception.Message -LogDirectory $logDirectory
    $global:LASTEXITCODE = 12
    return
}

$stdoutText = ($stdout | Out-String).Trim()
Set-Content -LiteralPath $stdoutPath -Value $stdoutText -Encoding utf8
$stderrText = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }

if ($exitCode -ne 0) {
    Write-WorkerFailure -Kind (Get-FailureKind -Text "$stdoutText`n$stderrText") -Message "agy exited with code $exitCode." -LogDirectory $logDirectory
    $global:LASTEXITCODE = 20
    return
}

try {
    $envelope = $stdoutText | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-WorkerFailure -Kind 'MALFORMED_OUTPUT' -Message 'agy did not return a parseable JSON envelope.' -LogDirectory $logDirectory
    $global:LASTEXITCODE = 21
    return
}

if ($envelope.status -ne 'SUCCESS') {
    $failureText = "$($envelope.error)`n$stderrText"
    Write-WorkerFailure -Kind (Get-FailureKind -Text $failureText) -Message ([string]$envelope.error) -LogDirectory $logDirectory
    $global:LASTEXITCODE = 22
    return
}

$report = $envelope.structured_output
if ($null -eq $report -or $report.status -notin @('DONE', 'NEED_LEAD', 'FAILED')) {
    Write-WorkerFailure -Kind 'MALFORMED_OUTPUT' -Message 'The successful agy response did not contain a valid structured worker report.' -LogDirectory $logDirectory
    $global:LASTEXITCODE = 23
    return
}

Write-Output "STATUS: $($report.status)"
Write-Output "TASK_COMPLETED: $($report.task_completed)"
Write-Output "FILES_READ: $($report.files_read -join '; ')"
Write-Output "FILES_CHANGED: $($report.files_changed -join '; ')"
Write-Output "COMMANDS_RUN: $($report.commands_run -join '; ')"
Write-Output "TEST_RESULTS: $($report.test_results -join '; ')"
Write-Output "ASSUMPTIONS: $($report.assumptions -join '; ')"
Write-Output "REMAINING_ISSUES: $($report.remaining_issues -join '; ')"
Write-Output "QUESTION: $($report.question)"
Write-Output "OPTIONS: $($report.options -join '; ')"
Write-Output "CURRENT_STATE: $($report.current_state)"
Write-Output "LOG_DIRECTORY: $logDirectory"

switch ($report.status) {
    'DONE' { $global:LASTEXITCODE = 0; return }
    'NEED_LEAD' { $global:LASTEXITCODE = 2; return }
    default { $global:LASTEXITCODE = 3; return }
}
