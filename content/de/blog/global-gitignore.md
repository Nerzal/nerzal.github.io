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

Jeder Entwickler hat es mindestens einmal erlebt: Eine `.DS_Store`-Datei, ein `.idea/`-Ordner oder ein anderes maschinenspezifisches Artefakt landet versehentlich in einem gemeinsam genutzten Repository. Eine projektbezogene `.gitignore` hilft, aber du musst sie in jedem Repo wiederholen. Die Lösung ist eine **globale `.gitignore`** – eine einzige Datei, die Git auf jedes Repository auf deinem Rechner anwendet.

## Wie Git entscheidet, was ignoriert wird

Git wertet Ignore-Regeln aus drei Quellen in der Reihenfolge ihrer Spezifität aus:

1. `.gitignore`-Dateien innerhalb des Repositories (eingecheckt, mit dem Team geteilt)
2. `.git/info/exclude` innerhalb des Repositories (lokal, nicht eingecheckt)
3. Die Datei, auf die `core.excludesFile` in deiner globalen Git-Konfiguration verweist (gilt für jedes Repo auf dem Rechner)

Die globale Exclude-Datei ist der richtige Ort für Regeln, die spezifisch für **dein Gerät oder dein Toolchain** sind, nicht für ein Projekt. Die vollständige Auflösungsreihenfolge findest du in der offiziellen [gitignore-Dokumentation](https://git-scm.com/docs/gitignore).

## Schritt 1 — Datei erstellen

Per Konvention heißt die Datei `.gitignore_global` und liegt im Home-Verzeichnis, aber du kannst sie überall ablegen und beliebig benennen.

**Linux / macOS:**

```bash
touch ~/.gitignore_global
```

**Windows (PowerShell):**

```powershell
New-Item -ItemType File -Path "$env:USERPROFILE\.gitignore_global"
```

{{< figure src="/img/global_gitignore_new_item.png" alt="PowerShell-Ausgabe von New-Item beim Erstellen der .gitignore_global" >}}

## Schritt 2 — Git darüber informieren

Registriere die Datei bei Git über den Konfigurationsschlüssel `core.excludesFile`.

**Linux / macOS:**

```bash
git config --global core.excludesFile ~/.gitignore_global
```

**Windows (PowerShell):**

```powershell
git config --global core.excludesFile "$env:USERPROFILE\.gitignore_global"
```

Damit wird eine Zeile in `~/.gitconfig` (Linux/macOS) bzw. `%USERPROFILE%\.gitconfig` (Windows) geschrieben:

```ini
[core]
    excludesFile = /home/you/.gitignore_global
```

Du kannst prüfen, ob der Wert korrekt gesetzt wurde:

```bash
git config --global core.excludesFile
```

```powershell
git config --global core.excludesFile
```

Beide Befehle sollten den gesetzten Pfad ausgeben.

## Schritt 3 — Datei befüllen

Hier gehört alles rein, was von deinem **Betriebssystem, Editor oder Toolchain** erzeugt wird – nicht vom Projekt selbst.

Ein praktischer Ausgangspunkt:

```bash
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

# mise / asdf Versionsmanager
.tool-versions
.mise.toml
```

Regeln verwenden dieselbe Glob-Syntax wie eine normale `.gitignore`. Leerzeilen und Zeilen, die mit `#` beginnen, werden ignoriert.

## Regeln automatisch generieren

Diese Liste manuell zu pflegen wird mühsam. [gitignore.io](https://www.toptal.com/developers/gitignore) (auch per API erreichbar) generiert maßgeschneiderte Ignore-Regeln für beliebige Kombinationen aus Betriebssystemen, Editoren und Sprachen. Um beispielsweise Regeln für macOS + Windows + JetBrains + Go im Terminal zu erhalten:

**Linux / macOS:**

```bash
curl -sL "https://www.toptal.com/developers/gitignore/api/macos,windows,jetbrains+all,go" \
  >> ~/.gitignore_global
```

**Windows (PowerShell):**

```powershell
Invoke-WebRequest -Uri "https://www.toptal.com/developers/gitignore/api/windows,jetbrains+all,go" `
  -UseBasicParsing | Select-Object -ExpandProperty Content `
  | Add-Content -Path "$env:USERPROFILE\.gitignore_global"
```

Das GitHub-Team pflegt außerdem eine kuratierte Sammlung von Templates unter [github/gitignore](https://github.com/github/gitignore). Jede Datei dort deckt eine Sprache oder ein Tool ab und ist eine zuverlässige Referenz.

## Funktionsweise prüfen

Erstelle eine temporäre Datei, die einer Regel entspricht, und bestätige, dass Git sie ignoriert:

**Linux / macOS:**

```bash
cd /tmp && git init test-repo && cd test-repo
touch .DS_Store
git status
```

**Windows (PowerShell):**

```powershell
$null = New-Item -ItemType Directory -Path "$env:TEMP\test-repo"; cd "$env:TEMP\test-repo"
git init
New-Item -ItemType File -Path "Thumbs.db"
git status
```

`git status` sollte einen sauberen Working Tree melden – die Datei ist für Git unsichtbar.

{{< figure src="/img/global_gitignore_verify.png" alt="PowerShell-Ausgabe von git status ohne getrackte Dateien" >}}

## Hinweise

- **Regeln sind additiv, nicht überschreibend.** Ein Muster in `.gitignore_global` überschreibt keine `!Negation` in der `.gitignore` eines Projekts. Die spezifischste passende Regel gewinnt.
- **Bereits getrackte Dateien sind nicht betroffen.** Wenn eine Datei bereits in ein Repository eingecheckt ist, bewirkt das Hinzufügen zur `.gitignore` (auch zur globalen) kein Untracking. Dazu ist zuerst `git rm --cached <datei>` nötig.
- **Teammitglieder benötigen ihre eigene Einrichtung.** Die globale Exclude-Datei ist rein lokal; sie wird nie eingecheckt. Wenn ein Muster für alle im Projekt gelten soll, gehört es in die projektbezogene `.gitignore`.

## Fazit

Eine globale `.gitignore` ist eine einmalige Einrichtung, die stillschweigend eine ganze Klasse von versehentlichen Commits in jedem Repository auf deinem Rechner verhindert. Einmal einrichten, fokussiert auf Geräte- und Tool-spezifische Artefakte halten, und projektspezifische Regeln der Repository-eigenen `.gitignore` überlassen.
