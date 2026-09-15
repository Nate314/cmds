---
description: Stop one or all active notifywhen watchers
argument-hint: "<id-or-'all'>"
---

`$1` is the watcher id to stop, or the literal string `all` to stop every active watcher.

Run this with the PowerShell tool (substitute the real value of `$1` for the `$target` assignment below), and report to the user which watcher(s) were stopped, or that none were found:

```powershell
$target = '<value of $1>'
$runRoot = Join-Path $env:TEMP 'cmds-notifywhen'
if (-not (Test-Path $runRoot)) {
    Write-Output 'No active notifywhen watchers.'
} else {
    $dirs = if ($target -eq 'all') {
        Get-ChildItem -Path $runRoot -Directory
    } else {
        Get-ChildItem -Path $runRoot -Directory | Where-Object { $_.Name -eq $target }
    }
    if (-not $dirs) {
        Write-Output "No watcher found with id '$target'."
    } else {
        foreach ($dir in $dirs) {
            $metaPath = Join-Path $dir.FullName 'meta.json'
            if (Test-Path $metaPath) {
                $meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json
                foreach ($pidProp in @('chromePid', 'watcherPid')) {
                    $pidVal = $meta.$pidProp
                    if ($pidVal) {
                        $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
                        if ($proc) { Stop-Process -Id $pidVal -Force }
                    }
                }
            }
            Remove-Item -Path $dir.FullName -Recurse -Force
            Write-Output "Stopped watcher '$($dir.Name)'."
        }
    }
}
```
