---
draft: false
title: "Einführung in Hugo #1"
date: 2023-01-02T23:46:14+01:00
tags: ["tutorial", "hugo"]
description: "Starte mit Hugo, dem schnellsten Framework zum Erstellen von Websites. Lerne Installation, Theme-Erstellung und Deployment-Grundlagen."
images: ["hugo-logo-wide.svg"]
featured_image: "hugo-logo-wide.svg"
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

### Unter Windows installieren (empfohlen)

Der einfachste Weg, Hugo Extended unter Windows zu installieren, ist **Winget** (Windows Package Manager), der in modernem Windows 10/11 integriert ist.

1.  Öffne PowerShell oder Eingabeaufforderung als Administrator.
2.  Führe den folgenden Befehl aus:
    ```powershell
    winget install Hugo.Hugo.Extended
    ```
3.  Starte dein Terminal neu, um sicherzustellen, dass der neue PATH geladen wird.

### Unter Linux installieren

Für Debian-basierte Systeme (wie Ubuntu):
1.  Lade die neueste Hugo Extended `.deb`-Datei von der Hugo Releases-Seite herunter. Suche nach `hugo_extended_VERSION_linux-amd64.deb`.
2.  Installiere sie mit `dpkg`:
    ```bash
    sudo dpkg -i /path/to/hugo_extended_VERSION_linux-amd64.deb
    ```

Für andere Linux-Distributionen kannst du das Tarball herunterladen:
1.  Lade `hugo_extended_VERSION_linux-amd64.tar.gz` von der Hugo Releases-Seite herunter.
2.  Entpacke es und verschiebe die ausführbare Datei in deinen PATH:
    ```bash
    tar -xf hugo_extended_VERSION_linux-amd64.tar.gz
    sudo mv hugo /usr/local/bin/
    ```

### Installation überprüfen

Öffne nach der Installation dein Terminal und führe aus:

```bash
hugo version
```
Du solltest die installierte Hugo-Version sehen, z.B. `hugo v0.124.1+extended`.

## Docker verwenden

Anstatt Hugo lokal auf deinem Rechner zu installieren, kannst du einen Docker-Container verwenden.

Beispiel:

```docker
FROM alpine:latest as build

ENV HUGO_VERSION 0.124.1

RUN wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    tar -xf hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    rm hugo_${HUGO_VERSION}_linux-amd64.tar.gz && \
    mv hugo /usr/local/bin/hugo

FROM gcr.io/distroless/static:nonroot
USER nonroot

COPY --from=build /usr/local/bin/hugo /usr/local/bin/hugo
COPY noobygames.de /site
WORKDIR /site

EXPOSE 80

ENTRYPOINT ["hugo", "server", "-p", "1313", "--bind", "0.0.0.0"]
```

Jetzt kannst du das Image mit folgenden Befehlen bauen:

> cd dein/pfad/wo/das/docker/file/ist
> docker build -t hugo-server .

Wenn das Image erfolgreich gebaut wurde, kannst du den Container mit folgendem Befehl starten:

> docker run hugo-server

## Eine neue Website erstellen

Um eine neue Website zu erstellen, führe einfach folgenden Befehl aus:

> hugo new site example.com

Der Befehl ist wie folgt aufgebaut:

> hugo(cli) new (Befehl) site (Parameter) siteName (Parameter)

Dadurch wird eine neue Ordnerstruktur für deine Seite erstellt.

Wenn du die Ausgabe des Create-Befehls betrachtest, sagt Hugo dir etwas wie das Folgende:

```bash

Just a few more steps and you're ready to go:

1. Download a theme into the same-named folder.
   Choose a theme from https://themes.gohugo.io/ or
   create your own with the "hugo new theme <THEMENAME>" command.
2. Perhaps you want to add some content. You can add single files
   with "hugo new <SECTIONNAME>/<FILENAME>.<FORMAT>".
3. Start the built-in live server via "hugo server".

Visit https://gohugo.io/ for quickstart guide and full documentation.
```

### Ein neues Theme erstellen

Du kannst jetzt entweder ein Hugo-Theme aus dem Internet herunterladen oder dein ganz eigenes Theme erstellen. In dieser Tutorial-Reihe werden wir unser eigenes Theme erstellen.

Also verwenden wir folgenden Befehl, während wir uns im Site-Verzeichnis befinden:

> hugo new theme my-theme

Dadurch wird die vollständige Ordnerstruktur für dein Theme erstellt.

### Hello World

Bevor wir endlich etwas rendern können, haben wir noch zwei Dinge zu tun.

Als ersten Schritt fügen wir folgende Zeile zur **index.html**-Datei hinzu, die sich in example.com (Site-Verzeichnis) -> themes -> my-theme -> layouts -> index.html befindet:

> {{ .Content }}

Das ist ein Template, das einfach den Markdown-Inhalt einer Datei in HTML rendert. Es gibt noch viel mehr über Templates, Shortcodes usw. zu erklären, aber für jetzt ist es nur wichtig, dass dadurch der Markdown-Inhalt deiner Datei in HTML umgewandelt wird.

Jetzt brauchen wir eine Inhaltsdatei zum Rendern. Verwende folgenden Befehl:

> hugo new _index.md

Dieser Befehl erstellt eine neue Datei mit dem angegebenen Pfad im Content-Verzeichnis.

Deine Datei sollte jetzt so aussehen:

```yaml
---
title: ""
date: 2023-01-05T23:13:47+01:00
draft: true
---
```

`title` ist der Titel der Seite.
`date` ist das Erstellungsdatum der Seite.
`draft` steuert, ob diese Seite veröffentlicht werden soll oder nicht.

Fügen wir eine schöne Begrüßung zu unserer ersten Seite hinzu. Du kannst eine beliebige Begrüßung wählen, ich nehme den Klassiker.

```yaml
---
title: "Meine erste Seite"
date: 2023-01-05T23:13:47+01:00
draft: true
---

## Hello World!

Es ist **sehr schön**, dich kennenzulernen!
```

Wir haben den letzten Schritt erreicht. Jetzt können wir einen Hugo-Server starten, um zu sehen, was wir erreicht haben. Verwende folgenden Befehl:

> hugo server -D

Dieser Befehl startet einen Server im Entwicklungsmodus, der auch Seiten im Draft-Status enthält. Besuche jetzt [http://localhost:1313/](http://localhost:1313/) in deinem Browser.

{{< image image="/img/hugo-world.png" imageAlt="Bild des Hello-World-Ergebnisses" >}}
