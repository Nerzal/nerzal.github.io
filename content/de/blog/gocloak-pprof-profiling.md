---
draft: false
title: "Wo geht die Zeit hin? gocloak mit pprof profilieren"
seo_title: "Go pprof in der Praxis: einen Keycloak-Client mit CPU-, Heap- und Diff-Graphen profilieren"
date: 2026-11-24T06:30:00+01:00
tags:
  [
    "go",
    "pprof",
    "profiling",
    "performance",
    "keycloak",
    "gocloak",
    "encoding-json-v2",
    "tls",
    "graphviz",
    "open-source",
  ]
categories: ["Software Engineering"]
series: ["Das gocloak-Universum"]
description: "CPU- und Heap-Profile aus den gocloak-Benchmarks mit go tool pprof: warum encoding/json v1 seine Eingabe zweimal liest, warum restys Body-Limit zwei Drittel aller allozierten Bytes verursacht und wie ein zu kleiner Connection-Pool TLS-Handshake-CPU auf die Keycloak-Seite verlagert."
toc: true
---

> **Serie: Das gocloak-Universum.** [Teil 1: gocloak-mcp](/de/blog/gocloak-mcp-first-mcp-server-homebrew/) · [Teil 2: gocloak-auth-proxy](/de/blog/gocloak-auth-proxy-keycloak/) · [Teil 3: gocloak-Performance](/de/blog/gocloak-performance-json-v2-http-clients/) · [Teil 4: die finalen Benchmark-Zahlen](/de/blog/gocloak-performance-final-benchmarks/) · Teil 5: pprof (du bist hier)

Benchmarks sagen, wie lange etwas dauert, aber nicht, warum. In [Teil 3](/de/blog/gocloak-performance-json-v2-http-clients/) und [Teil 4](/de/blog/gocloak-performance-final-benchmarks/) habe ich gocloak gegen Keycloak gemessen und drei Dinge gefunden, die eine Erklärung brauchen: json/v2 dekodiert schneller, gocloak alloziert rund 60 % mehr Bytes als reines resty, und ein kleiner Connection-Pool macht parallele Calls deutlich langsamer. Dieser Post öffnet die Profile hinter diesen Zahlen.

Zwei der drei Befunde unten haben sich erst in den Profilen gezeigt: das Body-Limit als größte Allokationsquelle und die Handshake-CPU, die auf der Serverseite landet.

## Profile aus Benchmarks

Das testing-Paket von Go schreibt für jeden Benchmark ein CPU- und ein Memory-Profil. Zusätzlicher Code ist nicht nötig:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
go test -run '^$' -bench 'BenchmarkJSONUnmarshal/payload=users1000/api=v1$' \
  -benchtime 5s -cpu 4 \
  -cpuprofile cpu.pprof -memprofile mem.pprof -o bench.test .

go tool pprof -top bench.test cpu.pprof                              # Text-Rangliste
go tool pprof -svg bench.test cpu.pprof > cpu.svg                    # Call-Graph
go tool pprof -svg -sample_index=alloc_space bench.test mem.pprof > mem.svg
go tool pprof -svg -diff_base old/cpu.pprof bench.test new/cpu.pprof > diff-cpu.svg
go tool pprof -http=:8080 bench.test cpu.pprof                       # Browser-UI mit Flamegraph
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
go test -run '^$' -bench 'BenchmarkJSONUnmarshal/payload=users1000/api=v1$' `
  -benchtime 5s -cpu 4 `
  -cpuprofile cpu.pprof -memprofile mem.pprof -o bench.test .

