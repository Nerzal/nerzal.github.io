---
draft: false
title: "Neuroclip bauen — Teil 1: Architektur eines Streaming-Toolkits in Go"
seo_title: "Neuroclip Architektur: Go-Toolkit für Streamer"
date: 2026-11-08T06:00:00+01:00
tags:
  [
    "go",
    "golang",
    "architecture",
    "neuroclip",
    "ffmpeg",
    "concurrency",
    "software-architecture",
    "streaming",
  ]
categories: ["Software Engineering"]
series: ["Building Neuroclip"]
description: "So ist Neuroclip aufgebaut: Go-Server, React-Dashboard und Helferprozesse. Rollen der Komponenten, Datenfluss und die Designentscheidungen dahinter."
images: ["img/neuroclip/og.png"]
featured_image: "img/neuroclip/heute-1440.jpg"
toc: true
---

> **Neuroclip bauen — eine Serie.** Teil 1: Architektur (du bist hier) · [Teil 2: VOD-zu-Short-Pipeline](/de/blog/neuroclip-2-vod-to-short-pipeline/) · [Teil 3: OBS-Regie](/de/blog/neuroclip-3-obs-regie/) · [Teil 4: Facecam-Upscaling](/de/blog/neuroclip-4-facecam-upscaling/) · [Teil 5: Auslieferung auf Kubernetes](/de/blog/neuroclip-5-shipping-kubernetes/). Die Produktseite ist [Neuroclip](/de/page/neuroclip/). Status: **Early Access, Beta mit einem einzigen Nutzer**.

Neuroclip ist ein Werkzeug, das ich für Streamer baue. In dieser Serie geht es um die Technik dahinter, nicht um Gaming: ein langlebiger Go-Prozess, der ffmpeg, OBS, Spracherkennung und ein paar LLM-Aufrufe so zusammenbringt, dass nichts mitten im Stream umfällt.

Neuroclip ist ein kommerzielles Produkt im Early Access. Deshalb bleibt diese Serie auf der Ebene der Ideen: Rollen der Komponenten, Designentscheidungen, Abwägungen und die allgemeinen Techniken dahinter. Es ist kein Bauplan, und der Code hier ist generisch.

In diesem ersten Teil gehe ich das System von oben durch: welches Problem es löst, welche Komponenten es gibt, wie Daten von einem Live-Stream bis zum Upload fließen, und die Designentscheidungen, die ich in einem Code-Review verteidigen würde. Das sind ein Server, der sich während des Streams zurückhält, ein profilgetriebenes Design ohne fest eingebaute Streamer-Werte und die Regel, dass nichts ohne ein menschliches Ja veröffentlicht wird.

## Das Problem: Stunden Stream, Minuten Inhalt

Ein Streamer spielt drei bis sechs Stunden. Daraus entstehen vielleicht eine Handvoll veröffentlichungswürdiger Momente: ein 30-Sekunden-Short, ein lustiger Clip, eine zehnminütige YouTube-Folge. Diese Momente zu finden heißt: durch das VOD scrubben, schneiden, Untertitel einfügen, auf Hochkant umrahmen, Titel schreiben und schließlich auf mehrere Plattformen mit unterschiedlichen Regeln hochladen. Von Hand ist das ein zweiter Job.

Neuroclip automatisiert die langweilige Mitte und lässt den Menschen bei den Entscheidungen:

- **Finden** von Kandidaten-Momenten (Lautstärke, Hype-Wörter, Chat-Aktivität, live gesetzte Marker).
- **Schneiden und Rendern** von Shorts und Episoden mit ffmpeg, mit Untertiteln aus der Spracherkennung.
- **Prüfen** von allem in einem Browser-Dashboard.
- **Hochladen** erst nach ausdrücklicher Bestätigung.

Alles andere in diesem Beitrag — Prozess-Layout, Nebenläufigkeit, Fallbacks — folgt daraus, diese Liste ernst zu nehmen.

![Neuroclip-Übersicht "Heute" mit dem Tagesstatus im Dashboard](/img/neuroclip/heute-1440.jpg)

