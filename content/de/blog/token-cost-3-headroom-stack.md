---
draft: false
title: "Token-Kosten in agentischer KI senken — Teil 3: Headroom, Auto-Updates und das kombinierte Setup"
seo_title: "Headroom einrichten für Claude Code, Codex und Cursor"
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
description: "Headroom komprimiert Tool-Ausgaben, bevor dein Coding-Agent sie liest. Lokales und globales Setup für Claude Code, Codex und Cursor, geplante Updates mit Desktop-Benachrichtigungen und wie man alle vier Werkzeuge kombiniert."
images: ["img/token-cost-agentic-ai.png"]
featured_image: "img/token-cost-agentic-ai.png"
toc: true
---

> **Serie: Token-Kosten in agentischer KI senken.** [Teil 1: Wohin die Tokens fließen, Caveman und Ponytail](/de/blog/token-cost-1-caveman-ponytail/) · [Teil 2: code-review-graph und Hooks](/de/blog/token-cost-2-code-review-graph/) · Teil 3: Headroom, Auto-Updates und das kombinierte Setup (du bist hier)

[Teil 1](/de/blog/token-cost-1-caveman-ponytail/) hat verkleinert, was der Agent schreibt, [Teil 2](/de/blog/token-cost-2-code-review-graph/), was er an Quellcode liest. Übrig bleibt der laute Rest: 400 Zeilen Testausgabe, eine 2 MB große JSON-Antwort einer API, ein Log-Dump mit genau einer interessanten Zeile. Solche Tool-Ergebnisse kommen einmal in den Kontext und werden danach mit jedem weiteren Turn erneut gesendet.

