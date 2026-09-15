# DESCRIPTION: Background watcher engine for notifywhen - polls a check script on an interval and shows a windowed Chrome notification when it succeeds.
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

Write-Log "condition met, launching notification window"

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
$profileDir = Join-Path $RunDir 'chrome-profile'
$meta = Get-Meta

# The notification page is served over HTTP from a loopback listener rather
# than opened as a file:// URL: Chrome treats file: URLs as unique, isolated
# origins and blocks/hangs navigation from a file: page to http://127.0.0.1,
# so a same-origin http:// page is required for the "open in default
# browser" link (below) to actually reach this listener.
$listener = $null
$startUrl = $null
if ($meta.linkPort) {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$($meta.linkPort)/")
    try {
        $listener.Start()
        $startUrl = "http://127.0.0.1:$($meta.linkPort)/"
        Write-Log "notification server listening on port $($meta.linkPort)"
    } catch {
        Write-Log "notification server failed to start on port $($meta.linkPort): $($_.Exception.Message)"
        $listener = $null
    }
}
if (-not $startUrl) {
    $startUrl = 'file:///' + ($htmlPath -replace '\\', '/')
}

# Size the window to half the primary monitor's width/height, centered.
Add-Type -AssemblyName System.Windows.Forms
$screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$winWidth = [int]($screenBounds.Width / 2)
$winHeight = [int]($screenBounds.Height / 2)
$winX = [int](($screenBounds.Width - $winWidth) / 2)
$winY = [int](($screenBounds.Height - $winHeight) / 2)

$chromeProc = Start-Process -FilePath $chromePath -ArgumentList @(
    "--app=$startUrl",
    '--new-window',
    "--user-data-dir=$profileDir",
    '--autoplay-policy=no-user-gesture-required',
    "--window-size=$winWidth,$winHeight",
    "--window-position=$winX,$winY"
) -PassThru

$meta = Get-Meta
$meta.status = 'notified'
$meta.chromePid = $chromeProc.Id
Set-Meta $meta
Write-Log "chrome launched, pid=$($chromeProc.Id)"

if ($listener) {
    # A single outstanding GetContextAsync() task is tracked across loop
    # iterations - a fresh call is only started once the previous one has
    # been handled, so a request that arrives right as a poll times out is
    # never silently abandoned (which would leave the browser hanging on a
    # response that never comes).
    $pendingTask = $listener.GetContextAsync()
}

while (-not $chromeProc.HasExited) {
    if ($listener) {
        if ($pendingTask.Wait(1000)) {
            $context = $pendingTask.Result
            $response = $context.Response
            $path = $context.Request.Url.AbsolutePath
            if ($path -eq '/open') {
                try {
                    Start-Process -FilePath $meta.url
                    Write-Log "opened $($meta.url) in default browser"
                } catch {
                    Write-Log "failed to open default browser: $($_.Exception.Message)"
                }
                # notify.html's link click is handled by fetch(), not a page
                # navigation, so this just needs to resolve the request - the
                # page itself shows the "opened" status alongside its
                # existing content once the fetch completes.
                $body = [System.Text.Encoding]::UTF8.GetBytes('ok')
                $response.ContentType = 'text/plain'
                $response.ContentLength64 = $body.Length
                $response.OutputStream.Write($body, 0, $body.Length)
                $response.OutputStream.Close()
            } else {
                $htmlBody = [System.IO.File]::ReadAllBytes($htmlPath)
                $response.ContentType = 'text/html'
                $response.ContentLength64 = $htmlBody.Length
                $response.OutputStream.Write($htmlBody, 0, $htmlBody.Length)
                $response.OutputStream.Close()
            }
            $pendingTask = $listener.GetContextAsync()
        }
    } else {
        Start-Sleep -Milliseconds 500
    }
}

if ($listener) {
    $listener.Stop()
    $listener.Close()
}

Write-Log "chrome window closed, cleaning up $RunDir"

Remove-Item -Path $RunDir -Recurse -Force
Write-Log "cleanup complete, exiting"
