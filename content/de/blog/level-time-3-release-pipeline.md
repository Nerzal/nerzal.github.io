---
draft: false
title: "Level Time bauen — Teil 3: Release-Pipeline mit Go-Installer, BigWigs-Packager und CurseForge"
seo_title: "WoW-Addon Release-Pipeline: BigWigs Packager + CurseForge"
date: 2026-11-25T08:00:00+01:00
tags:
  [
    "wow-addon",
    "lua",
    "go",
    "github-actions",
    "bigwigs-packager",
    "curseforge",
    "release-automation",
    "ci-cd",
  ]
categories: ["Software Engineering"]
series: ["Building Level Time"]
description: "Tag pushen, Release bekommen: ein WoW-Addon mit GitHub Actions und dem BigWigs-Packager zu CurseForge bringen, dazu ein kleiner Go-Installer für lokale Builds."
images: ["img/level-time/logo.png"]
featured_image: "img/level-time/logo.png"
toc: true
---

> **Serie: Level Time bauen** — Teil 3 von 4. [Teil 1: Addon-Architektur](/de/blog/level-time-1-addon-architecture/) · [Teil 2: Lua mit Go testen](/de/blog/level-time-2-testing-lua-with-go/) · **Teil 3: Release-Pipeline** · [Teil 4: Goals und die öffentliche API](/de/blog/level-time-4-goals-public-api/) · Produktseite: [Level Time](/de/page/level-time/)

Ein Addon zu schreiben ist eine Sache. Es zu den Spielern zu bringen, ohne mich durch mehrere Upload-Formulare zu klicken, eine andere. Für [Level Time](/de/page/level-time/), ein World-of-Warcraft-Addon, das Zeit, XP und Kills pro Level misst, wollte ich eine einzige Regel: **Ich pushe einen Git-Tag, und alles andere passiert von selbst.**

