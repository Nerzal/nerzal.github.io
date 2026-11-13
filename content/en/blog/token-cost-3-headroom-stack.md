---
draft: true
title: "Token Cost Minimization in Agentic AI — Part 3: Headroom, Auto-Updates and the Combined Setup"
seo_title: "Headroom Setup for Claude Code, Codex and Cursor"
date: 2026-12-02T08:00:00+01:00
tags:
  [
    "ai",
    "claude-code",
    "headroom",
    "llm-proxy",
    "token-optimization",
    "agentic-ai",
    "automation",
    "powershell",
  ]
categories: ["AI"]
series: ["Token Cost Minimization in Agentic AI"]
description: "Headroom compresses tool output before your coding agent reads it. Local and global setup for Claude Code, Codex and Cursor, scheduled updates with desktop notifications, and how to stack all four tools."
images: ["img/token-cost-agentic-ai.png"]
featured_image: "img/token-cost-agentic-ai.png"
toc: true
---

> **Series: Token Cost Minimization in Agentic AI.** [Part 1: where the tokens go, Caveman and Ponytail](/blog/token-cost-1-caveman-ponytail/) · [Part 2: code-review-graph and hooks](/blog/token-cost-2-code-review-graph/) · Part 3: Headroom, auto-updates and the combined setup (you are here)

[Part 1](/blog/token-cost-1-caveman-ponytail/) shrank what the agent writes, [Part 2](/blog/token-cost-2-code-review-graph/) what it reads from source code. What is left is the noisy rest: 400 lines of test output, a 2 MB JSON API response, a log dump with one interesting line in it. Those tool results enter the context once and are then re-sent with every following turn.

