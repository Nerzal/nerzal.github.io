---
draft: false
title: "Wie man prüft, ob ein Binary statisch oder dynamisch gelinkt ist"
seo_title: "Go Binary auf statisches Linking prüfen"
date: 2023-01-02T23:46:14+01:00
lastmod: 2026-11-13T17:36:59+01:00
tags: ["tutorial", "golang", "linking"]
description: "Lerne den Unterschied zwischen statischem und dynamischem Linking in Go und nutze Terminal-Tools, um die Portabilität deiner Anwendung zu prüfen."
images: ["img/statically_linked.png"]
featured_image: "img/statically_linked.png"
toc: true
---

{{< tldr >}}
- Mit `file <binary>` siehst du, ob ein Linux-Binary „statically linked“ oder „dynamically linked“ ist; `ldd` meldet bei einem statischen Binary „not a dynamic executable“.
- Ein Standard-`go build` unter Linux ist dynamisch gelinkt, wenn cgo aktiviert ist, weil Pakete wie `net` und `os/user` dann die C-Bibliothek des Systems nutzen.
- Mit `CGO_ENABLED=0` entsteht ein statisch gelinktes Go-Binary, und `go version -m <binary>` zeigt die in jedes Go-Binary eingebettete `CGO_ENABLED`-Einstellung.
- Führe `ldd` nie auf Binaries aus, denen du nicht vertraust, denn je nach Implementierung kann es sie ausführen; `file` liest das Binary nur.
- Ein statisch gelinktes Binary bekommt keine Sicherheitsupdates deiner Linux-Distribution und muss neu gebaut und neu deployt werden, wenn eine eingebettete Bibliothek einen Fix bekommt.
{{< /tldr >}}

## Was ist der Unterschied zwischen statisch und dynamisch gelinkten Binaries?

Statisches und dynamisches Linking sind zwei Arten, Software-Bibliotheken mit einem ausführbaren Programm zu verknüpfen.

Ein statisch gelinktes Binary **enthält alle notwendigen Bibliotheken** innerhalb der ausführbaren Datei selbst. Zur Laufzeit ist das Programm daher auf keine externen Bibliotheken angewiesen. Statisches Linking erzeugt größere Binärdateien, aber sie sind portabler und in sich abgeschlossen.

Ein dynamisch gelinktes Binary hingegen verknüpft sich zur Laufzeit mit externen Bibliotheken, anstatt diese ins Binary selbst einzubetten. Wenn ein dynamisch gelinktes Binary ausgeführt wird, verlässt es sich auf Shared Libraries, die auf dem System installiert sind. Das führt zu kleineren Binärdateien, erfordert aber, dass das System die notwendigen Shared Libraries installiert hat, um das Programm ausführen zu können.

Welche Variante du wählst, hängt davon ab, was das Programm braucht und wo es laufen soll.

## Wann sollte man statisch gelinkte Bibliotheken verwenden?

1. Kommandozeilen-Tools: Viele Kommandozeilen-Tools, wie Kompressionsprogramme oder Netzwerk-Monitoring-Tools, können als statisch gelinkte Binaries verteilt werden. Nutzer laden das Tool herunter und führen es aus, ohne zusätzliche Abhängigkeiten zu installieren.
2. Eingebettete Systeme: Bei der Entwicklung von Software für eingebettete Systeme hilft statisches Linken der notwendigen Bibliotheken dabei, dass das Programm auf dem Gerät korrekt läuft, weil die Zielumgebung möglicherweise begrenzte Ressourcen hat oder die benötigten Bibliotheken fehlen.
3. Plattformübergreifende Software: Programme, die auf mehreren Plattformen laufen müssen, wie Spiele oder Produktivitäts-Software, können als statisch gelinkte Binaries verteilt werden, damit sie auf verschiedenen Betriebssystemen und Architekturen gleich funktionieren.
4. Sicherheitsorientierte Software: Sicherheitsorientierte Software, wie Verschlüsselungs-Tools oder Passwort-Manager, wird manchmal als statisch gelinktes Binary verteilt, weil sie sich zur Laufzeit keine manipulierte Shared Library unterschieben lässt (zum Beispiel über `LD_PRELOAD`). Das ist allerdings ein Trade-off: Eine statisch gelinkte Bibliothek bekommt **keine** Sicherheitsupdates, die deine Linux-Distribution ausliefert. Wird eine Schwachstelle in einer eingebetteten Bibliothek gefunden, muss das Binary neu gebaut und neu deployt werden. Außerdem tun sich Security-Scanner schwerer, verwundbare Bibliotheksversionen in einem statischen Binary zu finden. Statisches Linking verschiebt die Verantwortung fürs Patchen vom Betriebssystem zu dir.

## Prüfen, ob ein Binary statisch oder dynamisch gelinkt ist

Wir haben ein Go-CLI-Tool namens `swag` und möchten es in unsere CI-Pipeline integrieren. Es wäre daher hilfreich, das Binary statisch zu linken.

Schauen wir uns an, was der Go-Compiler mit Standard-Parametern produziert.

