# DESCRIPTION: Prompt for a browser and a list of URLs, then open all URLs at once

$browserDefs = @(
    [PSCustomObject]@{
        Name  = 'Chrome'
        Paths = @(
            'chrome'
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
            'C:\Program Files\Google\Chrome\Application\chrome.exe'
        )
    }
    [PSCustomObject]@{
        Name  = 'Edge'
        Paths = @(
            'msedge'
            'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        )
    }
    [PSCustomObject]@{
        Name  = 'Firefox'
        Paths = @(
            'firefox'
            'C:\Program Files\Mozilla Firefox\firefox.exe'
            'C:\Program Files (x86)\Mozilla Firefox\firefox.exe'
        )
    }
    [PSCustomObject]@{
        Name  = 'Brave'
        Paths = @(
            'brave'
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
            'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe'
        )
    }
)

function Find-BrowserExe([string[]]$Paths) {
    foreach ($p in $Paths) {
        if (Get-Command $p -ErrorAction SilentlyContinue) { return $p }
        if (Test-Path $p) { return $p }
    }
}

$available = $browserDefs | ForEach-Object {
    $exe = Find-BrowserExe $_.Paths
    if ($exe) { [PSCustomObject]@{ Name = $_.Name; Exe = $exe } }
}

if (-not $available) {
    Write-Host 'No supported browsers found on this system.' -ForegroundColor Red
    exit 1
}

Write-Host 'Select a browser:' -ForegroundColor Yellow
for ($i = 0; $i -lt $available.Count; $i++) {
    Write-Host "  [$($i + 1)] $($available[$i].Name)"
}

do {
    $raw = Read-Host 'Enter number'
} while ($raw -notmatch '^\d+$' -or [int]$raw -lt 1 -or [int]$raw -gt $available.Count)

$browser = $available[[int]$raw - 1]

Write-Host "`nPaste URLs (one per line), then press Enter on a blank line:" -ForegroundColor Yellow
$urls = @()
while ($true) {
    $line = Read-Host
    if ([string]::IsNullOrWhiteSpace($line)) { break }
    $urls += $line.Trim()
}

if ($urls.Count -eq 0) {
    Write-Host 'No URLs provided.' -ForegroundColor Red
    exit 1
}

Write-Host "Opening $($urls.Count) URL(s) in $($browser.Name)..." -ForegroundColor Green
Start-Process $browser.Exe -ArgumentList $urls
