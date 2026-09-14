---
description: List active notifywhen watchers
---

Run this with the PowerShell tool and show the resulting table (or "No active notifywhen watchers.") to the user as your response:

```powershell
$runRoot = Join-Path $env:TEMP 'cmds-notifywhen'
$rows = @()
if (Test-Path $runRoot) {
    Get-ChildItem -Path $runRoot -Directory | ForEach-Object {
        $metaPath = Join-Path $_.FullName 'meta.json'
        if (Test-Path $metaPath) {
            $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json
            $pidToCheck = if ($meta.status -eq 'notified') { $meta.chromePid } else { $meta.watcherPid }
            $alive = $false
            if ($pidToCheck) {
                $proc = Get-Process -Id $pidToCheck -ErrorAction SilentlyContinue
                if ($proc) { $alive = $true }
            }
            if ($alive) {
                $rows += [pscustomobject]@{
                    Id = $meta.id
                    Status = $meta.status
                    Condition = $meta.condition
                    Url = $meta.url
                    Started = $meta.startedAt
                }
            } else {
                Remove-Item -Path $_.FullName -Recurse -Force
            }
        }
    }
}
if ($rows.Count -eq 0) {
    Write-Output 'No active notifywhen watchers.'
} else {
    $rows | Format-Table -AutoSize | Out-String | Write-Output
}
```
