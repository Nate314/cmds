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

# Write path to temp file so cdwork.bat can cd to it (child process can't change parent's directory)
$workDir | Set-Content "$env:TEMP\_cdwork_result.txt"
