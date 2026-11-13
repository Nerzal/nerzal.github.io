---
draft: false
title: "Einführung in Hugo #1"
date: 2023-01-02T23:46:14+01:00
tags: ["tutorial", "hugo"]
description: "Starte mit Hugo, dem schnellsten Framework zum Erstellen von Websites. Lerne Installation, Theme-Erstellung und Deployment-Grundlagen."
images: ["img/hugo-logo-wide.svg"]
featured_image: "img/hugo-logo-wide.svg"
toc: true
---

## Was ist Hugo?

Hugo ist ein Static-Site-Generator, der mehrere Vorteile beim Erstellen schneller und sicherer Websites bietet.

Er hat eine schnelle Build-Zeit, was ihn ideal für das schnelle Generieren großer Seiten macht. Seine intuitive Oberfläche und unkomplizierte Verzeichnisstruktur erleichtern den Einstieg für neue Benutzer. Darüber hinaus bietet Hugo Flexibilität durch Templates, Shortcodes und benutzerdefinierte Ausgabeformate und kann einfach auf einer Vielzahl von Hosting-Plattformen deployt werden.

Hugo eignet sich auch gut für große Seiten und ist sicherer als dynamische Seiten, weil es statische HTML-Dateien generiert. Insgesamt ist Hugo eine beliebte Wahl für Entwickler und Content-Creator, die effiziente und sichere Websites erstellen möchten.

## Warum Hugo verwenden?

