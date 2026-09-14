Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$bridge = Join-Path $repoRoot 'gemini-worker-protocol\scripts\gemini-worker-session.ps1'
$fakeSource = Join-Path $PSScriptRoot 'FakeAgy.cs'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gemini-worker-session-tests-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$fakeAgy = Join-Path $testRoot 'agy.exe'
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo "/out:$fakeAgy" $fakeSource
if ($LASTEXITCODE -ne 0) { throw 'Unable to compile the fake agy executable.' }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Bridge {
    param([string[]]$Messages)

    $command = "& '$($bridge.Replace("'", "''"))' -WorkingDirectory '$($repoRoot.Replace("'", "''"))'; [Console]::Out.WriteLine('__LASTEXITCODE=' + `$global:LASTEXITCODE)"
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.Arguments = "-NoProfile -EncodedCommand $encodedCommand"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['Path'] = "$testRoot;$env:Path"
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    foreach ($message in $Messages) { $process.StandardInput.WriteLine($message) }
    $process.StandardInput.Close()
    $output = $process.StandardOutput.ReadToEnd()
    $error = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return @{ Output = $output; Error = $error; ExitCode = $process.ExitCode }
}

$safeRun = Invoke-Bridge -Messages @('{"action":"delegate","task":"safe"}', '{"action":"stop"}')
Assert-True ($safeRun.Output -match '"event":"worker_progress"') 'Expected a compact worker_progress event.'
Assert-True (-not ($safeRun.Output -match 'TOP_SECRET')) 'Raw tool output must not reach bridge stdout.'

$turnMessages = 1..6 | ForEach-Object { '{"action":"delegate","task":"turn ' + $_ + '"}' }
$turnRun = Invoke-Bridge -Messages ($turnMessages + '{"action":"stop"}')
$completedTurns = ([regex]::Matches($turnRun.Output, '"event":"worker_result"')).Count
Assert-True ($completedTurns -eq 5) "Expected five completed turns, got $completedTurns."
Assert-True ($turnRun.Output -match 'SESSION_RESET_REQUIRED') 'Expected a reset requirement after the fifth turn.'

$failureRun = Invoke-Bridge -Messages @('{"action":"delegate","task":"FORCE_ERROR"}')
Assert-True ($failureRun.Output -match '"kind":"TIMEOUT"') 'Expected a classified timeout failure.'
Assert-True ($failureRun.Output -match '__LASTEXITCODE=20') "Expected a non-zero bridge result code after worker failure. Output: $($failureRun.Output)"

$source = Get-Content -LiteralPath $bridge -Raw
Assert-True ($source -match 'StreamWriter') 'Expected buffered transcript writing.'
Assert-True ($source -notmatch 'Add-Content -LiteralPath \$transcriptPath') 'Transcript must not flush every stream event.'

Write-Output 'STREAMING_BRIDGE_TESTS_PASSED'
