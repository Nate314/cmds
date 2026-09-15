# DESCRIPTION: Add PowerShell wrapper functions for directory-changing commands to $PROFILE

$wrappers = @{
    cdwork = 'function cdwork { Set-Location (& "$HOME\cmds\scripts\cdwork.ps1") }'
}

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Force $profileDir | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File $PROFILE | Out-Null
}

$profileContent = Get-Content $PROFILE -Raw
if (-not $profileContent) {
    $profileContent = ''
}

$added = @()
foreach ($name in $wrappers.Keys) {
    if ($profileContent -notmatch [regex]::Escape("function $name")) {
        Add-Content -Path $PROFILE -Value $wrappers[$name]
        $added += $name
    }
}

if ($added.Count -gt 0) {
    Write-Host "Added wrapper function(s) to $($PROFILE): $($added -join ', ')" -ForegroundColor Green
    Write-Host "Restart PowerShell (or run '. `$PROFILE') for the change to take effect." -ForegroundColor Yellow
} else {
    Write-Host "PowerShell profile already has all wrapper functions ($($wrappers.Keys -join ', '))." -ForegroundColor Green
}