In diesem Artikel gehe ich den ganzen Weg von `git tag` bis zur Datei auf CurseForge durch: den GitHub-Actions-Workflow, den [BigWigs-Packager](https://github.com/BigWigsMods/packager), die `.pkgmeta`, die `.toc`-Dateien für mehrere Spielversionen, einen Trick, um ein zweites Addon aus demselben Repository auszuliefern, und den kleinen Go-Installer, mit dem ich Builds in meinen eigenen WoW-Ordnern teste.

Alles hier stammt aus `release.yml`, `.pkgmeta`, `Makefile` und `tools/installer` des Repositories. Die Kommentare im Repo sind auf Deutsch, in den Code-Ausschnitten unten habe ich sie ins Englische übersetzt.

---

## Das Ziel: Ein Tag ist ein Release

Der Workflow startet bei Tags, die auf `v*` passen. Sonst veröffentlicht nichts. Normale Pushes auf `main` und Pull Requests laufen durch einen separaten `Test`-Workflow (`make vet` und `make test`), ein kaputter Test fällt also meist lange vor dem Tag auf.

{{< diagram src="level-time-3-pipeline.svg" caption="Vom Tag zum Release. Der Test-Job schützt den Release-Job; der Packager läuft zweimal, weil Level Time und Level Time Goals getrennte CurseForge-Projekte sind." >}}

Der Release-Workflow, auf das Gerüst gekürzt:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version: "1.27"
      - run: make test

  release:
    needs: test          # no green tests, no release
    runs-on: ubuntu-latest
    permissions:
      contents: write    # needed to create the GitHub release
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # the packager needs history for version and changelog
      - uses: BigWigsMods/packager@v2
```

Drei Details sind wichtig.

**`needs: test`.** Der Release-Job startet nur, wenn der Test-Job grün ist. Die Tests sind die Lua-Szenarien aus [Teil 2: Lua mit Go testen](/de/blog/level-time-2-testing-lua-with-go/) plus die Tests des Installers und der anderen Go-Tools. Ein Tag auf einem roten Commit erzeugt also kein Release. Siehe die GitHub-Doku zu [`needs`](https://docs.github.com/en/actions/using-jobs/using-jobs-in-a-workflow#defining-prerequisite-jobs).

**`fetch-depth: 0`.** `actions/checkout` holt standardmäßig nur einen Commit. Der Packager leitet die Version aus der Git-Historie ab und baut das Changelog aus den Commit-Nachrichten, braucht also die komplette Historie und die Tags.

**`contents: write`.** Zum Anlegen eines Releases braucht der Job Schreibrechte auf den Repository-Inhalt. Ich gebe sie nur dem Release-Job, nicht dem Test-Job. Siehe [Automatic token authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token).

---

## Der BigWigs-Packager

Der Packager ist ein Bash-Skript des BigWigs-Teams und im Addon-Ökosystem weit verbreitet. Er erledigt ein paar Aufgaben, die von Hand lästig sind:

1. Die Addon-Dateien in einen sauberen Ordner kopieren und alles aus der `ignore`-Liste weglassen.
2. Schlüsselwörter wie `@project-version@` in den Dateien ersetzen.
3. Aus der Git-Historie ein Changelog erzeugen.
4. Das Ergebnis zippen.
5. Zu den konfigurierten Plattformen hochladen und ein GitHub-Release anlegen.

Die Action `BigWigsMods/packager@v2` verpackt das Skript. Zu welchen Plattformen hochgeladen wird, entscheiden pro Plattform zwei Dinge: eine ID in der `.toc` und ein API-Token in der Umgebung. Der Kopf des Workflows dokumentiert den Vertrag:

| Plattform | `.toc`-Zeile | Secret |
| --- | --- | --- |
| CurseForge | `## X-Curse-Project-ID` | `CF_API_KEY` |
| Wago | `## X-Wago-ID` | `WAGO_API_TOKEN` |
| WoWInterface | `## X-WoWI-ID` | `WOWI_API_TOKEN` |

Fehlt eine ID oder ein Token, wird die Plattform übersprungen. Fehlt alles, bekommst du trotzdem das GitHub-Release. Das ist eine schöne Eigenschaft: Die Pipeline wird genügsamer, statt zu scheitern. Aktuell tragen meine `.toc`-Dateien nur eine CurseForge-Projekt-ID (1721235 für Level Time, 1744370 für Level Time Goals). Die Tokens liegen als Repository-Secrets und werden als Umgebungsvariablen durchgereicht; ihre Werte stehen nie im Repo.

### Den Upload benennen

Standardmäßig benennt der Packager die Datei nach dem Tag, etwa `v2.26.0`. Ich möchte überall denselben Namen, deshalb übergibt der Workflow `-n`:

```yaml
- uses: BigWigsMods/packager@v2
  with:
    args: -n "{package-name}-{project-version}:{package-name}-{project-version}.zip"
```

Das Format ist `{Dateiname}:{Label}`. Beide Teile werden zu `LevelTimer-v2.26.0`, sodass Zip und CurseForge-Anzeigename zu den Dateien aus der Zeit passen, in der ich von Hand hochgeladen habe. Die Platzhalter stehen in der [Packager-README](https://github.com/BigWigsMods/packager#usage).

---

## `.pkgmeta`: Was ins Zip kommt

Der Packager liefert das Repository ohne das aus, was `.pkgmeta` ignoriert. Das ist eine Deny-Liste, und die hat eine Konsequenz, die ich offen sagen will: **Jede neue Datei, die kein Addon-Code ist, muss in `ignore` eingetragen werden**, sonst landet sie im Zip. Hier die komplette Datei, Kommentare übersetzt:

```yaml
# Config for the BigWigs packager (.github/workflows/release.yml).
package-as: LevelTimer

# Load-on-demand archive: its own addon folder next to LevelTimer/
move-folders:
  LevelTimer/LevelTimer_Archive: LevelTimer_Archive

ignore:
  - tests
  - StreamGoal
  - tools
  - curseforge
  - Makefile
  - README.md
  - ROADMAP.md
  - ManualToCheck.md
  - image.png
```

Zeile für Zeile:

- **`package-as`** legt den Ordnernamen im Zip fest. Das Repository heißt `wow-statistics`, aber WoW erwartet, dass der Addon-Ordner wie die `.toc`-Datei heißt, also muss er `LevelTimer` sein.
- **`move-folders`** ist der interessante Teil. Level Time hat ein zweites Addon, das bei Bedarf geladen wird: `LevelTimer_Archive`, ein Journal-Archiv. WoW sieht nur Addons, die direkt in `Interface/AddOns/` liegen. Weil das Archiv im Repository in einem Unterordner liegt, legt der Packager es zuerst nach `LevelTimer/LevelTimer_Archive/`, und `move-folders` hebt es auf die oberste Ebene des Zips. Die eigene `.toc` des Archivs enthält `## LoadOnDemand: 1` und `## Dependencies: LevelTimer`.
- **`ignore`** schließt Tests, Go-Tools, CurseForge-Texte und Projektdokumente aus. Dazu `StreamGoal`, ein eigenes Addon mit eigenem Paket (nächster Abschnitt).

Alle Direktiven stehen in der [`.pkgmeta`-Dokumentation](https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File).

---

## Eine `.toc`, mehrere Spielversionen

World of Warcraft gibt es in mehreren Varianten: Retail, Classic Era und weitere. Sie teilen das Addon-Format, aber nicht die komplette API. Der `.toc`-Kopf von Level Time nennt mehrere Interface-Versionen in einer Zeile:

```text
## Interface: 120105, 11509, 20506, 16001
## Title: Level Time
## Version: @project-version@
## Author: Nerzal
## X-Curse-Project-ID: 1721235
## SavedVariables: LevelTimerDB, LevelTimerStatsDB, LevelTimerDebugLog
```

Die kommagetrennte `## Interface`-Liste lässt eine `.toc` mehrere Clients bedienen, so beschrieben auf der [TOC-format-Seite des WoW-Wikis](https://warcraft.wiki.gg/wiki/TOC_format). Die Projektnotizen im Repo halten die Regel fest, die daraus folgt: Ein API-Aufruf muss auf allen gelisteten Clients existieren oder abgesichert werden, denn es gibt keinen Build pro Variante. In Lua ist das ein simples `if GetPVPSessionStats then ...`. Die Struktur dahinter gehört zu [Teil 1](/de/blog/level-time-1-addon-architecture/).

Die Zeile `## Version: @project-version@` ist der Platzhalter, den der Packager durch den Tag ersetzt. Der Go-Installer ersetzt denselben Platzhalter, damit auch ein lokal installierter Build eine Version meldet.

---

## Zwei Addons, ein Repository

Level Time Goals ist ein zweites Addon, liegt im Ordner `StreamGoal/`, hängt von Level Time ab (`## Dependencies: LevelTimer`) und hat ein eigenes CurseForge-Projekt (ID 1744370). Wie es funktioniert, steht in [Teil 4](/de/blog/level-time-4-goals-public-api/). Für die Pipeline ist es ein Problem: Der Packager erwartet das Addon im **Wurzelverzeichnis eines Git-Repositories**, und sein Flag `-t` verlangt sogar ein `.git` dort.

Meine Lösung ist ein zweiter Packager-Lauf gegen einen Wegwerf-Klon, dessen Wurzel *selbst* `StreamGoal/` ist:

```yaml
- name: Split StreamGoal history
  run: |
    git clone -q . sg-repo
    cd sg-repo
    git filter-branch -f --subdirectory-filter StreamGoal --tag-name-filter cat -- --all
    git checkout -q "$GITHUB_REF_NAME"

- uses: BigWigsMods/packager@v2
  env:
    GITHUB_OAUTH: ""   # otherwise a second GitHub release is created for the same tag
  with:
    args: -t sg-repo -n "{package-name}-{project-version}:{package-name}-{project-version}.zip"
```

[`git filter-branch --subdirectory-filter`](https://git-scm.com/docs/git-filter-branch) schreibt den Klon so um, dass der Inhalt von `StreamGoal/` zur Repository-Wurzel wird, und nur Commits, die diesen Ordner berührt haben, bleiben übrig. `--tag-name-filter cat` schreibt die Tags mit der Historie um. Als Nebeneffekt enthält das Changelog von Level Time Goals nur Commits, die dieses Addon wirklich geändert haben.

Zwei ehrliche Anmerkungen:

- `git filter-branch` wird von Git selbst als nicht empfohlen markiert. [`git filter-repo`](https://github.com/newren/git-filter-repo) ist der empfohlene Nachfolger, aber eine zusätzliche Abhängigkeit, und der Klon ist ohnehin Wegwerfware. Deshalb bleibe ich bisher beim eingebauten Befehl.
- `GITHUB_OAUTH` im zweiten Lauf zu leeren ist Absicht. Der erste Lauf hat das GitHub-Release für den Tag bereits angelegt; ohne diese Zeile würde der zweite Lauf ein weiteres anlegen wollen.

Der Versions-Platzhalter funktioniert in beiden Läufen, weil beide `.toc`-Dateien `@project-version@` enthalten.

---

## Changelog und Versionierung

Ich nutze einfache Semver-artige Tags: `v2.25.0`, `v2.25.1`, `v2.26.0`. Patch für Fixes, Minor für Features. Bei einem Tag-Build ist die Projektversion des Packagers der Tag-Name.

Das Changelog erzeugt der Packager aus der Git-Historie. Eine handgeschriebene `CHANGELOG.md` gibt es im Repository nicht, die Qualität der Release Notes ist also die Qualität meiner Commit-Nachrichten. Das ist ein Kompromiss: Es kostet keine Pflege, belohnt aber saubere Commits. Der Listing-Text auf CurseForge (Beschreibung und Logo) liegt getrennt im Ordner `curseforge/` und wird von Hand gepflegt, weil er das Addon beschreibt und nicht ein einzelnes Release.

Lokale Builds folgen derselben Idee: Das `Makefile` berechnet `VERSION` mit `git describe --tags --always --dirty`. Ein lokales Zip heißt dann etwa `LevelTimer-v2.26.0-3-gabc1234-dirty.zip` und lässt sich nicht mit einem echten Release verwechseln.

---

## Der Go-Installer

Die Release-Pipeline deckt den öffentlichen Weg ab. Für meine eigenen Tests brauche ich das Gegenteil: einen schnellen Weg, die Arbeitskopie in meine WoW-Ordner zu bringen, für jede installierte Spielversion. Von Hand kopieren nervt spätestens beim dritten Mal, und eine alte Datei, die im Addon-Ordner liegen bleibt, kann unbemerkt veralteten Code laden. Darum gibt es `tools/installer`: ein kleines Go-Programm, nur mit der Standardbibliothek, getestet mit `go test` wie alles andere im Repository.

{{< diagram src="level-time-3-installer.svg" caption="Der Installer plant, bevor er schreibt. Der Plan ist ein Diff gegen das bereits Installierte, und nichts unter WTF wird je angefasst." >}}

Was er tut, der Reihe nach:

1. **Liest die Dateiliste aus der `.toc`.** Es gibt genau eine Stelle, die sagt, welche Dateien zum Addon gehören (die `.toc`), dazu alles unter `Media/`. Keine zweite Liste, die synchron bleiben muss. `LoadAddons` findet außerdem jeden Unterordner mit `<Ordner>/<Ordner>.toc`, sodass Level Time Goals und das Archiv automatisch dabei sind.
2. **Findet den WoW-Ordner.** Reihenfolge: Flag `-wow`, dann Umgebungsvariable `WOW_DIR`, dann Auto-Erkennung. Die sucht an üblichen Orten unter Windows (Laufwerke `C:` bis `Z:`, Ordner wie `World of Warcraft`, `Games\World of Warcraft`, `Program Files (x86)\World of Warcraft`) und macOS (`/Applications/World of Warcraft`). **Unter Linux gibt es keine Auto-Erkennung**, dort übergibst du `-wow` oder setzt `WOW_DIR`.
3. **Findet die Spielversionen.** Jeder Unterordner wie `_retail_` oder `_classic_era_` zählt. Du kannst `-wow` sogar auf einen solchen Ordner zeigen lassen, dann geht der Installer eine Ebene hoch.
4. **Baut einen Plan** pro Addon und Spielversion durch Byte-Vergleich: neue Datei (`+`), geändert (`~`), unverändert oder veraltet (`-`), also früher installiert und nicht mehr in der `.toc`.
5. **Zeigt den Plan und fragt nach.** `-dry-run` hört hier auf, `-yes` überspringt die Frage und aktualisiert standardmäßig die bereits installierten Spielversionen.
6. **Wendet ihn an.** Jede Datei wird erst in eine temporäre Datei geschrieben und dann umbenannt, damit das Spiel nie eine halb geschriebene Datei liest. Danach schreibt er `.install-manifest.json` in den Addon-Ordner, mit Version, Dateiliste und angewendeten Migrationen.

Das Manifest macht das Aufräumen veralteter Dateien sicher. Der Installer löscht nur Dateien, von denen er weiß, dass er sie selbst installiert hat. Bei alten manuellen Installationen ohne Manifest entfernt er nur Code-Dateien (`.lua`, `.toc`, `.xml`), die die aktuelle `.toc` nicht mehr referenziert.

### Die eine Regel, die er nie brechen darf

SavedVariables sind der Ort, an dem die Daten der Spieler liegen: Historie, Einstellungen, alles. Sie liegen unter dem Ordner `WTF`. Der Installer verweigert deshalb jeden Pfad, der eine `WTF`-Komponente enthält, geprüft einmal für das Ziel und noch einmal für jede Datei, die er schreibt (`ensureNotConfigPath`, `safeJoin`). Außerdem lehnt er relative Pfade ab, die aus dem Addon-Ordner ausbrechen würden. Ein Tool, das bei einem Tippfehler deine Spieldaten überschreibt, wäre schlimmer als kein Tool.

Nach einer Installation sagt die Ausgabe, ob `/reload` im Spiel reicht oder ob der Client neu starten muss, weil sich die `.toc` geändert hat. WoW liest `.toc`-Dateien nur beim Start.

### Benutzung

Das `Makefile` verpackt die gängigen Fälle.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# Interactive wizard: choose flavors, review the plan, confirm
make install

# Update every already-installed flavor without questions
make update

# Show what would change, write nothing
make dry-run

# Explicit WoW path (required on Linux)
make install ARGS="-flavors retail -wow '$HOME/Games/World of Warcraft'"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

Du kannst `make` nutzen, falls vorhanden, das Go-Tool selbst braucht aber nur Go:

```powershell
# Interactive wizard from the repository root
go -C tools/installer run . -src "$PWD" -version dev

# Dry run for one flavor with an explicit path
go -C tools/installer run . -src "$PWD" -version dev -dry-run -yes `
  -flavors retail -wow "D:\Games\World of Warcraft"
```

{{< /os-tab >}}
{{< /os-tabs >}}

Go installierst du nach [go.dev/doc/install](https://go.dev/doc/install). Das Flag `-C` des `go`-Befehls braucht Go 1.20 oder neuer, die CI nutzt Go 1.27.

Dasselbe Programm baut auch den manuellen Download. `make package` startet es im `-package`-Modus und schreibt `dist/LevelTimer-<version>.zip` (mit dem Archiv-Addon darin) und `dist/StreamGoal-<version>.zip`. Das ist eine praktische lokale Generalprobe für das, was der Packager erzeugt, aber das offizielle Release-Zip kommt vom Packager, nicht von diesem Weg.

Wenn dich interessiert, wie ich mit Go-Tooling an anderer Stelle umgehe: [Go-Anwendungen dockerisieren](/de/blog/go-docker/) behandelt eine andere Ecke desselben Werkzeugkastens.

---

## Weitere Go-Tools im Repository

Im Ordner `tools/` liegen weitere Programme. Je eine Zeile, denn sie gehören nicht zum Release-Weg selbst:

- **`tools/addontest`** ist das Test-Harness aus [Teil 2](/de/blog/level-time-2-testing-lua-with-go/).
- **`tools/artwork`** zeichnet das CurseForge-Logo sowie Icon und Texturen im Spiel (`make artwork`), sodass die Grafiken reproduzierbarer Code sind statt Binärdateien, die niemand bearbeiten kann.
- **`tools/records`** holt Speedrun-Rekorde von speedrun.com und erzeugt `Speedrun/SpeedrunRecords.lua` neu (`make records`, braucht Internet).
- **`tools/flights`** liest die Flugzeiten, die das Addon selbst gemessen hat, aus den SavedVariables jeder Spielversion (nur lesend) und erzeugt `Assist/FlightTimesData.lua` (`make flights`). Die Projektnotizen sagen, man soll es vor einem Release laufen lassen, um die neuesten Messwerte mitzuliefern.

---

## So schneide ich ein Release

Die Checkliste, der ich folge. Ersetze die Version durch deine nächste.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# 1. Be on a clean, up-to-date main
git switch main && git pull --ff-only

# 2. Run what CI will run
make vet && make test

# 3. Tag and push the tag; this triggers the Release workflow
git tag v2.27.0
git push origin v2.27.0

# 4. Watch the run
gh run watch
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
git switch main; git pull --ff-only

# Same checks as CI
make vet; if ($?) { make test }

git tag v2.27.0
git push origin v2.27.0

gh run watch
```

{{< /os-tab >}}
{{< /os-tabs >}}

Die [GitHub CLI](https://cli.github.com/) (`gh`) ist optional; der Actions-Tab zeigt denselben Lauf. Sind die Tests grün, packt der Release-Job, legt das GitHub-Release an und lädt zu CurseForge hoch. CurseForge prüft eine neue Datei unter Umständen kurz, bevor sie öffentlich erscheint; das liegt nicht in meiner Hand.

Geht ein Release schief, gibt es in der Pipeline keinen Rollback-Knopf. Ich korrigiere nach vorn mit einem neuen Patch-Tag (`v2.27.1`), statt einen bestehenden Tag zu verschieben, denn verschobene Tags verwirren Packager, GitHub und CurseForge gleichermaßen.

---

## Was ich gelernt habe

- **Der Standardweg soll der richtige Weg sein.** Ein Tag, ein Befehl. Je weniger manuelle Schritte, desto weniger vergessene.
- **Releases an Tests koppeln.** `needs: test` kostet eine Zeile.
- **Allow-Liste oder Deny-Liste ist eine echte Entscheidung.** Der Packager arbeitet mit einer Deny-Liste. Das ist bequem, bis man vergisst, eine neue Datei zu ignorieren. Mein lokales `make package` arbeitet mit einer Allow-Liste (nur, was die `.toc` nennt) und dient als Gegenprobe.
- **Werkzeuge bauen, die niemandem schaden können, auch dir selbst nicht.** Der WTF-Schutz im Installer existiert, weil ich weiß, dass ich mich irgendwann bei einem Pfad vertippe.

---

## Wie geht es weiter?

Im letzten Teil, [Teil 4: Goals und die öffentliche API](/de/blog/level-time-4-goals-public-api/), zeige ich, wie Level Time Goals über eine exportierte API an Level Time andockt und warum die beiden Addons getrennt sind. Wenn du das Ergebnis ausprobieren willst: Die [Level-Time-Seite](/de/page/level-time/) verlinkt CurseForge und GitHub.