*Die Seite "Heute" im Dashboard: was läuft, was fertig ist und was auf Prüfung wartet.*

## Komponentenüberblick

Neuroclip ist ein Go-Programm plus ein paar Satelliten. Intern heißt das Go-Programm **Cockpit**.

{{< diagram src="neuroclip-1-components.svg" caption="Das Cockpit ist ein einzelner Go-Prozess. Alles Schwere (ffmpeg, Spracherkennung, Claude, Upscaling) läuft als Kindprozess; alles Persönliche liegt in einem Workspace-Ordner." >}}

| Komponente | Was es ist | Warum getrennt |
| --- | --- | --- |
| **Cockpit** | Ein Go-Prozess: HTTP-API, Job-Runner, OBS-Client, Render-Logik. | Der einzige Besitzer von Zustand und jedem Kindprozess. |
| **Dashboard** | Eine React- und TypeScript-Single-Page-App. | Spricht nur mit der API des Cockpits. Das Cockpit liefert die gebauten Dateien aus. |
| **Upload-Brücke** | Ein kleiner lokaler Server. | Reicht Dateien in voller Qualität an die Browser-Erweiterung weiter. |
| **Browser-Erweiterung** | Legt Dateien in die Upload-Formulare von Videoplattformen. | Manche Plattformen haben keine brauchbare Upload-API; der Browser ist die API. |
| **Python-Helfer** | Spracherkennung, Personen-Tracking, Hintergrundentfernung. | Das ML-Ökosystem dafür lebt in Python. |
| **Claude-Jobs** | Die `claude`-CLI, vom Cockpit headless gestartet. | Momente zu ranken und zu benennen ist eine Sprachaufgabe. |

Zwei Details sind wichtiger, als sie aussehen:

