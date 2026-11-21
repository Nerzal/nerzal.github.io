---
draft: false
title: "gocloak benchmarks, final numbers: five HTTP stacks, json/v2 and a cold JVM"
seo_title: "gocloak Benchmarks: resty vs net/http vs fasthttp against Keycloak, with benchstat"
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
series: ["The gocloak universe"]
description: "The complete benchstat tables for gocloak against a fake and a real Keycloak: five HTTP stacks, connection pools, json/v2 over the whole request path, plus four benchmark traps: a cold JVM, a Docker port forwarder that one client poisoned for the next, Git Bash rewriting benchstat flags, and load changes between sequential runs. Plus what gocloak v15.1.0 on Go 1.27 changes."
toc: true
---

> **Series: The gocloak universe.** [Part 1: gocloak-mcp](/blog/gocloak-mcp-first-mcp-server-homebrew/) · [Part 2: gocloak-auth-proxy](/blog/gocloak-auth-proxy-keycloak/) · [Part 3: gocloak performance](/blog/gocloak-performance-json-v2-http-clients/) · Part 4: final benchmark numbers (you are here) · [Part 5: pprof](/blog/gocloak-pprof-profiling/)

In [Part 3](/blog/gocloak-performance-json-v2-http-clients/) I described how I benchmarked gocloak against Keycloak: the questions, the setup, the things that broke and the conclusions. This post has the complete tables from the final run, for everyone who wants to check the conclusions against the numbers, and four lessons the final run added.

## Environment

All numbers are benchstat medians with n=8 (n=10 for the interleaved A/B runs) and `GOMAXPROCS=4`, built with Go 1.26.2, against Keycloak 26.8.2 in Docker Desktop on Windows 11 (AMD Ryzen AI 9 HX 370). Other coding agents were running on the same machine. Time values scatter by 30 to 40 % in places, while allocations are deterministic (±0 %). "n.s." means not significant.

