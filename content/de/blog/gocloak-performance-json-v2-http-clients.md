---
draft: false
title: "Wie schnell spricht gocloak mit Keycloak? json/v2, fasthttp und der Connection-Pool"
seo_title: "gocloak Performance: encoding/json/v2, fasthttp und HTTP-Connection-Pools in Go"
date: 2026-11-22T06:30:00+01:00
tags:
  [
    "go",
    "keycloak",
    "gocloak",
    "performance",
    "benchmark",
    "json",
    "encoding-json-v2",
    "fasthttp",
    "resty",
    "http",
    "open-source",
  ]
categories: ["Software Engineering"]
series: ["Das gocloak-Universum"]
description: "gocloak gegen Keycloak 26 gebenchmarkt: encoding/json/v2 dekodiert Keycloak-Payloads ohne Codeänderung 26 bis 74 % schneller, kodiert kleine Structs aber langsamer, fasthttp gewinnt Mikrobenchmarks, spielt gegen ein echtes Keycloak aber kaum eine Rolle, und unter paralleler Last bremst vor allem der Default-Connection-Pool von resty. Go 1.27 macht json/v2 zum Default, gocloak v15.1.0 behebt den Pool."
toc: true
---

> **Serie: Das gocloak-Universum.** [Teil 1: gocloak-mcp](/de/blog/gocloak-mcp-first-mcp-server-homebrew/) · [Teil 2: gocloak-auth-proxy](/de/blog/gocloak-auth-proxy-keycloak/) · Teil 3: gocloak-Performance (du bist hier) · [Teil 4: die finalen Benchmark-Zahlen](/de/blog/gocloak-performance-final-benchmarks/) · [Teil 5: pprof](/de/blog/gocloak-pprof-profiling/)

{{< tldr >}}
- Die json/v2-Engine dekodiert Keycloak-Payloads ohne Codeänderung in gocloak 26 bis 74 % schneller, kodiert kleine Structs aber 39 bis 51 % langsamer.
- fasthttp ist in den meisten Mikrobenchmarks der schnellste Stack, spart gegen ein echtes Keycloak aber nur 6 bis 10 % bei kleinen Calls, nichts bei großen, und kann kein HTTP/2.
- Unter paralleler Last bremst restys Default `MaxIdleConnsPerHost` von `GOMAXPROCS + 1`; mit einem Pool von 256 war gocloak im verschränkten A/B-Lauf 2,6-mal so schnell.
- gocloak v15.1.0 setzt Go 1.27 voraus, wo json/v2 die Default-Engine ist, hebt beide Idle-Limits auf 100 und bringt das Opt-in `SetDirectBodyRead()`, das die Bytes pro Call bei 1.000 Usern um 39 % senkt.
- Jede Alt-gegen-neu-Zahl in diesem Post stammt aus einem verschränkten A/B-Lauf, weil getrennte Läufe auf meiner ausgelasteten Maschine Effekte von bis zu ±40 % vorgetäuscht haben.
{{< /tldr >}}

Lässt sich in der Kommunikation zwischen gocloak, dem Go-Client für die Keycloak REST API, und Keycloak noch "massiv" Performance holen? Darauf wollte ich eine Zahl statt eines Bauchgefühls, also habe ich drei Dinge geprüft:

