---
draft: false
title: "Where does the time go? Profiling gocloak with pprof"
seo_title: "Go pprof in Practice: Profiling a Keycloak Client with CPU, Heap and Diff Graphs"
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
series: ["The gocloak universe"]
description: "CPU and heap profiles from gocloak benchmarks with go tool pprof: why encoding/json v1 reads its input twice, why resty's body limit causes two thirds of all allocated bytes, and how a too small connection pool shifts TLS handshake CPU onto the Keycloak side."
toc: true
---

> **Series: The gocloak universe.** [Part 1: gocloak-mcp](/blog/gocloak-mcp-first-mcp-server-homebrew/) · [Part 2: gocloak-auth-proxy](/blog/gocloak-auth-proxy-keycloak/) · [Part 3: gocloak performance](/blog/gocloak-performance-json-v2-http-clients/) · [Part 4: final benchmark numbers](/blog/gocloak-performance-final-benchmarks/) · Part 5: pprof (you are here)

Benchmarks tell you how long something takes. They do not tell you why. In [Part 3](/blog/gocloak-performance-json-v2-http-clients/) and [Part 4](/blog/gocloak-performance-final-benchmarks/) I measured gocloak against Keycloak and found three things worth explaining: json/v2 decodes faster, gocloak allocates about 60 % more bytes than plain resty, and a small connection pool makes parallel calls much slower. This post opens the profiles behind those numbers.

Two of the three findings below only showed up in the profiles: the body limit as the biggest allocation source, and the handshake CPU that lands on the server side.

## Profiles from benchmarks

Go's testing package can write a CPU and a memory profile for any benchmark. No extra code is needed:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
go test -run '^$' -bench 'BenchmarkJSONUnmarshal/payload=users1000/api=v1$' \
  -benchtime 5s -cpu 4 \
  -cpuprofile cpu.pprof -memprofile mem.pprof -o bench.test .

go tool pprof -top bench.test cpu.pprof                              # text ranking
go tool pprof -svg bench.test cpu.pprof > cpu.svg                    # call graph
go tool pprof -svg -sample_index=alloc_space bench.test mem.pprof > mem.svg
go tool pprof -svg -diff_base old/cpu.pprof bench.test new/cpu.pprof > diff-cpu.svg
go tool pprof -http=:8080 bench.test cpu.pprof                       # browser UI with flame graph
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

A few details that matter:

- `-o bench.test` keeps the compiled test binary. pprof needs it to resolve function names.
- The memory profile records several sample types. `-sample_index=alloc_space` shows all bytes allocated during the run, which is what drives GC work. The default, `inuse_space`, shows only what is still alive at the end, which for a benchmark is close to nothing.
- `-diff_base` subtracts one profile from another. In the diff graph red means more in the new profile, green means less.
- `-focus=<regex>` and `-nodecount=<n>` cut a graph down to the part you care about. The graphs in this post use both.

