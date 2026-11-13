---
draft: false
title: "Windows 11 nutzt standardmäßig noch PowerShell 5.1 — und warum das ein Problem ist"
date: 2026-05-10T00:00:00+00:00
tags: ["tutorial", "windows", "windows11", "powershell", "oh-my-posh", "terminal", "devex"]
seo_title: "PowerShell 5.1 auf 7 upgraden unter Windows 11"
description: "Windows 11 setzt standardmäßig noch PowerShell 5.1 ein, eine 2016er-Version auf altem .NET Framework. So upgradest du auf PowerShell 7 als Standard."
images: ["img/powershell-51-vs-70.png"]
featured_image: "img/powershell-51-vs-70.png"
toc: true
---

Windows 11 ist ein modernes Betriebssystem. Das Standard-Terminal setzt jedoch auf eine Shell von 2016.

Wer PowerShell auf einem frischen Windows-11-System öffnet, landet bei **Windows PowerShell 5.1** — einer Version, die im August 2016 erschien, auf dem alten .NET Framework 4.x aufbaut und für immer eingefroren ist. Als PowerShell Core 6.0 im Januar 2018 GA wurde, [kündigte Microsoft an](https://devblogs.microsoft.com/powershell/powershell-core-6-0-generally-available-ga-and-supported/), dass Windows PowerShell ab dann nur noch kritische Fehlerbehebungen erhält — keine neuen Features. Sie wird über den [Windows-Lebenszyklus](https://learn.microsoft.com/de-de/powershell/scripting/install/powershell-support-lifecycle) gewartet, nicht weiterentwickelt.

Das ist mir auf die harte Tour klar geworden, als ich [Oh My Posh](https://ohmyposh.dev) auf einem frischen System einrichten wollte — ein Framework für individuell gestaltete Terminal-Prompts. Auf PowerShell 5.1 zeigte es entweder Fehler oder kaputte Symbole:

{{< image image="img/oh-my-posh-error-5.1.png" imageAlt="Oh My Posh mit kaputten Icons auf PowerShell 5.1" >}}

Die Lösung lag nicht im Anpassen der Oh-My-Posh-Konfiguration. Die Lösung war der Wechsel zu **PowerShell 7**.

{{< skip-to anchor="powershell-7-installieren" label="Direkt zur Installation" >}}

---

## Windows PowerShell vs. PowerShell — zwei verschiedene Produkte

Die Namensgebung ist verwirrend, aber wichtig. Microsoft liefert zwei verschiedene Produkte aus:

| | Windows PowerShell | PowerShell |
|---|---|---|
| **Version** | 5.1 (abgeschlossen) | 7.x (aktiv entwickelt) |
| **Laufzeit** | .NET Framework 4.x | Modernes .NET (7.6 LTS: .NET 10) |
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
$environment = $isProd ? "production" : "development"
```

In 5.1 ist dafür ein vollständiger `if/else`-Block notwendig.

### Null-bedingte und Null-zusammenführende Operatoren

```powershell
# Null-Coalescing: rechte Seite, wenn linke Seite null ist
$config = $userConfig ?? $defaultConfig

# Null-Conditional: Methode nur aufrufen wenn Objekt nicht null
# Die Klammern sind wichtig: `$str?.Length` würde eine Variable namens `str?` lesen
$laenge = ${str}?.Length
```

Die Null-Coalescing-Operatoren `??` und `??=` kamen mit PowerShell 7.0, die Null-Conditional-Operatoren `?.` und `?[]` wurden in PowerShell 7.1 stabil. In 5.1 fehlen sie alle.

### Parallele Pipeline-Ausführung

```powershell
# Elemente parallel verarbeiten — in 5.1 nicht möglich
1..20 | ForEach-Object -Parallel {
    Invoke-RestMethod "https://api.example.com/item/$_"
} -ThrottleLimit 5
```

`ForEach-Object -Parallel` ist seit PowerShell 7.0 verfügbar und nutzt Thread-basierte Parallelisierung ohne die Notwendigkeit von Background-Jobs.

### Bessere Fehlerbehandlung

PowerShell 7.0 brachte `Get-Error`, das vollständige Exception-Details strukturiert anzeigt — deutlich nützlicher als die abgeschnittenen Stack-Traces in 5.1.

### Moderner .NET-Zugriff

PowerShell 7 läuft auf modernem .NET — das aktuelle LTS-Release PowerShell 7.6 basiert auf .NET 10. Alle APIs und Typen dieser Laufzeit sind direkt zugänglich:

```powershell
# JsonNode — auf dem alten .NET Framework 4.x von 5.1 nicht verfügbar
[System.Text.Json.Nodes.JsonNode]::Parse('{"key": "value"}')
```

### SSH-basiertes Remoting

PowerShell 5.1 setzt für Remoting auf WinRM (Windows Remote Management), das Firewall-Konfiguration erfordert und plattformübergreifend nicht funktioniert. PowerShell 7 ergänzt SSH-basiertes Remoting, das direkt zu Linux- und macOS-Hosts funktioniert. Falls du Linux-Server verwaltest, solltest du den [SSH-Daemon absichern](/de/blog/secure-ssh-server/), bevor du Remote-Zugriff von PowerShell aus einrichtest.

### Eingebaute ANSI-Farbunterstützung und `$PSStyle`

PowerShell 7.2 führte `$PSStyle` ein — ein eingebautes Objekt, das die gesamte ANSI-Terminal-Ausgabe steuert. In 5.1 musste man Escape-Sequenzen manuell einbetten — und weil es das Escape `` `e `` erst ab PowerShell 6 gibt, sogar das Escape-Zeichen selbst per `[char]27` bauen. In PowerShell 7 ist das ein natives Sprachkonstrukt:

```powershell
# 5.1 — manuelle ANSI-Escape-Sequenzen
$esc = [char]27
Write-Host "$esc[32mErfolgreich$esc[0m"   # funktioniert nur in manchen Terminals

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

# Antwort-Header behalten alle Werte
$response = Invoke-WebRequest https://api.example.com
$response.Headers["Content-Type"]   # string[] in PS 7 — mehrfache Header bleiben getrennt
                                     # ein einzelner String in PS 5.1

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

### Syntax-Highlighting und Predictive IntelliSense

Beide Shells färben die Eingabe beim Tippen ein — Windows 10 und 11 liefern Windows PowerShell 5.1 mit [PSReadLine](https://github.com/PowerShell/PSReadLine) 2.0 aus, das bereits Syntax-Highlighting beherrscht. PowerShell 7 bringt ein aktuelles PSReadLine 2.x mit, das [Predictive IntelliSense](https://learn.microsoft.com/de-de/powershell/scripting/learn/shell/using-predictors) ergänzt: Vorschläge aus der History und aus Plugins, inline oder als Liste:

```powershell
# PSReadLine-Version prüfen
Get-Module PSReadLine | Select-Object Version

# Vorschläge aus History und Plugins (Standard seit PSReadLine 2.2.6)
Set-PSReadLineOption -PredictionSource HistoryAndPlugin

# Vorschläge als Liste unter dem Prompt statt als graue Inline-Vorschau
Set-PSReadLineOption -PredictionViewStyle ListView
```

Ein neueres PSReadLine lässt sich auch in 5.1 installieren und liefert dort History-basierte Vorschläge, Predictor-Plugins setzen aber PowerShell 7.2 oder neuer voraus. In PowerShell 7 ist die aktuelle Version einfach dabei.

### Startgeschwindigkeit

Die Startzeit hängt stark vom Rechner, vom Profil und von den geladenen Modulen ab — also lieber selbst messen, statt Zahlen aus einem Blogpost zu glauben:

```powershell
# Startzeit beider Shells ohne Profile vergleichen
Measure-Command { pwsh -NoProfile -Command "exit" }
Measure-Command { powershell -NoProfile -Command "exit" }
```

Jede Zeile ein paar Mal ausführen — der erste (kalte) Start ist meist deutlich langsamer als die folgenden. Wenn deine CI-Pipeline `pwsh -File skript.ps1` dutzende Male aufruft, ist `-NoProfile` der größte Hebel.

---

## PowerShell 7 installieren

### Option 1 — winget (empfohlen)

```powershell
winget install --id Microsoft.PowerShell --source winget
```

Damit wird die aktuell stabile Version installiert — zum Zeitpunkt des Schreibens PowerShell 7.6, das aktuelle LTS-Release (März 2026, basiert auf .NET 10). PowerShell 7.4 LTS und 7.5 haben am 10. November 2026 das Support-Ende erreicht; wer noch darauf läuft, sollte upgraden. Die `--id` bleibt über alle 7.x-Releases stabil, sodass Updates einfach möglich sind:

```powershell
winget upgrade --id Microsoft.PowerShell --source winget
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
winget install JanDeDobbeleer.OhMyPosh --source winget
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

{{< image image="img/powershell-51-vs-70.png" imageAlt="Oh My Posh funktioniert korrekt auf PowerShell 7" >}}

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

**`#Requires -PSEdition Desktop`** — Skripte mit diesem Header verweigern die Ausführung in PowerShell 7, denn das ist die `Core`-Edition. Ein einfaches `#Requires -Version 5` ist dagegen harmlos: Es bedeutet „5.0 oder neuer", PowerShell 7 erfüllt es also. Die Edition-Anforderung entfernen, sobald das Skript in 7 funktioniert.

**Windows-exklusive Cmdlets** — Module wie `ActiveDirectory`, `Hyper-V` oder `GroupPolicy` sind für PowerShell 7 möglicherweise nicht verfügbar. Microsoft ergänzt [Kompatibilitäts-Shims](https://learn.microsoft.com/de-de/powershell/scripting/whats-new/module-compatibility), aber eine Prüfung im Einzelfall ist notwendig.

**COM-Objekte und WMI** — `[wmiclass]` und COM-Automatisierung sind .NET-Framework-spezifisch. `Get-CimInstance` statt `Get-WmiObject` bevorzugen; CIM funktioniert in beiden Versionen.

---

## Zusammenfassung

Windows 11 setzt aus historischen und Kompatibilitätsgründen standardmäßig PowerShell 5.1 ein — aber es gibt keinen Grund, für die tägliche Arbeit dabei zu bleiben. PowerShell 7 ist leistungsfähiger, plattformübergreifend und Voraussetzung für moderne Entwicklerwerkzeuge wie Oh My Posh.

Der Migrationspfad ist unkompliziert:

1. `winget install --id Microsoft.PowerShell --source winget`
2. `winget install JanDeDobbeleer.OhMyPosh --source winget`
3. PowerShell 7 als Standard in Windows Terminal setzen
4. Bestehendes Profil kopieren und prüfen

Windows PowerShell 5.1 bleibt als Systemkomponente installiert — es verschwindet nirgendwo. Aber die Terminal-Sitzungen müssen nicht auf einer Shell laufen, die 2016 erschienen ist und seit 2018 kein neues Feature mehr bekommen hat.

---

## Weiterführende Links

- [PowerShell 7 Versionshinweise und Changelog](https://learn.microsoft.com/de-de/powershell/scripting/whats-new/what-s-new-in-powershell-7x)
- [PowerShell Support Lifecycle](https://learn.microsoft.com/de-de/powershell/scripting/install/powershell-support-lifecycle)
- [Oh My Posh Dokumentation](https://ohmyposh.dev/docs)
- [PowerShell auf GitHub](https://github.com/PowerShell/PowerShell)
- [Windows Terminal Dokumentation](https://learn.microsoft.com/de-de/windows/terminal/)