go tool pprof -top bench.test cpu.pprof
go tool pprof -svg bench.test cpu.pprof > cpu.svg
go tool pprof -svg -sample_index=alloc_space bench.test mem.pprof > mem.svg
go tool pprof -svg -diff_base old/cpu.pprof bench.test new/cpu.pprof > diff-cpu.svg
go tool pprof -http=:8080 bench.test cpu.pprof
```

{{< /os-tab >}}
{{< /os-tabs >}}

Ein paar Details, auf die es ankommt:

- `-o bench.test` behält das kompilierte Test-Binary. pprof braucht es, um Funktionsnamen aufzulösen.
- Das Memory-Profil zeichnet mehrere Sample-Typen auf. `-sample_index=alloc_space` zeigt alle Bytes, die während des Laufs alloziert wurden, und genau die treiben die GC-Arbeit. Der Default `inuse_space` zeigt nur, was am Ende noch lebt, und das ist bei einem Benchmark fast nichts.
- `-diff_base` zieht ein Profil von einem anderen ab. Im Diff-Graphen heißt rot mehr im neuen Profil, grün weniger.
- `-focus=<regex>` und `-nodecount=<n>` schneiden einen Graphen auf den interessanten Teil zu. Die Graphen in diesem Post nutzen beides.

Für SVG- und PNG-Ausgabe braucht pprof [Graphviz](https://graphviz.org/download/), die Browser-UI mit Flamegraph nicht:

{{< os-tabs >}}
{{< os-tab "Linux" >}}

```bash
sudo apt install graphviz
```

{{< /os-tab >}}
{{< os-tab "macOS" >}}

```bash
brew install graphviz
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
winget install --id Graphviz.Graphviz
# winget nimmt dot nicht in den PATH auf, für die aktuelle Session:
$env:Path += ";C:\Program Files\Graphviz\bin"
```

{{< /os-tab >}}
{{< /os-tabs >}}

Im gocloak-Repository erledigt [`benchmarks/profile.sh`](https://github.com/Nerzal/gocloak/tree/v15.1.0/benchmarks) das alles für fünf Szenarien. Jedes Szenario läuft zweimal 5 Sekunden: "alt" mit den heutigen Defaults (encoding/json v1, restys Default-Pool) und "neu" mit `GOEXPERIMENT=jsonv2` und, bei den Pool-Szenarien, einem Idle-Pool von 256. Die Zahlen in diesem Post stammen aus diesen einzelnen 5-Sekunden-Profiling-Läufen. Es sind nicht die benchstat-Mediane aus Teil 4, und wo beide vorkommen, kennzeichne ich das.

### Wie man die Graphen liest

Jede Box ist eine Funktion. Die erste Zahl ist die Flat-Zeit, die in der Funktion selbst verbracht wurde. "of" nennt die kumulierte Zeit inklusive allem, was sie aufruft. Größere Schrift heißt mehr Flat-Zeit, dickere und rötere Kanten heißen mehr Zeit auf diesem Pfad. Gepunktete Kanten heißen, dass der Filter Funktionen dazwischen entfernt hat. Die vollständige Legende steht in der [pprof-Dokumentation](https://github.com/google/pprof/blob/main/doc/README.md#interpreting-the-callgraph).

## Befund 1: encoding/json v1 liest seine Eingabe zweimal

Das erste Szenario dekodiert nur die Liste mit 1.000 Usern, ohne HTTP. Hier die v1-Engine, gefiltert auf alles unterhalb von `json.Unmarshal`:

![pprof-CPU-Call-Graph von encoding/json v1 beim Dekodieren von 1.000 Usern: json.Unmarshal verzweigt in decodeState.value mit 3,90 s und checkValid mit 1,25 s, das sind 20,9 Prozent der gesamten CPU](/img/gocloak/pprof/json-v1-cpu.svg)

`json.Unmarshal` hat zwei Kinder. Das rechte, `checkValid`, nimmt 20,9 % der CPU (13,9 % flat). Es lässt einen Scanner über die komplette Eingabe laufen, nur um zu prüfen, ob sie gültiges JSON ist, bevor das eigentliche Dekodieren beginnt. Danach läuft `decodeState.value` ein zweites Mal über dieselben Bytes und baut die Structs. Ein Fünftel der CPU geht also in einen Durchgang, der nur ein Ja oder Nein liefert. `unquoteBytes`, das JSON-Strings in Go-Strings verwandelt, kommt mit 8,7 % dazu.

Die v2-Engine unter derselben v1-API:

![pprof-CPU-Call-Graph desselben Decodings mit GOEXPERIMENT=jsonv2: kein checkValid-Knoten, die Arbeit läuft über makeStructArshaler und jsontext consumeValue bis zu jsonwire.ConsumeSimpleString mit 7 Prozent](/img/gocloak/pprof/json-v2-cpu.svg)

`checkValid` ist verschwunden. Die v2-Engine (darunter `encoding/json/jsontext`) validiert während des Dekodierens, in einem einzigen Durchgang. Die Arbeit steckt in den "Arshalern", den pro Typ erzeugten Marshal- und Unmarshal-Funktionen von v2, und unten in `jsonwire.ConsumeSimpleString`, einem schnellen Pfad für Strings ohne Escape-Sequenzen. Das trifft auf die meisten Strings in einem Keycloak-User zu.

Der Profiling-Lauf für dieses Szenario:

| 1.000 User dekodieren | v1-Engine | v2-Engine |
| --- | ---: | ---: |
| Zeit pro Op | 3,96 ms | 2,39 ms (-40 %) |
| Allokationen pro Op | 45.018 | 25.122 (-44 %) |
| Bytes pro Op | 1,41 MiB | 1,16 MiB (-18 %) |

Im Profiling-Lauf liefen alt und neu nacheinander, die Zeitspalte ist deshalb nur ein grober Anhaltspunkt. Der verschränkte A/B-Lauf aus [Teil 3](/de/blog/gocloak-performance-json-v2-http-clients/) hat für dieses Decoding -32 % gemessen (4,04 auf 2,74 ms), und dieser Zahl traue ich. Die Allokationszahlen sind in beiden identisch.

Der Heap-Diff zeigt, wohin die restlichen Allokationen gehen: v1 alloziert über Reflection in `decodeState.object` und `literalStore`, v2 über `reflect.mapassign` für die `Attributes`-Maps, `reflect.unsafe_New` und `makeString`, insgesamt weniger.

## Befund 2: Das Body-Limit alloziert mehr als der JSON-Decoder

Das zweite Szenario führt den kompletten Call `gocloak.GetUsers` mit `max=1000` gegen das In-Process-Fake-Keycloak aus. Auf der CPU-Seite gibt es keine Überraschung: `json.Unmarshal` nimmt mit v1 52 % der Client-CPU, mit v2 45 %. `runtime.cgocall`, die Socket-Syscalls unter Windows, liegt bei etwa 23 %, der In-Process-Server bei etwa 22 %, die GC-Worker bei 7 bis 8 %.

Spannend wird das Heap-Profil:

![pprof-Heap-Graph (alloc_space) von gocloak.GetUsers mit 1.000 Usern: resty.readAllWithLimit hat 2579 MB alloziert, 61,5 Prozent aller Bytes, der JSON-Decoder unter decodeState.value 1536 MB](/img/gocloak/pprof/getusers-mem.svg)

`resty.readAllWithLimit` hat in diesem Lauf 61,5 % aller Bytes alloziert, über mehrere Läufe 61 bis 67 %. Das komplette JSON-Decoding von 1.000 Usern kommt mit rund 37 % erst auf Platz zwei. Den Body einzulesen kostet mehr Speicher, als ihn in Go-Structs zu verwandeln.

Die Antwort ist etwa 470 KB groß, trotzdem alloziert das Einlesen rund 2,5 MB pro Call. gocloak setzt zur Härtung ein Limit für den Response-Body, damit ein kaputter oder bösartiger Server es nicht dazu bringen kann, eine endlose Antwort einzulesen. Ist ein Limit gesetzt, liest resty den Body in 512-Byte-Häppchen und hängt jedes Häppchen an einen Slice an, ohne vorher auf `Content-Length` zu schauen. Jedes Mal, wenn die Kapazität des Slices nicht reicht, alloziert `append` einen größeren und kopiert alles um. Große Slices lässt Go um etwa den Faktor 1,25 wachsen, so summieren sich die Zwischenkopien auf ungefähr das Fünffache der Body-Größe. Die kleinen Kästen unter `readAllWithLimit` im Graphen sind diese Wachstumsschritte: 344 KB, 432 KB, 544 KB und die vielen kleineren davor.

Die CPU merkt davon wenig, das sind etwa 7 % der Client-CPU. Der Garbage Collector merkt es, denn er muss das alles wegräumen.

Ohne Profil hätte ich die zusätzlichen Bytes von gocloak dem JSON-Decoder angelastet. gocloak v15.1.0 bietet jetzt ein Opt-in, `gocloak.SetDirectBodyRead()`: gocloak liest und dekodiert den Body selbst und alloziert einmal anhand von `Content-Length`, der es nur bis zum Limit glaubt. Einen Wrapper um den Transport habe ich verworfen, weil er `Transport()`, `SetTLSClientConfig` und `SetProxy` am resty-Client bricht. Bei 1.000 Usern sinken die Bytes pro Call um 39 %. Opt-in ist es, weil restys `OnAfterResponse`-Hooks und das Body-Logging von `SetDebug` für diese Calls nicht laufen. Die Kernidee als Skizze, die echte Umsetzung kümmert sich zusätzlich um gzip und dekodiert Fehlerantworten wie resty:

```go
// sketch: read a body with a hard limit and a single allocation when Content-Length is known
func readLimited(response *http.Response, limit int64) ([]byte, error) {
    if response.ContentLength > limit {
        return nil, fmt.Errorf("response body of %d bytes exceeds %d", response.ContentLength, limit)
    }
    if response.ContentLength >= 0 {
        // net/http already stops reading at Content-Length, so this is one exact allocation
        body := make([]byte, response.ContentLength)
        _, err := io.ReadFull(response.Body, body)
        return body, err
    }
    // unknown length (chunked encoding): read at most limit+1 bytes to detect an oversized body
    body, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
    if err != nil {
        return nil, err
    }
    if int64(len(body)) > limit {
        return nil, fmt.Errorf("response body exceeds %d bytes", limit)
    }
    return body, nil
}
```

## Befund 3: Ein kleiner Pool verbrennt CPU in TLS-Handshakes

Das dritte Szenario ist der Pool-Benchmark: 16 Goroutines rufen parallel `GetUserByID` über TLS mit HTTP/1.1 gegen den In-Process-Server auf. Mit gocloaks Default-Pool, gefiltert auf das Verbindungshandling:

![pprof-CPU-Call-Graph mit Default-Pool: crypto/tls HandshakeContext nimmt 27,4 Prozent der gesamten CPU; serverHandshakeStateTLS13 nimmt 20,4 Prozent, das meiste davon in RSA decrypt und bigmod montgomeryMul, der Client-Handshake 6,5 Prozent](/img/gocloak/pprof/pool-default-cpu.svg)

27,4 % der gesamten CPU gehen in `crypto/tls.(*Conn).HandshakeContext`. Die Serverseite des Handshakes nimmt 20,4 %, das meiste davon für die RSA-PSS-Signatur mit dem Serverzertifikat (`rsa.decrypt` und darunter die Großzahl-Arithmetik in `bigmod`). Die Clientseite nimmt 6,5 %, der Verbindungsaufbau (`dialConn`) weitere 3,8 %.

Dasselbe Szenario mit einem Idle-Pool von 256:

![pprof-CPU-Call-Graph mit Idle-Pool 256: keine TLS-Handshake-Knoten mehr; der Verbindungspfad besteht aus http Transport roundTrip, getConn und queueForIdleConn mit jeweils deutlich unter 2 Prozent](/img/gocloak/pprof/pool-tuned-cpu.svg)

Der Handshake-Anteil fällt auf 0,74 %. Vom Verbindungshandling bleibt nur `getConn`, das eine Idle-Verbindung aus dem Pool nimmt.

| Pool-Szenario (Profiling-Lauf) | Default-Pool | Pool 256 |
| --- | ---: | ---: |
| Zeit pro Op | 21,7 µs | 12,5 µs |
| Neue Verbindungen pro 1.000 Calls | 20,4 | 0,11 |
| CPU-Anteil der TLS-Handshakes | 27,4 % | 0,74 % |

Die absoluten Zeiten weichen von Teil 4 ab (39,2 und 15,2 µs im verschränkten A/B-Lauf), weil das hier ein einzelner, längerer Lauf bei anderer Last auf der Maschine war. Die Richtung ist dieselbe. gocloak v15.1.0 hält 100 Idle-Verbindungen pro Host.

Für die Produktion zählt Folgendes: In diesem Benchmark laufen beide Seiten in einem Prozess, und der Server-Anteil am Handshake ist dreimal so groß wie der des Clients. In einem echten Deployment läuft die Serverseite dort, wo TLS für Keycloak terminiert wird, in Keycloak selbst oder in einem Ingress davor. Ein Client mit zu kleinem Pool bremst also nicht nur sich selbst. Er lässt den TLS-Endpunkt des Identity-Providers immer wieder teure RSA-Signaturen rechnen, und das bezahlen alle anderen Anwendungen mit, die mit demselben Keycloak sprechen.

## Live: Keycloak dominiert

Zwei Szenarien liefen gegen das echte Keycloak in Docker über Plain HTTP.

`live-getusers1000` ging von 41,8 ms auf 38,9 ms, die Allokationen von 33.179 auf 24.216, die Bytes von 3,18 MiB auf 3,09 MiB. Im Profil taucht der Client fast nur beim Dekodieren und beim Einlesen des Bodys auf. Den Rest der Zeit wartet er auf Keycloak.

`live-pool` mit 16 parallelen Callern ging von 277,7 µs auf 212,5 µs pro Call (-23 %), bei 308,5 gegen 4,0 neuen Verbindungen pro 1.000 Calls. Ohne TLS ist eine neue Verbindung billig, deshalb ist der Effekt kleiner als im TLS-Szenario offline.

## Eine Behauptung eines anderen Tools prüfen

Während ich diese Serie geschrieben habe, hat ein anderes KI-Coding-Tool eine Anwendung analysiert, die gocloak nutzt. Es behauptete, die Pointer-Felder in `gocloak.User` verursachten 37,6 % aller Objekt-Allokationen, und ein Streaming-Decoder würde helfen. Beides lässt sich messen (Go 1.27, 1.000 User, n=6):

- User-Felder als Values statt Pointer: -40 % Allokationen, die erste Hälfte der Behauptung stimmt also. Es spart aber keine Zeit und kostet 49 % mehr Bytes, weil jedes Slice-Element größer wird. Und ein Update könnte kein `false`, `0` oder `""` mehr senden, weil der Nullwert wie "nicht gesetzt" aussähe. gocloak behält die Pointer.
- Streaming mit `json.NewDecoder` statt `json.Unmarshal`: +10 % Zeit und +82 % Bytes. Diese Hälfte der Behauptung ist falsch.

Der Hebel liegt in der Anwendung. Wer von vielen Usern nur wenige Felder liest, dekodiert in ein eigenes Struct. Mit einem Struct aus 8 Feldern spart das 54 % Zeit, 72 % Bytes und 84 % Allokationen. Die gocloak-README zeigt jetzt, wie:

```go
type userRow struct {
    ID       string `json:"id"`
    Username string `json:"username"`
    Email    string `json:"email"`
}

