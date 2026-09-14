---
description: Poll a natural-language condition against a URL and show a kiosk Chrome notification when it becomes true
argument-hint: "<condition>" "<url>" "<message>" ["<interval, default 5m>"]
---

You are implementing the `/cmds:notifywhen` command. Arguments (positional):
- `$1` = condition, natural language (e.g. "has more than 1 approval", "after 8pm")
- `$2` = url the condition is about
- `$3` = message to show in the kiosk notification
- `$4` = optional interval, e.g. `30s`, `5m`, `1h` (default `5m` if omitted)

Do the following using the PowerShell tool, in order:

1. **Generate a run id and run directory.**

   ```powershell
   $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
   $runDir = Join-Path $env:TEMP "cmds-notifywhen\$id"
   New-Item -ItemType Directory -Path $runDir -Force | Out-Null
   ```

2. **Parse the interval** (default 300 seconds if `$4` is absent). Accept `<number>s`, `<number>m`, `<number>h` suffixes and convert to seconds.

3. **Write `check.ps1` into `$runDir`, tailored to the condition text and URL.** The script's only contract: `exit 0` when true, non-zero otherwise, and never throw uncaught (catch network errors and treat as "not yet true"). Pick the closest pattern:

   - **GitHub PR/issue condition** (url matches `github.com/.../pull/N` or `.../issues/N`, and condition mentions approvals/reviews/merged/checks) — use the `gh` CLI, e.g. for an approval-count condition:

     ```powershell
     $prUrl = 'https://github.com/OWNER/REPO/pull/N'
     $requiredApprovals = 1  # "more than 1 approval" means > 1, i.e. count must exceed this
     try {
       $reviews = gh pr view $prUrl --json reviews | ConvertFrom-Json
       $approvalCount = ($reviews.reviews | Where-Object { $_.state -eq 'APPROVED' }).Count
       if ($approvalCount -gt $requiredApprovals) { exit 0 } else { exit 1 }
     } catch {
       exit 1
     }
     ```

     Adapt the field/condition (`--json reviews` for approvals, `gh pr checks` for CI status, `gh pr view --json state` for merged) to what the condition text actually asks for, filling in the real URL and threshold — never leave placeholder values in the generated script.

   - **Time/date condition** (e.g. "after 8pm", "on 2026-10-01") — no network call needed:

     ```powershell
     $target = Get-Date -Hour 20 -Minute 0 -Second 0
     if ((Get-Date) -ge $target) { exit 0 } else { exit 1 }
     ```

     Compute `$target` from the actual condition text (specific date, specific time, etc).

   - **Anything else** — generic fallback that fetches the URL and text-matches key terms extracted from the condition:

     ```powershell
     $url = 'https://example.com/status'
     $searchText = 'Completed'
     try {
       $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
       if ($resp.Content -match [regex]::Escape($searchText)) { exit 0 } else { exit 1 }
     } catch {
       exit 1
     }
     ```

4. **Write `notify.html` into `$runDir`.** Static HTML/CSS only, no external requests. It must render the literal message text and the URL as a clickable link, and mention that Alt+F4 closes the kiosk window. Example to adapt (substitute the real message and url):

   ```html
   <!doctype html>
   <html>
   <head>
   <meta charset="utf-8">
   <title>notifywhen</title>
   <style>
     body { display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; font-family: system-ui, sans-serif; background: #1e1e2e; color: #f5f5f5; text-align: center; }
     .card { max-width: 32rem; padding: 2rem; }
     h1 { font-size: 1.75rem; margin-bottom: 1rem; }
     a { color: #8ab4f8; font-size: 1.1rem; word-break: break-all; }
     p.hint { margin-top: 2rem; opacity: 0.6; font-size: 0.9rem; }
   </style>
   </head>
   <body>
     <div class="card">
       <h1>MESSAGE_TEXT_HERE</h1>
       <a href="URL_HERE">URL_HERE</a>
       <p class="hint">Press Alt+F4 to close this window.</p>
     </div>
   </body>
   </html>
   ```

5. **Write `meta.json` into `$runDir`:**

   ```powershell
   $meta = @{
     id = $id
     condition = '<the condition text>'
     url = '<the url>'
     message = '<the message text>'
     intervalSeconds = <parsed interval seconds>
     startedAt = (Get-Date).ToString('o')
     status = 'polling'
     watcherPid = $null
     chromePid = $null
   }
   $meta | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
   ```

6. **Launch the watcher engine detached and hidden**, then record its PID back into `meta.json`:

   ```powershell
   $watcherProc = Start-Process pwsh -ArgumentList @(
     '-NoProfile', '-File', (Join-Path (Get-Location) 'scripts\notifywhen-watch.ps1'),
     '-RunDir', $runDir,
     '-IntervalSeconds', $intervalSeconds
   ) -WindowStyle Hidden -PassThru

   $meta = Get-Content -Raw (Join-Path $runDir 'meta.json') | ConvertFrom-Json
   $meta.watcherPid = $watcherProc.Id
   $meta | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
   ```

7. **Report back to the user**: the run id, the watcher PID, the log file path (`logs\notifywhen-<id>.log`), and remind them they can check status with `/cmds:notifywhen-list` or cancel with `/cmds:notifywhen-stop "<id>"`.