1. **Geschwindigkeit**: Hugo ist für Schnelligkeit ausgelegt, mit einer Build-Zeit von Millisekunden für Seiten mit Tausenden von Seiten. Das macht ihn ideal für das schnelle Generieren großer Seiten. Außerdem führen statische HTML-Dateien oft zu blitzschnellen Ladezeiten, was zu guten [PageSpeedInsights](https://pagespeed.web.dev/)-Scores führt.

2. **Benutzerfreundlichkeit**: Hugo hat eine einfache und intuitive Oberfläche mit einer unkomplizierten Verzeichnisstruktur und Markdown-basierten Inhaltsdateien. Das macht es einfach für neue Benutzer, mit Hugo anzufangen.

3. **Flexibilität**: Hugo erlaubt es, Seiten mit Templates, Shortcodes und benutzerdefinierten Ausgabeformaten anzupassen. Das macht es einfach, eine Seite zu erstellen, die deinen spezifischen Bedürfnissen entspricht.

4. **Portabilität**: Hugo-Seiten können einfach auf einer Vielzahl von Hosting-Plattformen deployt werden, einschließlich GitHub Pages, Amazon S3 und Netlify. Das macht es einfach, die Seite dort zu hosten, wo man es bevorzugt.

5. **Skalierbarkeit**: Hugo ist dafür ausgelegt, große Seiten problemlos zu verwalten, was es einfach macht, die Seite zu skalieren, wenn sie wächst.

6. **Sicherheit**: Hugo generiert statische HTML-Dateien, was bedeutet, dass es keine dynamischen Elemente oder Datenbankabfragen gibt. Das macht Hugo-Seiten sicherer und weniger anfällig für Angriffe.

## Hugo installieren

Um die volle Funktionalität zu gewährleisten – besonders wenn dein Theme Sass/SCSS verwendet – empfiehlt es sich, die **Hugo Extended**-Version zu installieren.

### Hugo Extended installieren

{{< os-tabs >}}
{{< os-tab "Windows (PowerShell)" >}}

Der einfachste Weg, Hugo Extended unter Windows zu installieren, ist **Winget** (Windows Package Manager), der in modernem Windows 10/11 integriert ist.

1.  Öffne PowerShell oder Eingabeaufforderung als Administrator.
2.  Führe den folgenden Befehl aus:

    ```powershell
    winget install Hugo.Hugo.Extended
    ```

3.  Starte dein Terminal neu, um sicherzustellen, dass der neue PATH geladen wird.

{{< /os-tab >}}
{{< os-tab "macOS" >}}

Unter macOS geht es am einfachsten mit [Homebrew](https://brew.sh/). Die `hugo`-Formel installiert die Extended-Edition:

```bash
brew install hugo
```

{{< /os-tab >}}
{{< os-tab "Linux" >}}

Für Debian-basierte Systeme (wie Ubuntu):
1.  Lade die neueste Hugo Extended `.deb`-Datei von der [Hugo-Releases-Seite](https://github.com/gohugoio/hugo/releases) herunter. Suche nach `hugo_extended_VERSION_linux-amd64.deb`.
2.  Installiere sie mit `dpkg`:

    ```bash
    sudo dpkg -i /path/to/hugo_extended_VERSION_linux-amd64.deb
    ```

Für andere Linux-Distributionen kannst du das Tarball herunterladen:
1.  Lade `hugo_extended_VERSION_linux-amd64.tar.gz` von der [Hugo-Releases-Seite](https://github.com/gohugoio/hugo/releases) herunter.
2.  Entpacke es und verschiebe die ausführbare Datei in deinen PATH:

    ```bash
    tar -xf hugo_extended_VERSION_linux-amd64.tar.gz
    sudo mv hugo /usr/local/bin/
    ```

{{< /os-tab >}}
{{< /os-tabs >}}

### Installation überprüfen

Öffne nach der Installation dein Terminal und führe aus:

```bash
hugo version
```

Du solltest die installierte Hugo-Version sehen, z.B. `hugo v0.170.0-...+extended`. Das neueste Release samt Changelog findest du jederzeit auf der [Hugo-Releases-Seite](https://github.com/gohugoio/hugo/releases).

## Docker verwenden

Anstatt Hugo lokal auf deinem Rechner zu installieren, kannst du das offizielle Hugo-Container-Image [`ghcr.io/gohugoio/hugo`](https://github.com/gohugoio/hugo/pkgs/container/hugo) verwenden. Es enthält bereits die Extended-Edition, Dart Sass, Git und Node.js. Dafür muss [Docker](https://docs.docker.com/get-started/get-docker/) installiert sein.

### Entwicklungsserver im Container

Für die lokale Entwicklung bindest du dein Site-Verzeichnis in den Container ein und startest `hugo server`. Der Container lauscht auf Port `1313`, deshalb musst du diesen Port mit `-p 1313:1313` freigeben. `--bind 0.0.0.0` sorgt dafür, dass der Server von außerhalb des Containers erreichbar ist:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
docker run --rm -it \
  -v "$(pwd)":/project \
  -u "$(id -u):$(id -g)" \
  -p 1313:1313 \
  ghcr.io/gohugoio/hugo:v0.170.0 \
  server --bind 0.0.0.0
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
docker run --rm -it `
  -v "${PWD}:/project" `
  -p 1313:1313 `
  ghcr.io/gohugoio/hugo:v0.170.0 `
  server --bind 0.0.0.0
```

{{< /os-tab >}}
{{< /os-tabs >}}

`hugo server` ist ein Entwicklungsserver mit Live-Reload. Er ist nicht dafür gedacht, eine Website in Produktion auszuliefern.

### Produktions-Image

In Produktion soll Hugo die Seite nur **bauen**. Die generierten statischen Dateien in `public/` liefert dann ein normaler Webserver wie [nginx](https://hub.docker.com/_/nginx) aus. Ein [Multi-Stage-Build](https://docs.docker.com/build/building/multi-stage/) hält Hugo aus dem finalen Image heraus:

```dockerfile
# Stage 1: statische Seite mit dem offiziellen Hugo-Image bauen
FROM ghcr.io/gohugoio/hugo:v0.170.0 AS build

# Das Image läuft standardmäßig als unprivilegierter User "hugo". Diese Stage
# wird nach dem Build verworfen, daher wechseln wir zu root, um in /src schreiben zu können.
USER root
WORKDIR /src
COPY . .
RUN hugo build --minify

# Stage 2: generierte Dateien mit nginx ausliefern
FROM nginx:stable-alpine

COPY --from=build /src/public /usr/share/nginx/html

EXPOSE 80
```

Lege das `Dockerfile` in das Wurzelverzeichnis deiner Hugo-Seite und baue das Image:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
cd pfad/zu/deiner/seite
docker build -t my-hugo-site .
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
cd pfad\zu\deiner\seite
docker build -t my-hugo-site .
```

{{< /os-tab >}}
{{< /os-tabs >}}

Wenn das Image erfolgreich gebaut wurde, startest du den Container und leitest Port `8080` deines Rechners auf Port `80` von nginx weiter:

```bash
docker run --rm -p 8080:80 my-hugo-site
```

Der Befehl ist in Bash und PowerShell identisch. Deine Seite ist jetzt unter [http://localhost:8080/](http://localhost:8080/) erreichbar.

## Eine neue Website erstellen

Um eine neue Website zu erstellen, führe einfach folgenden Befehl aus:

```bash
hugo new site example.com
```

Der Befehl ist wie folgt aufgebaut:

```bash
hugo(cli) new (Befehl) site (Parameter) siteName (Parameter)
```

Dadurch wird eine neue Ordnerstruktur für deine Seite erstellt. Wechsle hinein, alle folgenden Befehle werden im Site-Verzeichnis ausgeführt:

```bash
cd example.com
```

Wenn du die Ausgabe des Create-Befehls betrachtest, sagt Hugo dir etwas wie das Folgende:

```text
Just a few more steps...

1. Change the current directory to example.com.
2. Create or install a theme:
   - Create a new theme with the command "hugo new theme <THEMENAME>"
   - Or, install a theme from https://themes.gohugo.io/
3. Edit hugo.toml, setting the "theme" property to the theme name.
4. Create new content with the command "hugo new content <SECTIONNAME>/<FILENAME>.<FORMAT>".
5. Start the embedded web server with the command "hugo server --buildDrafts".

See documentation at https://gohugo.io/.
```

### Ein neues Theme erstellen

Du kannst jetzt entweder ein Hugo-Theme aus dem [Hugo-Theme-Verzeichnis](https://themes.gohugo.io/) herunterladen oder dein ganz eigenes Theme erstellen. In dieser Tutorial-Reihe werden wir unser eigenes Theme erstellen.

Also verwenden wir folgenden Befehl, während wir uns im Site-Verzeichnis befinden:

```bash
hugo new theme my-theme
```

Dadurch wird die vollständige Ordnerstruktur für dein Theme in `themes/my-theme` erstellt.

Hugo verwendet ein Theme nicht automatisch, nur weil es im `themes`-Ordner liegt. Du musst es aktivieren, indem du folgende Zeile zur `hugo.toml` in deinem Site-Verzeichnis hinzufügst:

```toml
theme = 'my-theme'
```

### Hello World

Bevor wir endlich etwas rendern können, haben wir noch zwei Dinge zu tun.

Seit [Hugo v0.146.0](https://github.com/gohugoio/hugo/releases/tag/v0.146.0) verwendet ein Theme das neue Template-System (siehe [Template Lookup Order](https://gohugo.io/templates/lookup-order/)). Das Grundgerüst besteht aus `layouts/baseof.html`, der HTML-Hülle, von der jede Seite erbt, und spezialisierten Templates wie `layouts/home.html` für die Startseite. `baseof.html` definiert einen `main`-Block, den die anderen Templates füllen.

Als ersten Schritt ersetzen wir den Inhalt der **home.html**-Datei, die sich in example.com (Site-Verzeichnis) -> themes -> my-theme -> layouts -> home.html befindet, durch Folgendes:

```go-html-template
{{ define "main" }}
  {{ .Content }}
{{ end }}
```

`{{ .Content }}` ist eine Template-Aktion, die einfach den Markdown-Inhalt einer Datei in HTML rendert. Es gibt noch viel mehr über Templates, Shortcodes usw. zu erklären, aber für jetzt ist es nur wichtig, dass dadurch der Markdown-Inhalt deiner Datei in HTML umgewandelt wird.

Jetzt brauchen wir eine Inhaltsdatei zum Rendern. Verwende folgenden Befehl:

```bash
hugo new content _index.md
```

Dieser Befehl erstellt eine neue Datei mit dem angegebenen Pfad im `content`-Verzeichnis. `_index.md` ist die Inhaltsdatei der Startseite.

Deine Datei sollte jetzt so aussehen. Der Standard-Archetype verwendet [TOML-Front-Matter](https://gohugo.io/content-management/front-matter/), eingeschlossen von `+++`:

```toml
+++
date = '2026-11-13T17:29:35+01:00'
draft = true
title = ''
+++
```

`title` ist der Titel der Seite.
`date` ist das Erstellungsdatum der Seite.
`draft` steuert, ob diese Seite veröffentlicht werden soll oder nicht.

Fügen wir eine schöne Begrüßung zu unserer ersten Seite hinzu. Du kannst eine beliebige Begrüßung wählen, ich nehme den Klassiker.

```markdown
+++
date = '2026-11-13T17:29:35+01:00'
draft = true
title = 'Meine erste Seite'
+++

## Hello World!

Es ist **sehr schön**, dich kennenzulernen!
```

Wir haben den letzten Schritt erreicht. Jetzt können wir einen Hugo-Server starten, um zu sehen, was wir erreicht haben. Verwende folgenden Befehl:

```bash
hugo server -D
```

Dieser Befehl startet einen Server im Entwicklungsmodus, der auch Seiten im Draft-Status enthält (`-D` ist die Kurzform von `--buildDrafts`). Besuche jetzt [http://localhost:1313/](http://localhost:1313/) in deinem Browser.

{{< image image="/img/hugo-world.png" imageAlt="Bild des Hello-World-Ergebnisses" >}}
