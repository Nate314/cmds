param(
    [Parameter(Position = 0, Mandatory)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$CommandArgs
)

Write-Host $Command -ForegroundColor Magenta

$logDir = Join-Path $PSScriptRoot 'logs'
$null = New-Item -ItemType Directory -Force $logDir
$entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Command $($CommandArgs -join ' ')".TrimEnd()
Add-Content -Path (Join-Path $logDir 'commands.log') -Value $entry

$scriptPath = Join-Path $PSScriptRoot 'scripts' "$Command.ps1"
if (-not (Test-Path $scriptPath)) {
    Write-Host "No script found for command: $Command" -ForegroundColor Red
    exit 1
}

& $scriptPath @CommandArgs