The SVG and PNG output needs [Graphviz](https://graphviz.org/download/), the browser UI with the flame graph does not:

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
# winget does not add dot to PATH; add it for the current session:
$env:Path += ";C:\Program Files\Graphviz\bin"
```

{{< /os-tab >}}
{{< /os-tabs >}}

In the gocloak repository, [`benchmarks/profile.sh`](https://github.com/Nerzal/gocloak/tree/main/benchmarks) runs all of this for five scenarios. Each scenario runs 5 seconds twice: "old" with today's defaults (encoding/json v1, resty's default pool) and "new" with `GOEXPERIMENT=jsonv2` and, for the pool scenarios, an idle pool of 256. The numbers in this post come from those single 5-second profiling runs. They are not the benchstat medians from Part 4, and I label them where both appear.

### How to read the graphs

Every box is a function. The first number is the flat time, spent in the function itself; "of" gives the cumulative time including everything it calls. Bigger font means more flat time, thicker and redder edges mean more time along that path. Dotted edges mean that functions in between were removed by the filter. The [pprof documentation](https://github.com/google/pprof/blob/main/doc/README.md#interpreting-the-callgraph) has the full legend.

## Finding 1: encoding/json v1 reads its input twice

The first scenario only decodes the list of 1,000 users, no HTTP involved. Here is the v1 engine, filtered to everything below `json.Unmarshal`:

![pprof CPU call graph of encoding/json v1 decoding 1,000 users: json.Unmarshal splits into decodeState.value with 3.90 s and checkValid with 1.25 s, which is 20.9 percent of the total CPU](/img/gocloak/pprof/json-v1-cpu.svg)

`json.Unmarshal` has two children. The right one, `checkValid`, takes 20.9 % of the CPU (13.9 % flat). It runs a scanner over the whole input only to check that it is valid JSON, before the actual decoding starts. Then `decodeState.value` walks the same bytes a second time and builds the structs. So a fifth of the CPU goes into a pass that produces nothing but a yes or no. `unquoteBytes`, which turns JSON strings into Go strings, adds another 8.7 %.

The v2 engine under the same v1 API:

![pprof CPU call graph of the same decode with GOEXPERIMENT=jsonv2: no checkValid node, the work goes through makeStructArshaler and jsontext consumeValue down to jsonwire.ConsumeSimpleString with 7 percent](/img/gocloak/pprof/json-v2-cpu.svg)

`checkValid` is gone. The v2 engine (`encoding/json/jsontext` underneath) validates while it decodes, in a single pass. The work goes into the "arshalers", v2's generated per-type marshal and unmarshal functions, and down to `jsonwire.ConsumeSimpleString`, a fast path for strings without escape sequences, which describes most strings in a Keycloak user.

The profiling run for this scenario:

| Decode 1,000 users | v1 engine | v2 engine |
| --- | ---: | ---: |
| Time per op | 3.96 ms | 2.39 ms (-40 %) |
| Allocations per op | 45,018 | 25,122 (-44 %) |
| Bytes per op | 1.41 MiB | 1.16 MiB (-18 %) |

Old and new ran one after the other in the profiling run, so the time column is only a rough guide. The interleaved A/B run from [Part 3](/blog/gocloak-performance-json-v2-http-clients/) measured -32 % for this decode (4.04 to 2.74 ms), and that is the number I trust. The allocation counts are identical in both.

The heap diff shows where the remaining allocations go: v1 allocates through reflection in `decodeState.object` and `literalStore`, v2 through `reflect.mapassign` for the `Attributes` maps, `reflect.unsafe_New` and `makeString`, fewer in total.

## Finding 2: the body limit allocates more than the JSON decoder

The second scenario runs the whole `gocloak.GetUsers` call with `max=1000` against the in-process fake Keycloak. On the CPU side nothing surprises: `json.Unmarshal` takes 52 % of the client CPU with v1 and 45 % with v2. `runtime.cgocall`, the socket syscalls on Windows, takes about 23 %, the in-process server about 22 %, the GC workers 7 to 8 %.

The heap profile is where it gets interesting:

![pprof heap graph (alloc_space) of gocloak.GetUsers with 1,000 users: resty.readAllWithLimit allocated 2579 MB, 61.5 percent of all bytes, while the JSON decoder below decodeState.value allocated 1536 MB](/img/gocloak/pprof/getusers-mem.svg)

`resty.readAllWithLimit` allocated 61.5 % of all bytes in this run, 61 to 67 % across runs. The complete JSON decoding of 1,000 users comes in second with about 37 %. Reading the body costs more memory than turning it into Go structs.

The response is about 470 KB, yet reading it allocates about 2.5 MB per call. gocloak sets a response body limit as a hardening measure, so a broken or hostile server cannot make it read an endless response. With a limit set, resty reads the body in 512-byte chunks and appends each chunk to a slice, without looking at `Content-Length` first. Every time the slice runs out of capacity, `append` allocates a bigger one and copies everything over. For large slices Go grows by a factor of about 1.25, so the intermediate copies add up to roughly five times the body size. The small boxes under `readAllWithLimit` in the graph are those growth steps: 344 KB, 432 KB, 544 KB and the many smaller ones before.

CPU barely notices, this is about 7 % of the client CPU. The garbage collector notices, because it has to clean up all of that.

Without the profile I would have blamed the JSON decoder for gocloak's extra bytes. There are two ways out, both proposals, neither implemented. Moving the limit into the transport, by wrapping the response body in an `io.LimitReader`, lets resty read the body with a plain `io.ReadAll`; the gap measured in Part 4, 3.88 against 2.42 MiB per call, is roughly what that saves. Going further, gocloak could read and decode the body itself and allocate exactly once when the server sends a `Content-Length`:

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

## Finding 3: a small pool burns CPU on TLS handshakes

The third scenario is the pool benchmark: 16 goroutines call `GetUserByID` in parallel over TLS with HTTP/1.1 against the in-process server. With gocloak's default pool, filtered to the connection handling:

![pprof CPU call graph with the default pool: crypto/tls HandshakeContext takes 27.4 percent of all CPU; serverHandshakeStateTLS13 takes 20.4 percent, most of it in RSA decrypt and bigmod montgomeryMul, while the client handshake takes 6.5 percent](/img/gocloak/pprof/pool-default-cpu.svg)

27.4 % of the whole CPU goes into `crypto/tls.(*Conn).HandshakeContext`. The server side of the handshake takes 20.4 %, most of it in the RSA-PSS signature of the server certificate (`rsa.decrypt` and the big-number arithmetic in `bigmod` below it). The client side takes 6.5 %, opening the connections (`dialConn`) another 3.8 %.

The same scenario with an idle pool of 256:

![pprof CPU call graph with an idle pool of 256: no TLS handshake nodes left; the connection path consists of http Transport roundTrip, getConn and queueForIdleConn with well under 2 percent each](/img/gocloak/pprof/pool-tuned-cpu.svg)

The handshake share drops to 0.74 %. What remains of the connection handling is `getConn` taking an idle connection out of the pool.

| Pool scenario (profiling run) | Default pool | Pool 256 |
| --- | ---: | ---: |
| Time per op | 21.7 µs | 12.5 µs |
| New connections per 1,000 calls | 20.4 | 0.11 |
| CPU share of TLS handshakes | 27.4 % | 0.74 % |

The absolute times differ from Part 4 (39.2 and 15.2 µs in the interleaved A/B run) because this was a single, longer run with a different load on the machine. The direction is the same.

The part that matters for production: in this benchmark both sides run in one process, and the server's share of the handshake is three times the client's. In a real deployment the server side runs wherever TLS for Keycloak is terminated, in Keycloak itself or in an ingress in front of it. A client with a too small pool does not only slow itself down. It makes the TLS endpoint of the identity provider do expensive RSA signatures over and over, and every other application that talks to the same Keycloak pays for that.

## Live: Keycloak dominates

Two scenarios ran against the real Keycloak in Docker over plain HTTP.

`live-getusers1000` went from 41.8 ms to 38.9 ms, allocations from 33,179 to 24,216 and bytes from 3.18 MiB to 3.09 MiB. In the profile the client shows up almost only in decoding and reading the body. The rest of the time it waits for Keycloak.

`live-pool` with 16 parallel callers went from 277.7 µs to 212.5 µs per call (-23 %), with 308.5 against 4.0 new connections per 1,000 calls. Without TLS a new connection is cheap, so the effect is smaller than in the TLS scenario offline.

## What the profiles added

The benchmark numbers said "gocloak allocates 60 % more than resty" and "the default pool is slower under parallel load". The profiles explained both:

1. encoding/json v1 validates the whole input in a separate pass before it decodes. v2 does both in one pass, and that accounts for a large part of its advantage.
2. The extra bytes come from reading the body with a limit in 512-byte steps, not from JSON. A `LimitReader` with a buffer preallocated from `Content-Length` would fix it.
3. The cost of the small pool is TLS handshakes, and most of that cost lands on the server side, which in production means the Keycloak side.

The profiles have the same weakness as my first benchmark runs: old and new ran one after the other. For how much faster something is, the interleaved A/B runs from Part 3 and Part 4 are the reference. For where the time and the bytes go, the profiles are.
