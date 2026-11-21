---
title: "Containerisierung und Go: Eine starke Kombination"
seo_title: "Go und Docker: Multi-Stage-Builds"
date: 2023-03-16
lastmod: 2026-11-13T17:36:59+01:00
draft: false
description: "Erfahre, warum Go ideal für Containerisierung ist und wie du Multi-Stage-Docker-Builds einsetzt, um minimale, sichere Produktions-Images zu erstellen."
images: ["img/go-docker.png"]
tags: ["go", "docker"]
featured_image: "img/go-docker.png"
toc: true
---

{{< tldr >}}
- Go passt gut zu Containern, weil es kleine, statisch gelinkte Binaries erzeugt, sich einfach für andere Plattformen und Architekturen cross-kompilieren lässt und Goroutinen und Channels eingebaut hat.
- Das Beispiel-Multi-Stage-Dockerfile baut mit `golang:1.27-alpine` und `CGO_ENABLED=0` und kopiert nur das Binary in `gcr.io/distroless/static-debian13:nonroot`.
- Das Distroless-Runtime-Image enthält nur CA-Zertifikate, Zeitzonendaten und ein paar Dateien wie `/etc/passwd`, ohne Shell und ohne Paketmanager.
- `USER nonroot:nonroot` führt die Go-Anwendung als UID 65532 statt als root aus; sie lauscht deshalb auf Port 8080, weil dieser User keine Ports unter 1024 binden kann.
- Container teilen sich den Host-Kernel und isolieren schwächer als virtuelle Maschinen, haben aber eine kleinere Angriffsfläche und werden durch ein neu gebautes Image gepatcht.
{{< /tldr >}}

## Einführung