The five stacks are gocloak with its defaults, gocloak with an idle pool of 256 connections per host, plain resty, net/http with a tuned pool and a streaming decoder, and fasthttp. The benchmark code is in [`benchmarks/`](https://github.com/Nerzal/gocloak/tree/v15.1.0/benchmarks) in the gocloak repository, together with `run.sh` and `profile.sh`. In v15.1.0 the default keeps 100 idle connections per host, so the benchmark names changed: `gocloak` is the new default, `gocloak-restypool` the old resty pool and `gocloak-direct` uses `SetDirectBodyRead()`. The tables below are from before that change.

## Offline: fake Keycloak, plain HTTP/1.1, one caller at a time

Time per call; the percentage compares with gocloak's default:

| Endpoint | gocloak | gocloak, pool 256 | resty | net/http | fasthttp |
| --- | ---: | ---: | ---: | ---: | ---: |
| Token | 233 µs | 238 µs (n.s.) | 245 µs (n.s.) | 198 µs (n.s.) | 127 µs (-46 %) |
| One user | 136 µs | 157 µs (+15 %) | 173 µs (+27 %) | 188 µs (+38 %) | 111 µs (-19 %) |
| 100 users | 1,637 µs | 1,075 µs (-34 %) | 833 µs (-49 %) | 1,148 µs (-30 %) | 636 µs (-61 %) |
| 1,000 users | 5.33 ms | 6.03 ms (n.s.) | 5.53 ms (n.s.) | 7.52 ms (+41 %) | 5.93 ms (n.s.) |
| Groups | 306 µs | 252 µs (-18 %) | 184 µs (-40 %) | 312 µs (n.s.) | 354 µs (+15 %) |
| Clients | 502 µs | 327 µs (-35 %) | 361 µs (-28 %) | 1,206 µs (+140 %) | 436 µs (n.s.) |

There is no consistent pattern. The pool setting cannot make a sequential call 15 % slower, and net/http is not 140 % slower on clients but 30 % faster on 100 users. These are the swings of a loaded machine. Even with n=8 and a p-value, the time column offline says little more than "same order of magnitude".

The bytes per call are deterministic and tell a clear story:

| Bytes per call | gocloak | resty | net/http | fasthttp |
| --- | ---: | ---: | ---: | ---: |
| 1,000 users | 3.88 MiB | 2.42 MiB (-38 %) | 2.44 MiB (-37 %) | 1.93 MiB (-50 %) |
| Token | 35.2 KiB | 27.6 KiB | 29.5 KiB | 9.5 KiB (-73 %) |

All stacks need 45,100 to 45,200 allocations for 1,000 users, because the objects come from the JSON decoder. The extra 1.5 MiB in gocloak come from resty's body limit handling, which [Part 5](/blog/gocloak-pprof-profiling/) shows in the memory profile. v15.1.0 adds `SetDirectBodyRead()` as an opt-in that closes most of the gap.

## Offline: 16 parallel callers over TLS

16 goroutines call `GetUserByID` in parallel:

{{< diagram src="gocloak-pool-tls-h1.svg" caption="TLS with HTTP/1.1. The default pool keeps too few idle connections, so many calls pay for a new TCP connection and a TLS handshake." >}}

| Stack | TLS + HTTP/1.1 | Dials per 1,000 calls | TLS + HTTP/2 |
| --- | ---: | ---: | ---: |
| gocloak (default) | 51.0 µs | 30.4 | 25.2 µs |
| gocloak, pool 256 | 28.2 µs (-45 %) | 1.09 (-96 %) | 27.8 µs |
| plain resty | 27.0 µs | 13.8 | 27.1 µs |
| net/http (tuned) | 19.2 µs (-62 %) | 0.77 | 22.4 µs |
| fasthttp | 14.4 µs (-72 %) | 0.14 | 9.2 µs (falls back to HTTP/1.1) |

Under HTTP/2 none of the Go clients opens new connections, and gocloak's default is as fast as the large pool. Plain resty has the same default pool as gocloak but needed only 13.8 dials per 1,000 calls instead of 30.4. That value scatters by ±64 %, live resty was at gocloak's level (237 against 247), and gocloak always runs first in each group. Probably noise or an order effect; I have not verified it.

Default and large pool also ran one after the other here. An interleaved A/B run of just those two gives 39.2 µs against 15.2 µs per call (-61 %, 2.6 times as fast) and 33.0 against 0.67 new connections per 1,000 calls (-98 %). Bytes per call drop by 25 %, allocations by 15 %.

## Live: real Keycloak in Docker, plain HTTP/1.1, one caller at a time

| Endpoint | gocloak | gocloak, pool 256 | resty | net/http | fasthttp |
| --- | ---: | ---: | ---: | ---: | ---: |
| Token | 1.81 ms | 1.76 ms | 1.74 ms | 1.75 ms | 1.63 ms (-10 %) |
| One user | 906 µs | 938 µs | 952 µs | 959 µs | 820 µs (-9 %) |
| 100 users | 4.66 ms | 4.74 ms | 4.68 ms | 4.67 ms | 4.59 ms (n.s.) |
| 1,000 users | 39.8 ms | 38.9 ms | 39.4 ms | 39.0 ms | 38.6 ms (n.s.) |
| Groups | 3.03 ms | 2.99 ms | 3.00 ms | 3.03 ms | 2.92 ms (n.s.) |
| Clients | 1.25 ms | 1.28 ms | 1.23 ms | 1.24 ms | 1.18 ms (-6 %) |

Live, all Go variants are equally fast. fasthttp saves 80 to 180 µs on small calls and nothing measurable on large ones. Bytes per call for 1,000 users live: gocloak 3.20 MiB, resty 2.19 MiB (-31 %), net/http 2.26 MiB (-29 %), fasthttp 1.35 MiB (-58 %). For the token fasthttp allocates 85 % fewer bytes.

### Live with 16 parallel callers

| Stack | Time per call | Dials per 1,000 calls |
| --- | ---: | ---: |
| gocloak (default) | 359 µs | 247 |
| gocloak, pool 256 | 231 µs (-36 %) | 64 (-74 %) |
| plain resty | 442 µs (n.s.) | 237 |
| net/http (tuned) | 231 µs (-36 %) | 68 |
| fasthttp | 123 µs (-66 %) | 1.5 |

The 64 dials of the large pool come from the short ramp-up rounds of the benchmark, in which the pool fills. In a longer 5-second profiling run the default opened 309 connections per 1,000 calls and the large pool 4.

Local token verification with `DecodeAccessToken`, a real Keycloak token and a warm certificate cache: 50.5 µs.

## json/v2 over the whole gocloak path

Part 3 compared the JSON engines in isolation. Here is the same comparison through gocloak's full request path, default build against `GOEXPERIMENT=jsonv2`, as an interleaved A/B run against the fake Keycloak (n=10). Why interleaved: see the fourth lesson below.

| gocloak call, offline | v1 engine | v2 engine | Change |
| --- | ---: | ---: | ---: |
| `GetUsers`, 100 users | 697 µs | 529 µs | -24 % |
| `GetUsers`, 1,000 users | 6.53 ms | 5.30 ms | -19 % |
| Token, one user, groups, clients | | | not significant |
| `DecodeAccessToken` | 31.7 µs | 32.2 µs | not significant |

Only the user lists get measurably faster. For the other endpoints the JSON part is too small next to HTTP handling and the in-process server. The geometric mean over all A/B time values is -22 %.

Allocations drop everywhere: geometric mean -40 %, `GetUsers` -44 %, clients -29 %, one user -19 %, token -9 %, `DecodeAccessToken` -21 %.

Live I only have the sequential `run.sh` comparison. Latency does not change significantly there: 1,000 users go from 39.8 to 38.1 ms with p=0.065, and the remaining differences are within noise. Allocations drop as offline.

So json/v2 saves allocations and some CPU in the client. That counts for throughput under load. The latency of a single call does not change, because Keycloak dominates it. On Go 1.27 the v2 engine is the default, see [Part 3](/blog/gocloak-performance-json-v2-http-clients/).

## v15.0 on Go 1.26 against v15.1 on Go 1.27

The findings of this series went into gocloak v15.1.0 ([release notes](https://github.com/Nerzal/gocloak/releases/tag/v15.1.0), released on 21 November 2026): Go 1.27 as minimum version, which makes json/v2 the default engine, 100 idle connections per host, and `SetDirectBodyRead()` as an opt-in. `./ab.sh ref main` compares the branch against main, with the baseline built on Go 1.26.2, interleaved as before.

Offline (n=10): `GetUsers` with 1,000 users -24 % time and -44 % allocations, clients -20 % and -29 %; geometric mean over all endpoints -21 % time and -27 % allocations. The pool benchmark drops from 37.2 to 15.8 µs per call (-57 %) and from 33.3 to 0.64 new connections per 1,000 calls.

Live against Keycloak (n=6): no latency change, because Keycloak dominates. Allocations drop by 10 % (token) to 27 % (user lists), bytes by 3 to 12 %, and with 16 parallel callers the new connections by 70 % (187 to 55 per 1,000 calls).

v15.1.0 has no breaking API changes. The models and the generated `GoCloakIface` are unchanged, and the only new export is `SetDirectBodyRead()`. Three things still change for users:

- `go.mod` requires Go 1.27. With the default `GOTOOLCHAIN=auto` the go command downloads 1.27 itself; with `GOTOOLCHAIN=local` and an older Go the build fails.
- The idle pool is 100 connections per host instead of GOMAXPROCS+1.
- On Go 1.27 `encoding/json` can return different error texts for invalid JSON. If your code matches error strings, check it. `GOEXPERIMENT=nojsonv2` selects the old engine.

If you look at the diff, the test files now write `PolicyRepresentation{Clients: []string{...}}` instead of going through the embedded `ClientPolicyRepresentation`. That is new Go 1.27 syntax: composite literals can set promoted fields of embedded structs directly, and the linter's `embedlit` modernize check asks for it. The struct is the same, and the old notation still compiles.

## Four lessons from the final run

### A cold JVM lies to you

In my very first live run, 1,000 users took 153 to 185 ms. In the final run it was 39 ms. Same Keycloak container, same data, same client. The difference is the JVM: Keycloak keeps getting faster over many requests while the JIT compiler optimizes hot paths and caches fill. The 300 warm-up calls per endpoint in the setup were not enough for the first run.

With a JVM server like Keycloak, warm up generously and compare several runs before you trust a number. A benchmark against a freshly started Keycloak measures the warm-up, not the steady state.

### One benchmark client can poison the next

The first complete run failed in the live pool benchmark. After the default gocloak client with its massive connection churn, the following clients ran into dial timeouts against `[::1]:8080`. The churn had overloaded Docker Desktop's port forwarder on Windows. Even the large pool suddenly showed 300 dials per 1,000 calls and 1.1 ms instead of 0.2 ms per call. The previous client had ruined the conditions for the next one.

The fix is a configurable cool-down per target before each pool client: 2 seconds offline, 15 seconds live. After that the whole run went through without errors. If benchmarks run in a fixed order against shared infrastructure, check that a later candidate does not inherit the mess of an earlier one. Running them in a different order is a cheap test.

### Git Bash rewrites arguments that start with a slash

`go tool benchstat -col /client` failed under Git Bash on Windows:

```text
parsing -col: syntax error: expected key
```

MSYS, the layer under Git Bash, converts arguments that look like absolute Unix paths into Windows paths. `/client` became something like `C:/Program Files/Git/client`. Setting `MSYS_NO_PATHCONV=1` turns that off:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# no conversion happens here, the variable is harmless
go tool benchstat -col /client results/offline-v1.txt
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# PowerShell passes /client unchanged
go tool benchstat -col /client results/offline-v1.txt

# in Git Bash on Windows instead:
# MSYS_NO_PATHCONV=1 go tool benchstat -col /client results/offline-v1.txt
```

{{< /os-tab >}}
{{< /os-tabs >}}

A smaller note: `run.sh` uses `set -o pipefail`, so a single failed benchmark aborts the rest of the run. That is intended. I prefer an aborted run over half a data set that looks complete.

### Interleave old and new

The `run.sh` comparisons of the JSON engines ran the v1 suite and the v2 suite one after the other, minutes apart. The load on the machine changed in between and faked effects of up to ±40 %. `DecodeAccessToken` looked 35 % slower with json/v2 offline and 39 % faster live; the interleaved A/B run shows no difference. `go test -count` makes it worse, because it runs the same sub-benchmark eight times in a row, so a load spike hits all eight samples of one variant.

The same artifact produced an open question in my first draft of this post: the token response seemed to profit only through the direct v2 API (32.4 against 4.4 µs). In the A/B run the v1 API on the v2 engine is 74 % faster too (14.2 to 3.7 µs). The 32 µs came from a load phase.

`benchmarks/ab.sh` builds both variants once with `go test -c` and runs them alternately for 10 rounds, one sample per round, with the order flipped every round. [Part 3](/blog/gocloak-performance-json-v2-http-clients/) shows the loop. If you compare old against new on a machine whose load you do not control, interleave the runs.

## What the final numbers change

The conclusions from Part 3 hold, with sharper numbers:

- Live, the HTTP client does not matter for latency. All Go stacks are within noise of each other; fasthttp saves 6 to 10 % on small calls.
- The connection pool matters under parallel load: 2.6 times faster offline over TLS in the interleaved A/B run, 36 % faster live without TLS, and 98 % fewer new connections. v15.1.0 keeps 100 idle connections per host.
- json/v2 cuts allocations by 9 to 44 % on every call. Through the whole gocloak path only the user lists get measurably faster (19 to 24 % offline), and live latency does not change.
- gocloak allocates 30 to 60 % more bytes than plain resty because of the body limit handling. `SetDirectBodyRead()` in v15.1.0 cuts 39 % for 1,000 users.

The question that remained: where exactly does the time go, and why does gocloak allocate so much? That is what the profiles in [Part 5](/blog/gocloak-pprof-profiling/) answer.
