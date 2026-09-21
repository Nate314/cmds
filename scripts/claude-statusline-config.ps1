# DESCRIPTION: Show a menu of Claude Code status line items with their ON/OFF state and toggle them (saved to .dotfiles\.statusline)

. (Join-Path $PSScriptRoot '_common.ps1')
. (Join-Path $PSScriptRoot '_statusline-settings.ps1')

$state = Get-StatusLineState
$items = $script:StatusLineItems

while ($true) {
    Write-Host ''
    Write-Host 'Claude Code status line items' -ForegroundColor Cyan
    for ($i = 0; $i -lt $items.Count; $i++) {
        $on = $state[$items[$i].Key]
        $tag = if ($on) { ' ON' } else { 'OFF' }
        $color = if ($on) { 'Green' } else { 'DarkGray' }
        Write-Host ('{0,2}. [' -f ($i + 1)) -NoNewline
        Write-Host $tag -ForegroundColor $color -NoNewline
        Write-Host "] $($items[$i].Label)"
    }
    Write-Host ''
    $answer = Read-Host 'Number to toggle (Enter to quit)'
    if (-not $answer.Trim()) { break }

    $n = 0
    if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $items.Count) {
        $key = $items[$n - 1].Key
        $state[$key] = -not $state[$key]
        Save-StatusLineState $state
    } else {
        Write-Host "Enter a number from 1 to $($items.Count)." -ForegroundColor Red
    }
}
