---
title: "Neuroclip"
seo_title: "Neuroclip: Shorts und YouTube-Folgen aus Twitch-Streams"
date: 2026-11-08T06:00:00+01:00
draft: false
toc: true
description: "Neuroclip macht aus Twitch-Streams Shorts mit Untertiteln und YouTube-Folgen, mit OBS-Alarmen und Facecam-Upscaling. Ein Go-Projekt im Early Access."
metric: "Early Access · Go + React"
featured_image: "img/neuroclip/og.png"
images: ["img/neuroclip/og.png"]
---

Neuroclip ist ein Werkzeug für Twitch-Streamer, das ich selbst gebaut habe: Es findet die besten Momente deiner Streams, schneidet daraus Hochformat-Shorts mit Untertiteln und lange YouTube-Folgen, bereitet Titel, Hashtags und Zeitplan vor und hilft dir live in OBS. Du prüfst die Vorschläge und gibst frei, was rausgeht.

![Neuroclip-Übersicht Heute mit Shorts und Folgen zur Abnahme](/img/neuroclip/heute-1440.jpg)

## Hinweis zum Early Access

Neuroclip ist heute eine **Einzelnutzer-Beta**. Ich benutze es täglich im eigenen Stream, aber es ist nicht zu kaufen, es gibt noch keinen Installer und die Einrichtung braucht Handarbeit. Die nächsten geplanten Schritte (Installation als ein Programm für Windows, eigener Claude-Schlüssel, Server-Betrieb, Review-Links für Cutter) haben keinen festen Termin. Wenn du auf dem Laufenden bleiben willst, [komm auf die Warteliste](#ausprobieren-oder-auf-die-warteliste).

## Vom Stream zu Shorts und Folgen

Nach dem Stream fängt die Arbeit erst an: Momente suchen, Untertitel tippen, Hochformat bauen, dreimal posten. Neuroclip übernimmt diesen Teil.

- Lautstärke, Chat-Spitzen, Schlagwörter und deine eigenen OBS-Marker zeigen, wo im Stream etwas passiert.
- Jeder Kandidat bekommt einen Score von 0 bis 10. Ab deiner Schwelle entsteht daraus ein fertiges Hochformat-Short.
- Vorschläge kommen mit Titel, Länge und Score, per KI (Claude) oder regelbasiert.
- Untertitel entstehen aus der Mikrofonspur und lassen sich Wort für Wort korrigieren.
- Lange YouTube-Folgen bekommen Kapitel und eine Untertitelspur.

## Projekt-Editor

Jeder Vorschlag öffnet sich in einem Zeitleisten-Editor. Du kürzt, korrigierst Untertitel und legst Einblendungen, Memes, Sounds und Effekte auf eigene Spuren. Ein Marker, den du live in OBS setzt, wird später zur Sprungmarke im Editor.

![Neuroclip-Projekt-Editor mit Zeitleiste und Spuren](/img/neuroclip/editor-1440.jpg)

## OBS-Regie und Alarme

Die Regie ist die Oberfläche für live: Szenen, Audio, Marker, Replay und Zähler an einem Ort, bedienbar am PC, per Hotkey, Stream Deck oder Handy. Während du spielst, passt Neuroclip auf.

- Alarm bei stummem Mikro, fehlendem Spielton oder fallender Bitrate
- Gesundheit von OBS: CPU, Render- und Encoder-Lag, freier Platz
- Live-Sparmodus: Neuroclip nimmt sich zurück, solange du streamst

![OBS-Regie mit Alarm bei stummem Mikro](/img/neuroclip/regie-1440.jpg)

## Folien und Karussells

Patch-Notes oder dein eigenes Projekt werden zu Folien. Du baust sie in einem Editor, der sich wie PowerPoint bedient, spielst sie im Stream ab oder exportierst sie als HTML, PDF und Foto-Karussell für TikTok und Instagram, immer mit Quellenangabe.

![Folien-Editor in Neuroclip](/img/neuroclip/folien-1440.jpg)

## KI-Facecam

Im Stream-Layout ist deine Webcam klein, im Hochformat wird sie stark vergrößert. Neuroclip rechnet nur den Kamera-Ausschnitt mit [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) hoch, das Spielbild bleibt unangetastet. Die Stärke ist einstellbar, das Ergebnis wird je Clip gespeichert. Das läuft nach dem Stream, nie währenddessen, weil es die Grafikkarte braucht.

![Facecam normal vergrößert](/img/neuroclip/facecam-vorher-460.jpg)
*Vorher: normal vergrößert.*

![Facecam mit KI-Modell hochgerechnet](/img/neuroclip/facecam-nachher-460.jpg)
*Nachher: mit dem KI-Modell hochgerechnet.*

## Upload zu YouTube, TikTok und Instagram

Titel, Texte, Hashtags, Cover und Zeitplan liegen je Plattform bereit. Für das Hochladen gilt überall dieselbe Regel: **Nichts geht ohne deine Freigabe online.**

- YouTube: Upload über die offizielle YouTube-API, nachdem du freigegeben hast.
- TikTok und Instagram: Eine Browser-Brücke füllt das Upload-Formular aus, auf „Posten“ klickst du selbst.

## Speicher aufräumen

Rohaufnahmen, VOD-Downloads und Zwischendateien belegen schnell Hunderte Gigabyte. Neuroclip zeigt, was weg kann und warum. Angeboten werden nur fertige Streams (Clips und Folgen erledigt), alles landet im Papierkorb und nie ohne deine Bestätigung, und die laufende Aufnahme bleibt immer liegen.

![Speicher-Ansicht in Neuroclip](/img/neuroclip/speicher-1440.jpg)

## Datenschutz: Deine Daten bleiben auf deinem Rechner

Aufnahmen, Clips und dein Profil liegen in einem Ordner auf deinem eigenen Rechner. Eine Ausnahme steuerst du selbst: Für Clip-Vorschläge und Titel kann Neuroclip die KI Claude von Anthropic nutzen, dann gehen Ausschnitte des Transkripts dorthin. Ohne KI gibt es eine regelbasierte Vorauswahl. Die Daten in den Screenshots sind meine eigenen, keine Daten anderer Personen.

## Gebaut mit

Neuroclip ist zuallererst ein Go-Engineering-Projekt. Der Stack:

- [Go](https://go.dev) für den Server
- [React](https://react.dev), [Vite](https://vite.dev) und TypeScript für das Dashboard
- [ffmpeg](https://ffmpeg.org) zum Schneiden und Rendern
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) für die Untertitel
- Real-ESRGAN für die Facecam
- [Kubernetes](https://kubernetes.io) fürs Deployment

Wie das alles funktioniert, beschreibe ich in einer Serie:

1. [Teil 1: Architektur](/de/blog/neuroclip-1-architecture/)
2. [Teil 2: Die VOD-zu-Short-Pipeline](/de/blog/neuroclip-2-vod-to-short-pipeline/)
3. [Teil 3: OBS-Regie](/de/blog/neuroclip-3-obs-regie/)
4. [Teil 4: Facecam-Upscaling](/de/blog/neuroclip-4-facecam-upscaling/)
5. [Teil 5: Ausliefern mit Kubernetes](/de/blog/neuroclip-5-shipping-kubernetes/)

## Ausprobieren oder auf die Warteliste

<div class="product-cta">

Besuche [neuroclip.de](https://neuroclip.de), schau dir die [Präsentation in 12 Folien](https://neuroclip.de/praesentation/) an oder [komm per Mail auf die Warteliste](mailto:info@noobygames.de?subject=Neuroclip%20Early%20Access). Schreib bitte den Link zu deinem Kanal dazu. Es gibt keinen Newsletter und kein Tracking, nur eine persönliche Antwort, sobald ein Platz frei wird.

</div>
