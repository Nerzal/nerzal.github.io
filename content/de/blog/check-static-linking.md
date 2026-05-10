---
draft: false
title: "Wie man prüft, ob ein Binary statisch oder dynamisch gelinkt ist"
seo_title: "Go Binary auf statisches Linking prüfen"
date: 2023-01-02T23:46:14+01:00
tags: ["tutorial", "golang", "linking"]
description: "Lerne den Unterschied zwischen statischem und dynamischem Linking in Go und nutze Terminal-Tools, um die Portabilität deiner Anwendung zu prüfen."
images: ["img/statically_linked.png"]
featured_image: "img/statically_linked.png"
toc: true
---

## Was ist der Unterschied zwischen statisch und dynamisch gelinkten Binaries?

Statisch gelinkte Binaries und dynamisch gelinkte Binaries bezeichnen zwei unterschiedliche Arten, Software-Bibliotheken mit einem ausführbaren Programm zu verknüpfen.

Ein statisch gelinktes Binary **enthält alle notwendigen Bibliotheken** innerhalb der ausführbaren Datei selbst. Wenn das Programm ausgeführt wird, ist es daher auf keine externen Bibliotheken angewiesen, da alle benötigten Bibliotheken bereits im Binary enthalten sind. Statisches Linking erzeugt größere Binär-Dateien, aber sie sind portabler und in sich abgeschlossen.

Ein dynamisch gelinktes Binary hingegen verknüpft sich zur Laufzeit mit externen Bibliotheken, anstatt diese ins Binary selbst einzubetten. Wenn ein dynamisch gelinktes Binary ausgeführt wird, verlässt es sich auf Shared Libraries, die auf dem System installiert sind. Das führt zu kleineren Binär-Dateien, erfordert aber, dass das System die notwendigen Shared Libraries installiert hat, um das Programm ausführen zu können.

Kurz gesagt: Statisch gelinkte Binaries sind größer und selbst-enthaltend, während dynamisch gelinkte Binaries kleiner sind, aber auf externe Bibliotheken angewiesen sind. Die Wahl zwischen statischem und dynamischem Linking hängt von den spezifischen Anforderungen des Programms und der Zielumgebung ab.

## Wann sollte man statisch gelinkte Bibliotheken verwenden?

1. **Kommandozeilen-Tools**: Viele Kommandozeilen-Tools, wie Datei-Kompressions-Utilities oder Netzwerk-Monitoring-Tools, können als statisch gelinkte Binaries verteilt werden. Das ermöglicht es Nutzern, das Tool schnell und einfach herunterzuladen und auszuführen, ohne zusätzliche Abhängigkeiten installieren zu müssen.
2. **Eingebettete Systeme**: Bei der Entwicklung von Software für eingebettete Systeme kann statisches Linken der notwendigen Bibliotheken wichtig sein, um sicherzustellen, dass das Programm auf dem Gerät korrekt läuft, da die Zielumgebung möglicherweise begrenzte Ressourcen hat oder die benötigten Bibliotheken fehlen.
3. **Plattformübergreifende Software**: Programme, die auf mehreren Plattformen laufen müssen, wie Spiele oder Produktivitäts-Software, können als statisch gelinkte Binaries verteilt werden, um die Kompatibilität über verschiedene Betriebssysteme und Architekturen hinweg sicherzustellen.
4. **Sicherheitsorientierte Software**: Sicherheitsorientierte Software, wie Verschlüsselungs-Tools oder Passwort-Manager, kann als statisch gelinktes Binary verteilt werden, um die Angriffsfläche zu reduzieren und das Risiko von Schwachstellen zu minimieren.

## Prüfen, ob ein Binary statisch oder dynamisch gelinkt ist

Wir haben ein Go-CLI-Tool namens `swag` und möchten es in unsere CI-Pipeline integrieren. Es wäre daher hilfreich, das Binary statisch zu linken.

Schauen wir uns an, was der Go-Compiler mit Standard-Parametern produziert.

Das `-o`-Flag weist den Compiler an, wie die Ausgabe-Datei benannt werden soll.

Der Pfad ist der Pfad zur `main.go`-Datei.

> go build -o swag cmd/swag/main.go

Wir können jetzt den **file**-Befehl verwenden, um das Binary zu prüfen.

> file swag

Der Befehl gibt aus:

> swag: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, Go BuildID=gfj1RxRs_HuaewolHit9/HmUS_HdD_89W_XqAu3ee/wf7S14q1IwrJ5uuIdWJA/pmDUv61yXYXhrSKw7FtO, with debug_info, not stripped

Wir sehen, dass das Binary dynamisch gelinkt wurde.

Jetzt bauen wir dasselbe Go-Programm ohne CGO, was zu statisch gelinkten Binaries führen sollte.

> CGO_ENABLED=0 go build -o swag-static cmd/swag/main.go

Prüfen wir nun, ob wir ein statisch gelinktes Binary haben.

> file swag-static

Dieser Befehl produziert folgende Ausgabe:

> swag-static: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=7mPpucO9Ncafg5_JKWjE/DZbvRKfuHP9vWS79aEaM/3KcHlAJg9L4fvQnb8AL9/FxPS7iMjUAmw_Pc4KTaM, with debug_info, not stripped

Wir sehen, dass wir jetzt ein statisch gelinktes Binary haben.

## Fazit

Der **file**-Befehl kann verwendet werden, um herauszufinden, ob ein Binary statisch oder dynamisch gelinkt wurde.

Statisches Linking ist besonders relevant, wenn man Software in Containern ausliefert. Ein statisch gelinktes Go-Binary kann in einem `FROM scratch` Docker-Image ohne jegliche OS-Abhängigkeiten laufen — das kleinste und sicherste Image überhaupt. Wer Go-Anwendungen containerisieren möchte, findet dazu alle Details in [Containerisierung und Go: Eine starke Kombination](/de/blog/go-docker/).
