# DESCRIPTION: List all available commands and what they do

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

foreach ($cmd in $commands) {
    # Pad the plain name to column width first, then wrap the padded (already-aligned)
    # string in the link/color codes, so the invisible escape sequences don't throw off
    # PadRight's width calculation.
    $namePadded = $cmd.Command.PadRight($nameWidth)
    $nameLink = Format-Hyperlink (ConvertTo-FileUri $cmd.LinkTarget) (Format-ColorText '96' $namePadded)
    Write-Host $nameLink -NoNewline

    if ($cmd.Config) {
        Write-Host $cmd.Description.PadRight($descWidth) -NoNewline
        Write-Host "-> $($cmd.Config)" -ForegroundColor DarkGray
    } else {
        Write-Host $cmd.Description
    }
}
