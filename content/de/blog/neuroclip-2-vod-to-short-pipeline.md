---
draft: false
title: "Building Neuroclip — Teil 2: Vom VOD zum Short — die ffmpeg-, Whisper- und Untertitel-Pipeline"
seo_title: "VOD zu Short: ffmpeg, Whisper und Untertitel mit Go"
date: 2026-11-15T08:00:00+01:00
tags:
  [
    "go",
    "ffmpeg",
    "whisper",
    "faster-whisper",
    "nvenc",
    "untertitel",
    "videobearbeitung",
    "neuroclip",
    "twitch",
  ]
categories: ["Software Engineering"]
series: ["Building Neuroclip"]
description: "Wie Neuroclip aus einem Twitch-VOD einen untertitelten 9:16-Short macht: Spracherkennung, Vorauswahl, ffmpeg-Filtergraphen und robuste Prozesssteuerung mit Go."
images: ["img/neuroclip/og.png"]
featured_image: "img/neuroclip/editor-1440.jpg"
toc: true
---

> **Building Neuroclip, Teil 2 von 5.** [Teil 1: die Architektur](/de/blog/neuroclip-1-architecture/) · **Teil 2: VOD zum Short (du bist hier)** · [Teil 3: die OBS-Regie](/de/blog/neuroclip-3-obs-regie/) · [Teil 4: KI-Facecam-Upscaling](/de/blog/neuroclip-4-facecam-upscaling/) · [Teil 5: Auslieferung auf Kubernetes](/de/blog/neuroclip-5-shipping-kubernetes/). Das Produkt selbst findest du auf der [Neuroclip-Seite](/de/page/neuroclip/); es ist im Early Access und ich bin bisher der einzige Nutzer.

{{< tldr >}}
- Neuroclip lädt Twitch-VODs (HLS-Playlists, RFC 8216) segmentweise selbst in Go, setzt sie mit ffmpeg ohne Neukodierung zusammen und schreibt zuletzt eine Metadatei als Commit-Marker.
- Die Transkription von Neuroclip nutzt faster-whisper auf einer eigenen Mikrospur (16 kHz, mono), mit Wort-Zeitstempeln, Sprachaktivitätserkennung und einem Vokabel-Prompt aus Namen des Spiels.
- Neuroclip wählt Short-Kandidaten mit deterministischem Go aus Lautstärke, Schlagwörtern, Chat-Ausschlägen, live gesetzten Markern und Zuschauer-Clips; Claude ist eine optionale Bewertungsschicht obendrauf.
- Das 9:16-Layout von Neuroclip ist ein ffmpeg-Filtergraph aus `split`, `crop`, `scale` und `vstack`, dazu kommen wortgenaue Untertitel, die aus einem ASS-Skript eingebrannt werden.
- Schlägt NVENC fehl, versucht der Neuroclip-Renderer es nur dann mit x264 erneut, wenn der Fehler auf Encoder, CUDA oder Treiber zeigt, nie bei Filtergraph-Fehlern oder abgebrochenen Jobs.
{{< /tldr >}}

In [Teil 1](/de/blog/neuroclip-1-architecture/) habe ich die Form von Neuroclip beschrieben: ein Go-Server, ein React-Dashboard und ein paar kleine Python-Helfer. Dieser Teil begleitet ein Stück Material durch diese Maschinerie: Eine mehrstündige Twitch-Aufnahme geht hinein, ein kurzes Hochformat-Video mit eingebrannten Wort-für-Wort-Untertiteln kommt heraus.