[Headroom](https://github.com/headroomlabs-ai/headroom) (Apache-2.0, `headroom-ai` on PyPI, current release **v0.44.0** from 2026-11-10) targets exactly that. This part covers how it works, how to set it up for one project or for every agent on the machine, how to keep it updated automatically with desktop notifications, and finally how all four tools of this series fit together.

## How Headroom saves tokens

Headroom is a **local proxy** between your agent and the model API. The agent sends its request to `http://127.0.0.1:8787` instead of directly to Anthropic or OpenAI. Headroom compresses the request and forwards it:

- **ContentRouter** detects the content type of each block and picks a compressor.
- **SmartCrusher** handles JSON. Instead of 500 near-identical array items, the model sees the structure, statistical outliers, error items and the first and last entries.
- **CodeCompressor** is AST-aware for Python, JS/TS, Go, Rust, Java, C/C++, C# and PHP. By default, recent code and code the user asked to analyse pass through untouched.
- **Kompress-v2-base** is a small model, trained on agent traces, that compresses prose and logs.
- **Live-zone compression:** only *new* content (the latest tool output) is compressed. The frozen prefix of the conversation stays byte-identical, so the provider's [prompt cache](https://docs.claude.com/en/docs/build-with-claude/prompt-caching) keeps hitting. **CacheAligner** flags volatile content that would break that prefix.
- **CCR (reversible compression):** originals are stored locally. If the model needs the full text, it calls the `headroom_retrieve` tool and gets it back. That is the safety net for "the compressor dropped the one line that mattered".

Optional extras: an output shaper that appends a "be terse" note to the end of the system prompt (`HEADROOM_OUTPUT_SHAPER=1`, off by default), cross-agent memory, and `headroom learn`, which mines failed sessions and writes corrections into `CLAUDE.local.md`.

Headroom also works as a Python/TypeScript library (`compress(messages)`) for your own LLM applications and as an MCP server; this article focuses on coding agents.

## Installation

Headroom needs Python 3.11+. As with code-review-graph in [Part 2](/blog/token-cost-2-code-review-graph/#installation), [uv](https://docs.astral.sh/uv/) is the cleanest way:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
uv tool install --python 3.13 "headroom-ai[all]"
uv tool update-shell      # if ~/.local/bin is not on PATH yet
headroom --version
headroom doctor           # health check, confirms routing works
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
uv tool install --python 3.13 "headroom-ai[all]"
uv tool update-shell      # if the uv tool directory is not on PATH yet
headroom --version
headroom doctor           # health check, confirms routing works
```

{{< /os-tab >}}
{{< /os-tabs >}}

`[all]` contains the CLI and proxy without PyTorch. The ML text compressor needs the `[ml]` extra, which pulls PyTorch and, on Linux, possibly CUDA packages. Prebuilt wheels exist for Windows, Linux (x86_64, aarch64) and macOS. On Intel Macs without a prebuilt ONNX Runtime, the README documents a Homebrew workaround.

The npm package `headroom-ai` is only the TypeScript SDK; the `headroom` command comes from PyPI.

## Local setup: one session or one project

### One session: `headroom wrap`

The simplest mode starts a proxy, launches the agent routed through it, and stops the proxy when the agent exits:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
headroom wrap claude
headroom wrap codex
headroom wrap claude --memory    # plus persistent cross-session memory
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
headroom wrap claude
headroom wrap codex
headroom wrap claude --memory    # plus persistent cross-session memory
```

{{< /os-tab >}}
{{< /os-tabs >}}

Nothing is changed permanently, which makes it the right mode to try Headroom on one task and compare the bill with a normal session.

### One project: `.claude/settings.local.json`

To route only one repository through Headroom, put the base URL into the project's personal Claude Code settings. `headroom wrap claude --project-settings` writes this file for you; by hand it looks like this:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787",
    "ENABLE_TOOL_SEARCH": "true"
  }
}
```

[Claude Code settings](https://code.claude.com/docs/en/settings) are layered: `.claude/settings.local.json` (personal, per project, not committed) beats `.claude/settings.json` (team, per project) beats `~/.claude/settings.json` (user-wide). So this file affects only this repository and only you. A proxy must be running for it, either a `headroom proxy --port 8787` in a terminal or the persistent service from the next section.

**Why `ENABLE_TOOL_SEARCH`?** According to the help text of `headroom wrap claude --tool-search` ([issue #746](https://github.com/headroomlabs-ai/headroom/issues/746)), a custom `ANTHROPIC_BASE_URL` makes Claude Code load every tool schema eagerly instead of on demand. With many MCP servers that inflates every request and eats part of the savings. Setting the variable keeps on-demand loading.

Undo with `headroom unwrap claude`, or delete the file.

## Global setup: every agent on the machine

For daily use you want a proxy that survives reboots and every agent configured to use it. Headroom calls this a persistent install:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# turnkey: picks Docker, a native service or a scheduled watchdog for you
headroom deploy

# or explicitly: background service, configure every detected agent, user scope
headroom install apply --preset persistent-service --providers auto --scope user

# or only selected agents
headroom install apply --preset persistent-task --providers manual --target claude --target codex

headroom install status
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# turnkey: picks Docker, a native service or a scheduled watchdog for you
headroom deploy

# or explicitly: background service, configure every detected agent, user scope
headroom install apply --preset persistent-service --providers auto --scope user

# or only selected agents
headroom install apply --preset persistent-task --providers manual --target claude --target codex

headroom install status
```

{{< /os-tab >}}
{{< /os-tabs >}}

The presets: `persistent-service` uses a native background service, `persistent-task` a scheduled watchdog (launchd, Task Scheduler or cron), `persistent-docker` a container with a restart policy. `headroom install stop|start|restart|remove` manage it; `remove` reverts the configuration changes.

