---
draft: false
title: "Neuroclip bauen — Teil 3: OBS-Regie — WebSocket, Audiopegel und der Stumm-Alarm"
seo_title: "OBS WebSocket v5 in Go: Audiopegel und Stumm-Alarm"
date: 2026-11-25T08:00:00+01:00
tags:
  [
    "go",
    "obs",
    "obs-websocket",
    "websocket",
    "streaming",
    "audio",
    "sha256",
    "neuroclip",
    "software-engineering",
  ]
categories: ["Software Engineering"]
series: ["Building Neuroclip"]
description: "Wie ein Go-Dienst per obs-websocket v5 mit OBS spricht: SHA-256-Handshake, Audiopegel in dB und die Idee hinter einem Alarm für das stumme Mikro."
images: ["img/neuroclip/og.png"]
featured_image: "img/neuroclip/regie-1440.jpg"
toc: true
---

> **Neuroclip bauen, Teil 3 von 5.** Die Serie: [Teil 1: Architektur](/de/blog/neuroclip-1-architecture/) · [Teil 2: VOD-zu-Short-Pipeline](/de/blog/neuroclip-2-vod-to-short-pipeline/) · **Teil 3: OBS-Regie** · [Teil 4: Facecam-Upscaling](/de/blog/neuroclip-4-facecam-upscaling/) · [Teil 5: Auslieferung mit Kubernetes](/de/blog/neuroclip-5-shipping-kubernetes/). Mehr auf der [Neuroclip-Produktseite](/de/page/neuroclip/). Neuroclip ist im **Early Access** und eine **Single-User-Beta**, alles Folgende beschreibt also, was heute auf meinem Rechner läuft.

Die ersten beiden Teile handelten von dem, was *nach* einem Stream passiert: schneiden, untertiteln, exportieren. Dieser Teil handelt von der Live-Seite, die ich die **Regie** nenne. Die Regie spricht mit OBS, solange der Stream läuft: Szenen wechseln, Replays speichern, Marker setzen, die Encoder-Gesundheit im Auge behalten und (mein Liebling) mich warnen, wenn ich in ein stummes Mikrofon rede.

