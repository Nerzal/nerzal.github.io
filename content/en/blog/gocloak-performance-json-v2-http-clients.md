---
draft: false
title: "How fast can gocloak talk to Keycloak? json/v2, fasthttp and the connection pool"
seo_title: "gocloak Performance: encoding/json/v2, fasthttp and Go HTTP Connection Pools"
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
series: ["The gocloak universe"]
description: "Benchmarking gocloak against Keycloak 26: encoding/json/v2 decodes Keycloak payloads 26 to 74 % faster with no code change but encodes small structs more slowly, fasthttp wins micro-benchmarks but barely matters against a real Keycloak, and resty's default connection pool is the real bottleneck under parallel load."
toc: true
---

> **Series: The gocloak universe.** [Part 1: gocloak-mcp](/blog/gocloak-mcp-first-mcp-server-homebrew/) · [Part 2: gocloak-auth-proxy](/blog/gocloak-auth-proxy-keycloak/) · Part 3: gocloak performance (you are here) · [Part 4: final benchmark numbers](/blog/gocloak-performance-final-benchmarks/) · [Part 5: pprof](/blog/gocloak-pprof-profiling/)

Can gocloak, the Go client for the Keycloak REST API, get "massively" faster at talking to Keycloak? I wanted a number for that, not a gut feeling, so I checked three things:

