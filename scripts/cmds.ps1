# DESCRIPTION: List all available commands and what they do (-Border draws a rounded box around the list)

param([switch]$Border)

. (Join-Path $PSScriptRoot '_common.ps1')

$cmdsRoot = Split-Path $PSScriptRoot -Parent
$scriptsDir = $PSScriptRoot
$dotfilesDir = Join-Path $cmdsRoot '.dotfiles'

# A command is "configured" when a matching .dotfiles\.<name> file exists (the convention
# cdwork already uses for its work-directory target). Read its first non-comment line so
# the table can show what it currently resolves to.
function Get-DotfileConfig([string]$Name) {
    $dotfile = Join-Path $dotfilesDir ".$Name"
    if (-not (Test-Path $dotfile)) { return $null }
    $line = Get-Content $dotfile |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } |
        Select-Object -First 1
    if (-not $line) { return $null }
    return Format-HomePath $line.Trim()
}

$commands = Get-ChildItem -Path $cmdsRoot -Filter '*.bat' |
    Sort-Object BaseName |
    ForEach-Object {
        $name = $_.BaseName
        $scriptPath = Join-Path $scriptsDir "$name.ps1"
        $description = ''
        if (Test-Path $scriptPath) {
            $descLine = Get-Content $scriptPath |
                Where-Object { $_ -match '^#\s*DESCRIPTION:\s*(.+)' } |
                Select-Object -First 1
            if ($descLine -match '^#\s*DESCRIPTION:\s*(.+)') {
                $description = $Matches[1]
            }
        }
        [PSCustomObject]@{
            Command     = $name
            Description = $description
            Config      = Get-DotfileConfig $name
            LinkTarget  = if (Test-Path $scriptPath) { $scriptPath } else { $_.FullName }
        }
    }

$nameWidth = ($commands.Command | Measure-Object -Maximum -Property Length).Maximum + 2

# Only pad the description column for rows that actually show a "-> config" suffix,
# otherwise one long, unconfigured command's description would force a huge gap in
# front of every arrow.
$configuredDescriptions = $commands | Where-Object { $_.Config } | ForEach-Object { $_.Description }
$descWidth = if ($configuredDescriptions) {
    ($configuredDescriptions | Measure-Object -Maximum -Property Length).Maximum + 2
} else {
    0
}

# Build each row as rendered text (with link/color codes) plus its visible length, so the
# border can pad to the widest row without the invisible escape sequences skewing widths.
$rows = foreach ($cmd in $commands) {
    # Pad the plain name to column width first, then wrap the padded (already-aligned)
    # string in the link/color codes, so the invisible escape sequences don't throw off
    # PadRight's width calculation.
    $namePadded = $cmd.Command.PadRight($nameWidth)
    $text = Format-Hyperlink (ConvertTo-FileUri $cmd.LinkTarget) (Format-ColorText '96' $namePadded)
    $visible = $namePadded.Length

    if ($cmd.Config) {
        $descPadded = $cmd.Description.PadRight($descWidth)
        $configText = "-> $($cmd.Config)"
        $text += $descPadded + (Format-ColorText '90' $configText)
        $visible += $descPadded.Length + $configText.Length
    } else {
        $text += $cmd.Description
        $visible += $cmd.Description.Length
    }
    [PSCustomObject]@{ Text = $text; Visible = $visible }
}

if (-not $Border) {
    $rows | ForEach-Object { Write-Host $_.Text }
    return
}

$inner = ($rows | Measure-Object -Maximum -Property Visible).Maximum
$horizontal = [string][char]0x2500 * ($inner + 2)
$vertical = [char]0x2502
Write-Host "$([char]0x256D)$horizontal$([char]0x256E)"
foreach ($row in $rows) {
    Write-Host "$vertical $($row.Text)$(' ' * ($inner - $row.Visible)) $vertical"
}
Write-Host "$([char]0x2570)$horizontal$([char]0x256F)"
