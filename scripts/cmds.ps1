# DESCRIPTION: List all available commands and what they do

$cmdsRoot = Split-Path $PSScriptRoot -Parent
$scriptsDir = $PSScriptRoot

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
        [PSCustomObject]@{ Command = $name; Description = $description }
    }

$nameWidth = ($commands.Command | Measure-Object -Maximum -Property Length).Maximum + 2

foreach ($cmd in $commands) {
    Write-Host $cmd.Command.PadRight($nameWidth) -ForegroundColor Cyan -NoNewline
    Write-Host $cmd.Description
}
