---
description: Poll a natural-language condition against a URL and show a windowed Chrome notification (with a chime) when it becomes true
argument-hint: "<condition>" "<url>" "<message>" ["<interval, default 5m>"]
---

You are implementing the `/cmds:notifywhen` command. Arguments (positional):
- `$1` = condition, natural language (e.g. "has more than 1 approval", "after 8pm")
- `$2` = url the condition is about
- `$3` = message to show in the notification window
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

4. **Pick a local link-relay port** (so clicking the link opens the URL in the user's actual OS default browser, not just inside this Chrome window):

   ```powershell
   $linkPort = Get-Random -Minimum 20000 -Maximum 40000
   ```

5. **Write `notify.html` into `$runDir`.** Static HTML/CSS/JS only, no external requests, no external libraries, no third-party logos or trademarked assets (use the plain inline SVG sparkle icon shown below, not any company's actual logo). It must render the literal message text, the sparkle favicon/icon, and a clickable link whose visible text is the real URL but whose `href` is the relative path `/open`. The link click must be intercepted with JavaScript (`preventDefault` + `fetch('/open')`), not a normal navigation — a plain navigation would replace the whole page with the watcher's response; the fetch approach keeps the original message/link/icon on screen and only adds a small "opened" status line alongside it once the fetch resolves. `/open` is a same-origin request that lands back on the watcher (which serves this page itself from a loopback listener on `linkPort`); the watcher forwards it to `Start-Process` on the real URL, which Windows then hands to whatever browser is set as the OS default. The link must NOT be an absolute `http://127.0.0.1:.../` URL and the page must NOT be opened via a `file://` path — Chrome treats `file:` as a unique, isolated origin and blocks/hangs navigation from a `file:` page to `http://127.0.0.1`, which is why the page has to be served same-origin instead. Also mention that closing the window (the window's own close button, or Alt+F4) dismisses the notification, and play a short two-tone chime on load using the browser's built-in Web Audio API (no MIDI device, no external library — just `AudioContext`/`OscillatorNode`). Example to adapt (substitute the real message and url):

   ```html
   <!doctype html>
   <html>
   <head>
   <meta charset="utf-8">
   <title>notifywhen</title>
   <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M12 2 L14 10 L22 12 L14 14 L12 22 L10 14 L2 12 L10 10 Z' fill='%238ab4f8'/%3E%3C/svg%3E">
   <style>
     body { display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; font-family: system-ui, sans-serif; background: #1e1e2e; color: #f5f5f5; text-align: center; }
     .card { max-width: 32rem; padding: 2rem; }
     .icon { margin-bottom: 0.5rem; }
     h1 { font-size: 1.75rem; margin-bottom: 1rem; }
     a { color: #8ab4f8; font-size: 1.1rem; word-break: break-all; }
     p.hint { margin-top: 2rem; opacity: 0.6; font-size: 0.9rem; }
     p.status { margin-top: 1rem; color: #a6e3a1; font-size: 0.95rem; }
   </style>
   </head>
   <body>
     <div class="card">
       <svg class="icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="40" height="40">
         <path d="M12 2 L14 10 L22 12 L14 14 L12 22 L10 14 L2 12 L10 10 Z" fill="#8ab4f8"/>
       </svg>
       <h1>MESSAGE_TEXT_HERE</h1>
       <a href="/open" id="open-link">URL_HERE</a>
       <p class="status" id="status-msg" hidden></p>
       <p class="hint">Close this window when you're done.</p>
     </div>
     <script>
       try {
         const ctx = new (window.AudioContext || window.webkitAudioContext)();
         const now = ctx.currentTime;
         [523.25, 783.99].forEach((freq, i) => {
           const osc = ctx.createOscillator();
           const gain = ctx.createGain();
           osc.type = 'sine';
           osc.frequency.value = freq;
           const start = now + i * 0.15;
           gain.gain.setValueAtTime(0, start);
           gain.gain.linearRampToValueAtTime(0.3, start + 0.02);
           gain.gain.exponentialRampToValueAtTime(0.001, start + 0.6);
           osc.connect(gain).connect(ctx.destination);
           osc.start(start);
           osc.stop(start + 0.6);
         });
       } catch (e) {
         // Autoplay/audio unsupported — notification still shows visually.
       }
       document.getElementById('open-link').addEventListener('click', function (e) {
         e.preventDefault();
         var statusEl = document.getElementById('status-msg');
         fetch('/open').then(function () {
           statusEl.textContent = 'Opened in your default browser. You may now close this window.';
           statusEl.hidden = false;
         }).catch(function () {
           statusEl.textContent = 'Could not reach the watcher to open the link.';
           statusEl.hidden = false;
         });
       });
     </script>
   </body>
   </html>
   ```

6. **Write `meta.json` into `$runDir`:**

   ```powershell
   $meta = @{
     id = $id
     condition = '<the condition text>'
     url = '<the url>'
     message = '<the message text>'
     intervalSeconds = <parsed interval seconds>
     linkPort = $linkPort
     startedAt = (Get-Date).ToString('o')
     status = 'polling'
     watcherPid = $null
     chromePid = $null
   }
   $meta | ConvertTo-Json | Set-Content -Path (Join-Path $runDir 'meta.json')
   ```

7. **Launch the watcher engine detached and hidden**, then record its PID back into `meta.json`:

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

8. **Report back to the user**: the run id, the watcher PID, the log file path (`logs\notifywhen-<id>.log`), and remind them they can check status with `/cmds:notifywhen-list` or cancel with `/cmds:notifywhen-stop "<id>"`.

Note: the watcher engine (`scripts\notifywhen-watch.ps1`) launches the notification as a minimal Chrome app-mode window (`--app`), not a fullscreen kiosk — a normal, resizable, movable popup window with no address bar or tabs. It serves `notify.html` itself from a loopback HTTP listener on `linkPort` (not a `file://` path) for the duration of that window, so clicking the `/open` link reaches the watcher and opens the real URL in the user's actual default browser. If the listener fails to start (e.g. port in use), the watcher falls back to opening `notify.html` via `file://` so the message still displays, but the link won't work in that fallback case.