Ich bleibe hier bewusst auf Konzeptebene. Neuroclip ist ein kommerzielles Produkt, einen Bauplan bekommst du also nicht. Was ich dir geben kann: das öffentliche Protokoll, auf dem es aufbaut, die Audio-Mathematik, an der viele scheitern, und die Überlegungen hinter dem Alarm. Wenn dich nur das Protokoll interessiert, spring zum [Handshake](#der-obs-websocket-v5-handshake). Für die Alarm-Idee geht es weiter bei [Stumm-Alarm](#der-stumm-alarm-sprache-durch-ein-stummes-mikrofon-hören).

## Was die Regie kann

Die Regie-Seite des Dashboards zeigt die aktuelle Szene, Stream- und Aufnahmestatus, die Audio-Eingänge mit Live-Pegeln, ein paar Gesundheitswerte und eine Liste von Warnungen. Von dort (oder per Hotkey, Handy oder Stream Deck) kann ich:

- Szenen wechseln, Stream und Aufnahme starten und stoppen, den Replay-Puffer speichern,
- Eingänge stummschalten und Fader setzen,
- einen **Marker** setzen (ein Twitch-Stream-Marker während des Streams, ein Kapitel in der Aufnahme während der Aufnahme),
- **„Clip jetzt“** auslösen (ein Twitch-Clip der letzten Sekunden),
- Quellen der aktuellen Szene ein- und ausblenden.

![Die Regie-Seite des Neuroclip-Dashboards mit Szenen-Buttons, Audio-Pegeln, Gesundheitswerten und einer Mikrofon-Warnung](/img/neuroclip/regie-1440.jpg)

*Die Regie-Seite. Der Mikrofon-Alarm in diesem Screenshot wurde für das Bild gestellt. Ich habe nicht wirklich im Stream in ein stummes Mikro geredet.*

Das Dashboard ist React, der Server ist Go, und der gesamte OBS-Verkehr läuft durch eine Komponente auf dem Server, die das [obs-websocket-v5-Protokoll](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md) spricht. Seit OBS 28 ist der WebSocket-Server in OBS eingebaut, auf der OBS-Seite musst du also nichts installieren: *Werkzeuge › WebSocket-Servereinstellungen*, aktivieren, Passwort setzen.

## Der obs-websocket-v5-Handshake

Das Protokoll ist JSON über WebSocket ([RFC 6455](https://www.rfc-editor.org/rfc/rfc6455)). Jede Nachricht ist ein Umschlag `{"op": <int>, "d": {...}}`. Die Opcodes, die für einen einfachen Client zählen:

| op | Name | Richtung | Zweck |
| --- | --- | --- | --- |
| 0 | Hello | OBS → Client | Serverversion, optionale Auth-Challenge |
| 1 | Identify | Client → OBS | rpcVersion, Auth-Antwort, Event-Abos |
| 2 | Identified | OBS → Client | Anmeldung akzeptiert |
| 5 | Event | OBS → Client | etwas ist passiert |
| 6 | Request | Client → OBS | etwas tun oder lesen |
| 7 | RequestResponse | OBS → Client | Ergebnis, über `requestId` zugeordnet |

{{< diagram src="neuroclip-3-obs-websocket-flow.svg" caption="Drei Phasen auf der Leitung: der Handshake, Request/Response-Paare und eine eigene, langlebige Verbindung, die nur die High-Volume-Pegel-Events empfängt." >}}

### Challenge-Response-Authentifizierung

Ist ein Passwort gesetzt, legt OBS in seine Hello-Nachricht ein `authentication`-Objekt mit `challenge` und `salt`. Der Client beweist, dass er das Passwort kennt, ohne es zu senden, wie im [Protokolldokument](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md#creating-an-authentication-string) beschrieben:

1. `secret = base64( sha256( password + salt ) )`
2. `authentication = base64( sha256( secret + challenge ) )`

SHA-256 ist in [FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final) spezifiziert. In Go sind das ein paar Zeilen, nur mit der Standardbibliothek:

```go
package main

import (
    "crypto/sha256"
    "encoding/base64"
    "fmt"
)

func authenticationString(password, salt, challenge string) string {
    secretSum := sha256.Sum256([]byte(password + salt))
    secret := base64.StdEncoding.EncodeToString(secretSum[:])

    answerSum := sha256.Sum256([]byte(secret + challenge))
    return base64.StdEncoding.EncodeToString(answerSum[:])
}

func main() {
    fmt.Println(authenticationString("password", "salt-from-hello", "challenge-from-hello"))
}
```

Der Rest des Handshakes: Hello lesen, mit Identify antworten (den Authentifizierungs-String nur mitschicken, wenn Hello einen `authentication`-Block enthielt) und op 2 erwarten. Zwei Details verdienen Aufmerksamkeit. Erstens: **Fehlt der Authentifizierungs-Block, hat OBS kein Passwort**, und das ist ein legitimes Setup auf einem Rechner, der nur Loopback nutzt. Zweitens: Gib dem Login einen Timeout, damit ein hängendes OBS keinen Aufrufer ewig blockiert; eine kontextbewusste WebSocket-Bibliothek wie [`coder/websocket`](https://github.com/coder/websocket) macht das einfach.

### Requests und Events

Ein Request ist op 6 mit `requestType`, `requestId` und optionalem `requestData`. Die Antwort (op 7) trägt dieselbe ID plus einen Status mit Ergebnis-Flag und Kommentar. Weil zwischen deinem Request und seiner Antwort Events eintreffen können, muss ein Client alles überspringen, was nicht die passende Antwort ist. Alles Nützliche (Szene wechseln, Replay-Puffer speichern, Eingang stummschalten, Aufnahmekapitel anlegen) ist ein solcher Request. Die vollständige Liste steht im [Protokolldokument](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md#requests).

## Designlektionen von der Live-Seite

Ein paar Entscheidungen haben geprägt, wie sich die Regie verhält. Ich beschreibe die Ideen und lasse die Zahlen weg.

**Eine kurzlebige Sitzung pro Aktion.** Für „Knopf drücken“ verbindet der einfachste Client, meldet sich an, schickt seine Requests und schließt wieder. Es gibt keinen Verbindungszustand, den man falsch behandeln könnte: keine Reconnect-Logik, keine halbtoten Sockets nach einem OBS-Neustart. Der Preis: Polling wird teuer, weil jede Abfrage eine frische Verbindung plus Login plus eine Reihe von Requests bedeutet.

**Statusabfragen teilen.** Als mehrere Teile des Produkts (das Dashboard, eine Handy-Fernbedienung, ein Warnungs-Wächter) alle den aktuellen Status wollten, vervielfachten sie die Last auf einem OBS, das gerade ein Spiel encodierte. Die Lösung ist das klassische Paar: Gleichzeitige Aufrufer warten auf einen laufenden Abruf, statt jeweils einen eigenen zu starten, und Ergebnisse werden für einen kurzen Moment wiederverwendet. Zwei Dinge brauchen Sorgfalt. Jede Aktion, die OBS verändert, muss den Cache verwerfen, sonst zeigt die nächste Abfrage veralteten Zustand. Und Aufrufer müssen Kopien bekommen, damit einer, der seine Sicht verändert, die der anderen nicht verfälscht. Vorher-nachher-Zahlen habe ich nicht veröffentlicht; das war eine Ermessensentscheidung, die ich mit keinem Benchmark belegen kann.

**Eine dauerhafte Verbindung nur für die Pegel.** Die eine Stelle, die eine dauerhafte Verbindung braucht, sind die Audio-Pegel. `InputVolumeMeters` ist ein *High-Volume*-Event, das das Protokoll standardmäßig ausschaltet; du abonnierst es mit einem Bit in der Identify-Nachricht. Diese Verbindung existiert nur, solange jemand tatsächlich aufs Dashboard schaut, sie verbindet sich nach Fehlern neu und meldet der Oberfläche, wenn die Verbindung zu OBS verloren ist. Jeder Abonnent braucht immer nur den *neuesten* Frame, ein langsamer Browser darf also weder den Produzenten noch die anderen Abonnenten blockieren. Der veraltete Frame wird verworfen, der neue behalten. Der Browser bekommt die Frames per Server-Sent Events, einem [WHATWG-Standard](https://html.spec.whatwg.org/multipage/server-sent-events.html), der für einen Einweg-Strom deutlich besser passt als ein zweiter WebSocket.

Zum Stand dieses Designs: Eine einzige dauerhafte Sitzung mit Events wäre der elegantere Endzustand und steht noch auf meiner Roadmap. Die jetzige Form ist einfach und schwer kaputtzumachen, und das geteilte Status-Lesen existiert genau wegen ihrer Kosten. Ein zustandsloses Design hat seinen Preis, und beim Polling zahlst du ihn.

## Audio-Pegel: dB, linear und die dritte Zahl

OBS meldet Pegel als **lineare Multiplikatoren** statt in Dezibel. Jeder Eingang hat ein Array pro Kanal, und jedes Array hat drei Werte: `[Magnitude, Peak, Eingangs-Peak]`. Magnitude und Peak werden *nach* Fader und Mute gemessen; der dritte Wert ist der Peak des Signals *vor* Fader und Mute. Merk dir diesen dritten Wert, er ist der ganze Trick des Stumm-Alarms.

Die Umrechnung nach dBFS ist die Lehrbuchformel `20 · log10(x)` mit einer Falle: Stille ist ein Multiplikator von `0`, und `log10(0)` ist `-Inf`. OBS meldet `-inf` für den Fader eines stillen Eingangs, was **JSON nicht transportieren kann**, also kommt es als `null` an. Am sichersten ist es, dB-Werten von der Leitung nie zu trauen und immer vom Multiplikator aus zu rechnen, mit Stille auf einen Floor begrenzt:

```go
package main

import (
    "fmt"
    "math"
)

const silentDecibels = -100.0

func multiplierToDecibels(multiplier float64) float64 {
    if multiplier <= 0 || math.IsNaN(multiplier) {
        return silentDecibels
    }
    return math.Max(silentDecibels, 20*math.Log10(multiplier))
}

func main() {
    fmt.Println(multiplierToDecibels(0.01)) // -40
    fmt.Println(multiplierToDecibels(0))    // -100
}
```

Zwischen zwei veröffentlichten Pegel-Frames behältst du pro Eingang das **Maximum** statt des Mittelwerts, damit ein kurzer Schrei trotzdem auftaucht. Und denke überall in dB: Ein linearer Wert von 0,01 entspricht −40 dBFS, −50 dBFS entsprechen etwa 0,003. Menschen denken in dB, während die Hardware lineare Werte meldet, und der klassische Bug ist ein um Größenordnungen verschobener Schwellwert. Halte jeden Schwellwert in dBFS und rechne genau einmal um, am Rand.

## Der Stumm-Alarm: Sprache durch ein stummes Mikrofon hören

Der Fehler, den ich abfangen wollte, ist peinlich und häufig: Du bist live, fängst an zu reden, und dein Mikrofon ist in OBS stummgeschaltet. Der Chat tippt „hören dich nicht“, und du kannst es nicht lesen, weil du im Spiel steckst.

Ein simpler „Mikro ist stumm“-Alarm ist nutzlos, denn Stummschalten ist legitim, fürs Husten, für einen Anruf, für eine AFK-Pause. Der Fehler ist, in ein stummes Mikro zu reden. Das Signal, das beides trennt, ist der **rohe Eingangs-Peak**, der dritte Wert von oben. Ein stummer Eingang hat Ausgang null, aber OBS misst weiter, was das Mikrofon *vor* dem Mute hört. Liegt dieser Rohpegel deutlich über dem Raumrauschen, spricht jemand.

{{< diagram src="neuroclip-3-mute-alarm.svg" caption="Der Stumm-Alarm als Zustandsautomat. Sprache wird über ein gleitendes Fenster beurteilt, nicht anhand eines einzelnen lauten Frames, und der Alarm schaltet sich selbst wieder scharf, statt einzurasten." >}}

In Worten: Der Alarm feuert, wenn das Mikrofon eine Weile stumm war *und* kürzlich eine nennenswerte Menge Schall deutlich über dem Grundrauschen gehört hat. Die Warnung wiederholt sich in ruhigem Abstand, solange der Zustand anhält, und das Aufheben der Stummschaltung räumt sofort alles ab.

### Ehrlich zur Hysterese

Wer hier einen Lehrbuch-Schmitt-Trigger erwartet (zwei Schwellen, eine fürs Hinein- und eine fürs Hinausgehen aus dem Alarmzustand), den muss ich enttäuschen: Der Alarm hat kein klassisches Hysterese-Band. Flattern vermeidet er mit drei anderen Mitteln:

1. **Zeitdauern statt Momentanpegel.** Ein lauter Frame bewirkt nichts; Schall muss sich über ein Fenster ansammeln. Ein Husten oder ein Tastenklick tut das nicht.
2. **Ein Abstand über dem Grundrauschen.** Ein stummes Mikrofon hört weiter den Raum; der Abstand hält Lüftergeräusche draußen.
3. **Ein Wiederholintervall statt erneutem Auslösen.** Die Warnung hat eine Identität, und der Wächter bleibt dazu still, bis das Intervall vorbei ist.

Eine zeitintegrierte Regel wie diese verträgt ein Signal, das genau an der Schwelle sitzt. Eine Regel, die auf einem einzelnen Momentanpegel ein- und ausschaltet, bräuchte echte Hysterese, also entscheide, welche der beiden du baust. Zwei praktische Details: Begrenze, wie viel Zeit ein einzelner Frame gutgeschrieben bekommen darf (sonst sieht eine hängende Verbindung mit einem lauten Frame danach wie eine Minute Sprache aus), und summiere Dauern, statt Frames zu zählen, damit die Regel nicht von der Frame-Rate abhängt.

### Wo der Alarm schweigen muss

Ein Alarm, der zu falschen Zeiten feuert, wird abgeschaltet, und dann schützt er niemanden. Deshalb ist er mit Bedingungen versehen: Er läuft nur beim Streamen, er schweigt in Szenen, in denen Stille erwartet wird (AFK, gleich geht's los), er schaut nur auf Eingänge, die wirklich Mikrofone sind, und es gibt einen Aus-Schalter. Die Schwellen sind konfigurierbar und werden beim Laden begrenzt, sodass der Rest des Codes sich nie gegen Unsinnswerte wehren muss.

Dieselbe Maschinerie setzt auch den schlichteren Cousin um, „Mikrofon oder Spielton ist zu lange still“, mit dem Peak nach dem Fader und ohne stummgeschaltete Eingänge, denn stumm zählt als still.

Eine strukturelle Entscheidung machte das alles gut testbar: Ein zustandsbehafteter Tracker sammelt Fakten, eine zustandslose Regel bewertet sie. Diese Trennung ist das IOSP-Prinzip (Integration vs. Operation) in der Praxis: Du baust ein Fakten-Struct, rufst die Regel auf und prüfst die Warnungen, ganz ohne OBS.

## Gesundheit, Marker und Fernsteuerung

Die Gesundheitswerte kommen aus `GetStats`, das Zähler liefert, die seit dem OBS-Start wachsen. Ein Zähler allein ist nutzlos („37.412 übersprungene Frames“ seit wann?), nützlich ist deshalb ein **Anteil über ein jüngeres Fenster**: Render-Lag, Encoder-Lag und Netzwerk-Drops als Prozent der Frames. Zwei Regeln gelten für jeden solchen Zähler: keine Anteile aus einem zu kurzen Fenster berechnen, und einen Zähler, der *rückwärts* läuft, als OBS-Neustart behandeln, der die Historie zurücksetzt.

Aktionen sind eine kleine geschlossene Menge. Hotkeys, Handy und Dashboard rufen denselben Runner, das Verhalten kann also nicht auseinanderlaufen. Die Marker-Aktion hat zwei Ziele: einen Twitch-Stream-Marker beim Streamen, ein Kapitel via `CreateRecordChapter` beim Aufnehmen. Kapitel brauchen **OBS 30.2 oder neuer und Hybrid-MP4-Aufnahmen**, daher lohnt es sich, den kryptischen „unknown request“-Fehler in genau diesen Hinweis zu übersetzen. Marker werden außerdem protokolliert, und die Werkzeuge nach dem Stream lesen sie als Highlights. Das ist die Brücke zur VOD-Seite, die [Teil 2](/de/blog/neuroclip-2-vod-to-short-pipeline/) behandelt.

Für Handy und Stream Deck bleibt die Haupt-API auf Loopback, und eine separate, winzige HTTP-Oberfläche bietet nur eine Handvoll Operationen, geschützt durch ein langes Zufallstoken. Muss ein Token in einer URL reisen, gehört es ins **Fragment**: Browser senden es nie an den Server, es landet also in keinem Zugriffslog. Das ist für ein Heimnetz gedacht; wer so etwas darüber hinaus erreichbar macht, setzt TLS davor.

Schließlich kostet all das CPU auf demselben Rechner, der das Spiel rendert und den Stream encodiert. Während OBS streamt, tritt das Produkt deshalb zurück: Die eigenen Kindprozesse laufen mit niedrigerer Priorität, Pegel-Frames werden seltener veröffentlicht, und geplante schwere Messungen warten bis nach dem Stream.

## Fallstricke, vor denen ich warnen würde

1. **dB vs. linear.** Schwellen in dBFS halten, am Rand umrechnen und daran denken, dass `-inf` in JSON zu `null` wird.
2. **Rohpegel vs. Pegel nach dem Fader.** Alarmierst du auf den Peak eines stummen Mikros nach dem Fader, hörst du nie etwas. Der Wert vor dem Mute trägt die Information.
3. **Zähler seit dem Start.** `GetStats`-Zähler brauchen ein Fenster und eine Reset-bei-Rückgang-Regel.
4. **High-Volume-Events sind aus gutem Grund Opt-in.** Für eine einzelne Pegel-Verbindung sind sie in Ordnung, aber fatal, wenn jeder Poller sie abonniert.
5. **Zeitbasierte Regeln brauchen austauschbare Uhren.** Damit ist „eine Weile stumm“ in Mikrosekunden testbar.
6. **Ein zustandsloses Design kostet etwas.** Es ist einfach und schwer kaputtzumachen, und seine Polling-Kosten sind der Grund, warum es geteilte Statusabfragen gibt.

## Wie es weitergeht

Die Regie ist die Live-Hälfte des Produkts. In [Teil 4](/de/blog/neuroclip-4-facecam-upscaling/) gehe ich zurück in die Postproduktion und schaue auf die GPU-hungrigste Stufe: Facecam-Material hochskalieren, eine Aufgabe, die wie alles Schwere im Produkt nicht mit einem laufenden Stream konkurrieren sollte. Einen Gesamtüberblick gibt die [Neuroclip-Seite](/de/page/neuroclip/); Early-Access-Anfragen gehen an info@noobygames.de.

Wenn du eigene OBS-Werkzeuge in Go baust, ist der beste Startpunkt weiterhin das [offizielle Protokolldokument](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md), das präzise und kurz ist. Und für die Go-Seite liefern meine Artikel zum [Prüfen von statischem Linking](/de/blog/check-static-linking/) und zu [Go in Docker](/de/blog/go-docker/) Hintergrund für das Packaging in [Teil 5](/de/blog/neuroclip-5-shipping-kubernetes/).