1. Bringt das neue [`encoding/json/v2`](https://pkg.go.dev/encoding/json/v2) etwas bei üblichen Keycloak-Payloads?
2. Hilft ein anderer HTTP-Client, [fasthttp](https://github.com/valyala/fasthttp) oder ein anderer?
3. Gibt es sonst Hebel?

Kurz gesagt: json/v2 dekodiert Keycloak-Payloads 26 bis 74 % schneller, ohne eine einzige Codezeile zu ändern (User-Listen rund ein Drittel), kodiert kleine Structs aber 39 bis 51 % langsamer. fasthttp ist in den meisten Mikrobenchmarks der schnellste Stack, spart gegen ein echtes Keycloak aber höchstens ein Zehntel bei kleinen Calls und nichts bei großen. Und unter paralleler Last bremst vor allem ein Default im Connection-Pool, auf den kaum jemand schaut. Zwei Ergebnisse haben gocloak schon verändert: v15.1.0 setzt Go 1.27 voraus, wo json/v2 die Default-Engine ist, und hält 100 Idle-Verbindungen pro Host.

Dieser Post zeigt, wie ich vorgegangen bin, was unterwegs schiefging und die Ergebnisse. [Teil 4](/de/blog/gocloak-performance-final-benchmarks/) enthält die vollständigen benchstat-Tabellen und was mich der finale Lauf gelehrt hat, [Teil 5](/de/blog/gocloak-pprof-profiling/) die CPU- und Memory-Profile.

Der Rahmen: gocloak v15, Go 1.26.2, [resty](https://github.com/go-resty/resty) v2.17.2 als HTTP-Schicht, Keycloak 26.8.2 in Docker, auf einem AMD Ryzen AI 9 HX 370 (24 logische Kerne) mit Windows 11.

## Erst den Code lesen, dann messen

Alle gocloak-Calls laufen über einen gemeinsamen resty-Client. `NewClient` erzeugt ihn mit `resty.New()`, einem Timeout, einem Limit für den Response-Body und einer Redirect-Policy, die nur Weiterleitungen auf denselben Origin folgt. resty liest den Body komplett in den Speicher und ruft danach `json.Unmarshal` auf. Gestreamt wird nichts.

Bevor ich den ersten Benchmark geschrieben habe, habe ich die Fakten geprüft, die ich zu kennen glaubte. Die Hälfte davon war falsch oder veraltet:

- `go list encoding/json/v2` ohne Flag antwortet mit `build constraints exclude all Go files`. json/v2 steckt in Go 1.26 weiterhin hinter `GOEXPERIMENT=jsonv2`. Go 1.27 hat das geändert, was ich zuerst übersehen habe, dazu unten mehr.
- resty v3 gibt es nur als Release Candidate (v3.0.0-rc.4) und scheidet damit aus.
- fasthttp v1.79.0 ist aktuell.
- resty hat `SetJSONMarshaler` und `SetJSONUnmarshaler`. Nutzer können die JSON-Implementierung also tauschen, ohne dass gocloak etwas ändern muss.

Die üblichen Verdächtigen für versteckten Overhead habe ich auch geprüft. gocloak cacht die JWKS-Zertifikate, parst die Public Keys einmal pro Fetch und legt sie in einer Map nach `kid` ab. Die Token-Verifikation hat also keinen versteckten Netzwerk-Call und keinen Parse-Schritt. Die Serverversion wird ebenfalls gecacht.

Beim Lesen des resty-Quelltexts kam der erste echte Befund. Der Default-Transport setzt `MaxIdleConnsPerHost` auf `GOMAXPROCS + 1`. Keycloak ist für gocloak genau ein Host, und seit [Go 1.25 berücksichtigt GOMAXPROCS die cgroup-CPU-Limits](https://go.dev/doc/go1.25#container-aware-gomaxprocs). Ein Pod mit einem CPU-Limit von 1 hält damit höchstens zwei Idle-Verbindungen zu Keycloak offen. Warum das wehtut, steht weiter unten.

## Das Benchmark-Setup

Die Benchmarks liegen in einem eigenen Go-Modul unter [`benchmarks/`](https://github.com/Nerzal/gocloak/tree/v15.1.0/benchmarks) im gocloak-Repository, mit eigener `go.mod` und einer `replace`-Direktive auf das Hauptmodul. So landen fasthttp und benchstat nie in den Abhängigkeiten der Library.

Es gibt zwei Stufen:

- **Offline:** Ein In-Process-Fake-Keycloak auf Basis von [`net/http/httptest`](https://pkg.go.dev/net/http/httptest) liefert realistische Payloads auf den echten gocloak-URL-Pfaden. Das läuft ohne Docker, ist reproduzierbar und isoliert den Client-Overhead.
- **Live:** Dieselben Benchmarks gegen das echte Keycloak in Docker, hinter dem Build-Tag `keycloak`. Das Setup legt 1.000 User und 20 Gruppen mit je 5 Untergruppen an und wärmt Keycloak mit 300 Calls pro Endpoint auf, damit JIT und Caches heiß sind. Danach löscht es die Daten wieder und räumt vor dem Start auch Reste eines abgebrochenen Laufs ab. Das Admin-Token lebt im master-Realm 60 Sekunden. Eine Hintergrund-Goroutine erneuert es, damit nie ein Login in eine Messung fällt.

Die Payloads sind das, was eine Anwendung tatsächlich von Keycloak bekommt: eine Token-Response mit echt signierten RS256-JWTs, das JWKS, ein einzelner User, Listen mit 100 und 1.000 Usern, ein Gruppenbaum, die Clients und der komplette Realm-Export aus `testdata/gocloak-realm.json` (73 KB, ein echter Keycloak-Export).

Verglichen habe ich fünf HTTP-Stacks:

| Stack | Was er zeigt |
| --- | --- |
| gocloak (Default) | Was Nutzer heute bekommen |
| gocloak mit Idle-Pool 256 | Effekt einer einzigen Transport-Einstellung |
| reines resty | gocloaks eigener Overhead, herausgerechnet |
| net/http, getunter Pool, Streaming-Decoder | Was die Standardbibliothek kann |
| fasthttp | Der übliche Vorschlag "nimm doch fasthttp" |

Ein Skript, `run.sh`, führt alles mit festen Parametern aus: `COUNT=10`, `GOMAXPROCS=4`, `-benchtime 1s`. Jede Suite läuft einmal mit Standard-JSON und einmal mit `GOEXPERIMENT=jsonv2`. Rohdaten, benchstat-Vergleiche, Go-Version und Commit-Hash landen in `results/<timestamp>/`. Im Kopf des Skripts steht, dass es nur auf einer sonst ruhigen Maschine laufen soll.

[benchstat](https://pkg.go.dev/golang.org/x/perf/cmd/benchstat) ist als Go-Tool-Abhängigkeit eingebunden (`go tool benchstat`). Wer es global haben will:

```bash
go install golang.org/x/perf/cmd/benchstat@latest
```

So laufen die Suites. `run.sh` braucht eine Bash, unter Windows also Git Bash oder WSL, oder man ruft `go test` direkt auf:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
cd benchmarks
./run.sh offline              # ohne Docker
./run.sh live                 # startet Keycloak bei Bedarf per docker compose

# einzelne Suite von Hand, einmal pro JSON-Engine
go test -run '^$' -bench '^BenchmarkJSON' -benchmem -count 10 -cpu 4 . > v1.txt
GOEXPERIMENT=jsonv2 go test -run '^$' -bench '^BenchmarkJSON' -benchmem -count 10 -cpu 4 . > v2.txt
go tool benchstat v1engine=v1.txt v2engine=v2.txt
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
cd benchmarks
go test -run '^$' -bench '^BenchmarkJSON' -benchmem -count 10 -cpu 4 . > v1.txt
$env:GOEXPERIMENT = "jsonv2"
go test -run '^$' -bench '^BenchmarkJSON' -benchmem -count 10 -cpu 4 . > v2.txt
Remove-Item Env:GOEXPERIMENT
go tool benchstat v1engine=v1.txt v2engine=v2.txt
```

{{< /os-tab >}}
{{< /os-tabs >}}

### Fallen in der Methodik

Der In-Process-Server verbraucht selbst CPU, auf denselben Kernen wie der Client. Das bläht die Gesamtwerte auf. Deshalb vergleiche ich absolute Differenzen in ns/op und allocs/op zwischen den Clients, keine Prozentwerte vom Gesamtwert.

Das größere Problem war mein eigener Rechner. Parallel liefen andere Coding-Agents, und Einzelläufe streuten stark: Ein JSON-Benchmark sprang zwischen zwei Läufen auf das 2,4-Fache. Eine einzelne Zahl von einer belasteten Maschine sagt nichts. Darum ist jedes Ergebnis in diesem Post ein benchstat-Median (n=8, bei den A/B-Läufen n=10), das Median, Konfidenzintervall und p-Wert ausgibt. Trotzdem streuen die Zeitwerte auf dieser Maschine um bis zu 30 bis 40 %. Allokationen und Bytes pro Operation sind deterministisch, denen traue ich mehr. Das Skript gibt es, damit jeder den Lauf auf einer ruhigen Maschine wiederholen kann.

Mediane schützen nicht vor einer Laständerung zwischen zwei Läufen. Mein erster Vergleich der JSON-Engines ließ erst die v1-Suite laufen und Minuten später die v2-Suite. Dazwischen änderte sich die Last auf der Maschine, und das allein hat Effekte von bis zu ±40 % vorgetäuscht. Das deutlichste Beispiel war die lokale Token-Verifikation: Mit json/v2 sah sie offline 35 % langsamer und live 39 % schneller aus. In einem fairen Vergleich gibt es überhaupt keinen Unterschied.

Deshalb stammt jede Alt-gegen-neu-Zahl in diesem Post aus einem verschränkten A/B-Lauf (`benchmarks/ab.sh`). Beide Varianten werden einmal als Test-Binary gebaut und dann 10 Runden lang abwechselnd mit je einem Sample ausgeführt, die Reihenfolge wechselt jede Runde. Eine Lastspitze trifft dann beide Varianten gleich:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
go test -c -o v1.test .
GOEXPERIMENT=jsonv2 go test -c -o v2.test .
for round in $(seq 1 10); do
  if [ $((round % 2)) -eq 1 ]; then order="v1 v2"; else order="v2 v1"; fi
  for variant in $order; do
    ./$variant.test -test.run '^$' -test.bench '^BenchmarkJSON' -test.benchmem -test.count 1 -test.cpu 4 >> $variant.txt
  done
done
go tool benchstat v1engine=v1.txt v2engine=v2.txt
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
go test -c -o v1.test.exe .
$env:GOEXPERIMENT = "jsonv2"; go test -c -o v2.test.exe .; Remove-Item Env:GOEXPERIMENT
foreach ($round in 1..10) {
  $order = if ($round % 2) { "v1", "v2" } else { "v2", "v1" }
  foreach ($variant in $order) {
    & ".\$variant.test.exe" -test.run '^$' -test.bench '^BenchmarkJSON' -test.benchmem -test.count 1 -test.cpu 4 |
      Out-File -Append -Encoding utf8 "$variant.txt"
  }
}
go tool benchstat v1engine=v1.txt v2engine=v2.txt
```

{{< /os-tab >}}
{{< /os-tabs >}}

`go test -count 8` macht das Gegenteil: Es führt dieselbe Sub-Benchmark achtmal direkt hintereinander aus, eine Lastspitze landet also in allen acht Samples einer Variante und in keinem der anderen.

fasthttp gibt gepoolte Buffer zurück, die nach dem Freigeben des Requests wiederverwendet werden. Dass das hier sicher ist, habe ich geprüft: `json.Unmarshal` kopiert die Strings aus dem Buffer heraus, bevor er zurück in den Pool geht.

## Was unterwegs kaputtging

### fasthttp trifft auf HTTP/2

Der erste fasthttp-Lauf gegen den TLS-Testserver scheiterte mit:

```text
http2: server: error reading preface from client: bogus greeting
```

Die TLS-Config des Testservers bietet per ALPN `h2` an, und fasthttp spricht nur HTTP/1.1. Für den Benchmark war die Lösung, `NextProtos` für fasthttp auf `["http/1.1"]` zu setzen. Für die Praxis heißt das: fasthttp kann überhaupt kein HTTP/2.

### Der Pool-Benchmark, der den Listener lahmlegte

Der Pool-Benchmark schickt viele parallele Caller über TLS mit HTTP/1.1. Mit dem gocloak/resty-Default-Pool ist er komplett gescheitert. 32 bis 192 Goroutines teilten sich 5 bzw. 25 Idle-Verbindungen. Verbindungen wurden ständig geschlossen und neu aufgebaut, jedes Mal mit neuem TLS-Handshake, bis der Windows-Listener neue Verbindungen verweigerte:

```text
connectex: Es konnte keine Verbindung hergestellt werden, da der Zielcomputer die Verbindung verweigerte.
```

net/http und fasthttp mit großem Pool liefen durch denselben Test ohne Fehler. Ich habe den Benchmark so umgebaut, dass er Fehler und neue Verbindungen als Metriken zählt (`dials/1k-op` und `fails/1k-op`), statt abzubrechen. Außerdem bekommt jeder Client vor seiner Messung zwei Sekunden Abkühlzeit, damit er keinen vollen Accept-Backlog vom Vorgänger erbt.

Meine erste Version dieser Abkühlzeit lag in der gemessenen Schleife. Mit `b.N = 1` in der ersten Ramp-Runde waren das zwei Sekunden pro Operation, und das hat verfälscht, wie das testing-Paket `b.N` hochskaliert. Die Korrektur: nur in der ersten Runde schlafen, vor `b.ResetTimer()`.

## Ergebnis 1: encoding/json/v2

Mit `GOEXPERIMENT=jsonv2` läuft auch die alte `encoding/json`-API (v1) auf der neuen v2-Engine. gocloaks Code bleibt, wie er ist, und das Dekodieren wird schneller. Auf Go 1.27 passiert das ohne Flag, siehe unten.

{{< diagram src="gocloak-jsonv2-unmarshal.svg" caption="Unmarshal mit der v1-API, Default-Build gegen `GOEXPERIMENT=jsonv2`. Verschränkter A/B-Lauf, Median aus 10, GOMAXPROCS=4." >}}

| Unmarshal | v1-Engine | v2-Engine | Änderung |
| --- | ---: | ---: | ---: |
| Token-Response | 14,2 µs | 3,7 µs | -74 % |
| Certs (JWKS) | 5,2 µs | 1,9 µs | -65 % |
| Ein User | 4,1 µs | 2,6 µs | -36 % |
| 100 User | 413 µs | 270 µs | -35 % |
| 1.000 User | 4,04 ms | 2,74 ms | -32 % |
| Gruppenbaum | 102 µs | 82 µs | nicht signifikant |
| Clients | 91 µs | 53 µs | -42 % |
| Realm-Export | 472 µs | 350 µs | -26 % |

Am meisten gewinnt die Token-Response, drei lange JWT-Strings. User-Listen werden rund ein Drittel schneller.

Beim Kodieren geht es in die andere Richtung. Mit der v1-API auf der v2-Engine dauert das Marshalling eines neuen Users 2,00 statt 1,44 µs (+39 %) und das eines Clients 2,60 statt 1,72 µs (+51 %), der Realm-Export liegt gleichauf (nicht signifikant). Für Request-Bodies spielt das praktisch keine Rolle, denn Keycloak braucht Millisekunden, um sie zu verarbeiten.

Allokationen sind deterministisch und brauchen keinen A/B-Lauf. Die User-Listen allozieren 44 % weniger Objekte, das Realm-Marshalling fällt von 1.220 auf 197 Allokationen (-84 %), und über alle JSON- und HTTP-Benchmarks liegt das geometrische Mittel bei -40 %.

Mein erster, sequenzieller Lauf hatte bei 1.000 Usern -65 % und im Mittel -59 % gezeigt. Die Laständerung zwischen den Läufen hat diese Zahlen aufgebläht, deshalb verwende ich sie nicht mehr.

### Kommt dasselbe heraus?

Geschwindigkeit ist wertlos, wenn die dekodierten Structs abweichen. Ein eigener Test, `TestJSONv2Equivalence`, dekodiert jeden Payload mit v1 und mit der direkten v2-API und vergleicht die Ergebnisse per `reflect.DeepEqual`. Alles ist identisch, auch gocloaks Custom-Typen `StringOrArray` und `EnforcedString`. Aussagekräftig ist dieser Test vor allem für den Realm-Export und die Clients, denn das ist echte Keycloak-Ausgabe. Die übrigen Payloads erzeugt gocloak selbst per `json.Marshal`, dort passen die Feldnamen trivialerweise. Der stärkere Beleg ist die komplette gocloak-Integrationstestsuite, die unter `GOEXPERIMENT=jsonv2` gegen das echte Keycloak grün lief.

### Was Go 1.27 ändert

Alles oben habe ich mit Go 1.26.2 gemessen, der Version, die auf meinem Rechner installiert war. Ich habe geprüft, ob json/v2 ein Flag braucht, aber nicht, ob 1.26 noch das aktuelle Go war. War es nicht. In Go 1.27 (zum Zeitpunkt des Schreibens 1.27.4) gehört JSONv2 zum Baseline-Set der Experimente: `encoding/json` läuft standardmäßig auf der v2-Engine, und `encoding/json/v2` lässt sich ohne Flag importieren. Gemerkt habe ich das erst, als später jemand fragte, warum ich mit einer älteren Toolchain messe.

Also habe ich den Engine-Vergleich auf Go 1.27.4 wiederholt, mit `GOEXPERIMENT=nojsonv2` als alter Baseline (verschränkter A/B-Lauf, n=10). Unmarshal: Token-Response -70 %, JWKS -61 %, ein User -37 %, 100 User -30 %, 1.000 User -35 %, Clients -39 %, Realm-Export -28 %. Marshal eines Users +50 %, eines Clients +44 %. Über gocloak wird `GetUsers` bei 1.000 Usern 27 % schneller, bei 100 Usern 19 %. Die Allokationen sinken im geometrischen Mittel um 40 %. Die Größenordnungen decken sich mit dem Experiment auf Go 1.26, nur die Begründung ändert sich.

gocloak v15.1.0 ([Release Notes](https://github.com/Nerzal/gocloak/releases/tag/v15.1.0), erschienen am 21. November 2026) setzt Go 1.27 voraus. Damit ist die v2-Engine für alle Nutzer Baseline, ohne dass jemand ein Flag setzt. Wer bei einer älteren gocloak-Version mit Go 1.26 bleibt, bekommt dieselbe Engine per `GOEXPERIMENT=jsonv2`.

Wer die v2-API direkt nutzt, sollte wissen, dass ihre Defaults von v1 abweichen: Feldnamen werden case-sensitiv gematcht, doppelte Namen und ungültiges UTF-8 werden abgelehnt. Die [Paketdokumentation](https://pkg.go.dev/encoding/json/v2) listet alle Unterschiede. v1-Code unter dem Experiment-Flag behält das v1-Verhalten, weil die v1-API die v2-Engine mit v1-kompatiblen Optionen aufruft. Beim Dekodieren der Keycloak-Payloads hat nichts davon etwas geändert.

### Warum gocloak bei der v1-API bleibt

Die Gewinne oben kommen allein von der Engine: gocloak ruft weiterhin `encoding/json` auf, und das läuft auf Go 1.27 auf der v2-Engine. Ich habe zusätzlich die direkte `encoding/json/v2`-API gegen die v1-API gemessen, beide auf der v2-Engine. Das war ein einzelner Lauf mit n=8, nicht verschränkt, also weniger belastbar als die A/B-Zahlen. Einen User oder die JWKS zu dekodieren wurde mit der v2-API 28 bis 43 % schneller. User-Listen, Gruppen, Clients und der Realm-Export zeigten keinen signifikanten Unterschied. Das Encoding wurde 13 % schneller und brauchte 45 bis 57 % weniger Allokationen. Die Token-Response sah 86 % schneller aus, aber dieser Wert streute um ±24 %, und die v1-API auf der v2-Engine lag schon bei 4 µs. Deshalb zähle ich ihn nicht.

`TestJSONv2Equivalence` zeigt, dass die v2-API jeden Payload exakt wie v1 dekodiert. Beim Encoding gibt es Unterschiede: nil-Slices werden zu `[]` statt `null`, `omitempty` lässt andere Werte weg, und Feldnamen werden case-sensitiv gematcht. Für einen Keycloak-Client zählt das, denn Keycloak behandelt ein Feld, das im PUT-Body fehlt, als "aktuellen Wert behalten". Ändert sich das Encoding, kann ein Update andere Dinge ändern als vorher. Mit `json.DefaultOptionsV1()` verhält sich die v2-API wieder wie v1, und dann ist auch der Vorteil weg.

gocloak bleibt deshalb bei der v1-API. Wer v2 für Request-Bodies trotzdem will, kann es am resty-Client per `client.RestyClient().SetJSONMarshaler(...)` setzen, ohne Änderung an gocloak. Den großen Gewinn hat die Engine gratis geliefert. Die neue API würde nur dort helfen, wo Keycloak den Call ohnehin dominiert: bei kleinen Request-Bodies.

## Ergebnis 2: HTTP-Clients

Alle Zahlen hier sind benchstat-Mediane aus dem finalen Lauf (n=8, `GOMAXPROCS=4`). Die Maschine war weiterhin belastet, deshalb streuen die Zeitwerte um bis zu 30 bis 40 %, die Allokationen dagegen sind deterministisch. [Teil 4](/de/blog/gocloak-performance-final-benchmarks/) enthält die vollständigen Tabellen, hier stehen die Ergebnisse, auf die es ankommt.

### Offline: Bytes sagen mehr als Zeit

Mit dem Fake-Keycloak und einem Caller nach dem anderen sprangen die Zeitwerte von Endpoint zu Endpoint hin und her. Reines resty war bei 100 Usern 49 % schneller als gocloak und bei einem einzelnen User 27 % langsamer. Das ist das Rauschen der belasteten Maschine und kein Muster. Verlässlich sind die Bytes pro Call:

| 1.000 User, offline | Bytes pro Call | gegen gocloak |
| --- | ---: | ---: |
| gocloak | 3,88 MiB | |
| reines resty | 2,42 MiB | -38 % |
| net/http | 2,44 MiB | -37 % |
| fasthttp | 1,93 MiB | -50 % |

Alle Stacks brauchen für diesen Call rund 45.100 Allokationen. Die Objekte entstehen im JSON-Decoder, nicht im HTTP-Client.

### Viele Caller parallel

16 Goroutines mit `GOMAXPROCS=4`, die über TLS mit HTTP/1.1 einen einzelnen User abrufen:

| Stack | Zeit pro Call | Neue Verbindungen pro 1.000 Calls |
| --- | ---: | ---: |
| gocloak (Default) | 51,0 µs | 30,4 |
| gocloak, Pool 256 | 28,2 µs | 1,09 |
| net/http (getunt) | 19,2 µs | 0,77 |
| fasthttp | 14,4 µs | 0,14 |

In diesem Lauf machte der größere Pool gocloak 1,8-mal so schnell. Default und großer Pool liefen nacheinander, deshalb habe ich genau diesen Vergleich als verschränkten A/B-Lauf wiederholt: 39,2 µs mit Default-Pool gegen 15,2 µs mit 256 Idle-Verbindungen, 2,6-mal so schnell (-61 %), und die neuen Verbindungen fielen von 33,0 auf 0,67 pro 1.000 Calls (-98 %). Das ist eine einzige Transport-Einstellung. Über HTTP/2 hat keiner der Go-Clients neue Verbindungen geöffnet, denn HTTP/2 multiplext alle Requests über eine einzige Verbindung.

gocloak v15.1.0 setzt `MaxIdleConns` und `MaxIdleConnsPerHost` auf 100. Gemessen als v15.0 auf Go 1.26 gegen v15.1 auf Go 1.27 in einem verschränkten Lauf (n=10) fällt derselbe Benchmark von 37,2 auf 15,8 µs pro Call (-57 %) und von 33,3 auf 0,64 neue Verbindungen pro 1.000 Calls. Live über Plain HTTP sinken die neuen Verbindungen um 70 % (187 auf 55 pro 1.000 Calls), der Zeitunterschied ist dort nicht signifikant.

### Live gegen Keycloak

Gegen das echte Keycloak in Docker, Plain HTTP, ein Caller nach dem anderen, sind alle Go-Varianten gleich schnell. Ein einzelner User dauert etwa 0,9 ms, ein Token 1,8 ms, die Liste mit 1.000 Usern rund 39 ms. fasthttp spart bei kleinen Calls 80 bis 180 µs (6 bis 10 %), bei großen nichts Messbares.

In meinem allerersten Live-Lauf brauchten die 1.000 User noch 153 bis 185 ms. Die JVM in Keycloak war trotz 300 Aufwärm-Calls pro Endpoint noch nicht warm. Mehr dazu in Teil 4.

Der Connection-Pool zeigt sich auch live. Mit 16 parallelen Callern öffnete gocloak im Default 247 neue Verbindungen pro 1.000 Calls und brauchte 359 µs pro Call, mit Pool 256 waren es 231 µs. In einem längeren Profiling-Lauf über 5 Sekunden öffnete der Default 309 Verbindungen pro 1.000 Calls, der große Pool 4.

Die lokale Token-Verifikation (`DecodeAccessToken` mit echtem Keycloak-Token und warmem Cert-Cache) dauert 50,5 µs, reine CPU für die RSA-Signaturprüfung. json/v2 ändert diese Zeit nicht messbar, es spart nur 21 % der Allokationen.

## Ergebnis 3: weitere Befunde

### Das Body-Limit kostet Speicher

gocloak setzt ein Limit für den Response-Body, damit ein fehlerhafter Server es nicht dazu bringen kann, eine riesige Antwort einzulesen. Ist ein Limit gesetzt, liest resty den Body in 512-Byte-Häppchen per `append` ein (`readAllWithLimit`) und alloziert nicht anhand von `Content-Length` vor. Laut [pprof](https://pkg.go.dev/runtime/pprof)-Memory-Profil verursacht `readAllWithLimit` beim Abruf von 1.000 Usern 61 bis 67 % aller allozierten Bytes, mehr als das JSON-Decoding. Deshalb alloziert gocloak pro Call 3,88 MiB, wo reines resty 2,42 MiB braucht, also rund 60 % mehr. Die Laufzeit ändert sich kaum, aber der Garbage Collector hat mehr zu tun. [Teil 5](/de/blog/gocloak-pprof-profiling/) zeigt das Profil.

gocloak v15.1.0 bringt dafür eine Opt-in-Option mit, `gocloak.SetDirectBodyRead()`. Damit liest und dekodiert gocloak den Body selbst, in einen per `Content-Length` vorallozierten Buffer (`Content-Length` wird nur bis zum Limit geglaubt), mit demselben Limit, demselben gzip-Handling und derselben Fehlerdekodierung wie resty. Ein Parity-Test verlangt identische Ergebnisse und Fehler. Einen Wrapper um den Transport habe ich verworfen, weil er `Transport()`, `SetTLSClientConfig` und `SetProxy` am resty-Client brechen würde.

```go
client := gocloak.NewClient("https://keycloak.example.com", gocloak.SetDirectBodyRead())
```

Im verschränkten Lauf offline fällt `GetUsers` mit 1.000 Usern von 3,65 auf 2,22 MiB pro Call (-39 %) und von 6,56 auf 5,14 ms (-22 %). 100 User: -24 % Bytes, -19 % Zeit. Clients: -34 % Bytes. Token und einzelner User bleiben unverändert. Live gehen 1.000 User von 3,09 auf 2,18 MiB (-29 %), ohne signifikanten Zeitunterschied.

Opt-in ist es, weil resty für diese Calls seine Response-Middleware überspringt: `OnAfterResponse`-Hooks an `RestyClient()` laufen nicht, und `SetDebug` loggt den Response-Body nicht. resty v2 hält diese Hooks unexportiert, gocloak kann sie also nicht selbst aufrufen.

### Weniger Roundtrips schlagen jeden schnelleren Client

Der größte Hebel für Anwendungen ist die Zahl der Keycloak-Roundtrips, nicht der Client:

- Tokens wiederverwenden, statt pro Request neu einzuloggen. Jeder Login kostet gegen ein warmes lokales Keycloak etwa 1,8 ms, über ein echtes Netzwerk mehr.
- `briefRepresentation` und kleine `max`-Werte bei Listen nutzen. 1.000 User brauchen in einem warmen Keycloak rund 39 ms und ein Vielfaches davon, solange die JVM kalt ist.
- Tokens lokal per JWKS verifizieren statt per [Token-Introspection](https://www.rfc-editor.org/rfc/rfc7662). Die lokale Prüfung kostet etwa 50 µs CPU, Introspection einen Netzwerk-Roundtrip plus die Arbeit in Keycloak. Genau darauf baut [gocloak-auth-proxy](/de/blog/gocloak-auth-proxy-keycloak/) auf.

## Was ich mitnehme

1. Im HTTP-Client ist nichts "Massives" zu holen. Keycloak braucht Millisekunden, der Client Mikrosekunden. fasthttp ist in den meisten Mikrobenchmarks der schnellste Stack, spart live bei kleinen Calls 6 bis 10 % und bei großen nichts. Es kann außerdem kein HTTP/2, ist kein `http.RoundTripper` und würde `RestyClient()`/`SetRestyClient` sowie die Proxy-, TLS- und Tracing-Konfiguration der Nutzer brechen. Meine Empfehlung: nicht umsteigen.
2. Der echte Hebel unter Last ist der Connection-Pool. Der resty-Default koppelt `MaxIdleConnsPerHost` an `GOMAXPROCS + 1`, in Containern also oft 2 oder 3. Parallele Last über HTTP/1.1 erzeugt dann ständig neue Verbindungen und TLS-Handshakes: im verschränkten A/B-Test 2,6-mal langsamer, im Extremfall mit abgelehnten Verbindungen. gocloak v15.1.0 setzt in `NewClient` beide Idle-Limits auf 100: -57 % Zeit und 98 % weniger neue Verbindungen in diesem Benchmark. Wer Keycloak über TLS mit HTTP/2 anspricht, hat das Problem nicht.
3. json/v2 macht das Dekodieren ohne Codeänderung 26 bis 74 % schneller (User-Listen rund ein Drittel) und senkt die Allokationen um rund 40 %. Das Kodieren kleiner Structs wird 39 bis 51 % langsamer, was neben den Antwortzeiten von Keycloak keine Rolle spielt. Über gocloak werden nur die User-Listen messbar schneller, und die Latenz eines Live-Calls ändert sich nicht, denn die dominiert Keycloak. Auf Go 1.27 ist die v2-Engine der Default, und gocloak v15.1.0 setzt Go 1.27 voraus.
4. `SetDirectBodyRead()` senkt die Bytes pro Call bei 1.000 Usern um 39 %. Der Preis ist, dass restys Response-Hooks übersprungen werden, deshalb ist es Opt-in.
5. Zur Methodik: Erst die Fakten prüfen (`go list`, Modulversionen, den Quelltext der Library), dann messen. Dazu gehört auch, welche Toolchain aktuell ist. Ich habe mit der Go-Version gemessen, die zufällig installiert war. Benchmarks reproduzierbar machen mit Skript, festen Parametern, benchstat und protokollierter Umgebung, und offline und live trennen. Auf einer belasteten Maschine sind Einzelzahlen wertlos, nur Medianvergleiche mit p-Wert zählen. Und alt gegen neu nie in getrennten Läufen auf einer Maschine vergleichen, deren Last sich ändert, sondern die Läufe verschränken.

[Teil 4](/de/blog/gocloak-performance-final-benchmarks/) enthält die vollständigen benchstat-Tabellen, offline und live, und was mich der finale Lauf über JVM-Warmup und Benchmark-Clients gelehrt hat, die sich gegenseitig vergiften. [Teil 5](/de/blog/gocloak-pprof-profiling/) schaut in die CPU- und Memory-Profile.
