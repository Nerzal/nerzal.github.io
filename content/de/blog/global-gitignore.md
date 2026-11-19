---
draft: false
title: "Eine globale .gitignore einrichten"
date: 2026-05-09T00:00:00+00:00
tags: ["tutorial", "git", "developer-tooling"]
description: "Schluss mit versehentlich committeten .DS_Store-, Thumbs.db- und IDE-Ordnern. So konfigurierst du eine globale .gitignore für alle Repositories."
images: ["img/global_gitignore.png"]
featured_image: "img/global_gitignore.png"
toc: true
---

Jeder Entwickler hat es mindestens einmal erlebt: Eine `.DS_Store`-Datei, ein `.idea/`-Ordner oder ein anderes maschinenspezifisches Artefakt landet versehentlich in einem gemeinsam genutzten Repository. Eine projektbezogene `.gitignore` hilft, aber du musst sie in jedem Repo wiederholen. Abhilfe schafft eine **globale `.gitignore`**: eine einzige Datei, die Git auf jedes Repository auf deinem Rechner anwendet.

## Wie Git entscheidet, was ignoriert wird

Git wertet Ignore-Regeln aus drei Quellen in der Reihenfolge ihrer Spezifität aus:

1. `.gitignore`-Dateien innerhalb des Repositories (eingecheckt, mit dem Team geteilt)
2. `.git/info/exclude` innerhalb des Repositories (lokal, nicht eingecheckt)
3. Die Datei, auf die `core.excludesFile` in deiner globalen Git-Konfiguration verweist (gilt für jedes Repo auf dem Rechner)