[Headroom](https://github.com/headroomlabs-ai/headroom) (Apache-2.0, `headroom-ai` auf PyPI, aktuelles Release **v0.44.0** vom 10.11.2026) zielt genau darauf. Dieser Teil zeigt, wie es funktioniert, wie man es für ein Projekt oder für jeden Agenten auf dem Rechner einrichtet, wie es sich automatisch mit Desktop-Benachrichtigungen aktuell hält und wie die vier Werkzeuge dieser Serie zusammenpassen.

## Wie Headroom Tokens spart

Headroom ist ein **lokaler Proxy** zwischen deinem Agenten und der Modell-API. Der Agent schickt seinen Request an `http://127.0.0.1:8787` statt direkt an Anthropic oder OpenAI. Headroom komprimiert den Request und leitet ihn weiter:

- **ContentRouter** erkennt den Inhaltstyp jedes Blocks und wählt einen Kompressor.
- **SmartCrusher** kümmert sich um JSON. Statt 500 fast identischer Array-Einträge sieht das Modell die Struktur, statistische Ausreißer, Fehlereinträge sowie den ersten und letzten Eintrag.
- **CodeCompressor** arbeitet AST-basiert für Python, JS/TS, Go, Rust, Java, C/C++, C# und PHP. Standardmäßig bleiben aktueller Code und Code, den der Nutzer analysieren lassen will, unangetastet.
- **Kompress-v2-base** ist ein kleines, auf Agenten-Traces trainiertes Modell, das Fließtext und Logs komprimiert.
- **Live-Zone-Komprimierung:** Nur *neue* Inhalte (die letzte Tool-Ausgabe) werden komprimiert. Das eingefrorene Präfix des Gesprächs bleibt Byte für Byte gleich, damit der [Prompt-Cache](https://docs.claude.com/en/docs/build-with-claude/prompt-caching) des Anbieters weiter trifft. **CacheAligner** markiert flüchtige Inhalte, die dieses Präfix zerstören würden.
- **CCR (umkehrbare Komprimierung):** Originale werden lokal gespeichert. Braucht das Modell den vollständigen Text, ruft es das Tool `headroom_retrieve` auf und bekommt ihn zurück. Das ist das Sicherheitsnetz für „der Kompressor hat genau die eine wichtige Zeile entfernt“.

Optionale Extras: ein Output-Shaper, der einen „fass dich kurz“-Hinweis ans Ende des Systemprompts hängt (`HEADROOM_OUTPUT_SHAPER=1`, standardmäßig aus), agentenübergreifendes Memory und `headroom learn`, das fehlgeschlagene Sessions auswertet und Korrekturen in `CLAUDE.local.md` schreibt.

Headroom gibt es auch als Python-/TypeScript-Bibliothek (`compress(messages)`) für eigene LLM-Anwendungen und als MCP-Server; dieser Artikel konzentriert sich auf Coding-Agenten.

## Installation

Headroom braucht Python 3.11+. Wie bei code-review-graph in [Teil 2](/de/blog/token-cost-2-code-review-graph/#installation) ist [uv](https://docs.astral.sh/uv/) der sauberste Weg:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
uv tool install --python 3.13 "headroom-ai[all]"
uv tool update-shell      # falls ~/.local/bin noch nicht im PATH ist
headroom --version
headroom doctor           # Health-Check, bestätigt das Routing
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
uv tool install --python 3.13 "headroom-ai[all]"
uv tool update-shell      # falls das uv-Tool-Verzeichnis noch nicht im PATH ist
headroom --version
headroom doctor           # Health-Check, bestätigt das Routing
```

{{< /os-tab >}}
{{< /os-tabs >}}

`[all]` enthält CLI und Proxy ohne PyTorch. Der ML-Textkompressor braucht das Extra `[ml]`, das PyTorch und unter Linux eventuell CUDA-Pakete nachzieht. Fertige Wheels gibt es für Windows, Linux (x86_64, aarch64) und macOS. Für Intel-Macs ohne fertige ONNX Runtime dokumentiert das README einen Homebrew-Workaround.

Das npm-Paket `headroom-ai` ist nur das TypeScript-SDK; der Befehl `headroom` kommt von PyPI.

## Lokales Setup: eine Session oder ein Projekt

### Eine Session: `headroom wrap`

Der einfachste Modus startet einen Proxy, startet den Agenten darüber und beendet den Proxy, wenn der Agent beendet wird:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
headroom wrap claude
headroom wrap codex
headroom wrap claude --memory    # plus dauerhaftes Memory über Sessions hinweg
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
headroom wrap claude
headroom wrap codex
headroom wrap claude --memory    # plus dauerhaftes Memory über Sessions hinweg
```

{{< /os-tab >}}
{{< /os-tabs >}}

Dauerhaft wird nichts verändert. Damit ist das der richtige Modus, um Headroom an einer Aufgabe auszuprobieren und die Rechnung mit einer normalen Session zu vergleichen.

### Ein Projekt: `.claude/settings.local.json`

Um nur ein Repository über Headroom zu leiten, kommt die Basis-URL in die persönlichen Claude-Code-Einstellungen des Projekts. `headroom wrap claude --project-settings` schreibt diese Datei für dich; von Hand sieht sie so aus:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787",
    "ENABLE_TOOL_SEARCH": "true"
  }
}
```

[Claude-Code-Einstellungen](https://code.claude.com/docs/en/settings) sind geschichtet: `.claude/settings.local.json` (persönlich, pro Projekt, nicht committet) schlägt `.claude/settings.json` (Team, pro Projekt) schlägt `~/.claude/settings.json` (benutzerweit). Diese Datei wirkt also nur in diesem Repository und nur für dich. Dafür muss ein Proxy laufen, entweder `headroom proxy --port 8787` in einem Terminal oder der dauerhafte Dienst aus dem nächsten Abschnitt.

**Warum `ENABLE_TOOL_SEARCH`?** Laut Hilfetext von `headroom wrap claude --tool-search` ([Issue #746](https://github.com/headroomlabs-ai/headroom/issues/746)) lädt Claude Code mit einer eigenen `ANTHROPIC_BASE_URL` alle Tool-Schemas sofort statt bei Bedarf. Mit vielen MCP-Servern bläht das jeden Request auf und frisst einen Teil der Ersparnis. Die Variable erhält das Laden bei Bedarf.

Rückgängig machen mit `headroom unwrap claude` oder die Datei löschen.

## Globales Setup: jeder Agent auf dem Rechner

Für den Alltag will man einen Proxy, der Neustarts überlebt, und Agenten, die alle so konfiguriert sind, dass sie ihn nutzen. Headroom nennt das Persistent Install:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# schlüsselfertig: wählt Docker, einen nativen Dienst oder einen geplanten Watchdog
headroom deploy

# oder explizit: Hintergrunddienst, jeden erkannten Agenten einrichten, Benutzer-Scope
headroom install apply --preset persistent-service --providers auto --scope user

# oder nur ausgewählte Agenten
headroom install apply --preset persistent-task --providers manual --target claude --target codex

headroom install status
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# schlüsselfertig: wählt Docker, einen nativen Dienst oder einen geplanten Watchdog
headroom deploy

# oder explizit: Hintergrunddienst, jeden erkannten Agenten einrichten, Benutzer-Scope
headroom install apply --preset persistent-service --providers auto --scope user

# oder nur ausgewählte Agenten
headroom install apply --preset persistent-task --providers manual --target claude --target codex

headroom install status
```

{{< /os-tab >}}
{{< /os-tabs >}}

Die Presets: `persistent-service` nutzt einen nativen Hintergrunddienst, `persistent-task` einen geplanten Watchdog (launchd, Aufgabenplanung oder cron), `persistent-docker` einen Container mit Restart-Policy. `headroom install stop|start|restart|remove` verwalten ihn; `remove` macht die Konfigurationsänderungen rückgängig.

Was pro Agent konfiguriert wird, laut [Anleitung zu Persistent Installs](https://docs.headroomlabs.ai/docs/persistent-installs):

| Agent | Wie Headroom ihn umleitet |
| --- | --- |
| Claude Code | `env`-Block in `~/.claude/settings.json` |
| Codex | verwalteter Block in `~/.codex/config.toml` |
| OpenCode | verwalteter Provider-Block in `~/.config/opencode/opencode.json` |
| Copilot CLI, Aider, Goose, Cline, Continue, OpenHands … | `headroom wrap <agent>`; umgebungsvariablenbasierte Werkzeuge über `--scope user` oder `--scope system` |
| VS Code (Claude-Code-Erweiterung, Copilot) | `headroom wrap vscode-claude`, `headroom wrap vscode` |
| Cursor | manuell: `headroom wrap cursor` startet den Proxy und gibt die Basis-URLs für Cursors Einstellungen aus |
| Gemini CLI | **kein dokumentiertes Setup.** Der Proxy hat eine Gemini-`generateContent`-Route und `headroom learn` unterstützt Gemini, aber es gibt weder `headroom wrap gemini` noch eine Anleitung für die Gemini CLI (Stand v0.44.0) |
| Jeder MCP-Client | `headroom mcp install` fügt die Tools compress/retrieve/stats hinzu |

Prüfen lässt sich das mit `headroom install status`, dem Endpunkt `/health` und `headroom dashboard` für Live-Einsparungen. `headroom savings` zeigt, was es bei deinem echten Traffic gespart hat.

**Das eine große Risiko des globalen Setups:** Sobald `ANTHROPIC_BASE_URL` in den Benutzereinstellungen auf `127.0.0.1:8787` zeigt, hängt *jede* Claude-Code-Session an diesem Proxy. Läuft er nicht, erreicht der Agent das Modell überhaupt nicht. Deshalb bekommt der nächste Abschnitt einen Health-Check mit Desktop-Benachrichtigung.

**Telemetrie:** Laut README ist ein anonymer Beacon (Kompressionsraten, Modell-IDs, Betriebssystem; keine Prompts, kein Code) **standardmäßig an**; die Konfigurationsseite führt `HEADROOM_TELEMETRY` als standardmäßig aus. Die Dokumentation widerspricht sich, also im Zweifel explizit `HEADROOM_BEACON=off` setzen.

## Headroom automatisch aktuell halten

Neue Headroom-Versionen erscheinen häufig (vier Releases zwischen 26.10. und 10.11.2026). Eingebaut ist:

- `headroom update --check` meldet das neueste Release, ohne zu aktualisieren.
- `headroom update --yes` erkennt, wie Headroom installiert wurde (pip, pipx, uv tool), und führt das passende Upgrade ohne Rückfrage aus.
- Der Proxy zeigt beim Start höchstens einmal am Tag einen einzeiligen Hinweis „update available“. `HEADROOM_UPDATE_CHECK=off` schaltet ihn ab.

Einen **eingebauten Auto-Updater und Desktop-Benachrichtigungen gibt es nicht**, also bauen wir beides. Um das Verhalten richtig abzubilden, habe ich den Quellcode des `update`-Befehls gelesen ([`headroom/cli/update.py`](https://github.com/headroomlabs-ai/headroom/blob/main/headroom/cli/update.py)):

- `--check` beendet sich mit Exit-Code 0, sowohl wenn alles aktuell ist als auch wenn es ein Update gibt. Im zweiten Fall gibt es `Update available: <alt> → <neu>` aus. Nur ein nicht erreichbares PyPI führt zu einem Exit-Code ungleich 0.
- Bei Docker-, Editable- oder System-Python-Installationen aktualisiert es nicht, sondern gibt Hinweise aus und endet trotzdem mit 0. Das Skript vergleicht deshalb die Version vorher und nachher.
- Ein fehlgeschlagenes Upgrade endet mit einem Exit-Code ungleich 0.
- Der laufende Proxy muss neu gestartet werden, um die neue Version zu nutzen.

### Das Update-Skript

Das Skript sucht nach einem Update, spielt es mit Stopp und Start des dauerhaften Proxys ein, prüft, ob der Proxy antwortet, und schickt für alles Relevante eine Desktop-Benachrichtigung. Mit `AUTO_APPLY=0` wird man über Updates nur informiert.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

Als `~/.local/bin/headroom-update.sh` speichern und `chmod +x ~/.local/bin/headroom-update.sh` ausführen:

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

Einmalig das Modul [BurntToast](https://github.com/Windos/BurntToast) installieren (`Install-Module BurntToast -Scope CurrentUser`), dann als `$HOME\bin\headroom-update.ps1` speichern:

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

Die Aufrufe `install stop/start` setzen den Persistent Install aus dem vorigen Abschnitt voraus. Wer nur `headroom wrap` nutzt, entfernt sie; die nächste Wrap-Session startet dann mit der neuen Version. Unter Windows sperrt ein laufender Proxy das native Modul von Headroom, ein Grund mehr, ihn vorher zu stoppen. Wer unter Windows mit reinem `pip` installiert hat: `headroom update` übergibt das Upgrade dort an einen Kindprozess und kehrt zurück, bevor es fertig ist. Der Versionsvergleich meldet dann „not applied“; eine Installation per `uv tool` vermeidet das.

Das PowerShell-Skript läuft in PowerShell 7 und in Windows PowerShell 5.1. Wer noch auf 5.1 ist: [warum und wie man upgradet](/de/blog/upgrade-powershell-7/).

### Zeitplan einrichten

{{< os-tabs >}}
{{< os-tab "Linux (systemd)" >}}

Ein [systemd-User-Timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html) läuft in deiner Benutzersitzung, und genau die brauchen Desktop-Benachrichtigungen. `~/.config/systemd/user/headroom-update.service` anlegen:

```ini
[Unit]
Description=Check and apply Headroom updates

[Service]
Type=oneshot
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=%h/.local/bin/headroom-update.sh
```

und `~/.config/systemd/user/headroom-update.timer`:

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

Aktivieren und einmal testen:

```bash
systemctl --user daemon-reload
systemctl --user enable --now headroom-update.timer
systemctl --user start headroom-update.service   # jetzt ausführen
journalctl --user -u headroom-update.service -n 20
```

`Persistent=true` holt einen Lauf nach, der verpasst wurde, weil der Rechner aus war.

{{< /os-tab >}}
{{< os-tab "macOS (launchd)" >}}

Ein [launchd](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)-LaunchAgent läuft in deiner grafischen Sitzung. launchd expandiert `~` nicht, deshalb setzt das Heredoc unten dein Home-Verzeichnis ein:

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
launchctl kickstart "gui/$(id -u)/local.headroom-update"   # jetzt ausführen
```

Schläft der Mac um 09:00, führt launchd den Job beim Aufwachen aus.

{{< /os-tab >}}
{{< os-tab "Windows (Aufgabenplanung)" >}}

Eine tägliche Aufgabe für den aktuellen Benutzer mit dem Modul [ScheduledTasks](https://learn.microsoft.com/de-de/powershell/module/scheduledtasks/register-scheduledtask) registrieren:

```powershell
$script = Join-Path $HOME 'bin\headroom-update.ps1'
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Daily -At '09:00'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
Register-ScheduledTask -TaskName 'Headroom update' -Action $action -Trigger $trigger -Settings $settings

Start-ScheduledTask -TaskName 'Headroom update'   # jetzt ausführen
```

`powershell.exe` statt `pwsh.exe` verwenden, wenn PowerShell 7 nicht installiert ist. `-StartWhenAvailable` holt eine verpasste Ausführung nach, wenn der Rechner aus war.

{{< /os-tab >}}
{{< /os-tabs >}}

Wer unter Linux lieber cron nutzt: `0 9 * * * $HOME/.local/bin/headroom-update.sh` funktioniert für das Update selbst, aber zu Benachrichtigungen siehe unten.

### Benachrichtigungen: was wo funktioniert

Desktop-Benachrichtigungen aus einem Hintergrundjob sind auf allen drei Systemen möglich, aber nur unter Bedingungen. Die sollte man kennen, sonst gibt es stille Fehler, und genau die soll der Job ja verhindern.

| System | Mechanismus | Funktioniert, wenn | Funktioniert nicht |
| --- | --- | --- | --- |
| Linux | `notify-send` ([libnotify](https://gitlab.gnome.org/GNOME/libnotify)) | systemd-**User**-Timer in einer Desktop-Sitzung; GNOME und KDE geben den Session-Bus an den User-Manager weiter | aus cron (kein `DBUS_SESSION_BUS_ADDRESS`), auf Headless-Servern, vor dem Login |
| macOS | `osascript -e 'display notification …'` | LaunchAgent in der angemeldeten grafischen Sitzung; erscheint als Meldung von *Skripteditor*, das unter Systemeinstellungen › Mitteilungen erlaubt sein muss | LaunchDaemons (Systemkontext), vor dem Login |
| Windows | [BurntToast](https://github.com/Windos/BurntToast)-Toast | Aufgabe läuft als angemeldeter Benutzer (Standard oben) | Aufgabe auf „unabhängig von der Benutzeranmeldung ausführen“ gestellt, dann läuft sie in einer Sitzung ohne Desktop |

Auf einem Headless-Linux-Server gibt es kein Popup. Dort zählt der Exit-Code: `systemctl --user status headroom-update` und das Journal zeigen Fehler, und eine `OnFailure=`-Unit oder das vorhandene Monitoring können sie per Mail oder Chat weiterleiten.

## Die Zahlen

{{< diagram src="token-cost-headroom-scenarios.svg" caption="Vom Hersteller gemessen an vier synthetischen Szenarien aus echten MCP-Ausgabeformaten (mit Seed, offline, Tokenizer des Anbieters). Ersparnis: 21 % bei der Codesuche, 57 % beim Debugging eines SRE-Incidents, 42 % beim Erkunden einer Codebasis, 30 % bei der Triage von GitHub-Issues." >}}

| Szenario | Vorher | Nachher | Gespart |
| --- | --- | --- | --- |
| Codesuche (100 Treffer) | 17.199 | 13.597 | 21 % |
| Debugging eines SRE-Incidents | 55.957 | 24.340 | 57 % |
| Erkunden einer Codebasis | 58.801 | 33.895 | 42 % |
| Triage von GitHub-Issues | 46.067 | 32.429 | 30 % |

*Quelle: [Headroom-README](https://github.com/headroomlabs-ai/headroom), reproduzierbar mit `benchmarks/index_proof_table.py --seed 20260902`.*

Das sind Kompressionsraten auf vorbereiteten Payloads, keine ganzen Agenten-Sessions. Repetitive JSON-Arrays und Log-Zeilen kommen im Latenz-Benchmark über 90 %; Fließtext und dichte Ausgaben lassen sich kaum komprimieren. Die Komprimierung kostet 0,21 ms (p50) bei einem JSON-Ergebnis mit 10.000 Tokens.

Genauigkeit, ebenfalls vom Hersteller gemessen, mit N = 100 je Benchmark: GSM8K 0,870 → 0,870, TruthfulQA 0,530 → 0,560 (innerhalb des Konfidenzintervalls, also „kein erkennbarer Unterschied“), SQuAD v2 97 % bei 19 % Kompression, BFCL (Tool-Aufrufe) 97 % bei 32 % Kompression.

Headrooms eigene [Seite zu Einschränkungen](https://docs.headroomlabs.ai/docs/limitations) ist erfrischend direkt: Die Zahlen seien „one-off, synthetic measurements, not a published benchmark“, und agentische Gespräche seien „not independently measured“.

Die einzige Zahl von Dritten, die ich gefunden habe, stammt von einem Konkurrenten: Cavemans README berichtet, dass Headroom auf Cavemans eigener Testsuite mit sechs Dateien 15 von 18 Fragen richtig beantwortet hat, bei 6,7 % weniger Tokens; Cavemans eigene Engine kam auf 18 von 18 bei 33,2 % weniger. Ein Hersteller, der ein Konkurrenzprodukt auf seinem eigenen Benchmark misst, ist nicht unabhängig, also zähle ich das als einen Datenpunkt und mehr nicht. Einen **unabhängigen Benchmark** von Headroom habe ich nicht gefunden.

## Kosten und wann Headroom nicht hilft

- **Quellcode geht größtenteils unverändert durch.** Standardmäßig sind aktueller Code und Code unter Analyse geschützt. In einer reinen Coding-Session mit wenigen Logs ist die Ersparnis klein. Das ist das Revier von code-review-graph.
- **Kurze Wechsel und Fließtext.** Unterhalb einer Mindestgröße kommen Blöcke Byte für Byte gleich zurück, und bei kleinen Payloads kann der Overhead die Ersparnis übersteigen.
- **Ein neuer Single Point of Failure.** Im globalen Setup bedeutet ein toter Proxy einen toten Agenten. Der Health-Check oben mildert das ab.
- **Absichtlich verlustbehaftet.** Die Auswahl der Einträge ist heuristisch. CCR kann Originale zurückholen, aber nur, wenn das Modell merkt, dass es sie braucht.
- **Noch eine Komponente mit Lieferkette.** Ein Python-Paket mit nativem Code, ein ML-Modell-Download von Hugging Face, ONNX Runtime, häufige Releases. Für Firmennetze mit TLS-Inspektion hat das README einen eigenen Abschnitt zu Zertifikaten.
- **Telemetrie standardmäßig an** (siehe oben).

## Die Werkzeuge kombinieren

Die vier Werkzeuge wirken auf verschiedene Teile eines Requests, deshalb lassen sie sich stapeln:

{{< diagram src="token-cost-where-tools-act.svg" caption="Caveman-Stimme und Ponytail verkleinern die Ausgabe, code-review-graph das Lesen von Quellcode, Headroom komprimiert andere Tool-Ausgaben und caveman-compress verkleinert Memory-Dateien. Regeln und Tool-Schemas sind der Preis auf der Eingabeseite." >}}

| Ebene | Werkzeug | Überschneidet sich mit | Empfehlung |
| --- | --- | --- | --- |
| Code, den der Agent schreibt | Ponytail | Caveman-Stimme (beide verlangen kurze Antworten) | Immer an |
| Antworttext | Caveman-Stimme | Ponytail, Headroom-Output-Shaper | Optional; vorher messen |
| Memory-Dateien | `caveman-compress` | — | Einmal, für große `CLAUDE.md`-Dateien |
| Quellcode, den der Agent liest | code-review-graph | Headroom `--code-graph` (eigener Watcher) | In Code-Repositories an, mit Hooks |
| Logs, JSON, Testausgaben | Headroom | Cavemans v4-Engine „Read less“ | **Eines** von beiden wählen |

Was man nicht stapeln sollte:

- **Zwei Eingabe-Kompressoren.** Cavemans lokale v4-Engine und Headroom komprimieren beide Tool-Ausgaben. Beide zusammen heißt zwei Proxys, zwei Fehlerquellen und das Komprimieren bereits komprimierter Inhalte. Eines wählen.
- **Zwei Codegraphen.** `headroom wrap claude --code-graph` aktiviert Headrooms eigenen Codegraph-Watcher. Wer code-review-graph nutzt, lässt dieses Flag weg.
- **Drei „fass dich kurz“-Anweisungen.** Ponytail, die Caveman-Stimme und `HEADROOM_OUTPUT_SHAPER=1` drängen alle auf kurze Antworten. Eine reicht; jede kostet in jedem Request Eingabe.

### Mein empfohlenes Setup

1. **Ponytail als Claude-Code-Plugin.** Es hat den am besten dokumentierten Benchmark, einen unabhängigen Test mit positivem (wenn auch kleinerem) Ergebnis, und sein Nebeneffekt, weniger Code, ist unabhängig von der Rechnung gut.
2. **code-review-graph in jedem Code-Repository**, mit den Claude-Code- und Git-Hooks aus [Teil 2](/de/blog/token-cost-2-code-review-graph/#wo-man-es-einbindet-hooks-die-den-graphen-aktuell-halten). In Content-Repositories wie diesem Blog weglassen.
3. **Headroom global, wenn deine Sessions viel Log und JSON enthalten** (Ops, Debugging, API-Arbeit): Persistent Install, `ENABLE_TOOL_SEARCH=true`, der Update-Job mit Health-Benachrichtigungen. Für reine Feature-Arbeit erst `headroom wrap claude` an ein paar Aufgaben ausprobieren und nur behalten, wenn `headroom savings` und die Rechnung des Anbieters übereinstimmen.
4. **`/caveman-compress`** einmal für eine große `CLAUDE.md`, mit dem Original in der Versionskontrolle. Die Caveman-Stimme nur, wenn dir die Antworten danach noch zu lang sind.

### Messen statt glauben

Jede Zahl in dieser Serie, die von einem Hersteller kam, war größer als die unabhängigen. Die einzige Messung, die zählt, ist deine Rechnung für deine Arbeit. Dieselbe Aufgabe mit und ohne Werkzeug ausführen, den vom Anbieter gemeldeten Verbrauch vergleichen (die [Anthropic Console](https://console.anthropic.com/) oder die Nutzungsseite deines Abos) und die eigenen Zähler der Werkzeuge nur als Hinweis nehmen: Ponytails Band, `/caveman-stats`, `headroom savings` und das `context_savings` von code-review-graph schätzen alle gegen ein Gegenszenario, das sie nie beobachtet haben.

## Quellen

- Headroom: [README](https://github.com/headroomlabs-ai/headroom), [Dokumentation](https://docs.headroomlabs.ai/docs), [Persistent Installs](https://docs.headroomlabs.ai/docs/persistent-installs), [Konfiguration](https://docs.headroomlabs.ai/docs/configuration), [Einschränkungen](https://docs.headroomlabs.ai/docs/limitations), [`update.py`](https://github.com/headroomlabs-ai/headroom/blob/main/headroom/cli/update.py)
- Claude Code: [Einstellungen](https://code.claude.com/docs/en/settings), [Hooks](https://code.claude.com/docs/en/hooks)
- systemd: [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html); Apple: [launchd-Jobs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html); Microsoft: [Register-ScheduledTask](https://learn.microsoft.com/de-de/powershell/module/scheduledtasks/register-scheduledtask)
- Benachrichtigungen: [libnotify](https://gitlab.gnome.org/GNOME/libnotify), [BurntToast](https://github.com/Windos/BurntToast)
- Cavemans Vergleichslauf: [Caveman-README, „Read less“](https://github.com/JuliusBrussee/caveman#read-less-332-fewer-input-tokens)