Neuroclip ist ein kommerzielles Produkt, deshalb bleibt dieser Beitrag auf Konzeptebene: die Ideen, die Abwägungen und die allgemeinen Techniken. Eine Bauanleitung ist es nicht. [ffmpeg](https://ffmpeg.org/documentation.html) und [Whisper](https://github.com/openai/whisper) erledigen die schwere Arbeit, und meine Arbeit steckt darin, wie ein Go-Programm sie steuert: lang laufende Kindprozesse abbrechbar halten, keine halbfertigen Dateien hinterlassen und dem Spiel, das auf derselben Maschine läuft, nicht im Weg stehen.

![Der Neuroclip-Projekt-Editor mit der Timeline eines Stream-Clips](/img/neuroclip/editor-1440.jpg)

*Der Projekt-Editor: der Ort, an dem das Ergebnis der Pipeline geprüft und korrigiert wird.*

{{< diagram src="neuroclip-2-pipeline.svg" caption="Die sechs Stufen vom VOD bis zur Abnahme. Gestrichelte Pfeile sind Eingaben, die eine Stufe steuern; die durchgezogene Kette ist der Datenfluss." >}}

## Stufe 1: Das VOD holen

Ein Twitch-VOD ist eine HLS-Playlist: eine Liste kurzer Mediensegmente, spezifiziert in [RFC 8216](https://www.rfc-editor.org/rfc/rfc8216). Neuroclip lädt sie selbst in Go herunter, statt einen Downloader aufzurufen. Die Gründe drehen sich alle um Fehlerbehandlung:

- Segmente werden zu mehreren gleichzeitig in einen Arbeitsordner geladen,
- ein Segment zählt erst, wenn es von einem temporären Namen umbenannt wurde, sodass ein abgebrochener Download dort weitermacht, wo er stehen geblieben ist,
- sind alle Segmente da, setzt ffmpeg sie **ohne Neukodierung** zusammen,
- eine kleine Metadatei wird zuletzt geschrieben, und ohne sie gilt das Video nicht als heruntergeladen.

Weil die Metadatei zuletzt geschrieben wird, ist sie ein billiger Commit-Marker. Jeder Code, der fragt „liegt dieses VOD lokal vor?“, schaut nach dem Marker und nie nach der großen Datei. Ein Absturz mittendrin kann also kein Video hinterlassen, das nur vollständig aussieht. Das Chatlog des Streams wird daneben geholt, weil die Vorauswahl es später braucht.

Vor dem Download schätzt der Code die Größe und prüft den freien Speicherplatz mit einem Sicherheitspuffer. Ein volles Laufwerk in der dritten Stunde eines Downloads ist ein Fehler, den du lieber als Meldung vor dem ersten Byte bekommst.

## Stufe 2: Audiospuren, oder warum das Mikro eine eigene bekommt

Die wertvollste Entscheidung für die Qualität der Transkription fällt in OBS, noch bevor Neuroclip ins Spiel kommt. Ich nehme mehrere Audiospuren auf: die Gesamtmischung, wie im Stream zu hören (als **erste** Spur, weil die meisten Clip-Werkzeuge standardmäßig den ersten Audiostream nehmen), das Mikrofon allein und das Spiel allein.

Ein Spracherkennungsmodell, das Spielexplosionen, Alert-Sounds und einen Freund im Call gleichzeitig hört, rät schlechter. Ihm nur das Mikrofon zu geben, ist deshalb der billigste Genauigkeitsgewinn, den es gibt. Hat die Quelle mehr als eine Audiospur, wird die Mikrospur in eine temporäre WAV-Datei (16 kHz, mono) extrahiert; sonst bleibt es bei der Mischung. Das ist schlichtes ffmpeg, und du kannst es an deiner eigenen Aufnahme ausprobieren:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# Die 2. Audiospur (Index ab 0 gezählt) als 16-kHz-Mono-WAV extrahieren
ffmpeg -hide_banner -loglevel error -y -i stream.mkv \
  -map 0:a:1 -ac 1 -ar 16000 -c:a pcm_s16le mic.wav
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# Derselbe Befehl in PowerShell; der Backtick setzt die Zeile fort
ffmpeg -hide_banner -loglevel error -y -i stream.mkv `
  -map 0:a:1 -ac 1 -ar 16000 -c:a pcm_s16le mic.wav
```

{{< /os-tab >}}
{{< /os-tabs >}}

Was deine eigene Aufnahme enthält, prüfst du mit ffprobe, das mit ffmpeg mitkommt. Der Befehl ist auf beiden Plattformen derselbe:

```bash
ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=title -of compact recording.mkv
```

### ffmpeg installieren

Wenn du den Filtergraphen unten nachvollziehen willst, brauchst du ffmpeg im `PATH`. Die [Download-Seite](https://ffmpeg.org/download.html) listet alle Möglichkeiten.

{{< os-tabs >}}
{{< os-tab "Linux" >}}

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y ffmpeg
```

{{< /os-tab >}}
{{< os-tab "macOS" >}}

```bash
# Homebrew (https://brew.sh/)
brew install ffmpeg
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# Windows 10/11 mit winget (Gyan.FFmpeg ist der volle Build)
winget install --id Gyan.FFmpeg -e
```

{{< /os-tab >}}
{{< /os-tabs >}}

## Stufe 3: Spracherkennung mit faster-whisper

Die Erkennung ist ein kleiner Python-Helfer, den der Go-Server als Kindprozess startet. Ich hätte ein Go-Binding für Whisper nehmen können, aber das Python-Ökosystem rund um [faster-whisper](https://github.com/SYSTRAN/faster-whisper) (eine CTranslate2-Neuimplementierung von Whisper) liefert mir CUDA-Unterstützung und Wort-Zeitstempel mit dem wenigsten Code. Er läuft auf der GPU und fällt auf ein langsameres, ungenaueres CPU-Modell zurück, wenn kein nutzbarer GPU-Stack da ist. Ich will, dass er überall läuft und dort gut ist, wo die Hardware es erlaubt.

Der Großteil der Qualität kommt aus drei Dingen:

- **Wort-Zeitstempel** sind der ganze Grund für diesen Weg. Die Wort-für-Wort-Hervorhebung im fertigen Video braucht Start und Ende für jedes einzelne Wort; Satz-Zeitstempel sind zu grob.
- **Sprachaktivitätserkennung** läuft zuerst, damit aus Stille und Spielgeräuschen keine erfundenen Wörter werden.
- **Ein Vokabel-Prompt** aus Figurennamen und Fachjargon des Spiels. Whisper ist ein Sprachmodell; ihm zu sagen, welche ungewöhnlichen Wörter kommen, hilft mehr als jede Nachbearbeitung. Eine Liste manueller Korrekturen fängt Namen ab, die es trotzdem falsch schreibt.

Die Erkennung läuft als Strom von Segmenten, der Helfer kann also bei einer langen Aufnahme Fortschritt melden. Das Ergebnis ist eine Cue-Liste: ein Eintrag pro Untertitelzeile mit Text sowie Start und Ende jedes Wortes, als ein gemeinsamer Go-Typ zwischen Transkription und Renderer. Ich habe keine Reihe von Modellen verglichen und nenne deshalb keine Zahlen.

## Stufe 4: Kandidaten wählen ohne LLM

Welche 45 Sekunden eines vierstündigen Streams verdienen einen Short? Ein Weg ist, Claude das Transkript lesen und Fenster bewerten zu lassen, und Neuroclip kann das. Es kostet aber pro Lauf Geld und hat einen Fehlerfall, der mir nicht gefiel: Ist die API nicht erreichbar oder das Budget erreicht, ist das ganze Feature tot.

Deshalb ist die Vorauswahl schlichtes, deterministisches Go. Sie führt voneinander unabhängige Signale über den Stream zu einer Rangliste zusammen, jeder Moment mit einer Wertung und einer Begründung in Worten:

- wie laut und aufgeregt ein Audioabschnitt ist,
- Schlagwörter im Transkript,
- Ausschläge der Chat-Aktivität,
- Momente, die ich beim Streamen selbst markiert habe (siehe [Teil 3](/de/blog/neuroclip-3-obs-regie/)),
- Clips, die Zuschauer auf Twitch gemacht haben.

Jedes Signal geht mit eigenem Gewicht ein. Signale, die zeitlich dicht beieinanderliegen, zählen als ein Moment, und ein Moment, den mehrere verschiedene Signalarten bestätigen, steht höher als einer mit nur einem starken Signal. Die Gewichte sind benannte Konstanten im Code. Wer sie abstimmt, macht eine Änderung, die jemand im Pull Request reviewen kann, und muss nicht mit Prompts experimentieren.

Das Chat-Signal ist das spannendste davon. Der Chat reagiert ein paar Sekunden *nach* dem Ereignis, deshalb werden die Nachrichtenzeiten zurückgeschoben. Ein Ausbruch wird am **lokalen** Niveau der Chat-Aktivität gemessen statt an einem globalen Schwellwert. So wird ein ruhiger Stream mit plötzlichem Ausbruch genauso erkannt wie ein belebter. Wenn du etwas Ähnliches baust, stimme die Zahlen auf dein eigenes Publikum ab.

Auch die Vorschlagsschwelle ist nicht fest. Sie startet bei einem Standardwert und passt sich an das an, was ich tatsächlich fertigstelle und was ich verwerfe. Was ein Mensch von Hand gewählt hat, ein Marker oder ein Zuschauer-Clip, wird immer vorgeschlagen, unabhängig von der Wertung.

**Claude ist eine optionale Schicht obendrauf.** Ist Claude aktiviert, hängt die Vorauswahl nur ihre Begründungen an die Kandidaten, und Claude bewertet; ohne Claude zeigt der Editor direkt die regelbasierte Liste. Beide Wege enden im selben Editor, und die Begründungen sind einfache Sätze, die sagen, warum ein Moment auf der Liste steht.

## Stufe 5: Von 16:9 auf 9:16

Ein Stream ist 1920 x 1080 mit der Facecam irgendwo im Bild. Ein Short ist 1080 x 1920. Das Layout ist der Klassiker: Facecam-Streifen oben, Gameplay darunter.

{{< diagram src="neuroclip-2-layout.svg" caption="Zwei Ausschnitte der Quelle werden zu zwei Streifen des Shorts. Die Untertitelzone sitzt im Spielstreifen." >}}

Zwei Rechtecke beschreiben das Layout, und woher sie kommen, folgt einer Rangfolge: Eine ausdrückliche Wahl für diesen Render gewinnt, dann das für genau diesen Stream gespeicherte Layout, dann der Profil-Standard. Der mittlere Punkt existiert, weil ich mein Stream-Overlay im Lauf der Zeit geändert habe. Ein Short aus einem älteren Stream mit dem heutigen Profil-Rahmen würde ein abgeschnittenes Gesicht zeigen, deshalb wird das Layout einmal pro Stream festgehalten.

### Der Filtergraph

Der Renderer baut einen ffmpeg-[`-filter_complex`](https://ffmpeg.org/ffmpeg-filters.html)-String aus Zahlen und festen Bausteinen zusammen. Lies das Folgende als Pipeline: `split` dupliziert das Video, jede Kopie wird auf ihren Rahmen zugeschnitten und auf volle Breite skaliert, und `vstack` stapelt die beiden Streifen. Beide Streifen brauchen gerade Abmessungen, weil H.264 mit 4:2:0-Chroma-Subsampling das verlangt. Dieses generische Beispiel nutzt Zahlen zur Illustration für einen 480 x 270 großen Webcam-Rahmen oben rechts und einen annähernd hochformatigen Spielrahmen:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
ffmpeg -ss 600 -t 30 -i vod.mp4 -filter_complex \
  "[0:v]split=2[a][b];[a]crop=480:270:1440:0,scale=1080:608[c];[b]crop=880:1070:100:5,scale=1080:1312[g];[c][g]vstack" \
  -c:v libx264 -crf 20 -preset veryfast -pix_fmt yuv420p -c:a aac short.mp4
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
ffmpeg -ss 600 -t 30 -i vod.mp4 -filter_complex `
  "[0:v]split=2[a][b];[a]crop=480:270:1440:0,scale=1080:608[c];[b]crop=880:1070:100:5,scale=1080:1312[g];[c][g]vstack" `
  -c:v libx264 -crf 20 -preset veryfast -pix_fmt yuv420p -c:a aac short.mp4
```

{{< /os-tab >}}
{{< /os-tabs >}}

(608 + 1312 = 1920. Ersetze `libx264` durch `h264_nvenc`, wenn du eine NVIDIA-GPU hast.)

Der Renderer ergänzt zwei Verfeinerungen:

- **Toleranz beim Seitenverhältnis.** Hat der Spielrahmen ungefähr die Form seines Streifens, wird er einfach zugeschnitten und skaliert. Hat er eine ganz andere Form, wird er **verzerrungsfrei** in die Mitte des Streifens **eingepasst**, und der Rest des Streifens zeigt dasselbe Bild vergrößert, weichgezeichnet (`boxblur`) und abgedunkelt. Das ist der bekannte Look mit unscharfem Hintergrund, gebaut aus demselben Filter-Vokabular.
- **Lange Graphen landen in einer Datei.** Mit Effekten und Overlays kann der String lang werden. Dann ist es besser, ihn in eine Datei zu legen und diese an ffmpeg zu übergeben, als an Kommandozeilen-Grenzen zu stoßen. Seit ffmpeg 7.0 geht das über die allgemeine Syntax `-/option datei`, hier also `-/filter_complex graph.txt`; das ältere `-filter_complex_script` funktioniert noch, ist aber [veraltet](https://ffmpeg.org/ffmpeg.html#Main-options).

Weil der Prozess mit einer Argumentliste statt über eine Shell startet und der Graph aus Zahlen und festen Bausteinen entsteht, gibt es keine Stelle, an der eine bösartige Eingabe etwas einschleusen könnte. Benutzertext, der in der Untertiteldatei landet, wird mit derselben Sorgfalt behandelt, womit wir bei den Untertiteln sind.

### Wortgenaue Untertitel in ASS

Die eingebrannten Untertitel sind ein [Advanced-SubStation-Alpha-Skript (ASS)](https://www.aegisub.org/), das der ffmpeg-Filter `ass` rendert. Ich habe ASS statt SRT gewählt, weil ASS einzelne Ereignisse gestalten, Text frei positionieren und eine Box hinter ein Wort zeichnen kann; SRT kann das alles nicht. Der Builder schreibt ein Ereignis pro gesprochenem Wort: Der Textblock steht für die Dauer seiner Zeile, und in der Zeitspanne jedes Wortes bekommt genau dieses Wort die Hervorhebung. Hervorhebungsstil, Schrift und Farben sind einstellbar.

Alles, was ein Nutzer tippen kann, landet in diesem Skript, und ASS hat eine eigene Steuersyntax: `{` startet Override-Tags und ein Backslash leitet eine Escape-Sequenz ein. Deshalb wird Text bereinigt, bevor er in ein Ereignis gelangt, und Stil-Overrides werden geprüft. Niemand betrachtet ein Untertitelformat als Angriffsfläche, bis die Chat-Nachricht eines Zuschauers darin landet.

### Die sichere Zone

Vertikale Plattformen verdecken Teile des Bildes mit ihrer eigenen Oberfläche: oben eine Kopfzeile, seitlich Buttons, unten Bedienelemente. Eingebrannter Text muss diese Bereiche freihalten, deshalb zeichnet der Editor ein Overlay mit der sicheren Zone. Die Ränder sind meine eigenen Arbeitswerte für die Plattformen, auf denen ich poste, und stammen aus keiner offiziellen Spezifikation. Prüfe also die aktuellen Richtlinien deiner Plattform.

## Stufe 6: Hardware-Kodierung, und was bei Fehlern passiert

[NVENC](https://developer.nvidia.com/video-codec-sdk) ist der Hardware-Encoder auf NVIDIA-GPUs; er nimmt die Kodierlast von einer CPU, die ohnehin ein Spiel betreibt. Der Renderer probiert zuerst den GPU-Encoder und hat einen passenden x264-Rückfall.

Die Zuverlässigkeit kommt vor allem aus der Wiederholungsregel. Schlägt NVENC fehl, versucht der Renderer es mit x264 erneut, aber nur, wenn die GPU plausibel schuld ist: Die Fehlerausgabe von ffmpeg erwähnt den Encoder, CUDA oder den Treiber, oder es gibt gar keine Meldung, was meist heißt, dass der Prozess beendet wurde. Geht es im Fehler um den Filtergraphen oder eine fehlende Datei, würde ein zweiter Versuch mit x264 identisch scheitern, nach Minuten an Arbeit, also bricht er sofort ab. Auch ein abgebrochener Job wird nicht wiederholt, denn ein Abbruch sagt nichts über die GPU. Eine billige Prüfung, die ein paar Bilder eines erzeugten Testbilds kodiert, sagt dem Programm einmalig, ob Hardware-Kodierung überhaupt verfügbar ist.

Nach dem Rendern misst ein zweiter Durchgang die Lautheit des Shorts und wendet, wenn sie deutlich vom Ziel abweicht, eine einzige lineare Verstärkung an, während das Bild ohne Neukodierung kopiert wird. Dieser Durchgang darf scheitern, und ein Fehler dort erzeugt nur einen Hinweis.

## Wie Go externe Prozesse robust steuert

All das nützt nichts, wenn ein Render ewig hängen, eine kaputte Datei hinterlassen oder das Spiel einfrieren kann, das du gerade streamst. Das sind allgemeine Muster, die für jedes Werkzeug funktionieren, das ffmpeg umhüllt.

**1. Context-Abbruch überall.** Nutze [`exec.CommandContext`](https://pkg.go.dev/os/exec#CommandContext), dann beendet der Abbruch des Contexts ffmpeg. Gib für einen abgebrochenen Lauf immer einen bekannten Fehler zurück, damit Aufrufer „der Nutzer hat abgebrochen“ nicht mit „der Encoder ist kaputt“ verwechseln.

**2. Part-Dateien und atomares Umbenennen.** Schreibe unter einem temporären Namen und benenne erst auf den echten Namen um, nachdem ffmpeg mit 0 beendet wurde. Bei jedem Fehler oder Abbruch wird die Part-Datei gelöscht und die vorherige Ausgabe bleibt, sodass nichts weiter hinten eine halb kodierte Datei für eine fertige halten kann. Behalte die ursprüngliche Endung im temporären Namen, denn ffmpeg wählt den Muxer anhand der Endung.

**3. Fortschritt ohne stderr-Scraping.** ffmpeg kann maschinenlesbaren Fortschritt mit `-progress <datei> -nostats` in eine Datei schreiben. Lies diese Key=Value-Datei regelmäßig und teile die Ausgabezeit durch die erwartete Länge, dann hast du einen Anteil von 0 bis 1 für die Oberfläche.

```text
out_time_us=12480000
out_time_ms=12480000
progress=continue
```

(`out_time_ms` ist trotz des Namens ebenfalls in Mikrosekunden.)

**4. Hintergrundpriorität.** Läuft das Werkzeug auf dem Streaming-PC selbst, sollen Renders OBS und dem Spiel weichen. Kinder erben die Priorität ihres Elternprozesses. Wer sie für die gestarteten Prozesse senkt, erwischt also auch einen Python-Helfer, der ffmpeg startet. Unter Windows ist das ein Flag beim Prozessstart; unter Linux kannst du den Befehl in `nice` packen. Auch ffmpegs eigene Thread-Begrenzungen helfen.

**5. Prozesse ohne Shell.** Starte Werkzeuge mit `exec.Command(name, args...)`, nie über eine Shell, und leite ihre Ausgabe in ein Log, dem deine Oberfläche folgen kann. Beende beim Herunterfahren alle Kinder und warte auf sie, damit kein Helfer den Server überlebt und weiter Dateien schreibt. Unter Windows beendest du den ganzen Prozessbaum.

**6. Panics beenden den Prozess nicht.** Starte Goroutinen über einen Wrapper, der Panics abfängt und den Besitzer informiert, damit der Zustand zurückgesetzt werden kann. Ein hängendes Flag „Stream endet“ würde sonst den nächsten Lauf blockieren.

Die Standardbibliothek erledigt das meiste: [`os/exec`](https://pkg.go.dev/os/exec), [`context`](https://pkg.go.dev/context) und [`os.Rename`](https://pkg.go.dev/os#Rename). Wie man so eine Binärdatei ausliefert, steht in meinem [Go-und-Docker-Beitrag](/de/blog/go-docker/).

## Stufe 7: Abnahme und Prüfungen

Wenn ffmpeg endet, muss der Short noch durch die Abnahme. Sobald er existiert, schauen automatische Qualitätsprüfungen auf den Schnitt, den fertigen Render, den Kamera-Ausschnitt und die Lautheit. Jede liefert ok, Warnung, Problem oder „konnte nicht laufen“, und das Dashboard verdichtet sie zu einer Ampel.

Die Designregel dazu: **Eine Prüfung ist ein weicher Schritt.** Eine fehlschlagende oder fehlende Prüfung lässt den Job nie scheitern, weil ein kaputter Prüfer mich nicht daran hindern soll, das Video zu sehen.

Shorts sind nur das erste von zwei Produkten. Dieselben Bausteine speisen eine Pipeline für längere YouTube-Episoden, und beide gehen unterschiedlich mit Untertiteln um: Shorts brennen die Untertitel ein, Episoden liefern eine Untertitel-*Spur*, weil eingebrannter Text bei langen Videos stört und YouTube Untertitelspuren indexiert.

## Was noch holprig ist

- Das Projekt ist Early Access und Single-User. Jeder Pfad oben wurde auf meiner Maschine mit meinem Overlay und meinen Aufnahmen durchlaufen. Auf anderen Setups habe ich es nicht überprüft.
- Der Code für Filtergraph und Untertitel ist organisch gewachsen. Er hat Tests, aber es ist die erste Stelle, die ich umbauen würde.
- Die Spracherkennung ist nur so gut wie die Mikrospur und der Vokabel-Prompt. Ungewöhnliche Namen brauchen weiterhin manuelle Korrekturen.

## Wie es weitergeht

Als Nächstes wird der Stream selbst zu Daten: [Teil 3 behandelt die OBS-Regie](/de/blog/neuroclip-3-obs-regie/), die Schaltzentrale, die mit OBS spricht, Alarme auslöst und die Marker schreibt, die diese Pipeline so hoch bewertet. Wenn du das Ganze lieber sehen als lesen willst, findest du Details und die Early-Access-Warteliste auf der [Neuroclip-Seite](/de/page/neuroclip/).
