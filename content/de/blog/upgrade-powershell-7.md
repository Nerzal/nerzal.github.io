---
draft: false
title: "Windows 11 nutzt standardmäßig noch PowerShell 5.1 — und warum das ein Problem ist"
date: 2026-05-10T00:00:00+00:00
tags: ["tutorial", "windows", "windows11", "powershell", "oh-my-posh", "terminal", "devex"]
seo_title: "PowerShell 5.1 auf 7 upgraden unter Windows 11"
description: "Windows 11 setzt standardmäßig PowerShell 5.1 ein — eine Version von 2016, die auf dem alten .NET Framework basiert. Erfahre, warum das relevant ist, wie du auf PowerShell 7 upgraden und es als Standard setzen kannst."
images: ["img/powershell-51-vs-70.png"]
featured_image: "img/powershell-51-vs-70.png"
toc: true
---

Windows 11 ist ein modernes Betriebssystem. Das Standard-Terminal setzt jedoch auf eine Shell von 2016.

Wer PowerShell auf einem frischen Windows-11-System öffnet, landet bei **Windows PowerShell 5.1** — einer Version, die auf dem alten .NET Framework 4.x aufbaut, seit 2018 offiziell im [Maintenance-Modus](https://learn.microsoft.com/de-de/powershell/scripting/powershell-support-lifecycle) ist und von Microsoft keine neuen Features mehr erhält.

Das ist mir auf die harte Tour klar geworden, als ich [Oh My Posh](https://ohmyposh.dev) auf einem frischen System einrichten wollte — ein Framework für individuell gestaltete Terminal-Prompts. Auf PowerShell 5.1 zeigte es entweder Fehler oder kaputte Symbole:

{{< image src="img/oh-my-posh-error-5.1.png" alt="Oh My Posh mit kaputten Icons auf PowerShell 5.1" >}}

Die Lösung lag nicht im Anpassen der Oh-My-Posh-Konfiguration. Die Lösung war der Wechsel zu **PowerShell 7**.

{{< skip-to anchor="powershell-7-installieren" label="Direkt zur Installation" >}}

---

## Windows PowerShell vs. PowerShell — zwei verschiedene Produkte

Die Namensgebung ist verwirrend, aber wichtig. Microsoft liefert zwei verschiedene Produkte aus:

| | Windows PowerShell | PowerShell |
|---|---|---|
| **Version** | 5.1 (abgeschlossen) | 7.x (aktiv entwickelt) |
| **Laufzeit** | .NET Framework 4.x | .NET 8+ |
| **Plattform** | Nur Windows | Windows, macOS, Linux |
| **Quellcode** | Geschlossen | [Open Source auf GitHub](https://github.com/PowerShell/PowerShell) |
| **Status** | Nur Wartung | Aktive Entwicklung, LTS-Releases |
| **Speicherort** | `C:\Windows\System32\WindowsPowerShell\v1.0\` | `C:\Program Files\PowerShell\7\` |

**Windows PowerShell** (blaues Icon, `powershell.exe`) ist eine fest im Windows-System verankerte Komponente und wird nie über Version 5.1 hinaus aktualisiert. **PowerShell** (schwarzes Icon, `pwsh.exe`) ist der Nachfolger — ein kompletter Neuanfang, der 2016 als PowerShell Core 6 erschien und mit Version 7 den Namen erhielt, als er Funktionsparität erreichte.

Beide können problemlos nebeneinander installiert sein. Eine Installation von PowerShell 7 entfernt Windows PowerShell 5.1 nicht.

---

## Was PowerShell 7 konkret bringt

Das sind die Unterschiede, die man täglich bemerkt.

### Pipeline-Verkettungsoperatoren

PowerShell 7.0 führte `&&` und `||` ein — die Operatoren, die jeder Entwickler von einer Shell erwartet:

```powershell
# Build ausführen, dann nur deployen wenn erfolgreich
npm run build && npm run deploy

# Schnellen Pfad versuchen, bei Fehler zurückfallen
Get-Command pwsh || Write-Host "PowerShell 7 nicht gefunden"
```

PowerShell 5.1 kennt kein Äquivalent. Dort braucht man umständliche `if ($LASTEXITCODE -eq 0)`-Konstrukte.

### Ternärer Operator

```powershell
$env = $isProd ? "production" : "development"
```

In 5.1 ist dafür ein vollständiger `if/else`-Block notwendig.

### Null-bedingte und Null-zusammenführende Operatoren

```powershell
# Null-Coalescing: rechte Seite, wenn linke Seite null ist
$config = $userConfig ?? $defaultConfig

# Null-Conditional: Methode nur aufrufen wenn Objekt nicht null
$laenge = $str?.Length
```

Beide kamen mit PowerShell 7.1 und fehlen in 5.1 vollständig.

### Parallele Pipeline-Ausführung

```powershell
# Elemente parallel verarbeiten — in 5.1 nicht möglich
1..20 | ForEach-Object -Parallel {
    Invoke-RestMethod "https://api.example.com/item/$_"
} -ThrottleLimit 5
```

`ForEach-Object -Parallel` ist seit PowerShell 7.0 verfügbar und nutzt Thread-basierte Parallelisierung ohne die Notwendigkeit von Background-Jobs.

### Bessere Fehlerbehandlung

PowerShell 7.2 vereinheitlichte die Fehlerbehandlung und machte `$ErrorActionPreference = 'Stop'` konsistenter. Dazu kam `Get-Error`, das vollständige Exception-Details strukturiert anzeigt — deutlich nützlicher als die abgeschnittenen Stack-Traces in 5.1.

### Moderner .NET-Zugriff

Da PowerShell 7 auf .NET 8 läuft, sind alle .NET-8-APIs und -Typen direkt zugänglich:

```powershell
# JsonNode — auf dem alten .NET Framework 4.x von 5.1 nicht verfügbar
[System.Text.Json.JsonNode]::Parse('{"key": "value"}')
```

### SSH-basiertes Remoting

PowerShell 5.1 setzt für Remoting auf WinRM (Windows Remote Management), das Firewall-Konfiguration erfordert und plattformübergreifend nicht funktioniert. PowerShell 7 ergänzt SSH-basiertes Remoting, das direkt zu Linux- und macOS-Hosts funktioniert.

### Eingebaute ANSI-Farbunterstützung und `$PSStyle`

PowerShell 7.2 führte `$PSStyle` ein — ein eingebautes Objekt, das die gesamte ANSI-Terminal-Ausgabe steuert. In 5.1 musste man Escape-Sequenzen manuell einbetten. In PowerShell 7 ist das ein natives Sprachkonstrukt:

```powershell
# 5.1 — manuelle ANSI-Escape-Sequenzen
Write-Host "`e[32mErfolgreich`e[0m"   # funktioniert nur in manchen Terminals

# PowerShell 7 — $PSStyle ist immer verfügbar
Write-Host "$($PSStyle.Foreground.Green)Erfolgreich$($PSStyle.Reset)"

# Farben, Fett, Unterstrichen, Blinken — alles eingebaut
$header = $PSStyle.Bold + $PSStyle.Foreground.Cyan
Write-Host "${header}Deployment abgeschlossen$($PSStyle.Reset)"
```

`$PSStyle` steuert auch, wie PowerShell selbst Ausgaben rendert — Listenansichten, Fehler und Dateisystem-Einträge nutzen es alle, und es lässt sich anpassen:

```powershell
# Farbe vollständig deaktivieren, z.B. für CI-Pipelines
$PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText
```

### Übersichtlichere Fehlerausgabe

PowerShell 7 nutzt standardmäßig `ErrorView = 'ConciseView'`. Der Unterschied für denselben Fehler:

**5.1-Ausgabe:**

```text
Get-Item : Cannot find path 'C:\existiert\nicht' because it does not exist.
At line:1 char:1
+ Get-Item C:\existiert\nicht
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : ObjectNotFound: (C:\existiert\nicht:String) [Get-Item], ItemNotFoundException
    + FullyQualifiedErrorId : PathNotFound,Microsoft.PowerShell.Commands.GetItemCommand
```

**PowerShell 7 ConciseView:**

```text
Get-Item: Cannot find path 'C:\existiert\nicht' because it does not exist.
```

Wenn man die vollständigen Details braucht, liefert `Get-Error` eine strukturierte, navigierbare Ansicht der letzten Exception — inklusive innerer Exceptions, Typ-Informationen und vollständigem Stack-Trace, ohne das Rauschen der abgeschnittenen 5.1-Ausgabe.

```powershell
Get-Item C:\existiert\nicht
Get-Error   # vollständige strukturierte Details des letzten Fehlers
```

### Verbesserungen bei `Invoke-RestMethod` und `Invoke-WebRequest`

Die HTTP-Cmdlets in 5.1 waren funktional, aber karg. PowerShell 7 brachte eine Reihe praktischer Verbesserungen:

```powershell
# Automatische Wiederholung mit Wartezeit — in 5.1 nicht verfügbar
Invoke-RestMethod https://api.example.com/daten `
    -MaximumRetryCount 3 `
    -RetryIntervalSec 2

# HTTP/2-Unterstützung
Invoke-WebRequest https://api.example.com `
    -HttpVersion 2.0

# Antwort-Header als echtes Dictionary
$response = Invoke-WebRequest https://api.example.com
$response.Headers["Content-Type"]   # funktioniert korrekt in PS 7
                                     # gibt string[] in PS 5.1 zurück

# Zertifikatsprüfung für lokale Entwicklung überspringen
Invoke-RestMethod https://localhost:5001/api `
    -SkipCertificateCheck
```

In 5.1 gab `Invoke-RestMethod` für JSON immer ein `PSCustomObject` zurück — kein Weg, ein Hashtable zu bekommen. PowerShell 7 ergänzte `ConvertFrom-Json` um `-AsHashtable`:

```powershell
# 5.1 — PSCustomObject, dynamischer Zugriff auf Keys umständlich
$daten = '{"status": "ok"}' | ConvertFrom-Json
$daten.status   # funktioniert, aber Property-Namen müssen bekannt sein

# PowerShell 7 — echtes Hashtable
$daten = '{"status": "ok"}' | ConvertFrom-Json -AsHashtable
$daten["status"]   # funktioniert für jeden Key, auch dynamische
```

### `Join-String` — ein fehlendes Cmdlet endlich vorhanden

In PowerShell 5.1 gab es keinen eingebauten Weg, Pipeline-Ausgabe zu einem einzigen String zu verbinden. Die Lösung war `($array -join ", ")` oder vorheriges Sammeln in einer Variable. PowerShell 7 liefert `Join-String`:

```powershell
# Sauberes, pipeline-natives Verbinden
Get-Process | Select-Object -ExpandProperty Name | Join-String -Separator ", "

# Mit Präfix und Suffix pro Element
Get-ChildItem *.ps1 | Join-String -Property Name -Separator "`n" -OutputPrefix "Skripte:`n"

# Ausgabe in Anführungszeichen — nützlich für Argument-Generierung
"alpha", "beta", "gamma" | Join-String -SingleQuote -Separator ", "
# 'alpha', 'beta', 'gamma'
```

### Syntax-Highlighting in der Konsole

PowerShell 7 liefert eine neuere Version von [PSReadLine](https://github.com/PowerShell/PSReadLine) mit standardmäßig aktiviertem Syntax-Highlighting. Beim Tippen werden Schlüsselwörter, Strings, Variablen und Operatoren in Echtzeit eingefärbt:

```powershell
# PSReadLine-Version prüfen
Get-Module PSReadLine | Select-Object Version

# Syntax-Highlighting ist in PS 7 standardmäßig aktiv
# Inline-Vorschau — zeigt Vervollständigungen in Grau während der Eingabe (PS 7.2+)
Set-PSReadLineOption -PredictionViewStyle InlineView
```

PowerShell 5.1 liefert PSReadLine 1.x ohne Syntax-Highlighting. Ein Upgrade in 5.1 ist möglich, aber fehleranfällig; in PowerShell 7 ist es die Standarderfahrung.

### Startgeschwindigkeit

PowerShell 7.2 brachte durch Ahead-of-Time-Kompilierung (AOT) der häufigsten Code-Pfade signifikante Verbesserungen der Startzeit. Auf einem typischen Entwicklerrechner:

```powershell
# Kalte Startzeit messen
Measure-Command { pwsh -NoProfile -Command "exit" }
# PowerShell 7.4+: ~150–250 ms

Measure-Command { powershell -NoProfile -Command "exit" }
# Windows PowerShell 5.1: ~400–700 ms
```

Der Unterschied spielt vor allem bei Skripten eine Rolle, die Unterprozesse starten — etwa CI-Pipeline-Schritte, die `pwsh -File skript.ps1` dutzende Male aufrufen. Auch die interaktive Nutzung (Win+R, `pwsh` tippen, schnellen Befehl ausführen) ist spürbar flotter.

---

## PowerShell 7 installieren

### Option 1 — winget (empfohlen)

```powershell
winget install Microsoft.PowerShell
```

Damit wird die aktuell stabile Version aus der 7.x-Reihe installiert. Die `--id` bleibt über Hauptversionen stabil, sodass Updates einfach möglich sind:

```powershell
winget upgrade Microsoft.PowerShell
```

Der Installer trägt `pwsh` automatisch in den `PATH` ein.

### Option 2 — Microsoft Store

Im Microsoft Store nach **PowerShell** suchen. Die Store-Version aktualisiert sich automatisch und benötigt keine erhöhten Rechte.

### Option 3 — GitHub Releases

Das MSI-Installationsprogramm von der [offiziellen Releases-Seite](https://github.com/PowerShell/PowerShell/releases) herunterladen. Für 64-Bit-Systeme: `PowerShell-7.x.x-win-x64.msi`.

### Installation prüfen

```powershell
pwsh --version
# PowerShell 7.x.x
```

---

## Oh My Posh einrichten

Mit installiertem PowerShell 7 funktioniert Oh My Posh korrekt. Installation per winget:

```powershell
winget install JanDeLaars.OhMyPosh
```

Anschließend einen [Nerd Font](https://www.nerdfonts.com/) installieren — Oh My Posh nutzt Schrift-Ligaturen und Icons, die einen gepatchten Font voraussetzen. [Cascadia Code NF](https://github.com/microsoft/cascadia-code) ist eine gute Wahl, die Microsoft ebenfalls ausliefert:

```powershell
winget install Microsoft.CascadiaCode
```

Die Oh-My-Posh-Initialisierung gehört in das PowerShell-7-Profil. Das Profil für `pwsh` liegt unter:

```text
$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

Mit folgendem Befehl öffnen (und bei Bedarf anlegen):

```powershell
New-Item -ItemType File -Path $PROFILE -Force
notepad $PROFILE
```

Diese Zeile in das Profil einfügen:

```powershell
oh-my-posh init pwsh | Invoke-Expression
```

Um ein bestimmtes Theme zu nutzen — Oh My Posh liefert über 100 eingebaute Themes mit, gespeichert unter:

```text
$env:POSH_THEMES_PATH
```

```powershell
# Verfügbare Themes auflisten
Get-ChildItem $env:POSH_THEMES_PATH

# Ein Theme verwenden
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression
```

Terminal neu starten. Oh My Posh rendert jetzt korrekt mit Icons und Powerline-Segmenten:

{{< image src="img/powershell-51-vs-70.png" alt="Oh My Posh funktioniert korrekt auf PowerShell 7" >}}

---

## PowerShell 7 als Standard setzen

Die Installation von `pwsh` ändert nicht, was sich öffnet, wenn man Win+X drückt oder auf das Terminal in der Taskleiste klickt. Das öffnet standardmäßig weiterhin Windows PowerShell 5.1.

### Windows Terminal

Windows Terminal ist die empfohlene Terminal-Anwendung unter Windows 11. **Einstellungen** öffnen (Strg+,) → **Starten** → **Standardprofil** → **PowerShell** auswählen (das mit dem schwarzen Icon und Version 7.x). Falls es nicht erscheint: **Neues Profil hinzufügen** → **Neues leeres Profil** und die Befehlszeile auf `pwsh.exe` setzen.

Alternativ die `settings.json` direkt bearbeiten (Strg+Umschalt+, in Windows Terminal) und `defaultProfile` auf die GUID des PowerShell-7-Profils setzen.

### Visual Studio Code

**Einstellungen** → nach `terminal.integrated.defaultProfile.windows` suchen → auf `PowerShell` setzen. VS Code verwendet dann `pwsh.exe` für alle integrierten Terminal-Sitzungen.

Oder direkt in `settings.json`:

```json
{
  "terminal.integrated.defaultProfile.windows": "PowerShell",
  "terminal.integrated.profiles.windows": {
    "PowerShell": {
      "source": "PowerShell",
      "icon": "terminal-powershell"
    }
  }
}
```

### JetBrains IDEs

**Einstellungen** → **Extras** → **Terminal** → **Shell-Pfad** auf `pwsh.exe` setzen (oder den vollständigen Pfad `C:\Program Files\PowerShell\7\pwsh.exe`).

---

## Profil migrieren

Wer Anpassungen im Windows-PowerShell-5.1-Profil hat (`$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`), wird feststellen, dass die meisten davon direkt im PowerShell-7-Profil (`$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`) funktionieren.

Die häufigsten Inkompatibilitäten:

**Modul-Verfügbarkeit** — ältere Windows-spezifische Module existieren nur für 5.1. Vor dem Übernehmen von `Import-Module`-Zeilen prüfen:

```powershell
pwsh -Command "Import-Module DeinModul -ErrorAction Stop"
```

**`#Requires -Version 5`** — Skripte mit diesem Header verweigern die Ausführung in PowerShell 7. Die Versionsanforderung entfernen oder aktualisieren.

**Windows-exklusive Cmdlets** — Module wie `ActiveDirectory`, `Hyper-V` oder `GroupPolicy` sind für PowerShell 7 möglicherweise nicht verfügbar. Microsoft ergänzt [Kompatibilitäts-Shims](https://learn.microsoft.com/de-de/powershell/scripting/whats-new/module-compatibility), aber eine Prüfung im Einzelfall ist notwendig.

**COM-Objekte und WMI** — `[wmiclass]` und COM-Automatisierung sind .NET-Framework-spezifisch. `Get-CimInstance` statt `Get-WmiObject` bevorzugen; CIM funktioniert in beiden Versionen.

---

## Zusammenfassung

Windows 11 setzt aus historischen und Kompatibilitätsgründen standardmäßig PowerShell 5.1 ein — aber es gibt keinen Grund, für die tägliche Arbeit dabei zu bleiben. PowerShell 7 ist schneller, leistungsfähiger, plattformübergreifend und Voraussetzung für moderne Entwicklerwerkzeuge wie Oh My Posh.

Der Migrationspfad ist unkompliziert:

1. `winget install Microsoft.PowerShell`
2. `winget install JanDeLaars.OhMyPosh`
3. PowerShell 7 als Standard in Windows Terminal setzen
4. Bestehendes Profil kopieren und prüfen

Windows PowerShell 5.1 bleibt als Systemkomponente installiert — es verschwindet nirgendwo. Aber die Terminal-Sitzungen müssen nicht auf einer Shell laufen, die 2018 aufgehört hat, sich weiterzuentwickeln.

---

## Weiterführende Links

- [PowerShell 7 Versionshinweise und Changelog](https://learn.microsoft.com/de-de/powershell/scripting/whats-new/what-s-new-in-powershell-7x)
- [PowerShell Support Lifecycle](https://learn.microsoft.com/de-de/powershell/scripting/powershell-support-lifecycle)
- [Oh My Posh Dokumentation](https://ohmyposh.dev/docs)
- [PowerShell auf GitHub](https://github.com/PowerShell/PowerShell)
- [Windows Terminal Dokumentation](https://learn.microsoft.com/de-de/windows/terminal/)