Das `-o`-Flag legt fest, wie die Ausgabedatei heißt, und der Pfad zeigt auf die Datei `main.go`.

```bash
go build -o swag cmd/swag/main.go
```

Wir können jetzt den [**file**](https://man7.org/linux/man-pages/man1/file.1.html)-Befehl verwenden, um das Binary zu prüfen.

```bash
file swag
```

Der Befehl gibt aus:

```text
swag: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, Go BuildID=gfj1RxRs_HuaewolHit9/HmUS_HdD_89W_XqAu3ee/wf7S14q1IwrJ5uuIdWJA/pmDUv61yXYXhrSKw7FtO, with debug_info, not stripped
```

Das Binary wurde dynamisch gelinkt. Der Grund ist [cgo](https://pkg.go.dev/cmd/cgo): Pakete wie `net` oder `os/user` nutzen die C-Bibliothek des Systems, wenn cgo aktiviert ist. Das ist unter Linux der Standard, sofern ein C-Compiler installiert ist.

Jetzt bauen wir dasselbe Go-Programm ohne cgo, was zu einem statisch gelinkten Binary führen sollte.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
CGO_ENABLED=0 go build -o swag-static cmd/swag/main.go
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# Ein Linux-Binary cross-kompilieren; file und ldd funktionieren nur mit Linux-ELF-Binaries
$env:CGO_ENABLED = "0"
$env:GOOS = "linux"
go build -o swag-static cmd/swag/main.go
```

{{< /os-tab >}}
{{< /os-tabs >}}

Prüfen wir nun, ob wir ein statisch gelinktes Binary haben.

```bash
file swag-static
```

Dieser Befehl produziert folgende Ausgabe:

```text
swag-static: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=7mPpucO9Ncafg5_JKWjE/DZbvRKfuHP9vWS79aEaM/3KcHlAJg9L4fvQnb8AL9/FxPS7iMjUAmw_Pc4KTaM, with debug_info, not stripped
```

Jetzt ist das Binary statisch gelinkt.

## Alternativen zum file-Befehl

### ldd

[`ldd`](https://man7.org/linux/man-pages/man1/ldd.1.html) gibt die Shared Libraries aus, die ein Binary zur Laufzeit benötigt:

```bash
ldd swag
```

Für das dynamisch gelinkte Binary listet es die Bibliotheken auf, z. B. `libc.so.6` und den dynamischen Loader `/lib64/ld-linux-x86-64.so.2`. Für das statisch gelinkte Binary meldet es, dass nichts zu laden ist:

```bash
ldd swag-static
```

```text
        not a dynamic executable
```

Führe `ldd` niemals auf Binaries aus, denen du nicht vertraust: Je nach Implementierung kann es das Binary ausführen. `file` liest es nur.

### go version -m

Wenn du nur das Binary hast, aber wissen willst, wie es gebaut wurde, kann Go selbst Auskunft geben. [`go version -m`](https://pkg.go.dev/cmd/go#hdr-Print_Go_version) gibt die Build-Informationen aus, die in jedes Go-Binary eingebettet sind, einschließlich der `CGO_ENABLED`-Einstellung. Das funktioniert auf jedem Betriebssystem, auch für Binaries, die für eine andere Plattform gebaut wurden:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
go version -m swag-static | grep CGO_ENABLED
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
go version -m swag-static | Select-String CGO_ENABLED
```

{{< /os-tab >}}
{{< /os-tabs >}}

```text
        build   CGO_ENABLED=0
```

`CGO_ENABLED=0` bedeutet, dass das Binary nicht gegen die C-Bibliothek gelinkt und damit statisch gelinkt ist (sofern keine speziellen Linker-Flags verwendet wurden).

### Ein Hinweis zu Windows

Unter Windows ist die Frage weniger relevant: Go-Binaries hängen dort nie von einer C-Runtime ab, sie laden nur System-DLLs wie `kernel32.dll`, die Teil jeder Windows-Installation sind. Wenn du die DLLs sehen willst, die eine Windows-Executable importiert, verwende `dumpbin /dependents myapp.exe` aus den [Visual-Studio-Entwicklertools](https://learn.microsoft.com/de-de/cpp/build/reference/dependents).

## Fazit

Mit dem **file**-Befehl findest du heraus, ob ein Binary statisch oder dynamisch gelinkt wurde. `ldd` und `go version -m` sind nützliche Alternativen.

Am meisten zählt statisches Linking, wenn du Software in Containern auslieferst. Ein statisch gelinktes Go-Binary kann in einem `FROM scratch`- oder Distroless-Docker-Image ohne jegliche OS-Abhängigkeiten laufen. Das ergibt ein sehr kleines Image, in dem ein Angreifer kaum etwas vorfindet, das er nutzen könnte. Denk nur daran, es regelmäßig neu zu bauen, damit es Fixes in Go und deinen Abhängigkeiten mitbekommt. Wer Go-Anwendungen containerisieren möchte, findet mehr dazu in [Containerisierung und Go: Eine starke Kombination](/de/blog/go-docker/).
