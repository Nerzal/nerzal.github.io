---
draft: false
title: "Building Neuroclip — Teil 4: KI-Facecam mit Real-ESRGAN (und warum nicht CodeFormer)"
seo_title: "Facecam hochskalieren mit Real-ESRGAN in Go"
date: 2026-12-06T08:00:00+01:00
tags:
  [
    "go",
    "real-esrgan",
    "ffmpeg",
    "upscaling",
    "open-source-lizenzen",
    "neuroclip",
    "videoverarbeitung",
  ]
categories: ["Software Engineering"]
series: ["Building Neuroclip"]
description: "Wie Neuroclip die kleine Facecam in Shorts schärft: externer Upscaler hinter einem Go-Interface, Cache, sicherer Rückfall und warum nicht CodeFormer."
images: ["img/neuroclip/og.png"]
featured_image: "img/neuroclip/facecam-nachher-460.jpg"
toc: true
---

> **Building Neuroclip, Teil 4 von 5.** Davor: [Teil 3: die OBS-Regie](/de/blog/neuroclip-3-obs-regie/). Weitere Teile: [Teil 1: Architektur](/de/blog/neuroclip-1-architecture/), [Teil 2: die VOD-zu-Short-Pipeline](/de/blog/neuroclip-2-vod-to-short-pipeline/), [Teil 5: Ausliefern auf Kubernetes](/de/blog/neuroclip-5-shipping-kubernetes/). Die Produktseite ist [Neuroclip](/de/page/neuroclip/) (Early Access, Single-User-Beta).

Ein Twitch-Stream hat 1920x1080 Pixel, und die Facecam in der Ecke ist klein, nur ein paar hundert Pixel breit. Ein Hochkant-Short ist 1080 Pixel breit, und das Layout zeigt die Cam als Streifen über die volle Breite. Das ist eine Vergrößerung um mehr als das Doppelte, und es sieht aus, wie du es dir vorstellst: weich, pixelig, ein bisschen traurig.

In diesem Artikel geht es um das Feature, das ich dagegen gebaut habe, und um drei Engineering-Entscheidungen, die ich spannender finde als das KI-Modell selbst:

1. **Umfang**: nur den Cam-Ausschnitt hochskalieren, nie das Spiel.
2. **Grenzen**: das Modell als externes Programm hinter einem kleinen Interface betreiben, mit Cache und einem Rückfall, der einen Render nie kaputtmachen kann.
3. **Lizenz**: warum ich Real-ESRGAN statt CodeFormer gewählt habe, obwohl Gesichts-Restauration auf den ersten Blick besser passt.

Neuroclip ist mein eigenes Werkzeug für Streamer (siehe [Teil 1](/de/blog/neuroclip-1-architecture/)). Es ist im Early Access, und ich bin bisher der einzige Nutzer. Nimm alles Folgende also als „läuft bei mir, an einem Gesicht“.

## Das Problem: kleiner Ausschnitt auf breitem Streifen