What gets configured per agent, according to the [persistent installs guide](https://docs.headroomlabs.ai/docs/persistent-installs):

| Agent | How Headroom routes it |
| --- | --- |
| Claude Code | `env` block in `~/.claude/settings.json` |
| Codex | managed block in `~/.codex/config.toml` |
| OpenCode | managed provider block in `~/.config/opencode/opencode.json` |
| Copilot CLI, Aider, Goose, Cline, Continue, OpenHands … | `headroom wrap <agent>`; env-driven tools via `--scope user` or `--scope system` |
| VS Code (Claude Code extension, Copilot) | `headroom wrap vscode-claude`, `headroom wrap vscode` |
| Cursor | manual: `headroom wrap cursor` starts the proxy and prints the base URLs to paste into Cursor's settings |
| Gemini CLI | **no documented setup.** The proxy has a Gemini `generateContent` route and `headroom learn` supports Gemini, but there is no `headroom wrap gemini` and no Gemini CLI guide as of v0.44.0 |
| Any MCP client | `headroom mcp install` adds the compress/retrieve/stats tools |

Check it with `headroom install status`, the `/health` endpoint, and `headroom dashboard` for live savings. `headroom savings` reports what it saved on your real traffic.

**The one big risk of the global setup:** once `ANTHROPIC_BASE_URL` points at `127.0.0.1:8787` in your user settings, *every* Claude Code session depends on that proxy. If it is down, the agent cannot reach the model at all. That is why the next section adds a health check with a desktop notification.

**Telemetry:** the README states that an anonymous beacon (compression ratios, model IDs, OS; no prompts or code) is **on by default**; the configuration page lists `HEADROOM_TELEMETRY` as off by default. The docs disagree, so set `HEADROOM_BEACON=off` explicitly if you care.

## Keeping Headroom up to date automatically

Headroom ships often (four releases between 2026-10-26 and 2026-11-10). Its built-in support:

- `headroom update --check` reports the latest release without upgrading.
- `headroom update --yes` detects how Headroom was installed (pip, pipx, uv tool) and runs the matching upgrade without asking.
- The proxy prints a one-line "update available" notice at startup, at most once a day. `HEADROOM_UPDATE_CHECK=off` disables it.

There is **no built-in auto-updater and no desktop notification**, so we build both. I read the source of the `update` command ([`headroom/cli/update.py`](https://github.com/headroomlabs-ai/headroom/blob/main/headroom/cli/update.py)) to get the behaviour right:

- `--check` exits with code 0 both when you are up to date and when an update exists. It prints `Update available: <old> → <new>` in the second case. Only an unreachable PyPI is a non-zero exit.
- For Docker, editable or system-Python installs it does not upgrade; it prints guidance and still exits 0. So the script compares versions before and after.
- A failed upgrade exits non-zero.
- The running proxy must be restarted to use the new version.

### The update script

The script checks for an update, applies it with a stop and start of the persistent proxy, checks that the proxy answers, and sends a desktop notification for anything noteworthy. Set `AUTO_APPLY=0` if you only want to be told about updates.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

Save as `~/.local/bin/headroom-update.sh` and run `chmod +x ~/.local/bin/headroom-update.sh`:

```bash
#!/usr/bin/env bash
# Checks for Headroom updates, applies them, verifies the proxy, notifies on the desktop.
set -u
AUTO_APPLY="${AUTO_APPLY:-1}"
HEALTH_URL="http://127.0.0.1:8787/health"

notify() { # $1 = message, $2 = urgency (normal|critical)
  echo "headroom-update: $1"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name=Headroom --urgency="${2:-normal}" "Headroom" "$1"
  elif command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$1\" with title \"Headroom\""
  fi
}

if ! check_output=$(headroom update --check 2>&1); then
  notify "Update check failed: $(printf '%s' "$check_output" | tail -n 1)" critical
  exit 1
fi

if printf '%s' "$check_output" | grep -q "Update available"; then
  if [ "$AUTO_APPLY" != "1" ]; then
    notify "$(printf '%s' "$check_output" | grep "Update available")"
  else
    before=$(headroom --version 2>&1)
    headroom install stop >/dev/null 2>&1
    if headroom update --yes; then
      after=$(headroom --version 2>&1)
      if [ "$before" = "$after" ]; then
        notify "Update available but not applied automatically. Run: headroom update" critical
      else
        notify "Updated: $after"
      fi
    else
      notify "Update failed. Run 'headroom update' manually." critical
    fi
    headroom install start >/dev/null 2>&1
  fi
fi

sleep 5
if ! curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null; then
  notify "Proxy is not answering on $HEALTH_URL. Agents using it cannot reach the model." critical
  exit 1
fi
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

Install the [BurntToast](https://github.com/Windos/BurntToast) module once (`Install-Module BurntToast -Scope CurrentUser`), then save as `$HOME\bin\headroom-update.ps1`:

```powershell
# Checks for Headroom updates, applies them, verifies the proxy, notifies on the desktop.
$autoApply = if ($env:AUTO_APPLY) { $env:AUTO_APPLY } else { '1' }
$healthUrl = 'http://127.0.0.1:8787/health'

function Send-HeadroomNotice([string]$Message) {
    Write-Output "headroom-update: $Message"
    if (Get-Module -ListAvailable -Name BurntToast) {
        New-BurntToastNotification -Text 'Headroom', $Message
    }
}

$checkOutput = headroom update --check 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Send-HeadroomNotice "Update check failed: $($checkOutput.Trim())"
    exit 1
}

if ($checkOutput -match 'Update available.*') {
    $availableLine = $Matches[0]
    if ($autoApply -ne '1') {
        Send-HeadroomNotice $availableLine
    }
    else {
        $before = headroom --version 2>&1 | Out-String
        headroom install stop | Out-Null
        headroom update --yes
        $updateExitCode = $LASTEXITCODE
        headroom install start | Out-Null
        $after = headroom --version 2>&1 | Out-String
        if ($updateExitCode -ne 0) {
            Send-HeadroomNotice "Update failed. Run 'headroom update' manually."
        }
        elseif ($before -eq $after) {
            Send-HeadroomNotice 'Update available but not applied automatically. Run: headroom update'
        }
        else {
            Send-HeadroomNotice "Updated: $($after.Trim())"
        }
    }
}

Start-Sleep -Seconds 5
try {
    Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5 | Out-Null
}
catch {
    Send-HeadroomNotice "Proxy is not answering on $healthUrl. Agents using it cannot reach the model."
    exit 1
}
```

{{< /os-tab >}}
{{< /os-tabs >}}

The `install stop/start` calls assume the persistent install from the previous section. If you only use `headroom wrap`, remove them; the next wrapped session starts the new version. On Windows, a running proxy holds a lock on Headroom's native module, which is one more reason to stop it first. If you installed with plain `pip` on Windows, `headroom update` hands the upgrade to a child process and returns before it finishes, so the version comparison reports "not applied"; a `uv tool` install avoids that.

The PowerShell script runs in PowerShell 7 and in Windows PowerShell 5.1. If you are still on 5.1, [here is why and how to upgrade](/blog/upgrade-powershell-7/).

### Scheduling it

{{< os-tabs >}}
{{< os-tab "Linux (systemd)" >}}

A [systemd user timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html) runs in your user session, which is what desktop notifications need. Create `~/.config/systemd/user/headroom-update.service`:

```ini
[Unit]
Description=Check and apply Headroom updates

[Service]
Type=oneshot
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=%h/.local/bin/headroom-update.sh
```

and `~/.config/systemd/user/headroom-update.timer`:

```ini
[Unit]
Description=Daily Headroom update check

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

Enable it and test it once:

```bash
systemctl --user daemon-reload
systemctl --user enable --now headroom-update.timer
systemctl --user start headroom-update.service   # run now
journalctl --user -u headroom-update.service -n 20
```

`Persistent=true` catches up on a run missed while the machine was off.

{{< /os-tab >}}
{{< os-tab "macOS (launchd)" >}}

A [launchd](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) LaunchAgent runs in your GUI session. launchd does not expand `~`, so the heredoc below fills in your home directory:

```bash
cat > ~/Library/LaunchAgents/local.headroom-update.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.headroom-update</string>
  <key>ProgramArguments</key>
  <array><string>$HOME/.local/bin/headroom-update.sh</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>/tmp/headroom-update.log</string>
  <key>StandardErrorPath</key><string>/tmp/headroom-update.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/local.headroom-update.plist
launchctl kickstart "gui/$(id -u)/local.headroom-update"   # run now
```

If the Mac sleeps at 09:00, launchd runs the job when it wakes up.

{{< /os-tab >}}
{{< os-tab "Windows (Task Scheduler)" >}}

Register a daily task for the current user with the [ScheduledTasks](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask) module:

```powershell
$script = Join-Path $HOME 'bin\headroom-update.ps1'
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Daily -At '09:00'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
Register-ScheduledTask -TaskName 'Headroom update' -Action $action -Trigger $trigger -Settings $settings

Start-ScheduledTask -TaskName 'Headroom update'   # run now
```

Use `powershell.exe` instead of `pwsh.exe` if PowerShell 7 is not installed. `-StartWhenAvailable` runs a missed task after the machine was off.

{{< /os-tab >}}
{{< /os-tabs >}}

If you prefer cron on Linux: `0 9 * * * $HOME/.local/bin/headroom-update.sh` works for the update itself, but see below for notifications.

### Notifications: what works where

Desktop notifications from a background job are possible on all three systems, with conditions. Be aware of them, otherwise you get silent failures, which is exactly what the job is meant to prevent.

| System | Mechanism | Works when | Does not work |
| --- | --- | --- | --- |
| Linux | `notify-send` ([libnotify](https://gitlab.gnome.org/GNOME/libnotify)) | systemd **user** timer in a desktop session; GNOME and KDE export the session bus to the user manager | from cron (no `DBUS_SESSION_BUS_ADDRESS`), on headless servers, before login |
| macOS | `osascript -e 'display notification …'` | LaunchAgent in the logged-in GUI session; appears as coming from *Script Editor*, which must be allowed under System Settings › Notifications | LaunchDaemons (system context), before login |
| Windows | [BurntToast](https://github.com/Windos/BurntToast) toast | task runs as the logged-on user (the default above) | task set to "run whether user is logged on or not", which runs in a session without a desktop |

On a headless Linux server there is no popup to show. There, rely on the exit code: `systemctl --user status headroom-update` and the journal show failures, and an `OnFailure=` unit or your existing monitoring can forward them by mail or chat.

## The numbers

{{< diagram src="token-cost-headroom-scenarios.svg" caption="Vendor-measured on four synthetic scenarios built from real MCP output formats (seeded, offline, provider tokenizer). Savings: 21 % on code search, 57 % on SRE incident debugging, 42 % on codebase exploration, 30 % on GitHub issue triage." >}}

| Scenario | Before | After | Saved |
| --- | --- | --- | --- |
| Code search (100 results) | 17,199 | 13,597 | 21 % |
| SRE incident debugging | 55,957 | 24,340 | 57 % |
| Codebase exploration | 58,801 | 33,895 | 42 % |
| GitHub issue triage | 46,067 | 32,429 | 30 % |

*Source: [Headroom README](https://github.com/headroomlabs-ai/headroom), reproducible with `benchmarks/index_proof_table.py --seed 20260902`.*

These are compression ratios on prepared payloads, not whole agent sessions. Repetitive JSON arrays and log lines exceed 90 % in the latency benchmark; prose and dense output compress very little. Compression adds 0.21 ms (p50) on a 10K-token JSON result.

Accuracy, also vendor-measured with N = 100 per benchmark: GSM8K 0.870 → 0.870, TruthfulQA 0.530 → 0.560 (within the confidence interval, so "no detectable difference"), SQuAD v2 97 % at 19 % compression, BFCL tool calling 97 % at 32 % compression.

Headroom's own [limitations page](https://docs.headroomlabs.ai/docs/limitations) is refreshingly direct: the figures are "one-off, synthetic measurements, not a published benchmark", and agentic conversations are "not independently measured".

The only third-party number I found comes from a competitor: Caveman's README reports that on its own six-file test suite, Headroom answered 15 of 18 questions correctly with 6.7 % fewer tokens, while Caveman's own engine got 18 of 18 with 33.2 % fewer. A vendor measuring a competing product on its own benchmark is not independent, so treat it as a data point, not a verdict. I found **no independent benchmark** of Headroom.

## Costs and when Headroom does not help

- **Source code mostly passes through.** By default, recent code and code under analysis are protected. In a pure coding session with few logs, the savings are small. That is the domain of code-review-graph.
- **Short exchanges and prose.** Below a minimum size, blocks come back byte-identical, and on small payloads the overhead can exceed the savings.
- **A new single point of failure.** In the global setup, a dead proxy means a dead agent. The health check above mitigates it.
- **Lossy by design.** Item selection is heuristic. CCR can bring originals back, but only if the model notices it needs them.
- **Another component with a supply chain.** A Python package with native code, an ML model download from Hugging Face, ONNX Runtime, frequent releases. In corporate networks with TLS inspection, the README has a whole section on certificates.
- **Telemetry on by default** (see above).

## Combining the tools

The four tools act on different parts of a request, which is why they stack:

{{< diagram src="token-cost-where-tools-act.svg" caption="Caveman voice and Ponytail shrink the output, code-review-graph shrinks source-code reads, Headroom compresses other tool output, and caveman-compress shrinks memory files. Rules and tool schemas are the price on the input side." >}}

| Layer | Tool | Overlaps with | Recommendation |
| --- | --- | --- | --- |
| Code the agent writes | Ponytail | Caveman voice (both demand short replies) | Always on |
| Reply prose | Caveman voice | Ponytail, Headroom output shaper | Optional; measure first |
| Memory files | `caveman-compress` | — | Once, for large `CLAUDE.md` files |
| Source code the agent reads | code-review-graph | Headroom `--code-graph` (its own watcher) | On in code repositories, with hooks |
| Logs, JSON, test output | Headroom | Caveman v4 "Read less" engine | Pick **one** of the two |

Things not to stack:

- **Two input compressors.** Caveman v4's local engine and Headroom both compress tool output. Running both means two proxies, two failure points and compressing already-compressed content. Choose one.
- **Two code graphs.** `headroom wrap claude --code-graph` enables Headroom's own code-graph watcher. If you use code-review-graph, leave that flag off.
- **Three "be terse" instructions.** Ponytail, the caveman voice and `HEADROOM_OUTPUT_SHAPER=1` all push for short replies. One is enough; each one costs input on every request.

### My recommended setup

1. **Ponytail as a Claude Code plugin.** It has the best-documented benchmark, an independent test with a positive (if smaller) result, and its side effect, less code, is good regardless of the bill.
2. **code-review-graph in every code repository**, with the Claude Code and git hooks from [Part 2](/blog/token-cost-2-code-review-graph/#where-to-integrate-it-hooks-that-keep-the-graph-fresh). Skip it in content repositories like this blog.
3. **Headroom globally, if your sessions are log- and JSON-heavy** (ops, debugging, API work): persistent install, `ENABLE_TOOL_SEARCH=true`, the update job with health notifications. For pure feature work, try `headroom wrap claude` on a few tasks first and keep it only if `headroom savings` and your provider bill agree.
4. **`/caveman-compress`** once for a large `CLAUDE.md`, with the original kept in version control. The caveman voice only if replies are still too long for your taste.

### Measure, don't believe

Every number in this series that came from a vendor was larger than the independent ones. The only measurement that matters is your bill for your work. Run the same task with and without a tool, compare the provider-reported usage (the [Anthropic Console](https://console.anthropic.com/) or your plan's usage page), and use the tools' own counters only as a hint: Ponytail's band, `/caveman-stats`, `headroom savings` and code-review-graph's `context_savings` all estimate against a counterfactual they never observed.

## Sources

- Headroom: [README](https://github.com/headroomlabs-ai/headroom), [docs](https://docs.headroomlabs.ai/docs), [persistent installs](https://docs.headroomlabs.ai/docs/persistent-installs), [configuration](https://docs.headroomlabs.ai/docs/configuration), [limitations](https://docs.headroomlabs.ai/docs/limitations), [`update.py`](https://github.com/headroomlabs-ai/headroom/blob/main/headroom/cli/update.py)
- Claude Code: [settings](https://code.claude.com/docs/en/settings), [hooks](https://code.claude.com/docs/en/hooks)
- systemd: [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html); Apple: [launchd jobs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html); Microsoft: [Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask)
- Notifications: [libnotify](https://gitlab.gnome.org/GNOME/libnotify), [BurntToast](https://github.com/Windos/BurntToast)
- Caveman's comparison run: [Caveman README, "Read less"](https://github.com/JuliusBrussee/caveman#read-less-332-fewer-input-tokens)
