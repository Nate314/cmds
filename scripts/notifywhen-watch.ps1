# DESCRIPTION: Background watcher engine for notifywhen - polls a check script on an interval and shows a kiosk notification when it succeeds.
param(
    [Parameter(Mandatory = $true)][string]$RunDir,
    [Parameter(Mandatory = $true)][int]$IntervalSeconds
)

$ErrorActionPreference = 'Stop'

function Get-Meta {
    Get-Content -Raw -Path (Join-Path $RunDir 'meta.json') | ConvertFrom-Json
}

function Set-Meta($meta) {
    $meta | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $RunDir 'meta.json')
}

$id = (Get-Meta).id
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir "notifywhen-$id.log"

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line
}

$checkScript = Join-Path $RunDir 'check.ps1'
Write-Log "watcher started, interval=${IntervalSeconds}s, checkScript=$checkScript"

while ($true) {
    $conditionMet = $false
    try {
        & pwsh -NoProfile -File $checkScript
        if ($LASTEXITCODE -eq 0) { $conditionMet = $true }
        Write-Log "check exit code: $LASTEXITCODE"
    } catch {
        Write-Log "check errored: $($_.Exception.Message)"
    }

    if ($conditionMet) { break }
    Start-Sleep -Seconds $IntervalSeconds
}

Write-Log "condition met, launching kiosk notification"

$chromeCmd = Get-Command chrome -ErrorAction SilentlyContinue
if ($chromeCmd) {
    $chromePath = $chromeCmd.Source
} else {
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    $chromePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $chromePath) {
    Write-Log "ERROR: chrome.exe not found on PATH or in common install locations"
    $meta = Get-Meta
    $meta.status = 'notify-failed'
    Set-Meta $meta
    exit 1
}

$htmlPath = Join-Path $RunDir 'notify.html'
$fileUrl = 'file:///' + ($htmlPath -replace '\\', '/')
$profileDir = Join-Path $RunDir 'chrome-profile'

$chromeProc = Start-Process -FilePath $chromePath -ArgumentList @(
    '--kiosk',
    '--new-window',
    "--user-data-dir=$profileDir",
    $fileUrl
) -PassThru

$meta = Get-Meta
$meta.status = 'notified'
$meta.chromePid = $chromeProc.Id
Set-Meta $meta
Write-Log "chrome launched, pid=$($chromeProc.Id)"

$chromeProc.WaitForExit()
Write-Log "chrome window closed, cleaning up $RunDir"

Remove-Item -Path $RunDir -Recurse -Force
Write-Log "cleanup complete, exiting"
