<#
Installs this portable package for the current Windows user.
It never overwrites an existing skill or worker script unless -Force is supplied.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$ScriptsDirectory = (Join-Path $HOME 'Scripts'),
    [switch]$InstallWorker,
    [switch]$AddGwToProfile,
    [switch]$AddScriptsToUserPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$skillName = 'gemini-worker-protocol'
$packageRoot = Split-Path -Parent $PSScriptRoot
$skillRoot = Join-Path $CodexHome 'skills'
$targetSkill = Join-Path $skillRoot $skillName
$workerSource = Join-Path $PSScriptRoot 'gemini-worker.ps1'
$workerTarget = Join-Path $ScriptsDirectory 'gemini-worker.ps1'
$sessionSource = Join-Path $PSScriptRoot 'gemini-worker-session.ps1'
$sessionTarget = Join-Path $ScriptsDirectory 'gemini-worker-session.ps1'

$sourceResolved = (Resolve-Path -LiteralPath $packageRoot).Path
$targetResolved = if (Test-Path -LiteralPath $targetSkill) { (Resolve-Path -LiteralPath $targetSkill).Path } else { $null }
if ($targetResolved -and $sourceResolved -eq $targetResolved) {
    Write-Output "Skill is already installed at $targetSkill"
}
else {
    if (Test-Path -LiteralPath $targetSkill) {
        if (-not $Force) { throw "Target skill already exists: $targetSkill. Use -Force only to replace this package." }
        if ($PSCmdlet.ShouldProcess($targetSkill, 'replace existing skill package')) { Remove-Item -LiteralPath $targetSkill -Recurse -Force }
    }
    if ($PSCmdlet.ShouldProcess($targetSkill, 'install skill package')) {
        New-Item -ItemType Directory -Force -Path $skillRoot | Out-Null
        Copy-Item -LiteralPath $packageRoot -Destination $targetSkill -Recurse -Force
        Write-Output "Installed Codex skill: $targetSkill"
    }
}

if ($InstallWorker) {
    foreach ($target in @($workerTarget, $sessionTarget)) {
        if ((Test-Path -LiteralPath $target) -and -not $Force) {
            throw "Worker script already exists: $target. Use -Force only to replace it."
        }
    }
    if ($PSCmdlet.ShouldProcess($ScriptsDirectory, 'install Gemini worker wrappers')) {
        New-Item -ItemType Directory -Force -Path $ScriptsDirectory | Out-Null
        Copy-Item -LiteralPath $workerSource -Destination $workerTarget -Force
        Copy-Item -LiteralPath $sessionSource -Destination $sessionTarget -Force
        Write-Output "Installed one-shot worker wrapper: $workerTarget"
        Write-Output "Installed streaming worker bridge: $sessionTarget"
    }
}

if ($AddScriptsToUserPath) {
    $oldPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($oldPath -split ';' | Where-Object { $_ })
    if ($entries -notcontains $ScriptsDirectory -and $PSCmdlet.ShouldProcess('User PATH', "add $ScriptsDirectory")) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $ScriptsDirectory) -join ';'), 'User')
        $env:Path = "$env:Path;$ScriptsDirectory"
        Write-Output "Added to User PATH: $ScriptsDirectory"
    }
}

if ($AddGwToProfile) {
    if (-not (Test-Path -LiteralPath $workerTarget) -or -not (Test-Path -LiteralPath $sessionTarget)) { throw 'Install the worker wrappers first: rerun with -InstallWorker -AddGwToProfile.' }
    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDirectory = Split-Path -Parent $profilePath
    $startMarker = '# >>> gemini-worker-protocol >>>'
    $endMarker = '# <<< gemini-worker-protocol <<<'
    $escapedWorkerTarget = $workerTarget.Replace("'", "''")
    $escapedSessionTarget = $sessionTarget.Replace("'", "''")
    $profileBlock = @"
$startMarker
function global:gw { & '$escapedWorkerTarget' @args }
function global:gws { & '$escapedSessionTarget' @args }
$endMarker
"@
    $existingProfile = if (Test-Path -LiteralPath $profilePath) { Get-Content -LiteralPath $profilePath -Raw } else { '' }
    if ($existingProfile -notmatch [regex]::Escape($startMarker) -and $PSCmdlet.ShouldProcess($profilePath, 'add gw and gws functions')) {
        New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
        Add-Content -LiteralPath $profilePath -Value "`n$profileBlock" -Encoding utf8
        Write-Output "Added gw and gws functions to profile: $profilePath"
    }
    elseif ($existingProfile -match [regex]::Escape($startMarker) -and $Force) {
        $profilePattern = '(?ms)^# >>> gemini-worker-protocol >>>.*?^# <<< gemini-worker-protocol <<<\s*'
        if ($PSCmdlet.ShouldProcess($profilePath, 'update gw and gws functions')) {
            $updatedProfile = [regex]::Replace($existingProfile, $profilePattern, "$profileBlock`n")
            Set-Content -LiteralPath $profilePath -Value $updatedProfile -Encoding utf8
            Write-Output "Updated gw and gws functions in profile: $profilePath"
        }
    }
    elseif ($existingProfile -match [regex]::Escape($startMarker)) {
        Write-Output "The profile already has a gemini-worker-protocol block. Rerun with -Force to add gws."
    }
}

Write-Output 'Open a new PowerShell window after profile or PATH changes. Use gw for one turn and gws for a persistent streaming session.'