Die Rechnung ist simpel: ein paar hundert Pixel Quelle müssen 1080 Pixel Ausgabe füllen. Der [`scale`-Filter](https://ffmpeg.org/ffmpeg-filters.html#scale-1) von ffmpeg mit Lanczos macht das ordentlich, kann aber keine Details erfinden, die der Stream-Encoder schon weggeworfen hat. Heraus kommt ein glattes, aber unscharfes Gesicht.

Ich habe vier Optionen erwogen, und die letzte Zeile hat gewonnen:

| Option | Warum nicht (oder warum doch) |
| --- | --- |
| Stream-Bitrate oder Cam-Größe erhöhen | Ändert den Live-Stream, hilft nur künftigen Streams |
| Den ganzen Clip hochskalieren | Volle Bilder durch ein neuronales Netz sind viel zu langsam, und das Spiel braucht es nicht |
| Gesichts-Restaurationsmodell (CodeFormer) | Für Gesichter gemacht, aber ein Lizenzproblem (dazu unten mehr) |
| **Allgemeine Super-Resolution nur auf dem Cam-Ausschnitt** | Kleine Eingabe, klarer Umfang, freizügige Lizenz |

## Der Ansatz in einem Bild

{{< diagram src="neuroclip-4-upscale-flow.svg" caption="Datenfluss der KI-Facecam: ausschneiden, in einem externen Prozess hochskalieren, in eine Cache-Datei kodieren und dem Short-Render als zweiten Eingang geben." >}}

Auf Kasten-und-Pfeil-Ebene:

1. **Bilder auslesen.** ffmpeg schneidet den Kamera-Ausschnitt aus der Quelle und schreibt Einzelbilder. Ausgelesen werden nur die Stücke, die im Short wirklich zu sehen sind, und die Bildrate ist begrenzt, weil die Cam nicht mehr braucht.
2. **Hochskalieren.** Ein externes Super-Resolution-Programm läuft auf der GPU über den Ordner mit den Bildern.
3. **Kodieren.** ffmpeg setzt die Bilder wieder auf die Zeitachse der Quelle und kodiert sie zu einem kleinen Zwischenvideo. Optional wird die normale Vergrößerung dazugemischt, damit sich der Effekt abschwächen lässt.
4. **Cache.** Das Ergebnis wird unter einem Schlüssel abgelegt, der alles enthält, was es beeinflusst: Quelle, Ausschnitt, sichtbare Stücke und Einstellungen. Ein erneuter Render desselben Clips nimmt die Datei aus dem Cache.
5. **Render.** Der Short-Render bekommt diese Datei als zusätzlichen Eingang und nutzt sie statt des normal vergrößerten Ausschnitts.

Eine Entwurfsentscheidung hält Schnitte, Zeitlupe und Intros funktionsfähig: Die hochskalierte Cam wird an das Quellbild angehängt und hat keine eigene Zeitlogik, sodass alles danach beide Teile gleich behandelt. Die ffmpeg-Filter [`pad`](https://ffmpeg.org/ffmpeg-filters.html#pad-1) und [`overlay`](https://ffmpeg.org/ffmpeg-filters.html#overlay-1) sind die Bausteine für so einen Trick.

## Warum ein externes Programm hinter einem Interface

Real-ESRGAN ist als Python/PyTorch-Projekt gestartet. Davon wollte ich nichts auf dem Rechner eines Streamers: keine Python-Umgebung und keine CUDA-Toolchain. Das [Real-ESRGAN-Repository](https://github.com/xinntao/Real-ESRGAN) liefert zusätzlich ein portables Programm auf Basis von [ncnn](https://github.com/Tencent/ncnn), das auf Vulkan-fähigen GPUs läuft. Die Installation steht in der README.

Die Go-Seite behandelt den Upscaler deshalb als Nahtstelle. Eine generische Version der Idee sieht so aus:

```go
// Upscaler enlarges a folder of frames into another folder.
// It is the seam for other engines and for fakes in tests.
type Upscaler interface {
    Upscale(ctx context.Context, inputDir, outputDir string) error
}

type ExternalTool struct{ Executable string }

func (tool ExternalTool) Upscale(ctx context.Context, inputDir, outputDir string) error {
    command := exec.CommandContext(ctx, tool.Executable, "-i", inputDir, "-o", outputDir)
    return command.Run()
}
```

Die Flags unterscheiden sich je Programm, prüfe also die des Programms, das du nutzt. Was mir an diesem Aufbau gefällt:

- **Ordner rein, Ordner raus.** Keine Pipes, kein eigenes Protokoll, leicht zu debuggen, weil du einfach in die Ordner schauen kannst.
- **Der Context beendet den Prozess.** Mit [`exec.CommandContext`](https://pkg.go.dev/os/exec#CommandContext) stoppt ein abgebrochener Render auch den GPU-Job. Das vergisst man beim Aufruf externer Programme leicht.
- **Tests nutzen eine Attrappe.** Weil Aufrufer nur das Interface kennen, lassen sich Cache und Rückfall ohne GPU testen, und eine künftige Engine ist nur eine weitere Umsetzung.

Die Aufrufstelle folgt derselben Disziplin wie überall bei mir: Sie integriert und entscheidet nur, die schwere Arbeit steckt in Funktionen, die nur operieren. **Jeder Fehlerpfad gibt die ursprünglichen, unveränderten Optionen zurück**, sodass kein Fehler nach oben durchschlägt und den Render abbricht.

## Sauberer Rückfall

{{< diagram src="neuroclip-4-fallback.svg" caption="Jeder Nein-Zweig endet in einem normalen Render mit einer Protokollzeile, die den Grund nennt. Der Cache wird geprüft, bevor das Programm überhaupt gesucht wird." >}}

Alles, was schiefgeht, fällt auf einen normalen Render zurück: Programm oder Modelle fehlen, der Lauf schlägt fehl, die Platte ist voll, der Job würde unverhältnismäßig lange dauern, oder das Layout hat schlicht keine Verwendung für eine größere Cam. In allen Fällen wird der Short wie gewohnt gerendert, und das Protokoll nennt den Grund. Bei einem Werkzeug, das unbeaufsichtigt rendern kann, ist mir „Cam etwas weicher, Video ist da“ immer lieber als „kein Video“.

Das Feature ist außerdem **standardmäßig aus**. Es ist langsam, also schalte ich es gezielt für ausgewählte Top-Shorts ein und rendere nie während eines Streams. Auf meiner Laptop-GPU braucht das gute Modell Minuten statt Sekunden pro Short, deshalb ist der Cache wichtig: Ein erneuter Render desselben Clips geht schnell.

## Der A/B-Test

Dasselbe Bild, beide Wege gerendert:

<div style="display:flex;gap:1rem;flex-wrap:wrap">
<figure style="margin:0;flex:1 1 220px">
<img src="/img/neuroclip/facecam-vorher-460.jpg" alt="Facecam-Ausschnitt mit dem normalen Scale-Filter vergrößert, weich und pixelig" loading="lazy" style="width:100%;height:auto">
<figcaption>Vorher: normale Vergrößerung</figcaption>
</figure>
<figure style="margin:0;flex:1 1 220px">
<img src="/img/neuroclip/facecam-nachher-460.jpg" alt="Derselbe Facecam-Ausschnitt nach dem Hochskalieren mit Real-ESRGAN, schärfer als die normale Vergrößerung" loading="lazy" style="width:100%;height:auto">
<figcaption>Nachher: Real-ESRGAN</figcaption>
</figure>
</div>

Auf den Bildern bin ich selbst zu sehen. Ich habe ein allgemeines Modell mit einem leichteren, auf Anime ausgelegten verglichen. Das allgemeine sah klar am besten aus, das Anime-Modell wirkte auf Gesichtern wachsig und gemalt. Am natürlichsten fand ich es, das KI-Bild mit der normalen Vergrößerung zu mischen, statt es mit voller Stärke zu nutzen. Das ist der Eindruck einer einzelnen Person an einem einzigen Gesicht, bitte lies es also nicht als Benchmark.

## Warum nicht CodeFormer

[CodeFormer](https://github.com/sczhou/CodeFormer) ist ein Modell zur Gesichts-Restauration und für eine Facecam das naheliegendere Werkzeug. Ich habe es mir angesehen und mich dagegen entschieden, weil es nach meinem Verständnis seiner Lizenz nur für nichtkommerzielle Nutzung gedacht ist, was sich nicht mit meinem Ziel verträgt, Neuroclip irgendwann zu verkaufen. [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) steht unter freizügigen Lizenzen. **Lies beide Lizenzen bitte selbst**, statt meiner Einzeiler-Zusammenfassung zu vertrauen: Lizenzen ändern sich, Modelle und Code können unterschiedlich lizenziert sein, und dein Anwendungsfall kann von meinem abweichen. CodeFormer habe ich nicht ausprobiert, daher mache ich keine Aussage zu seiner Qualität im Vergleich zu Real-ESRGAN.

### Lizenzentscheidungen in der CI durchsetzen

Lizenz-Überlegungen helfen nur, wenn sie durchgesetzt werden. Ein kleines Skript in der CI, das auflistet, was wirklich in deine Artefakte gelinkt oder gebündelt wird, und bei Copyleft-Lizenzen fehlschlägt, die du nicht akzeptieren kannst, ist eine billige Versicherung. Go linkt statisch, Copyleft würde also im Binary landen. Ein externes Programm, das du als Prozess startest, ist eine andere Grenze und braucht eine manuelle Entscheidung. Wenn du etwas Ähnliches baust, mach diese Grenze explizit. Mehr dazu, was alles in einem Go-Binary landet, steht in [check-static-linking](/de/blog/check-static-linking/).

## Gelernt

- **Zuerst die Eingabe verkleinern.** Die Eingabe vom ganzen Bild auf die sichtbaren Stücke eines kleinen Ausschnitts zu verkleinern, macht aus einer unmöglichen Aufgabe eine machbare.
- **Das Langsame und Optionale gehört hinter ein Interface und einen Cache.** Alles, was schiefgehen kann, fällt auf den billigen Weg zurück.
- **Kläre Lizenzen, bevor du dich in ein Modell verliebst.** Die schönste Option ist wertlos, wenn du sie nicht ausliefern darfst.
- **Messen.** Ein A/B-Test hat die Modellwahl an einem Nachmittag entschieden.

## Wie es weitergeht

In [Teil 5](/de/blog/neuroclip-5-shipping-kubernetes/) geht es ums Ausliefern von Neuroclip: Container-Images, Kubernetes und wie Releases verifiziert werden. Wenn du streamst und den Early Access ausprobieren willst, schau auf die [Neuroclip-Seite](/de/page/neuroclip/).