1. **Kindprozesse statt Bibliotheken.** Das Cockpit linkt weder ffmpeg noch das Sprachmodell. Es startet sie als Prozesse, leitet ihre Ausgabe in ein begrenztes Log und kann den ganzen Baum beenden. Ein Absturz in einem Helfer ist ein fehlgeschlagener Job, kein toter Server. Go hält das Cockpit außerdem als einzelne, leicht auslieferbare Binärdatei (warum das wichtig ist, steht in [Containerisierung und Go](/de/blog/go-docker/)).
2. **Das Dashboard ist nichts Besonderes.** Es ist ein Client einer einfachen HTTP-API mit Server-Sent Events für Live-Logs ([SSE-Spezifikation](https://html.spec.whatwg.org/multipage/server-sent-events.html)). Fernsteuerungen erreichen das Cockpit auf demselben Weg.

Der Code ist in viele kleine Pakete mit je einem Vokabular gegliedert. Wenn du meinen Beitrag über [Bounded Contexts](/de/blog/bounded-context/) kennst: Das ist derselbe Instinkt im Paketmaßstab. Jedes Paket hat eine kleine Oberfläche, und die HTTP-Schicht ist der einzige Ort, der sie zusammenfügt.

## Streaming-PC gegen Server

Neuroclip ist **local-first**: Videos, Profil und Zugangsdaten bleiben auf dem Rechner des Streamers. Dieselbe Binärdatei kann auch in einem Container auf einem Server laufen (mehr in [Teil 5](/de/blog/neuroclip-5-shipping-kubernetes/)). Die spannende Frage ist, welche Teile umziehen können.

Was auf dem Streaming-PC bleiben muss:

- **OBS und sein WebSocket.** OBS läuft dort, wo der Stream läuft.
- **Hotkeys** für Marker und Clips während des Streams.
- **Die Upload-Brücke und die Browser-Erweiterung.** Sie arbeiten im eingeloggten Browser des Streamers.
- **GPU-lastige Arbeit** wie Spracherkennung, wo die GPU die Geschwindigkeit bringt (ein CPU-Fallback existiert).
- **Claude-Jobs**, die die eigene `claude`-CLI des Streamers nutzen.

Ein Server kann das Dashboard und die API ausliefern, den Workspace als Volume halten und die Teile ausführen, die den Desktop nicht brauchen. Die Grenze wird durchgesetzt statt erhofft: Der Server weigert sich, ohne Authentifizierung über Loopback hinaus zu lauschen, das Dashboard fragt, welche Fähigkeiten dieser Rechner bietet, und jedes Tool deklariert, was es braucht. Ein Job mit fehlender Voraussetzung wird mit einer verständlichen Begründung abgelehnt, statt auf halbem Weg zu scheitern.

Ich will ehrlich zum Stand sein: Der Container-Weg existiert, aber das Produkt ist eine Early-Access-Beta mit genau einem Nutzer, mir. Die Aufteilung oben ist das Design, nichts im großen Maßstab Bewiesenes.

## Der Datenfluss: vom Stream zum Upload

{{< diagram src="neuroclip-1-dataflow.svg" caption="Von einem Live-Stream bis zum Upload. Rote Schritte brauchen einen Menschen; der Upload läuft erst nach ausdrücklicher Bestätigung." >}}

Der Weg, Schritt für Schritt:

1. **Stream.** OBS nimmt auf oder streamt mit getrennten Audiospuren (Mix, Mikrofon, Spiel). Getrennte Spuren machen spätere Schritte zuverlässig: Die Spracherkennung braucht nur das Mikrofon.
2. **VOD und Chat.** Das Cockpit holt VOD und Chat über die öffentlichen APIs von Twitch.
3. **Transkribieren.** Ein Helfer lässt [Whisper](https://github.com/openai/whisper) über die Mikrofonspur laufen.
4. **Analysieren.** Audio- und Transkript-Signale werden zu *Kandidaten-Momenten*.
5. **Vorschlagen.** Entweder ein Claude-Job oder ein regelbasiertes Ranking bewertet die Kandidaten.
6. **Bearbeiten.** Der Streamer öffnet einen Vorschlag im Projekt-Editor und passt den Schnitt an.
7. **Rendern.** ffmpeg erzeugt den Short oder die Episode.
8. **Bereit.** Das Ergebnis landet in einem Ready-Ordner zusammen mit einem kleinen Plan: Titel, Beschreibung, Ziele.
9. **Prüfen.** Der Streamer gibt im Dashboard frei — oder schickt es zurück in den Editor.
10. **Hochladen.** Über eine Plattform-API oder über Brücke und Erweiterung.

Zwei Regeln liegen über diesem Fluss. **Claude-Jobs laden nie hoch**: Posting-Werkzeuge stehen ihnen schlicht nicht zur Verfügung. Und **nichts wird veröffentlicht, ohne dass ein Mensch im Dashboard bestätigt.** [Teil 2](/de/blog/neuroclip-2-vod-to-short-pipeline/) behandelt die Mitte dieses Flusses.

## Claude als optionale Erweiterung, nicht als Abhängigkeit

Ich nutze die `claude`-CLI headless für Aufgaben, die eigentlich Sprachprobleme sind: Kandidaten-Momente bewerten, Episoden benennen, Kapitel vorschlagen. Das Cockpit startet sie als Kindprozess. Weil diese Sitzungen den Chat und die Sprache anderer Leute lesen, laufen sie mit eingeschränkten Rechten: kein Zugriff auf Geheimnisse, kein Bearbeiten von Code oder Einstellungen, keine Posting-Werkzeuge.

Die Designentscheidung, die mir am wichtigsten ist: **Jeder Claude-Pfad hat einen Fallback ohne LLM.** Ist die CLI nicht installiert oder bevorzugt der Streamer es so, zeigt der Editor stattdessen ein regelbasiertes Ranking. Es fasst mehrere Signale — Lautstärke, Hype-Wörter, Chat-Aktivität, live gesetzte Marker, Clips von Zuschauern — zu einer Bewertung zusammen, und Signale, die nah beieinander liegen, zählen als ein Moment. Übereinstimmung verschiedener Signalarten erhöht die Bewertung. Neben jedem Vorschlag stehen die Gründe, sodass ein Ranking nie eine Blackbox ist.

Die Form ist wichtiger als die Zahlen. Das Ranking ist eine reine Funktion, und eine getrennte integrierende Funktion liest die Dateien und schreibt das Ergebnis. Das ist die IOSP-Regel (Integration Operation Segregation Principle), die ich überall zu befolgen versuche: Eine Funktion integriert entweder andere Funktionen oder rechnet, nie beides.

```go
// rank is pure: same input, same ordered list. No files, no clock, no network.
func rank(signals []Signal) []Moment {
    moments := groupNearbySignals(signals)
    for index := range moments {
        moments[index].Score = scoreMoment(moments[index])
    }
    sortByScore(moments)
    return moments
}

// generateSuggestions integrates: load, rank, store.
func generateSuggestions(source Source, sink Sink) error {
    signals, err := source.Load()
    if err != nil {
        return err
    }
    return sink.Store(rank(signals))
}
```

Das ist eine generische Illustration des Musters, kein Produktcode. Der reine Kern lässt sich leicht mit tabellengetriebenen Tests prüfen, und der Fallback ist kein abgespeckter Nachgedanke, sondern ein vollwertiger Pfad.

## Der Job-Runner und Go-Nebenläufigkeit

Jedes Tool, das echte Arbeit macht — rendern, transkribieren, analysieren, hochladen — läuft über einen Job-Manager. Die API startet einen Job, bekommt eine ID zurück, und das Dashboard folgt dem Log per SSE.

Die Designentscheidungen, allgemein gehalten:

- **Nur Tools auf der Whitelist.** Ein Job ist eine Tool-ID plus validierte Werte. Pfade werden gegen den Workspace aufgelöst, bevor irgendetwas startet, und die Argumentliste entsteht aus geprüften Werten, nie über eine Shell.
- **Ein laufender Job pro Tool.** Der Platz wird unter einem Mutex reserviert, *bevor* der Prozess startet, sodass zwei schnelle Klicks nicht denselben Render zweimal starten.
- **Ein begrenztes Log.** Jeder Job behält nur das Ende seiner Ausgabe, damit ein gesprächiges Tool nicht den Speicher füllt.
- **Eine injizierte Starter-Funktion.** Tests übergeben eine Attrappe, die nie einen Prozess startet; die Produktion übergibt die echte.

Das Nebenläufigkeitsmodell ist bewusst langweilig: eine Map hinter einem Mutex, eine wartende Goroutine pro Job und ein Channel, der bei jeder Änderung geschlossen und ersetzt wird, um die SSE-Leser zu wecken. Kein Worker-Pool, keine Queue-Bibliothek.

### Einen Prozessbaum beenden

Einen Job abzubrechen klingt trivial und ist es nicht. Ein Tool startet einen Helfer, der ein weiteres Programm startet. `exec.CommandContext` beendet nur das direkte Kind, sodass Enkelprozesse überleben und Pipes offen halten können. Die allgemeine Lösung ist ein eigenes `Cancel` plus ein `WaitDelay` (beides seit Go 1.20, siehe die [`os/exec`-Dokumentation](https://pkg.go.dev/os/exec#Cmd)):

```go
cmd := exec.CommandContext(ctx, "ffmpeg", "-version")
cmd.Cancel = func() error {
    killProcessTree(cmd.Process.Pid) // platform-specific, see below
    return cmd.Process.Kill()
}
cmd.WaitDelay = 5 * time.Second // a surviving grandchild can hold the pipes open
```

Unter Linux startest du das Kind in einer eigenen Prozessgruppe (`SysProcAttr{Setpgid: true}`) und sendest `SIGKILL` an die negative PID. Unter Windows beendet `taskkill /PID <pid> /T /F` den Baum. Halte jede Variante in einer eigenen Datei mit Build-Constraint, statt `runtime.GOOS`-Prüfungen zu streuen.

### Panics dürfen den Abend nicht beenden

Ein langlebiger lokaler Server muss einen Bug in einer Goroutine überleben. Zwei kleine Helfer erledigen das meiste: einer macht aus einer Panic einen Fehler, der andere startet eine Goroutine, die sich erholt und ihren Besitzer benachrichtigt, sodass Zustand wie "ein Ablauf ist aktiv" zurückgesetzt werden kann, statt den nächsten Lauf zu blockieren. HTTP-Handler sind so umhüllt, dass eine Panic zu einem JSON-`500` wird statt zu einer abgebrochenen Verbindung.

## Live-Sparmodus: dem Streamer nicht die CPU wegfressen

Das ist der Teil, der das Projekt nach echter Ingenieursarbeit anfühlen ließ. Ein Streaming-PC hat eine Aufgabe unter Volllast: OBS plus das Spiel. Startet das Cockpit mitten im Stream einen ffmpeg-Render mit normaler Priorität, kann der Stream Frames verlieren. Ein Werkzeug, das nach dem Stream hilft, darf währenddessen nicht schaden.

Eine statische Durchsicht des Codes fand ein klassisches Problem: Statusabfragen an OBS waren teuer, weil jeder Aufruf eine neue WebSocket-Verbindung öffnete, sich anmeldete und viele Fragen stellte, und mehrere Aufrufer fragten ständig nach. Die erste Korrektur ist ein kleiner, kurzlebiger Cache, den alle Aufrufer teilen.

Die zweite Korrektur ist ein **Live-Sparmodus**. Solange OBS streamt und der Streamer ihn im Profil aktiviert hat, dreht das Cockpit an mehreren Stellschrauben gleichzeitig:

- **Niedrigere Prozesspriorität** für Kindprozesse, auch für bereits laufende Jobs.
- **Weniger ffmpeg-Threads.**
- **Ein kleineres `GOMAXPROCS`** für das Cockpit selbst.
- **Seltenere UI-Updates** und aufgeschobene Hintergrundmessungen.

Alle werden gebraucht, weil [`runtime.GOMAXPROCS`](https://pkg.go.dev/runtime#GOMAXPROCS) nur die Threads begrenzt, die Go-Code ausführen. Kindprozesse begrenzt es nicht. Zwei Details, die ich mag: Ein OBS, das nicht antwortet, zählt als "streamt nicht", weil es nichts zu schützen gibt, und `GOMAXPROCS` kehrt am Ende des Streams auf den Wert vom Start zurück, nicht auf einen angenommenen Standard.

Unter Windows ist die Priorität ein Creation-Flag für neue Prozesse (`BELOW_NORMAL_PRIORITY_CLASS`) und `SetPriorityClass` für laufende; Kinder erben die Klasse, sodass auch eine Kette Python-zu-ffmpeg zurücktritt. Eine verwandte Idee, vor einem schweren Job während des Streams nachzufragen und ihn bis zum Stream-Ende zu queuen, steht auf der Roadmap, nicht im Produkt.

![OBS-Regie-Seite mit Stumm-Alarm](/img/neuroclip/regie-1440.jpg)

*Die Regie-Seite ist das Live-Gegenstück zum Cockpit; [Teil 3](/de/blog/neuroclip-3-obs-regie/) zeigt, wie sie mit OBS spricht.*

## Workspace und Profil: Design für jemanden, der nicht ich ist

Neuroclip begann als mein eigenes Werkzeug, und die erste Version war voller mir: mein Kanalname in einem String, meine Hype-Wörter, mein Ordnerlayout. Daraus etwas zu machen, das andere Streamer nutzen können, bedeutete eine Regel, die ich heute bei jeder Änderung anwende: **kein streamerspezifischer Wert im Code**.

Zwei Dinge ersetzen sie:

- **Der Workspace.** Ein Ordner hält alle persönlichen Daten — Videos, Berichte, Zustandsdateien. Er ist git-ignoriert, und jeder Pfad aus dem Browser wird geprüft, damit ein API-Aufruf ihn nicht verlassen kann.
- **Das Profil.** Eine typisierte Konfiguration mit Handles, Sprache, Hype-Wörtern, Untertitelstil und Upload-Zielen des Streamers. Geheimnisse liegen getrennt, und ein Pre-Commit-Hook verhindert, dass beides committet wird.

Jedes Feld hat einen neutralen Standardwert, sodass ein fehlender Schlüssel nie zur Überraschung wird und das Format über Versionen hinweg nachsichtig bleibt.

### Finder-Funktionen mit Umgebungsvariable als Override

Externe Programme sind der andere Ort, an dem sich "läuft auf meinem Rechner" versteckt. ffmpeg, optionale Upscaler, die `claude`-CLI und ein Browser sind auf verschiedenen Rechnern an verschiedenen Orten installiert. Das Muster für alle: ein Finder mit fester Suchreihenfolge, bei dem eine Umgebungsvariable immer gewinnt. Hier für ffmpeg:

```go
// findFFmpeg returns $FFMPEG if set, otherwise ffmpeg from the PATH.
func findFFmpeg(environmentValue string, lookPath func(string) (string, error)) (string, error) {
    if environmentValue != "" {
        return environmentValue, nil
    }
    return lookPath("ffmpeg")
}
```

Die entscheidende Funktion nimmt ihre Lookups als Parameter, sodass ein Unit-Test jeden Zweig abdeckt, ohne etwas zu installieren, während ein dünner Aufrufer `os.Getenv` und `exec.LookPath` einsteckt. So zeigst du einem Tool ein bestimmtes ffmpeg:

```bash
export FFMPEG=/usr/local/bin/ffmpeg
```

```powershell
$env:FFMPEG = "C:\tools\ffmpeg\bin\ffmpeg.exe"
```

Wenn du ffmpeg selbst brauchst, listet die offizielle [Download-Seite](https://ffmpeg.org/download.html) Builds für beide Plattformen. Ein fehlendes optionales Programm ist eine *Fähigkeit*, die das Dashboard mit Begründung als nicht verfügbar anzeigt, kein Absturz.

## Testen unter Windows und Linux

Das Cockpit wird unter Windows entwickelt und als Linux-Container ausgeliefert, also zählen beide Plattformen. Ich lasse die komplette Suite mit Race-Detector lokal unter Windows laufen, und die CI führt die Go-Tests unter Linux aus. Ich bin absichtlich genau: **Die CI läuft nicht unter Windows.** Windows-spezifischer Code wird von Testdateien abgedeckt, die nur auf meinem Rechner laufen. Das ist eine bekannte Lücke.

Plattformunterschiede sind über Dateisuffixe und Build-Constraints (`_windows.go`, `_other.go`) isoliert statt über `if runtime.GOOS == ...` im ganzen Code. Die üblichen Prüfungen für jedes Go-Projekt:

```bash
go vet ./... && go test -race ./...
```

```powershell
go vet ./...; if ($?) { go test -race ./... }
```

Go installierst du über [go.dev/doc/install](https://go.dev/doc/install); der Race-Detector ist unter [go.dev/doc/articles/race_detector](https://go.dev/doc/articles/race_detector) beschrieben.

## Was ich anders machen würde

- **Am Anfang weniger, größere Pakete.** Ich habe zu fein geschnitten, und viele winzige Pakete haben ihren Preis in der Navigation.
- **Früher natives Go.** Die Python-Helfer sind der schwächste Teil der Installationsgeschichte. Sie zu ersetzen ist geplant, nicht erledigt.
- **Ein Windows-CI-Runner.** Die ehrliche Antwort auf die Testlücke oben.

## Wie es weitergeht

Als Nächstes kommt der Kern des Produkts: [Teil 2, vom VOD zum Short](/de/blog/neuroclip-2-vod-to-short-pipeline/), mit den allgemeinen ffmpeg- und Untertitel-Techniken dahinter. Wenn du streamst und Neuroclip im Early Access ausprobieren willst, findest du Details auf der [Neuroclip-Seite](/de/page/neuroclip/).
