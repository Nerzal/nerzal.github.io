---
draft: false
title: "gocloak-Benchmarks, die finalen Zahlen: fünf HTTP-Stacks, json/v2 und eine kalte JVM"
seo_title: "gocloak-Benchmarks: resty, net/http und fasthttp gegen Keycloak, mit benchstat"
date: 2026-11-23T06:30:00+01:00
tags:
  [
    "go",
    "keycloak",
    "gocloak",
    "performance",
    "benchmark",
    "benchstat",
    "encoding-json-v2",
    "fasthttp",
    "resty",
    "docker",
    "open-source",
  ]
categories: ["Software Engineering"]
series: ["Das gocloak-Universum"]
description: "Die vollständigen benchstat-Tabellen für gocloak gegen ein Fake- und ein echtes Keycloak: fünf HTTP-Stacks, Connection-Pools, json/v2 über den ganzen Request-Pfad, dazu vier Benchmark-Fallen: eine kalte JVM, ein Docker-Portforwarder, den ein Client für den nächsten vergiftet hat, Git Bash, das benchstat-Flags umschreibt, und Laständerungen zwischen sequenziellen Läufen. Dazu, was gocloak v15.1.0 auf Go 1.27 ändert."
toc: true
---

> **Serie: Das gocloak-Universum.** [Teil 1: gocloak-mcp](/de/blog/gocloak-mcp-first-mcp-server-homebrew/) · [Teil 2: gocloak-auth-proxy](/de/blog/gocloak-auth-proxy-keycloak/) · [Teil 3: gocloak-Performance](/de/blog/gocloak-performance-json-v2-http-clients/) · Teil 4: die finalen Benchmark-Zahlen (du bist hier) · [Teil 5: pprof](/de/blog/gocloak-pprof-profiling/)

{{< tldr >}}
- Gegen ein echtes Keycloak 26.8.2 in Docker waren alle fünf HTTP-Stacks bei einzelnen Calls gleich schnell, fasthttp sparte nur bei kleinen Calls 6 bis 10 %.
- Mit 16 parallelen Callern über TLS und HTTP/1.1 machte ein Idle-Pool von 256 gocloak im verschränkten A/B-Lauf 2,6-mal so schnell und senkte die neuen Verbindungen um 98 %.
- Über gocloaks kompletten Request-Pfad senkt json/v2 die Allokationen bei jedem Call um 9 bis 44 %, messbar schneller werden aber nur die User-Listen (offline 19 bis 24 %).
- gocloak v15.1.0 hat keine Breaking Changes an der API: Es verlangt Go 1.27, hält 100 Idle-Verbindungen pro Host und bringt `SetDirectBodyRead()` als Opt-in.
- Eine kalte Keycloak-JVM ließ 1.000 User in meinem ersten Live-Lauf 153 bis 185 ms dauern, im finalen Lauf mit demselben Container und denselben Daten waren es 39 ms.
{{< /tldr >}}

In [Teil 3](/de/blog/gocloak-performance-json-v2-http-clients/) habe ich beschrieben, wie ich gocloak gegen Keycloak gebenchmarkt habe: die Fragen, das Setup, was kaputtging und die Schlussfolgerungen. Dieser Post enthält die vollständigen Tabellen aus dem finalen Lauf, für alle, die die Schlussfolgerungen an den Zahlen prüfen wollen, und vier Lektionen, die der finale Lauf dazugebracht hat.

## Umgebung

Alle Zahlen sind benchstat-Mediane mit n=8 (bei den verschränkten A/B-Läufen n=10) und `GOMAXPROCS=4`, gebaut mit Go 1.26.2, gegen Keycloak 26.8.2 in Docker Desktop unter Windows 11 (AMD Ryzen AI 9 HX 370). Auf derselben Maschine liefen andere Coding-Agents. Die Zeitwerte streuen stellenweise um 30 bis 40 %, die Allokationen sind deterministisch (±0 %). "n. s." heißt nicht signifikant.