Containerisierung gehört heute zur normalen Softwareentwicklung, weil sie das Deployen und Verwalten von Anwendungen in verschiedenen Umgebungen erleichtert. [Go](https://go.dev/) hat sich für containerisierte Anwendungen als sehr gut geeignet erwiesen.

In diesem Blog-Post sehen wir uns an, warum Go eine gute Wahl für containerisierte Anwendungen ist und wie es mit Containerisierungstechnologien wie Docker und Kubernetes zusammenarbeitet.

## Gos Vorteile für die Containerisierung

1. Leichtgewichtige Binaries: Go kompiliert zu kleinen, [statisch gelinkten Binaries](/de/blog/check-static-linking/), die alle Abhängigkeiten enthalten. Container-Images bleiben klein, starten schneller und brauchen weniger Ressourcen.

2. Cross-Compilation: Mit Go lassen sich Binaries einfach für verschiedene Plattformen und Architekturen cross-kompilieren, was das Erstellen von Multi-Plattform-Container-Images vereinfacht.

3. Performance: Go ist für seine hohe Leistung bekannt, und die zählt in containerisierten Umgebungen, in denen Ressourcen oft begrenzt sind.

4. Nebenläufigkeit: Goroutinen und Channels sind in die Sprache eingebaut. Damit schreibst du effiziente, responsive Anwendungen, die CPU und Speicher eines Containers gut ausnutzen.

5. Einfacher und wartbarer Code: Gos schlichte Syntax führt zu lesbarem, wartbarem Code, und das zahlt sich aus, sobald ein containerisiertes System groß wird.

## Go mit Docker integrieren

[Docker](https://www.docker.com/) ist eine beliebte Containerisierungsplattform, die das Verpacken, Verteilen und Ausführen von Anwendungen in Containern vereinfacht. Hier ist ein einfaches Beispiel für ein `Dockerfile` für eine Go-Anwendung:

```dockerfile
# Offizielles Golang-Base-Image
FROM golang:1.27-alpine AS build

# Arbeitsverzeichnis setzen
WORKDIR /app

# go.mod und go.sum kopieren
COPY go.mod go.sum ./

# Abhängigkeiten herunterladen
RUN go mod download

# Quell-Dateien kopieren
COPY . .

# Statisch gelinktes Binary ohne cgo bauen
RUN CGO_ENABLED=0 go build -o myapp

# Neue Stage von einem minimalen Distroless-Image, das als Non-Root-User läuft
FROM gcr.io/distroless/static-debian13:nonroot

# Arbeitsverzeichnis setzen
WORKDIR /app

# Binary aus der Build-Stage kopieren
COPY --from=build /app/myapp /app/

# Die Anwendung niemals als root ausführen
USER nonroot:nonroot

# Port der Anwendung freigeben
EXPOSE 8080

# Anwendung ausführen
CMD ["/app/myapp"]
```

Dieses `Dockerfile` baut ein Docker-Image für eine Go-Anwendung: Es startet mit dem offiziellen Golang-Base-Image, lädt die Abhängigkeiten herunter und kompiliert die Anwendung.

## Multi-Stage Dockerfiles

Multi-Stage Dockerfiles helfen, den Build-Prozess zu optimieren und das finale Docker-Image kleiner zu machen. Das Beispiel-`Dockerfile` oben nutzt bereits einen Multi-Stage-Build für ein kleineres, effizienteres Image. Das sind die Vorteile:

1. Trennung von Build- und Laufzeitumgebung: Du verwendest separate Base-Images für das Bauen und Ausführen der Anwendung. Die Build-Stage bekommt ein Image mit allen notwendigen Build-Tools und Abhängigkeiten, die Runtime-Stage wechselt auf ein minimales Image, und das finale Image bleibt klein.

2. Reduzierte Image-Größe: Nur das kompilierte Binary und erforderliche Assets werden von der Build-Stage in die Runtime-Stage kopiert, das finale Image schrumpft dadurch deutlich. Kleinere Images laden schneller, brauchen weniger Speicher und verbrauchen weniger Bandbreite.

3. Mehr Sicherheit: Ein minimales Runtime-Image mit nur den notwendigen Komponenten verkleinert die Angriffsfläche der Anwendung. Es gibt weniger Schwachstellen, die ein Angreifer in der Laufzeitumgebung ausnutzen könnte.

4. Schnellere Builds: Multi-Stage Dockerfiles ermöglichen ein besseres Caching von Zwischenbuild-Layern. Sind die Build-Schritte auf Stages aufgeteilt, nutzt Docker seinen Build-Cache effektiver, und die Builds werden schneller.

Schritt für Schritt macht das Multi-Stage-`Dockerfile` aus unserem Beispiel Folgendes:

- Die erste Stage, `FROM golang:1.27-alpine AS build`, verwendet das [offizielle Go-Alpine-Image](https://hub.docker.com/_/golang) als Basis für die Build-Umgebung. Dieses Image enthält den Go-Compiler und andere notwendige Build-Tools. Pinne die Go-Version, mit der du entwickelst, und aktualisiere sie regelmäßig: Das Go-Team unterstützt nur die [zwei neuesten Major-Releases](https://go.dev/doc/devel/release#policy).
- `CGO_ENABLED=0` sorgt dafür, dass der Go-Compiler ein [statisch gelinktes Binary](/de/blog/check-static-linking/) erzeugt, das nicht von der C-Bibliothek des Base-Images abhängt.
- Die zweite Stage, `FROM gcr.io/distroless/static-debian13:nonroot`, verwendet ein [Distroless](https://github.com/GoogleContainerTools/distroless)-Image für die Runtime-Umgebung. Es enthält nur CA-Zertifikate, Zeitzonendaten und ein paar Dateien wie `/etc/passwd`. Es gibt keine Shell und keinen Paketmanager, was einem Angreifer kaum Werkzeuge lässt.
- `USER nonroot:nonroot` führt die Anwendung als unprivilegierten User (UID 65532) statt als root aus. Gelingt es einem Angreifer, deine Anwendung auszunutzen, erhält er im Container keine root-Rechte. Da der User keine Ports unter 1024 binden kann, lauscht die Anwendung auf Port 8080.
- Der `COPY --from=build`-Befehl kopiert das kompilierte Binary von der Build-Stage in die Runtime-Stage, sodass nur die notwendigen Dateien im finalen Image landen.

## Sicherheitsaspekte: Container vs. Virtuelle Maschinen

Container und virtuelle Maschinen haben unterschiedliche Stärken und Schwächen bei der Sicherheit. Das sind die wichtigsten Unterschiede:

### Isolation

**Virtuelle Maschinen**: VMs isolieren Instanzen stark, weil jede VM ihr eigenes Betriebssystem ausführt und auf Hypervisor-Ebene getrennt ist. Eine kompromittierte VM beeinflusst andere VMs auf demselben Host daher kaum.

**Container**: Container teilen sich den OS-Kernel des Hosts und laufen in isolierten User-Space-Instanzen. Diese Isolation ist im Allgemeinen schwächer als bei VMs, weil Schwachstellen im Host-Kernel oder in der Container-Laufzeit alle Container auf dem Host betreffen können.

### Ressourcenverbrauch und Angriffsfläche

**Virtuelle Maschinen**: Jede VM führt ein vollständiges Betriebssystem aus. Das kostet mehr Ressourcen und vergrößert die Angriffsfläche, denn mehr Komponenten bedeuten mehr Stellen, an denen eine Schwachstelle stecken kann.

**Container**: Container sind leichtgewichtig und führen nur die Komponenten aus, die die Anwendung braucht. Sie verbrauchen weniger Ressourcen und haben eine kleinere Angriffsfläche, was sie für bestimmte Arten von Angriffen weniger anfällig macht.

### Patching und Updates

**Virtuelle Maschinen**: Das Patchen und Aktualisieren von VMs kann mehr Zeit und Ressourcen kosten, weil jede VM einzeln aktualisiert werden muss. Deshalb bleibt veraltete oder anfällige Software manchmal im Einsatz, einfach weil es mühsam ist, jede VM aktuell zu halten.

**Container**: Bei Containern aktualisierst du das Image und deployst neue Container daraus. Updates gehen schneller und einfacher, und die Anwendungen bleiben gepatcht.

### Sicherheits-Tools und -Praktiken

**Virtuelle Maschinen**: Traditionelle Sicherheits-Tools und -Praktiken wie Firewalls, Intrusion-Detection-Systeme und Antivirus-Software schützen VMs. Diese Tools sind oft nicht für containerisierte Umgebungen optimiert und schützen Container nicht unbedingt genauso gut.

**Container**: Container-spezifische Tools und Praktiken wie Vulnerability Scanning, Image Signing und Runtime Security Monitoring wurden für die besonderen Probleme containerisierter Umgebungen entwickelt. Mit ihnen lassen sich sichere und widerstandsfähige Container-Deployments betreiben.

Beide Modelle haben also eigene Sicherheitsvorteile und -herausforderungen. Lerne die Unterschiede kennen und wähle das Deployment-Modell nach den Sicherheitsanforderungen deiner Anwendung. Mit Best Practices und passenden Sicherheitsmaßnahmen kannst du sichere Anwendungen sowohl in Containern als auch auf VMs betreiben.


## Go und Kubernetes

[Kubernetes](https://kubernetes.io/) ist eine Orchestrierungsplattform für die Verwaltung containerisierter Anwendungen in großem Maßstab. Go wird häufig für Anwendungen verwendet, die auf Kubernetes laufen, und für Tools und Dienste, die mit der Kubernetes-API sprechen.

Das Kubernetes-Projekt selbst ist hauptsächlich in Go geschrieben. Wer Go kann, kann also zum Projekt beitragen und eigene Erweiterungen und Integrationen schreiben.

## Fazit

Go macht das Deployen, Skalieren und Verwalten containerisierter Anwendungen einfacher. Kleine statische Binaries, einfache Cross-Compilation und gute Performance ergeben effiziente, responsive Anwendungen, die gut auf Plattformen wie Docker und Kubernetes laufen.
