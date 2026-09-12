<#
Persistent JSONL bridge for a single Gemini execution-worker session.
Run `gws -WorkingDirectory <repo>` in a persistent terminal, then send one line
per turn: {"action":"delegate","task":"<explicit Lead brief>"}. Send
{"action":"stop"} or close stdin to end the session.
#>
[CmdletBinding()]
param(
    [string]$WorkingDirectory = (Get-Location).Path,

    [ValidateRange(1, 60)]
    [int]$TimeoutMinutes = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$model = 'gemini-3.8-flash-high'

function Write-SessionJson {
    param([Parameter(Mandatory)][hashtable]$Value)
    $Value | ConvertTo-Json -Depth 32 -Compress
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
    Write-SessionJson @{ event = 'failure'; kind = 'INVALID_WORKING_DIRECTORY'; message = "Directory does not exist: $WorkingDirectory" }
    $global:LASTEXITCODE = 10
    return
}

$agy = Get-Command agy -ErrorAction SilentlyContinue
if ($null -eq $agy) {
    Write-SessionJson @{ event = 'failure'; kind = 'MISSING_COMMAND'; message = 'The Antigravity CLI command `agy` was not found on PATH.' }
    $global:LASTEXITCODE = 11
    return
}

$sessionId = "gemini-session-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))-$PID"
$logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) $sessionId
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$schemaPath = Join-Path $logDirectory 'report-schema.json'
$transcriptPath = Join-Path $logDirectory 'stream.ndjson'

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

$arguments = "--input-format stream-json --output-format stream-json --model $model --json-schema `"$schemaPath`" --print-timeout $TimeoutMinutes`m"
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $agy.Path
$startInfo.Arguments = $arguments
$startInfo.WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $false
$startInfo.CreateNoWindow = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo

if (-not $process.Start()) {
    Write-SessionJson @{ event = 'failure'; kind = 'CLI_ERROR'; message = 'Unable to start agy.'; log_directory = $logDirectory }
    $global:LASTEXITCODE = 12
    return
}

$turn = 0
$sessionReady = @{ event = 'session_ready'; session_id = $sessionId; model = $model; log_directory = $logDirectory; protocol = 'Send JSONL: {"action":"delegate","task":"<explicit Lead brief>"}; wait for worker_result before another turn.' }
Write-SessionJson $sessionReady

try {
    while ($null -ne ($requestLine = [Console]::In.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }

        try {
            $request = $requestLine | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-SessionJson @{ event = 'failure'; kind = 'MALFORMED_INPUT'; message = 'Each bridge input line must be a JSON object.'; session_id = $sessionId }
            continue
        }

        $actionProperty = $request.PSObject.Properties['action']
        $taskProperty = $request.PSObject.Properties['task']
        $action = if ($null -ne $actionProperty) { [string]$actionProperty.Value } else { '' }
        $task = if ($null -ne $taskProperty) { [string]$taskProperty.Value } else { '' }

        if ($action -eq 'stop') {
            Write-SessionJson @{ event = 'session_stopping'; session_id = $sessionId }
            break
        }
        if ($action -ne 'delegate' -or [string]::IsNullOrWhiteSpace($task)) {
            Write-SessionJson @{ event = 'failure'; kind = 'INVALID_REQUEST'; message = 'Use {"action":"delegate","task":"<explicit Lead brief>"}.'; session_id = $sessionId }
            continue
        }
        if ($process.HasExited) {
            Write-SessionJson @{ event = 'failure'; kind = 'INTERRUPTED'; message = "agy exited with code $($process.ExitCode)."; session_id = $sessionId; log_directory = $logDirectory }
            break
        }

        $turn++
        if ($turn -eq 1) {
            $content = @"
You are Gemini 3.8 Flash High, an execution worker. The currently selected Codex Desktop model is the Lead Agent and is the only planner, decision-maker, reviewer, and user-facing agent.

Carry out only the bounded Lead brief below, within the supplied working directory. Do not invent context, infer missing requirements, broaden scope, clean up unrelated code, make architecture/business/security decisions, select another worker/model, or claim to be the Lead. Do not commit, push, merge, deploy, publish, change credentials, or modify CI/release configuration unless this exact brief explicitly authorizes it.

If the brief is unclear or conflicting, repository facts need a decision, required context is missing, a permission boundary blocks you, or the work would exceed scope: stop immediately. Do not make further changes. Return status NEED_LEAD with one precise question, concrete safe options, and the current state.

If you complete the task, return status DONE. If execution cannot continue, return FAILED. Always fill every field required by the JSON schema truthfully. Include all files read/changed, commands run, test results (or "Not run" with a reason), assumptions, and remaining issues. The Lead will independently review the diff and tests; completion is not acceptance.

Lead brief begins:
$task
Lead brief ends.
"@
        }
        else {
            $content = @"
This is an explicit follow-up from the Lead. Apply only this authorization and preserve all previous worker rules. If it requires a new decision or expands scope, return NEED_LEAD instead of proceeding.

Lead follow-up begins:
$task
Lead follow-up ends.
"@
        }

        $agyMessage = @{ event = 'user'; message = @{ content = $content } } | ConvertTo-Json -Depth 8 -Compress
        $process.StandardInput.WriteLine($agyMessage)
        $process.StandardInput.Flush()
        Add-Content -LiteralPath $transcriptPath -Value $agyMessage -Encoding utf8

        $receivedResult = $false
        while (-not $receivedResult) {
            $eventLine = $process.StandardOutput.ReadLine()
            if ($null -eq $eventLine) {
                $exitCode = if ($process.HasExited) { $process.ExitCode } else { -1 }
                Write-SessionJson @{ event = 'failure'; kind = 'INTERRUPTED'; message = "agy ended before a terminal result (exit code $exitCode)."; session_id = $sessionId; log_directory = $logDirectory }
                break 2
            }
            Add-Content -LiteralPath $transcriptPath -Value $eventLine -Encoding utf8
            try {
                $event = $eventLine | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-SessionJson @{ event = 'failure'; kind = 'MALFORMED_OUTPUT'; message = 'agy emitted a non-JSON stream event.'; session_id = $sessionId; log_directory = $logDirectory }
                break 2
            }

            if ($event.event -eq 'result') {
                $receivedResult = $true
                $result = $event.result
                if ($result.status -ne 'SUCCESS') {
                    $kind = Get-FailureKind -Text ([string]$result.error)
                    Write-SessionJson @{ event = 'failure'; kind = $kind; message = [string]$result.error; session_id = $sessionId; log_directory = $logDirectory }
                    break 2
                }
                if ($null -eq $result.structured_output -or $result.structured_output.status -notin @('DONE', 'NEED_LEAD', 'FAILED')) {
                    Write-SessionJson @{ event = 'failure'; kind = 'MALFORMED_OUTPUT'; message = 'The terminal result lacks a valid structured worker report.'; session_id = $sessionId; log_directory = $logDirectory }
                    break 2
                }
                Write-SessionJson @{ event = 'worker_result'; session_id = $sessionId; turn = $turn; report = $result.structured_output; log_directory = $logDirectory }
            }
            else {
                Write-SessionJson @{ event = 'worker_event'; session_id = $sessionId; turn = $turn; payload = $event }
            }
        }
    }
}
finally {
    if (-not $process.HasExited) {
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(5000)) { $process.Kill() }
    }
    $process.Dispose()
}

$global:LASTEXITCODE = 0