Die fünf Stacks sind gocloak mit seinen Defaults, gocloak mit einem Idle-Pool von 256 Verbindungen pro Host, reines resty, net/http mit getuntem Pool und Streaming-Decoder sowie fasthttp. Der Benchmark-Code liegt in [`benchmarks/`](https://github.com/Nerzal/gocloak/tree/v15.1.0/benchmarks) im gocloak-Repository, zusammen mit `run.sh` und `profile.sh`. In v15.1.0 hält der Default 100 Idle-Verbindungen pro Host, deshalb heißen die Benchmarks jetzt anders: `gocloak` ist der neue Default, `gocloak-restypool` der alte resty-Pool und `gocloak-direct` nutzt `SetDirectBodyRead()`. Die Tabellen unten stammen von vor dieser Änderung.

## Offline: Fake-Keycloak, Plain HTTP/1.1, ein Caller nach dem anderen

Zeit pro Call, der Prozentwert vergleicht mit gocloaks Default:

| Endpoint | gocloak | gocloak, Pool 256 | resty | net/http | fasthttp |
| --- | ---: | ---: | ---: | ---: | ---: |
| Token | 233 µs | 238 µs (n. s.) | 245 µs (n. s.) | 198 µs (n. s.) | 127 µs (-46 %) |
| Ein User | 136 µs | 157 µs (+15 %) | 173 µs (+27 %) | 188 µs (+38 %) | 111 µs (-19 %) |
| 100 User | 1.637 µs | 1.075 µs (-34 %) | 833 µs (-49 %) | 1.148 µs (-30 %) | 636 µs (-61 %) |
| 1.000 User | 5,33 ms | 6,03 ms (n. s.) | 5,53 ms (n. s.) | 7,52 ms (+41 %) | 5,93 ms (n. s.) |
| Gruppen | 306 µs | 252 µs (-18 %) | 184 µs (-40 %) | 312 µs (n. s.) | 354 µs (+15 %) |
| Clients | 502 µs | 327 µs (-35 %) | 361 µs (-28 %) | 1.206 µs (+140 %) | 436 µs (n. s.) |

Ein durchgängiges Muster gibt es nicht. Die Pool-Einstellung macht einen sequenziellen Call nicht 15 % langsamer, und net/http ist nicht bei Clients 140 % langsamer und bei 100 Usern 30 % schneller. Das sind die Ausschläge einer belasteten Maschine. Selbst mit n=8 und p-Wert sagt die Zeitspalte offline kaum mehr als "dieselbe Größenordnung".

Die Bytes pro Call sind deterministisch und erzählen eine klare Geschichte:

| Bytes pro Call | gocloak | resty | net/http | fasthttp |
| --- | ---: | ---: | ---: | ---: |
| 1.000 User | 3,88 MiB | 2,42 MiB (-38 %) | 2,44 MiB (-37 %) | 1,93 MiB (-50 %) |
| Token | 35,2 KiB | 27,6 KiB | 29,5 KiB | 9,5 KiB (-73 %) |

Alle Stacks brauchen für 1.000 User 45.100 bis 45.200 Allokationen, denn die Objekte stammen aus dem JSON-Decoder. Die zusätzlichen 1,5 MiB bei gocloak kommen aus restys Umgang mit dem Body-Limit, das zeigt [Teil 5](/de/blog/gocloak-pprof-profiling/) im Memory-Profil. v15.1.0 bringt `SetDirectBodyRead()` als Opt-in mit, das den Großteil der Lücke schließt.

## Offline: 16 parallele Caller über TLS

16 Goroutines rufen parallel `GetUserByID` auf:

{{< diagram src="gocloak-pool-tls-h1.svg" caption="TLS mit HTTP/1.1. Der Default-Pool hält zu wenige Idle-Verbindungen, deshalb zahlen viele Calls für eine neue TCP-Verbindung und einen TLS-Handshake." >}}

| Stack | TLS + HTTP/1.1 | Dials pro 1.000 Calls | TLS + HTTP/2 |
| --- | ---: | ---: | ---: |
| gocloak (Default) | 51,0 µs | 30,4 | 25,2 µs |
| gocloak, Pool 256 | 28,2 µs (-45 %) | 1,09 (-96 %) | 27,8 µs |
| reines resty | 27,0 µs | 13,8 | 27,1 µs |
| net/http (getunt) | 19,2 µs (-62 %) | 0,77 | 22,4 µs |
| fasthttp | 14,4 µs (-72 %) | 0,14 | 9,2 µs (fällt auf HTTP/1.1 zurück) |

Unter HTTP/2 öffnet keiner der Go-Clients neue Verbindungen, und gocloaks Default ist so schnell wie der große Pool. Reines resty hat denselben Default-Pool wie gocloak, brauchte aber nur 13,8 Dials pro 1.000 Calls statt 30,4. Dieser Wert streut um ±64 %, live lag resty auf gocloak-Niveau (237 gegen 247), und gocloak läuft in jeder Gruppe als Erstes. Vermutlich Rauschen oder ein Reihenfolge-Effekt, verifiziert habe ich das nicht.

Auch Default- und großer Pool liefen hier nacheinander. Ein verschränkter A/B-Lauf nur dieser beiden ergibt 39,2 µs gegen 15,2 µs pro Call (-61 %, 2,6-mal so schnell) und 33,0 gegen 0,67 neue Verbindungen pro 1.000 Calls (-98 %). Die Bytes pro Call sinken um 25 %, die Allokationen um 15 %.

## Live: echtes Keycloak in Docker, Plain HTTP/1.1, ein Caller nach dem anderen

| Endpoint | gocloak | gocloak, Pool 256 | resty | net/http | fasthttp |
| --- | ---: | ---: | ---: | ---: | ---: |
| Token | 1,81 ms | 1,76 ms | 1,74 ms | 1,75 ms | 1,63 ms (-10 %) |
| Ein User | 906 µs | 938 µs | 952 µs | 959 µs | 820 µs (-9 %) |
| 100 User | 4,66 ms | 4,74 ms | 4,68 ms | 4,67 ms | 4,59 ms (n. s.) |
| 1.000 User | 39,8 ms | 38,9 ms | 39,4 ms | 39,0 ms | 38,6 ms (n. s.) |
| Gruppen | 3,03 ms | 2,99 ms | 3,00 ms | 3,03 ms | 2,92 ms (n. s.) |
| Clients | 1,25 ms | 1,28 ms | 1,23 ms | 1,24 ms | 1,18 ms (-6 %) |

Live sind alle Go-Varianten gleich schnell. fasthttp spart bei kleinen Calls 80 bis 180 µs, bei großen nichts Messbares. Bytes pro Call für 1.000 User live: gocloak 3,20 MiB, resty 2,19 MiB (-31 %), net/http 2,26 MiB (-29 %), fasthttp 1,35 MiB (-58 %). Beim Token alloziert fasthttp 85 % weniger Bytes.

### Live mit 16 parallelen Callern

| Stack | Zeit pro Call | Dials pro 1.000 Calls |
| --- | ---: | ---: |
| gocloak (Default) | 359 µs | 247 |
| gocloak, Pool 256 | 231 µs (-36 %) | 64 (-74 %) |
| reines resty | 442 µs (n. s.) | 237 |
| net/http (getunt) | 231 µs (-36 %) | 68 |
| fasthttp | 123 µs (-66 %) | 1,5 |

Die 64 Dials des großen Pools stammen aus den kurzen Ramp-Runden des Benchmarks, in denen sich der Pool füllt. In einem längeren Profiling-Lauf über 5 Sekunden öffnete der Default 309 Verbindungen pro 1.000 Calls, der große Pool 4.

Lokale Token-Verifikation mit `DecodeAccessToken`, echtem Keycloak-Token und warmem Cert-Cache: 50,5 µs.

## json/v2 über den ganzen gocloak-Pfad

Teil 3 hat die JSON-Engines isoliert verglichen. Hier derselbe Vergleich über gocloaks kompletten Request-Pfad, Default-Build gegen `GOEXPERIMENT=jsonv2`, als verschränkter A/B-Lauf gegen das Fake-Keycloak (n=10). Warum verschränkt, erklärt die vierte Lektion unten.

| gocloak-Call, offline | v1-Engine | v2-Engine | Änderung |
| --- | ---: | ---: | ---: |
| `GetUsers`, 100 User | 697 µs | 529 µs | -24 % |
| `GetUsers`, 1.000 User | 6,53 ms | 5,30 ms | -19 % |
| Token, ein User, Gruppen, Clients | | | nicht signifikant |
| `DecodeAccessToken` | 31,7 µs | 32,2 µs | nicht signifikant |

Nur die User-Listen werden messbar schneller. Bei den anderen Endpoints ist der JSON-Anteil neben dem HTTP-Handling und dem In-Process-Server zu klein. Das geometrische Mittel über alle A/B-Zeitwerte liegt bei -22 %.

Die Allokationen sinken überall: geometrisches Mittel -40 %, `GetUsers` -44 %, Clients -29 %, ein User -19 %, Token -9 %, `DecodeAccessToken` -21 %.

Live habe ich nur den sequenziellen Vergleich aus `run.sh`. Die Latenz ändert sich dort nicht signifikant: 1.000 User gehen von 39,8 auf 38,1 ms bei p=0,065, die übrigen Unterschiede liegen im Rauschen. Die Allokationen sinken wie offline.

json/v2 spart also Allokationen und etwas CPU im Client. Das zählt beim Durchsatz unter Last. Die Latenz eines einzelnen Calls ändert sich nicht, denn die dominiert Keycloak. Auf Go 1.27 ist die v2-Engine der Default, siehe [Teil 3](/de/blog/gocloak-performance-json-v2-http-clients/).

## v15.0 auf Go 1.26 gegen v15.1 auf Go 1.27

Die Befunde dieser Serie sind in gocloak v15.1.0 eingeflossen ([Release Notes](https://github.com/Nerzal/gocloak/releases/tag/v15.1.0), erschienen am 21. November 2026): Go 1.27 als Mindestversion, womit json/v2 die Default-Engine ist, 100 Idle-Verbindungen pro Host und `SetDirectBodyRead()` als Opt-in. `./ab.sh ref main` vergleicht den Branch mit main, die Baseline mit Go 1.26.2 gebaut, verschränkt wie zuvor.

Offline (n=10): `GetUsers` mit 1.000 Usern -24 % Zeit und -44 % Allokationen, Clients -20 % und -29 %, geometrisches Mittel über alle Endpoints -21 % Zeit und -27 % Allokationen. Der Pool-Benchmark fällt von 37,2 auf 15,8 µs pro Call (-57 %) und von 33,3 auf 0,64 neue Verbindungen pro 1.000 Calls.

Live gegen Keycloak (n=6): keine Latenzänderung, denn Keycloak dominiert. Die Allokationen sinken um 10 % (Token) bis 27 % (User-Listen), die Bytes um 3 bis 12 %, und mit 16 parallelen Callern die neuen Verbindungen um 70 % (187 auf 55 pro 1.000 Calls).

v15.1.0 hat keine Breaking Changes an der API. Die Models und das generierte `GoCloakIface` sind unverändert, der einzige neue Export ist `SetDirectBodyRead()`. Drei Dinge ändern sich für Nutzer trotzdem:

- `go.mod` verlangt Go 1.27. Mit dem Default `GOTOOLCHAIN=auto` lädt das go-Kommando 1.27 selbst herunter, mit `GOTOOLCHAIN=local` und einem älteren Go schlägt der Build fehl.
- Der Idle-Pool hat 100 Verbindungen pro Host statt GOMAXPROCS+1.
- Auf Go 1.27 kann `encoding/json` für ungültiges JSON andere Fehlertexte liefern. Wer Fehlerstrings vergleicht, sollte das prüfen. `GOEXPERIMENT=nojsonv2` wählt die alte Engine.

Wer in den Diff schaut, sieht in den Testdateien jetzt `PolicyRepresentation{Clients: []string{...}}` statt des Umwegs über die eingebettete `ClientPolicyRepresentation`. Das ist neue Syntax aus Go 1.27: Composite Literals dürfen promotete Felder eingebetteter Structs direkt setzen, und der `embedlit`-Check des Linters (modernize) verlangt das. Das Struct ist dasselbe, die alte Schreibweise kompiliert weiterhin.

## Vier Lektionen aus dem finalen Lauf

### Eine kalte JVM lügt

In meinem allerersten Live-Lauf brauchten 1.000 User 153 bis 185 ms. Im finalen Lauf waren es 39 ms. Derselbe Keycloak-Container, dieselben Daten, derselbe Client. Der Unterschied ist die JVM: Keycloak wird über viele Requests immer schneller, während der JIT-Compiler heiße Pfade optimiert und sich die Caches füllen. Die 300 Aufwärm-Calls pro Endpoint im Setup reichten für den ersten Lauf nicht.

Bei einem JVM-Server wie Keycloak großzügig aufwärmen und mehrere Läufe vergleichen, bevor man einer Zahl traut. Ein Benchmark gegen ein frisch gestartetes Keycloak misst das Aufwärmen, nicht den Dauerzustand.

### Ein Benchmark-Client kann den nächsten vergiften

Der erste komplette Lauf scheiterte im Live-Pool-Benchmark. Nach dem Default-gocloak-Client mit seinem massiven Verbindungs-Churn liefen die folgenden Clients in Dial-Timeouts gegen `[::1]:8080`. Der Churn hatte den Portforwarder von Docker Desktop unter Windows überlastet. Selbst der große Pool zeigte plötzlich 300 Dials pro 1.000 Calls und 1,1 ms statt 0,2 ms pro Call. Der vorherige Client hatte dem nächsten die Bedingungen ruiniert.

Die Lösung ist eine konfigurierbare Abkühlzeit pro Ziel vor jedem Pool-Client: offline 2 Sekunden, live 15 Sekunden. Danach lief der komplette Lauf fehlerfrei durch. Wenn Benchmarks in fester Reihenfolge gegen gemeinsame Infrastruktur laufen, lohnt sich die Prüfung, ob ein späterer Kandidat das Chaos eines früheren erbt. Ein Lauf in anderer Reihenfolge ist ein billiger Test.

### Git Bash schreibt Argumente um, die mit einem Slash beginnen

`go tool benchstat -col /client` scheiterte unter Git Bash auf Windows:

```text
parsing -col: syntax error: expected key
```

MSYS, die Schicht unter Git Bash, wandelt Argumente, die wie absolute Unix-Pfade aussehen, in Windows-Pfade um. Aus `/client` wurde etwas wie `C:/Program Files/Git/client`. `MSYS_NO_PATHCONV=1` schaltet das ab:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# hier wird nichts umgewandelt
go tool benchstat -col /client results/offline-v1.txt
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# PowerShell reicht /client unverändert durch
go tool benchstat -col /client results/offline-v1.txt

# in Git Bash unter Windows stattdessen:
# MSYS_NO_PATHCONV=1 go tool benchstat -col /client results/offline-v1.txt
```

{{< /os-tab >}}
{{< /os-tabs >}}

Noch eine kleinere Notiz: `run.sh` nutzt `set -o pipefail`, ein einzelner fehlgeschlagener Benchmark bricht also den Rest des Laufs ab. Das ist gewollt. Lieber ein abgebrochener Lauf als ein halber Datensatz, der vollständig aussieht.

### Alt und neu verschränken

Die `run.sh`-Vergleiche der JSON-Engines ließen die v1- und die v2-Suite nacheinander laufen, Minuten auseinander. Dazwischen änderte sich die Last auf der Maschine und täuschte Effekte von bis zu ±40 % vor. `DecodeAccessToken` sah mit json/v2 offline 35 % langsamer und live 39 % schneller aus, der verschränkte A/B-Lauf zeigt keinen Unterschied. `go test -count` macht es schlimmer, weil es dieselbe Sub-Benchmark achtmal direkt hintereinander ausführt. Eine Lastspitze trifft dann alle acht Samples einer Variante.

Dasselbe Artefakt hatte in meinem ersten Entwurf dieses Posts eine offene Frage erzeugt: Die Token-Response schien nur über die direkte v2-API zu profitieren (32,4 gegen 4,4 µs). Im A/B-Lauf ist auch die v1-API auf der v2-Engine 74 % schneller (14,2 auf 3,7 µs). Die 32 µs stammten aus einer Lastphase.

`benchmarks/ab.sh` baut beide Varianten einmal per `go test -c` und führt sie 10 Runden lang abwechselnd aus, ein Sample pro Runde, mit wechselnder Reihenfolge. [Teil 3](/de/blog/gocloak-performance-json-v2-http-clients/) zeigt die Schleife. Wer alt gegen neu auf einer Maschine vergleicht, deren Last er nicht kontrolliert, sollte die Läufe verschränken.

## Was die finalen Zahlen ändern

Die Schlussfolgerungen aus Teil 3 halten, mit schärferen Zahlen:

- Live spielt der HTTP-Client für die Latenz keine Rolle. Alle Go-Stacks liegen im Rauschen beieinander, fasthttp spart bei kleinen Calls 6 bis 10 %.
- Der Connection-Pool zählt unter paralleler Last: offline über TLS im verschränkten A/B-Lauf 2,6-mal so schnell, live ohne TLS 36 % schneller, und 98 % weniger neue Verbindungen. v15.1.0 hält 100 Idle-Verbindungen pro Host.
- json/v2 senkt die Allokationen bei jedem Call um 9 bis 44 %. Über den ganzen gocloak-Pfad werden nur die User-Listen messbar schneller (offline 19 bis 24 %), und die Live-Latenz ändert sich nicht.
- gocloak alloziert wegen des Body-Limits 30 bis 60 % mehr Bytes als reines resty. `SetDirectBodyRead()` in v15.1.0 spart bei 1.000 Usern 39 %.

Offen blieb die Frage, wo genau die Zeit hingeht und warum gocloak so viel alloziert. Darauf antworten die Profile in [Teil 5](/de/blog/gocloak-pprof-profiling/).