var rows []userRow
resp, err := client.GetRequestWithBearerAuth(ctx, token.AccessToken).
    SetQueryParams(map[string]string{"briefRepresentation": "true", "max": "1000"}).
    SetResult(&rows).
    Get("https://keycloak.example.com/admin/realms/myrealm/users")
if err == nil && resp.IsError() {
    err = fmt.Errorf("get users: %s", resp.Status())
}
```

Ein Profil zeigt, wo alloziert wird. Ob ein vorgeschlagener Fix hilft, zeigt erst eine Messung.

## Was die Profile dazugebracht haben

Die Benchmark-Zahlen sagten "gocloak alloziert 60 % mehr als resty" und "der Default-Pool ist unter paralleler Last langsamer". Die Profile haben beides erklärt:

1. encoding/json v1 validiert die komplette Eingabe in einem eigenen Durchgang, bevor es dekodiert. v2 erledigt beides in einem Durchgang, und das macht einen großen Teil seines Vorsprungs aus.
2. Die zusätzlichen Bytes kommen vom Einlesen des Bodys mit Limit in 512-Byte-Schritten, nicht vom JSON. `SetDirectBodyRead()` in v15.1.0 behebt das als Opt-in.
3. Der kleine Pool kostet TLS-Handshakes, und der Großteil dieser Kosten landet auf der Serverseite, in der Produktion also auf der Keycloak-Seite. v15.1.0 hält 100 Idle-Verbindungen pro Host.

Die Profile haben dieselbe Schwäche wie meine ersten Benchmark-Läufe: Alt und neu liefen nacheinander. Für die Frage, wie viel schneller etwas ist, sind die verschränkten A/B-Läufe aus Teil 3 und Teil 4 die Referenz. Für die Frage, wohin Zeit und Bytes gehen, sind es die Profile.