1. Does the new [`encoding/json/v2`](https://pkg.go.dev/encoding/json/v2) help with typical Keycloak payloads?
2. Does a different HTTP client, [fasthttp](https://github.com/valyala/fasthttp) or something else, help?
3. Are there other levers?

The short answer: json/v2 decodes Keycloak payloads 26 to 74 % faster without a single code change (user lists about a third), but encodes small structs 39 to 51 % more slowly. fasthttp is the fastest stack in most micro-benchmarks, but against a real Keycloak it saves at most a tenth on small calls and nothing on large ones. And the biggest problem under parallel load is a default in the connection pool that nobody looks at.

This post covers how I approached it, what went wrong along the way and the results. [Part 4](/blog/gocloak-performance-final-benchmarks/) has the complete benchstat tables and what the final run taught me, [Part 5](/blog/gocloak-pprof-profiling/) the CPU and memory profiles.

The setup: gocloak v15, Go 1.26.2, [resty](https://github.com/go-resty/resty) v2.17.2 as the HTTP layer, Keycloak 26.8.2 in Docker, on an AMD Ryzen AI 9 HX 370 (24 logical cores) with Windows 11.

## Read the code before you measure

All gocloak calls go through one shared resty client. `NewClient` creates it with `resty.New()`, a timeout, a response body limit and a redirect policy that only follows redirects to the same origin. resty reads the whole response body into memory and then calls `json.Unmarshal` on it. Nothing is streamed.

Before writing a single benchmark I checked the facts I thought I knew, because half of them were wrong or outdated:

- `go list encoding/json/v2` without any flag answers with `build constraints exclude all Go files`. In Go 1.26, json/v2 is still behind `GOEXPERIMENT=jsonv2`.
- resty v3 exists only as a release candidate (v3.0.0-rc.4), so it was out.
- fasthttp v1.79.0 is current.
- resty has `SetJSONMarshaler` and `SetJSONUnmarshaler`. A user can swap the JSON implementation without gocloak changing anything.

I also checked the usual suspects for hidden overhead. gocloak caches the JWKS certificates, parses the public keys once per fetch and keeps them in a map by `kid`, so token verification has no hidden network call or parsing step. The server version is cached too.

Reading resty's source turned up the first real finding. Its default transport sets `MaxIdleConnsPerHost` to `GOMAXPROCS + 1`. Keycloak is exactly one host for gocloak, and since [Go 1.25 GOMAXPROCS respects cgroup CPU limits](https://go.dev/doc/go1.25#container-aware-gomaxprocs). A pod with a CPU limit of 1 keeps at most two idle connections to Keycloak open. More on why that hurts below.

## The benchmark setup

The benchmarks live in their own Go module under [`benchmarks/`](https://github.com/Nerzal/gocloak/tree/main/benchmarks) in the gocloak repository, with its own `go.mod` and a `replace` directive pointing at the main module. That way fasthttp and benchstat never end up in the library's dependencies.

There are two stages:

- **Offline:** an in-process fake Keycloak built with [`net/http/httptest`](https://pkg.go.dev/net/http/httptest) serves realistic payloads on the real gocloak URL paths. This runs without Docker, is reproducible and isolates the client overhead.
- **Live:** the same benchmarks against the real Keycloak in Docker, behind the build tag `keycloak`. The setup creates 1,000 users and 20 groups with 5 subgroups each, then warms Keycloak up with 300 calls per endpoint so the JIT and the caches are hot. Afterwards it deletes the data again, and it also cleans up leftovers of an aborted run before it starts. The admin token lives 60 seconds in the master realm, so a background goroutine renews it and no login ever lands inside a measurement.

The payloads are what an application actually gets from Keycloak: a token response with really signed RS256 JWTs, the JWKS, a single user, lists of 100 and 1,000 users, a group tree, the clients and the full realm export from `testdata/gocloak-realm.json` (73 KB, a real Keycloak export).

I compared five HTTP stacks:

| Stack | What it shows |
| --- | --- |
| gocloak (default) | What users get today |
| gocloak with an idle pool of 256 | Effect of a single transport setting |
| plain resty | gocloak's own overhead, subtracted |
| net/http, tuned pool, streaming decoder | What the standard library can do |
| fasthttp | The usual "just use fasthttp" suggestion |

A script, `run.sh`, runs everything with fixed parameters: `COUNT=10`, `GOMAXPROCS=4`, `-benchtime 1s`. Every suite runs once with the standard JSON and once with `GOEXPERIMENT=jsonv2`. Raw output, benchstat comparisons, the Go version and the commit hash go into `results/<timestamp>/`. The script says in its header to run it only on an otherwise idle machine.

[benchstat](https://pkg.go.dev/golang.org/x/perf/cmd/benchstat) is wired in as a Go tool dependency (`go tool benchstat`). If you want it globally:

```bash
go install golang.org/x/perf/cmd/benchstat@latest
```

Running the suites looks like this. `run.sh` needs a Bash, so on Windows use Git Bash or WSL, or call `go test` directly:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
cd benchmarks
./run.sh offline              # no Docker needed
./run.sh live                 # starts Keycloak via docker compose if needed

# single suite by hand, once per JSON engine
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

### Traps in the methodology

The in-process server burns CPU too, on the same cores as the client. That inflates the totals, so I compare absolute differences in ns/op and allocs/op between clients, not percentages of the total.

The bigger problem was my own machine. Other coding agents were running in parallel, and single runs scattered wildly: one JSON benchmark jumped to 2.4 times its value between two runs. A single number from a busy machine says nothing. So every result in this post is a benchstat median (n=8, or n=10 for the A/B runs), which reports the median, a confidence interval and a p-value. Even so, time values on that machine scatter by up to 30 to 40 %. Allocations and bytes per operation are deterministic, so I trust those more. The script exists so anyone can repeat the run on an idle machine.

Medians do not protect against a load change between two runs. My first comparison of the JSON engines ran the v1 suite and then, minutes later, the v2 suite. The load on the machine changed in between, and that alone faked effects of up to ±40 %. The clearest example was local token verification: with json/v2 it looked 35 % slower offline and 39 % faster live. In a fair comparison there is no difference at all.

So every old-against-new number in this post comes from an interleaved A/B run (`benchmarks/ab.sh`). Both variants are compiled once as test binaries, then run alternately for 10 rounds with one sample each, and the order flips every round. A load spike then hits both variants equally:

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

`go test -count 8` does the opposite: it runs the same sub-benchmark eight times in a row, so one load spike lands in all eight samples of one variant and none of the other.

fasthttp returns pooled buffers that get reused after the request is released. I checked that this is safe here: `json.Unmarshal` copies the strings out of the buffer before the buffer goes back to the pool.

## Things that broke along the way

### fasthttp meets HTTP/2

The first fasthttp run against the TLS test server failed with:

```text
http2: server: error reading preface from client: bogus greeting
```

The test server's TLS config offers `h2` via ALPN, and fasthttp speaks only HTTP/1.1. The fix for the benchmark was to set `NextProtos` to `["http/1.1"]` for fasthttp. For production that means fasthttp cannot use HTTP/2 at all.

### The pool benchmark that took down the listener

The pool benchmark sends many parallel callers over TLS with HTTP/1.1. With the gocloak/resty default pool it failed outright. 32 to 192 goroutines shared 5 or 25 idle connections, so connections were closed and re-dialed constantly, each with a new TLS handshake, until the Windows listener started refusing new connections:

```text
connectex: No connection could be made because the target machine actively refused it.
```

net/http and fasthttp with a large pool ran through the same test without errors. I changed the benchmark so it counts errors and new connections as metrics (`dials/1k-op` and `fails/1k-op`) instead of aborting, and gave each client two seconds of cool-down before its measurement, so it does not inherit a full accept backlog from the previous client.

My first version of that cool-down sat inside the measured loop. With `b.N = 1` in the first ramp-up round that meant two seconds per operation, which skewed how the testing package scaled `b.N`. The fix: sleep only in the first round, before `b.ResetTimer()`.

## Result 1: encoding/json/v2

With `GOEXPERIMENT=jsonv2`, the old `encoding/json` API (v1) runs on the new v2 engine. gocloak's code stays exactly as it is, and the decoding gets faster.

{{< diagram src="gocloak-jsonv2-unmarshal.svg" caption="Unmarshal with the v1 API, default build vs `GOEXPERIMENT=jsonv2`. Interleaved A/B run, median of 10, GOMAXPROCS=4." >}}

| Unmarshal | v1 engine | v2 engine | Change |
| --- | ---: | ---: | ---: |
| Token response | 14.2 µs | 3.7 µs | -74 % |
| Certs (JWKS) | 5.2 µs | 1.9 µs | -65 % |
| One user | 4.1 µs | 2.6 µs | -36 % |
| 100 users | 413 µs | 270 µs | -35 % |
| 1,000 users | 4.04 ms | 2.74 ms | -32 % |
| Group tree | 102 µs | 82 µs | not significant |
| Clients | 91 µs | 53 µs | -42 % |
| Realm export | 472 µs | 350 µs | -26 % |

The token response, three long JWT strings, gains the most. User lists get about a third faster.

Encoding goes the other way. With the v1 API on the v2 engine, marshalling a new user takes 2.00 instead of 1.44 µs (+39 %) and a client 2.60 instead of 1.72 µs (+51 %); the realm export is level (not significant). For request bodies that does not matter in practice, because Keycloak needs milliseconds to process them.

Allocations are deterministic and need no A/B run. The user lists allocate 44 % fewer objects, marshalling the realm drops from 1,220 to 197 allocations (-84 %), and across all JSON and HTTP benchmarks the geometric mean is -40 %.

My first, sequential run had shown -65 % for 1,000 users and -59 % on average. The load change between the runs inflated those numbers, so I no longer use them.

### Is the output the same?

Speed is worthless if the decoded structs differ. A dedicated test, `TestJSONv2Equivalence`, decodes every payload with v1 and with the direct v2 API and compares the results with `reflect.DeepEqual`. Everything is identical, including gocloak's custom types `StringOrArray` and `EnforcedString`. That test means most for the realm export and the clients, which are real Keycloak output; the other payloads come from gocloak's own `json.Marshal`, so their field names match trivially. The stronger evidence is the complete gocloak integration test suite, which ran green under `GOEXPERIMENT=jsonv2` against the real Keycloak.

### Why gocloak does not switch yet

json/v2 is still an experiment in Go 1.26. If gocloak imported `encoding/json/v2` directly, the build would break for every user who does not set the flag. So for now it is opt-in on the user's side, in one of two ways:

- Build your application with `GOEXPERIMENT=jsonv2`. That changes the engine under all v1 code, gocloak included.
- Plug a v2-based unmarshaler into gocloak's resty client via `client.RestyClient().SetJSONUnmarshaler(...)`.

gocloak will switch once json/v2 is stable.

If you use the v2 API directly, be aware that its defaults differ from v1: field names match case-sensitively, and duplicate names and invalid UTF-8 are rejected. The [package documentation](https://pkg.go.dev/encoding/json/v2) lists all differences. v1 code under the experiment flag keeps the v1 behavior, because the v1 API runs the v2 engine with v1-compatible options. For the Keycloak payloads none of this changed anything.

## Result 2: HTTP clients

All numbers below are benchstat medians from the final run (n=8, `GOMAXPROCS=4`). The machine was still busy, so time values scatter by up to 30 to 40 %, while allocations are deterministic. [Part 4](/blog/gocloak-performance-final-benchmarks/) has the complete tables; here are the results that matter.

### Offline: bytes tell more than time

With the fake Keycloak and one caller at a time, the time values jumped around from endpoint to endpoint. Plain resty was 49 % faster than gocloak for 100 users and 27 % slower for a single user. That is the noise of a loaded machine, not a pattern. The bytes per call are reliable:

| 1,000 users, offline | Bytes per call | vs gocloak |
| --- | ---: | ---: |
| gocloak | 3.88 MiB | |
| plain resty | 2.42 MiB | -38 % |
| net/http | 2.44 MiB | -37 % |
| fasthttp | 1.93 MiB | -50 % |

All stacks need about 45,100 allocations for this call. The objects are created by the JSON decoder, not by the HTTP client.

### Many callers in parallel

16 goroutines with `GOMAXPROCS=4` fetching a single user over TLS with HTTP/1.1:

| Stack | Time per call | New connections per 1,000 calls |
| --- | ---: | ---: |
| gocloak (default) | 51.0 µs | 30.4 |
| gocloak, pool 256 | 28.2 µs | 1.09 |
| net/http (tuned) | 19.2 µs | 0.77 |
| fasthttp | 14.4 µs | 0.14 |

In this run the larger pool made gocloak 1.8 times faster. Default and large pool ran one after the other, so I repeated just that comparison as an interleaved A/B run: 39.2 µs with the default pool against 15.2 µs with 256 idle connections, 2.6 times as fast (-61 %), and new connections dropped from 33.0 to 0.67 per 1,000 calls (-98 %). That is one transport setting. Over HTTP/2 none of the Go clients opened new connections, because HTTP/2 multiplexes all requests over a single connection.

### Live against Keycloak

Against the real Keycloak in Docker, plain HTTP, one caller at a time, all Go variants are equally fast. A single user takes about 0.9 ms, a token 1.8 ms, the list of 1,000 users about 39 ms. fasthttp saves 80 to 180 µs on small calls (6 to 10 %) and nothing measurable on large ones.

In my very first live run the 1,000 users took 153 to 185 ms. The JVM in Keycloak was not warm yet, even after 300 warm-up calls per endpoint. Part 4 has the details.

The connection pool shows up live too. With 16 parallel callers gocloak's default opened 247 new connections per 1,000 calls and needed 359 µs per call; with a pool of 256 it was 231 µs. In a longer 5-second profiling run the default opened 309 connections per 1,000 calls, the large pool 4.

Local token verification (`DecodeAccessToken` with a real Keycloak token and a warm certificate cache) takes 50.5 µs, pure CPU for the RSA signature check. json/v2 does not change that time measurably; it only saves 21 % of the allocations.

## Result 3: other findings

### The response body limit costs memory

gocloak sets a response body limit so a misbehaving server cannot make it read a gigantic response. When a limit is set, resty reads the body in 512-byte chunks with `append` (`readAllWithLimit`) and does not preallocate from `Content-Length`. According to the [pprof](https://pkg.go.dev/runtime/pprof) memory profile, `readAllWithLimit` causes 61 to 67 % of all allocated bytes when fetching 1,000 users, more than the JSON decoding. That is why gocloak allocates 3.88 MiB per call where plain resty needs 2.42 MiB, roughly 60 % more. The run time barely changes, but the garbage collector has more to do. [Part 5](/blog/gocloak-pprof-profiling/) shows the profile.

Moving the limit into the transport, for example by wrapping the response body in an `io.LimitReader`, would let resty read the body with a plain `io.ReadAll`. The gap measured above, 3.88 against 2.42 MiB per call, is roughly what that saves. Preallocating the buffer from `Content-Length` would save more, but only if gocloak read and decoded the body itself.

### Fewer round trips beat a faster client

The biggest lever for applications is the number of Keycloak round trips, not the client:

- Reuse tokens instead of logging in per request. Each login costs about 1.8 ms on a warm local Keycloak, more over a real network.
- Use `briefRepresentation` and small `max` values for lists. 1,000 users take about 39 ms in a warm Keycloak, and several times that while the JVM is cold.
- Verify tokens locally against the JWKS instead of calling [token introspection](https://www.rfc-editor.org/rfc/rfc7662). Local verification costs about 50 µs of CPU; introspection is a network round trip plus Keycloak's work. [gocloak-auth-proxy](/blog/gocloak-auth-proxy-keycloak/) is built around exactly that.

## What I take away

1. There is nothing "massive" to gain in the HTTP client. Keycloak needs milliseconds, the client microseconds. fasthttp is the fastest stack in most micro-benchmarks, saves 6 to 10 % on small live calls and nothing on large ones. It also cannot do HTTP/2, is not an `http.RoundTripper` and would break `RestyClient()`/`SetRestyClient` as well as users' proxy, TLS and tracing configuration. My recommendation: don't switch.
2. The real lever under load is the connection pool. resty's default ties `MaxIdleConnsPerHost` to `GOMAXPROCS + 1`, which in containers often means 2 or 3. Parallel load over HTTP/1.1 then keeps opening new connections and TLS handshakes: 2.6 times slower in an interleaved A/B test, and refused connections in the extreme case. The fix is a small change in `NewClient` that raises `MaxIdleConnsPerHost`; I am proposing it for gocloak. If you talk to Keycloak over TLS with HTTP/2, you do not have the problem.
3. json/v2 makes decoding 26 to 74 % faster with no code change, via `GOEXPERIMENT=jsonv2` (user lists about a third), and cuts allocations by about 40 %. Encoding small structs gets 39 to 51 % slower, which does not matter next to Keycloak's response times. Through the whole gocloak path only the user lists get measurably faster (19 to 24 %), and the latency of a live call does not change, because Keycloak dominates it. Because the feature is still experimental, it stays opt-in for users for now.
4. Moving the body limit from resty into the transport would cut gocloak's bytes per call for 1,000 users from 3.88 to about 2.42 MiB.
5. On method: check the facts first (`go list`, module versions, the library's source), then measure. Make benchmarks reproducible with a script, fixed parameters, benchstat and a recorded environment, and keep offline and live apart. On a loaded machine single numbers are worthless; only median comparisons with a p-value count. And never compare old against new in separate runs on a machine whose load changes; interleave them.

[Part 4](/blog/gocloak-performance-final-benchmarks/) has the complete benchstat tables, offline and live, and what the final run taught me about JVM warm-up and benchmark clients that poison each other. [Part 5](/blog/gocloak-pprof-profiling/) looks at the CPU and memory profiles.
