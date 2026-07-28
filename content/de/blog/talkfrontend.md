---
draft: false
title: "talkfrontend: Vortragsfolien als Markdown statt PowerPoint"
seo_title: "talkfrontend: Vorträge als Markdown"
date: 2026-07-28T00:00:00+00:00
tags: ["react", "typescript", "open-source", "developer-tooling", "showcase"]
description: "Eine Open-Source React-Web-App, die Markdown-Dateien in Fullscreen-Vortragsfolien verwandelt – ganz ohne Rebuild für neue Vorträge."
images: ["img/talkfrontend.svg"]
featured_image: "img/talkfrontend.svg"
toc: true
---

Jedes Mal, wenn ich einen Konferenzvortrag vorbereite, nervt mich dasselbe: PowerPoint und Keynote sind für Office-Dokumente gebaut, nicht für Entwickler-Content. Code-Snippets werden von der Autokorrektur verhunzt, Syntax-Highlighting ist manuelle Fleißarbeit, und jede Folie liegt als undurchsichtige Binärdatei vor, die sich kaum diffen, reviewen oder in Git versionieren lässt.

Deshalb habe ich **[talkfrontend](https://github.com/Nerzal/talkfrontend)** gebaut – einen schlanken Web-Viewer für Vortragsfolien. Präsentation im gewohnten Stil, aber als React-Web-App statt als Office-Dokument. Folien werden als reines Markdown geschrieben und zur Laufzeit geladen, sodass das Veröffentlichen eines neuen Vortrags nie einen Rebuild oder Redeploy der App selbst erfordert.

Live im Einsatz siehst du es mit meinem eigenen Vortragsarchiv, das bis 2021 zurückreicht, unter **[talks.noobygames.de](https://talks.noobygames.de)** – auch von meiner [Vorträge & Podcasts-Seite](/de/page/talks/) aus verlinkt.

## Warum Markdown-Folien?

Ein Foliensatz ist Entwickler-Content. Er verdient Entwickler-Tooling:

- **Git-freundlich** – Vorträge sind reiner Text, `git diff` zeigt also tatsächlich, was sich zwischen zwei Versionen eines Vortrags geändert hat.
- **Portabel** – eine `talk.md`-Datei kann von jedem Tool gelesen, bearbeitet oder generiert werden, auch von einem LLM, ohne ein Binärformat anzufassen.
- **Kein Vendor-Lock-in** – kein proprietäres `.pptx`/`.key`-Format, keine Lizenz nötig, um einen Vortrag anzusehen oder zu bearbeiten.
- **Korrekter Code by construction** – Snippets sind eingezäunte Markdown-Codeblöcke, sie werden also nie stillschweigend "smart" umformatiert, wie es Textverarbeitungen gerne tun.

## Wie es funktioniert

talkfrontend trennt App und Daten strikt. Die App (ein statischer React-Build) enthält selbst keinerlei Vortragsinhalte – Vorträge werden zur Laufzeit per HTTP aus einem konfigurierbaren Verzeichnis geladen:

```text
/                 → Jahresübersicht
/:year            → Monatsübersicht für ein Jahr
/:year/:month     → Vortragsliste für einen Monat
/talk/:id         → Fullscreen-Präsentation
```

Dieses Datenverzeichnis braucht genau drei Dinge:

- eine `index.json` – ein Array aller Vortrags-IDs
- eine `default-slides.md` – die Intro-/End-Folien, die automatisch jedem Vortrag voran- bzw. nachgestellt werden
- pro Vortrags-ID ein `<id>/talk.md` – der eigentliche Vortrag in Markdown

Weil die App das zur Laufzeit lädt statt es beim Build zu bündeln, ist das Veröffentlichen eines neuen Vortrags ein Zwei-Schritte-Vorgang: eine neue `<id>/talk.md`-Datei neben die anderen legen und ihre ID in `index.json` eintragen. Keine CI-Pipeline, kein Rebuild, kein Redeploy.

## Einen Vortrag schreiben

Eine `talk.md`-Datei beginnt mit einem YAML-Frontmatter-Block für die Metadaten des Vortrags, gefolgt von den Folien. Jede Folie beginnt mit einer Trennzeile – `--- <layout>` – mehr braucht es nicht, kein schließendes Trennzeichen:

````markdown
---
id: my-talk-2026-01
title: My Talk
description: Short description
year: 2026
month: 1
tags: [example]
---

--- title
# My Talk

## Subtitle

--- content
# Agenda

- Point 1
- Point 2

--- code
# Example

```go
func main() {
  fmt.Println("hi")
}
```
````

Das ist bereits das gesamte Format. `title`, `content`, `code`, `image` und `blank`-Folien sind reines Markdown – eine Überschrift, eine Bullet-Liste, ein eingezäunter Codeblock, ein Bild oder freier Fließtext. `table` und `speaker` tragen strukturierte Daten, die sich nicht sauber auf Fließtext abbilden lassen (Tabellenzeilen, Social-Links mit QR-Codes) – diese beiden Folientypen werden deshalb als reines YAML geschrieben, ganz ohne Wrapper-Syntax:

```yaml
--- table
title: CREATE
statement: "INSERT INTO people VALUES (1, 'Alice', 'active')"
columns: [id, name, status]
rows:
  - cells: ['1', 'Alice', 'active']
    variant: highlight
caption: A new row.
```

Jede Vortragsdatei wird in der CI validiert: `src/data/schema.test.ts` parst jede `talk.md` und prüft sie gegen ein JSON Schema (generiert aus den TypeScript-Typen via `make schema`) mit [ajv](https://ajv.js.org/). Eine ungültige Vortragsdatei lässt die Testsuite fehlschlagen, bevor sie jemals live geht.

## Acht Folien-Layouts

| Layout | Zweck |
| --- | --- |
| `title` | Eröffnungsfolie eines Vortrags oder Abschnitts |
| `content` | Bullet-Point-Listen, optional mit Click-to-reveal-Fragmenten |
| `code` | Syntax-highlighteter Code, optional mit animierten Schritt-für-Schritt-Übergängen |
| `image` | Ein einzelnes Bild, folienfüllend |
| `blank` | Freier Text – Q&A, Abschnittstrenner, Schlussworte |
| `table` | Strukturierte Tabellendaten, inklusive eines ASCII-Art-Animationsmodus für SQL-artige Demos |
| `speaker` | Foto, Fakten und Social-Links mit generierten QR-Codes |
| `mixed` | Überschrift, Bullets, Absatz und Code frei kombiniert auf einer Folie |

Ein paar davon verdienen einen genaueren Blick:

**Animierte Code-Walkthroughs.** Eine `code`-Folie kann mehrere Versionen eines Snippets enthalten, die sich Schritt für Schritt ineinander verwandeln – ähnlich wie [Slidevs Shiki Magic Move](https://sli.dev/features/shiki-magic-move). Das läuft über [Shiki](https://shiki.style/) und [`@shikijs/magic-move`](https://github.com/shikijs/shiki/tree/main/packages/magic-move), lazy-geladen, damit es die Bundle-Größe der Haupt-App für Vorträge ohne diese Funktion nicht beeinflusst. Normales Code-Highlighting (ohne Animation) läuft über [Prism.js](https://prismjs.com/), zur Build-Zeit gebündelt – kein CDN-Request zur Laufzeit.

**Click-Fragmente.** In einer `content`- oder `mixed`-Folie lässt sich ein Bullet mit `->` statt einem einfachen `-` markieren, um ihn erst per Klick/Pfeiltaste einzublenden, statt die komplette Liste sofort zu zeigen – praktisch, wenn die Aufmerksamkeit des Publikums erst auf einem Punkt liegen soll, bevor der nächste kommt.

**Speaker-Folien mit selbst gehosteten QR-Codes.** Das `speaker`-Layout akzeptiert die Felder `website`, `linkedin`, `github`, `twitter`, `bluesky` und `mastodon`. Zu jedem konfigurierten Link wird ein eigener QR-Code generiert, damit das Publikum ihn direkt vom Beamer abscannen kann, dazu ein Marken-Icon, sofern eines verfügbar ist. Die Icons stammen aus dem CC0-lizenzierten [simple-icons](https://simpleicons.org/)-Paket und werden zur Build-Zeit gebündelt – zur Laufzeit wird nichts von einem Drittanbieter-CDN nachgeladen, es gibt also kein DSGVO-relevantes Tracking-Problem, nur weil eine Folie deine Social-Links zeigt.

**Gemeinsame Intro-/End-Folien.** Jeder Vortrag bekommt automatisch dieselbe gebrandete Intro- und "Danke"-Schlussfolie, einmal definiert in `default-slides.md` – die eigene Bio muss also nicht in jede neue `talk.md` kopiert werden.

## Präsentieren

Der Fullscreen-Modus reagiert sowohl auf Tastatur als auch auf Presenter-Fernbedienungen:

| Taste | Aktion |
| --- | --- |
| `→`, `Leertaste`, `Bild ab` | Nächste Folie |
| `←`, `Bild auf` | Vorherige Folie |
| `Esc` | Zurück zur Übersicht |

`Bild auf`/`Bild ab` deckt gängige Presenter-Fernbedienungen wie das Logitech Spotlight ab, sodass sich Folien steuern lassen, ohne das Trackpad anzufassen.

## Tech-Stack

- [React 19](https://react.dev/) + [TypeScript](https://www.typescriptlang.org/) + [Vite 6](https://vite.dev/)
- [Tailwind CSS v4](https://tailwindcss.com/) über das `@tailwindcss/vite`-Plugin – keine `tailwind.config.js`, Klassen werden automatisch aus dem Quellcode erkannt
- [React Router v7](https://reactrouter.com/) für das Jahr/Monat/Vortrag-Routing
- [js-yaml](https://github.com/nodeca/js-yaml) zum Parsen von Frontmatter und strukturiertem Folien-YAML
- [Vitest](https://vitest.dev/) und [Testing Library](https://testing-library.com/) für Tests
- [ESLint](https://eslint.org/) (Flat Config, typgeprüft) und [Prettier](https://prettier.io/) für Code-Qualität

## Self-Hosting mit Docker

Ein vorgebautes Image wird auf GHCR veröffentlicht: `ghcr.io/nerzal/talkfrontend`. Es kommt **ohne meine eigenen Vortragsdaten** – der Publish-Workflow baut das Image und tauscht `dist/talks` anschließend gegen ein generisches Platzhalter-Verzeichnis, bevor es gepusht wird. Es lässt sich also gefahrlos von jedem so verwenden. Vorträge werden vom Browser zur Laufzeit geladen, du kannst also eigene Daten liefern, ohne das Image überhaupt neu zu bauen – einfach ein Verzeichnis über `/app/dist/talks` bind-mounten:

**Linux / macOS:**

```bash
docker run -p 8080:8080 \
  -v $(pwd)/my-talks:/app/dist/talks:ro \
  ghcr.io/nerzal/talkfrontend:edge
```

**Windows (PowerShell):**

```powershell
docker run -p 8080:8080 `
  -v "${PWD}/my-talks:/app/dist/talks:ro" `
  ghcr.io/nerzal/talkfrontend:edge
```

Dein `my-talks`-Verzeichnis braucht dieselbe Struktur aus `index.json`, `default-slides.md` und `<id>/talk.md`, wie oben beschrieben.

Um Vorträge stattdessen zur Build-Zeit einzubacken – etwa wenn sie von einem anderen Origin ausgeliefert werden – übergib `VITE_TALKS_DIR` als Build-Argument mit einer absoluten URL:

```bash
docker build --build-arg VITE_TALKS_DIR=https://example.com/talks -t my-talkfrontend .
```

Verfügbare Image-Tags: `edge` (aktuellster `main`-Stand) sowie `1.2.3` / `1.2` / `1` / `latest` für getaggte Releases.

## Lokal ausführen

**Linux / macOS:**

```bash
git clone git@github.com:Nerzal/talkfrontend.git
cd talkfrontend
npm install
npm run dev
```

**Windows (PowerShell):**

```powershell
git clone git@github.com:Nerzal/talkfrontend.git
Set-Location talkfrontend
npm install
npm run dev
```

Der Dev-Server startet unter `http://localhost:5173`. Der eingebaute Vortrag `feature-tour-2026-07` demonstriert und erklärt jedes Layout direkt in der App – öffne ihn als lebende Referenz, während du deinen eigenen Vortrag schreibst.

## Live ausprobieren

Mein eigenes Vortragsarchiv läuft mit talkfrontend unter **[talks.noobygames.de](https://talks.noobygames.de)** – von TinyGo-IoT-Vorträgen bis zu Software-Architektur-Workshops, alles als reine Markdown-Dateien direkt aus einem Verzeichnis ausgeliefert. Wenn dich interessiert, wie ein echter, nicht-platzhalter Foliensatz end-to-end aussieht, findest du dort die Antwort. Eine textuelle Übersicht derselben Vorträge gibt es auf meiner [Vorträge & Podcasts-Seite](/de/page/talks/).

Der Quellcode liegt auf GitHub unter [github.com/Nerzal/talkfrontend](https://github.com/Nerzal/talkfrontend), MIT-lizenziert. Issues, Feature-Wünsche und Pull Requests sind willkommen.