Die globale Exclude-Datei ist der richtige Ort für Regeln, die spezifisch für **dein Gerät oder deine Toolchain** sind, nicht für ein Projekt. Die vollständige Auflösungsreihenfolge findest du in der offiziellen [gitignore-Dokumentation](https://git-scm.com/docs/gitignore).

## Schritt 1: Datei erstellen

Per Konvention heißt die Datei `.gitignore_global` und liegt im Home-Verzeichnis, aber du kannst sie überall ablegen und beliebig benennen.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
touch ~/.gitignore_global
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
New-Item -ItemType File -Path "$env:USERPROFILE\.gitignore_global"
```

{{< /os-tab >}}
{{< /os-tabs >}}

{{< figure src="/img/global_gitignore_new_item.png" alt="PowerShell-Ausgabe von New-Item beim Erstellen der .gitignore_global" >}}

## Schritt 2: Git darüber informieren

Registriere die Datei bei Git über den Konfigurationsschlüssel `core.excludesFile`.

> **Abkürzung:** Ist `core.excludesFile` nicht gesetzt, liest Git bereits `$XDG_CONFIG_HOME/git/ignore`, ersatzweise `~/.config/git/ignore` (`%USERPROFILE%\.config\git\ignore` unter Windows). Legst du deine Regeln dort ab, kannst du diesen Schritt komplett überspringen. Die explizite Einstellung unten lohnt sich, wenn die Datei woanders liegen oder in deiner `.gitconfig` sofort sichtbar sein soll.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
git config --global core.excludesFile ~/.gitignore_global
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
git config --global core.excludesFile "$env:USERPROFILE\.gitignore_global"
```

{{< /os-tab >}}
{{< /os-tabs >}}

Damit wird eine Zeile in `~/.gitconfig` (Linux/macOS) bzw. `%USERPROFILE%\.gitconfig` (Windows) geschrieben:

```ini
[core]
    excludesFile = /home/you/.gitignore_global
```

Du kannst prüfen, ob der Wert korrekt gesetzt wurde:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
git config --global core.excludesFile
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
git config --global core.excludesFile
```

{{< /os-tab >}}
{{< /os-tabs >}}

Beide Befehle sollten den gesetzten Pfad ausgeben.

## Schritt 3: Datei befüllen

Hier gehört alles rein, was dein Betriebssystem, dein Editor oder deine Toolchain erzeugt. Dateien, die das Projekt selbst erzeugt, gehören nicht hierher.

Ein praktischer Ausgangspunkt:

```text
# macOS
.DS_Store
.AppleDouble
.LSOverride

# Windows
Thumbs.db
ehthumbs.db
desktop.ini

# Linux
*~
.nfs*


# Vim / Neovim
*.swp
*.swo
Session.vim

# Emacs
\#*\#
.\#*

# direnv
.envrc
```

Versionsmanager-Dateien wie `.tool-versions` (asdf, mise) oder `mise.toml` gehören nicht in diese Liste. Viele Teams checken sie bewusst ein, um Tool-Versionen festzunageln. Global ignoriert verschwinden sie aus `git status`, und du merkst nie, wenn die Änderung eines Kollegen daran in deinem Commit fehlt.

Regeln verwenden dieselbe Glob-Syntax wie eine normale `.gitignore`. Leerzeilen und Zeilen, die mit `#` beginnen, werden ignoriert.

## Regeln automatisch generieren

Diese Liste von Hand zu pflegen, wird schnell mühsam. [gitignore.io](https://www.toptal.com/developers/gitignore) (auch per API erreichbar) generiert maßgeschneiderte Ignore-Regeln für beliebige Kombinationen aus Betriebssystemen, Editoren und Sprachen. Um beispielsweise Regeln für macOS + Windows + JetBrains + Go im Terminal zu erhalten:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
curl -sL "https://www.toptal.com/developers/gitignore/api/macos,windows,jetbrains+all,go" \
  >> ~/.gitignore_global
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
Invoke-WebRequest -Uri "https://www.toptal.com/developers/gitignore/api/macos,windows,jetbrains+all,go" `
  -UseBasicParsing | Select-Object -ExpandProperty Content `
  | Add-Content -Path "$env:USERPROFILE\.gitignore_global"
```

{{< /os-tab >}}
{{< /os-tabs >}}

Das GitHub-Team pflegt außerdem eine kuratierte Sammlung von Templates unter [github/gitignore](https://github.com/github/gitignore). Jede Datei dort deckt eine Sprache oder ein Tool ab und ist eine zuverlässige Referenz.

## Funktionsweise prüfen

Erstelle eine temporäre Datei, die einer Regel entspricht, und bestätige, dass Git sie ignoriert:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
cd /tmp && git init test-repo && cd test-repo
touch .DS_Store
git status
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
$null = New-Item -ItemType Directory -Path "$env:TEMP\test-repo"; cd "$env:TEMP\test-repo"
git init
New-Item -ItemType File -Path "Thumbs.db"
git status
```

{{< /os-tab >}}
{{< /os-tabs >}}

`git status` sollte einen sauberen Working Tree melden, weil die Datei für Git unsichtbar ist.

{{< figure src="/img/global_gitignore_verify.png" alt="PowerShell-Ausgabe von git status ohne getrackte Dateien" >}}

## Hinweise

- **Die Quellen haben eine feste Rangfolge.** Muster in den `.gitignore`-Dateien eines Repositorys schlagen `.git/info/exclude`, das wiederum `core.excludesFile` schlägt. Eine `!Negation` in der `.gitignore` eines Projekts holt also eine Datei zurück, die deine globale Datei ignoriert. Innerhalb einer Quelle gewinnt das **letzte** passende Muster, auch wenn ein früheres spezifischer ist.
- **Bereits getrackte Dateien sind nicht betroffen.** Wenn eine Datei bereits in ein Repository eingecheckt ist, bewirkt das Hinzufügen zur `.gitignore` (auch zur globalen) kein Untracking. Dazu ist zuerst `git rm --cached <datei>` nötig.
- **Teammitglieder benötigen ihre eigene Einrichtung.** Die globale Exclude-Datei ist rein lokal; sie wird nie eingecheckt. Wenn ein Muster für alle im Projekt gelten soll, gehört es in die projektbezogene `.gitignore`.

## Fazit

Eine globale `.gitignore` richtest du einmal ein, und ab dann hält sie Artefakte von Betriebssystem, Editor und Tools aus den Commits in jedem Repository auf deinem Rechner fern. Beschränke sie auf geräte- und toolspezifische Artefakte und überlass projektspezifische Regeln der `.gitignore` des jeweiligen Repositorys.
