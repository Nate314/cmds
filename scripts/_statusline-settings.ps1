# DESCRIPTION: Shared status line item definitions and ON/OFF state, dot-sourced by claude-statusline.ps1 and claude-statusline-config.ps1 — not a standalone command, so it has no .bat entry point.

$script:StatusLineDotfile = Join-Path $PSScriptRoot '..\.dotfiles\.statusline'

# Every item the status line can render, in display order. Default is the state used when
# the dotfile has no entry for the item; price items default OFF so nothing touches the
# network until the user opts in.
$script:StatusLineItems = @(
    @{ Key = 'dir';    Label = 'Directory';     Default = $true }
    @{ Key = 'model';  Label = 'Model';         Default = $true }
    @{ Key = 'branch'; Label = 'Git branch';    Default = $true }
    @{ Key = 'ctx';    Label = 'Context usage'; Default = $true }
    @{ Key = '5h';     Label = '5-hour usage';  Default = $true }
    @{ Key = '7d';     Label = '7-day usage';   Default = $true }
    @{ Key = 'lines';  Label = 'Lines added/removed'; Default = $true }
    @{ Key = 'crypto'; Label = 'BTC/ETH prices';      Default = $false }
    @{ Key = 'metals'; Label = 'Gold/silver prices';  Default = $false }
    @{ Key = 'clock';  Label = 'Date/time';     Default = $true }
)

# Read the dotfile's `key=on|off` lines into a hashtable of key -> bool. Missing file or
# unknown/malformed lines are ignored, so defaults apply.
function Read-StatusLineSettings {
    $saved = @{}
    if (-not (Test-Path $script:StatusLineDotfile)) { return $saved }
    foreach ($line in Get-Content $script:StatusLineDotfile) {
        if ($line -match '^\s*([^#=\s]+)\s*=\s*(on|off)\s*$') {
            $saved[$Matches[1]] = ($Matches[2] -eq 'on')
        }
    }
    return $saved
}

# Resolve every item to its effective state (saved value, else its default).
function Get-StatusLineState {
    $saved = Read-StatusLineSettings
    $state = [ordered]@{}
    foreach ($item in $script:StatusLineItems) {
        $state[$item.Key] = if ($saved.ContainsKey($item.Key)) { $saved[$item.Key] } else { $item.Default }
    }
    return $state
}

function Save-StatusLineState($State) {
    $lines = @('# Claude Code status line items (managed by claude-statusline-config)')
    foreach ($item in $script:StatusLineItems) {
        $lines += "$($item.Key)=$(if ($State[$item.Key]) { 'on' } else { 'off' })"
    }
    New-Item -ItemType Directory -Force (Split-Path $script:StatusLineDotfile) | Out-Null
    $lines | Set-Content $script:StatusLineDotfile
}
