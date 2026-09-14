# DESCRIPTION: Change directory to the configured work directory (~\cmds\.dotfiles\.cdwork)

$dotfile = Join-Path $HOME 'cmds\.dotfiles\.cdwork'

if (-not (Test-Path $dotfile)) {
    Write-Host "Work directory not configured. Set a path in: $dotfile" -ForegroundColor Red
    exit 1
}

$workDir = Get-Content $dotfile |
    Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } |
    Select-Object -First 1

if (-not $workDir) {
    Write-Host "No path found in $dotfile" -ForegroundColor Red
    exit 1
}

$workDir = $workDir.Trim()

if (-not (Test-Path $workDir)) {
    Write-Host "Configured work directory does not exist: $workDir" -ForegroundColor Red
    exit 1
}

# Resolve to a fully-expanded absolute path before handing it to cdwork.bat: PowerShell's
# Test-Path understands shorthand like "~", but the "cd /d" that cdwork.bat runs in cmd.exe
# does not, so a literal "~/..." string fails there with a syntax error.
$workDir = (Resolve-Path $workDir).ProviderPath

# Write path to temp file so cdwork.bat can cd to it (child process can't change parent's directory)
$workDir | Set-Content "$env:TEMP\_cdwork_result.txt"

# Also print the path to stdout, since the PowerShell wrapper documented in the README
# (`function cdwork { Set-Location (& "$HOME\cmds\scripts\cdwork.ps1") }`) needs this
# script's output, not the temp file, to do the actual Set-Location.
Write-Output $workDir
