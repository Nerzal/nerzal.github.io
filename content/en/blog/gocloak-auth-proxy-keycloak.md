---
draft: false
title: "gocloak-auth-proxy: a fast, Keycloak-native auth proxy in Go"
seo_title: "gocloak-auth-proxy: Keycloak Forward-Auth for Traefik and nginx"
date: 2026-11-21T11:30:00+01:00
tags:
  [
    "go",
    "keycloak",
    "gocloak",
    "oidc",
    "jwt",
    "traefik",
    "nginx",
    "oauth2-proxy",
    "security",
    "performance",
    "open-source",
  ]
categories: ["Software Engineering"]
series: ["The gocloak universe"]
description: "gocloak-auth-proxy verifies Keycloak JWTs locally for Traefik and nginx forward-auth, as a reverse proxy or with OIDC browser SSO. Benchmarks against oauth2-proxy, gogatekeeper and reference proxies in Rust, Java and Python, the security model and a setup guide."
images: ["img/gocloak/gocloak-auth-proxy-og.jpg"]
featured_image: "img/gocloak/gocloak-auth-proxy-og.jpg"
toc: true
---

> **Series: The gocloak universe.** [Part 1: gocloak-mcp](/blog/gocloak-mcp-first-mcp-server-homebrew/) · Part 2: gocloak-auth-proxy (you are here) · [Part 3: gocloak performance](/blog/gocloak-performance-json-v2-http-clients/) · [Part 4: final benchmark numbers](/blog/gocloak-performance-final-benchmarks/) · [Part 5: pprof](/blog/gocloak-pprof-profiling/)

{{< tldr >}}
- gocloak-auth-proxy is a Keycloak-only authentication proxy in Go, built on gocloak v15, that runs as forward-auth for Traefik and nginx, as a reverse proxy, or with OIDC browser SSO.
- JWT checks in gocloak-auth-proxy run against an in-memory JWKS snapshot, so a valid request never waits for the network.
- Only asymmetric algorithms pass (default `RS256,ES256`): the proxy rejects `none` and `HS*` and strips client identity headers in both dash and underscore spellings.
- In the project's benchmark, gocloak-auth-proxy v0.2.0 answered 15,002 forward-auth requests per second with a full signature check on every request, 2.5 times as many as oauth2-proxy v7.15.6.
- A Rust reference proxy (21,616 requests per second) beats gocloak-auth-proxy without its token cache; with the v0.2.0 cache, gocloak-auth-proxy reaches 25,169.
{{< /tldr >}}

**Update, 21 November 2026:** gocloak-auth-proxy v0.2.0 is out, with a faster token verifier, a cache for verified tokens and a benchmark suite in the repository. I added its numbers and charts to the benchmark section and updated the install commands; the v0.1.0 numbers stay below for comparison.

In [Part 1](/blog/gocloak-mcp-first-mcp-server-homebrew/) I wrote about gocloak v15 and the Keycloak MCP server built on it. At the same time a second project went public: [gocloak-auth-proxy](https://github.com/Nerzal/gocloak-auth-proxy), an authentication proxy that sits in front of your services and lets only requests with a valid Keycloak token through.

It runs in three modes:

- Forward-auth: Traefik's `forwardAuth` or nginx's `auth_request` ask the proxy on `/auth` whether a request may pass. The proxy answers 200 with identity headers, or 401/403.
- Reverse proxy: the proxy itself forwards verified requests to one upstream.
- Browser SSO: OIDC authorization code flow with PKCE, an encrypted session cookie and logout, for web apps that should not deal with OIDC themselves.

In the project's own benchmark, v0.2.0 answered 15,002 forward-auth requests per second with a full signature check on every request, 2.5 times as many as oauth2-proxy on the same machine, and 25,169 with its token cache. Below are those numbers with their caveats, my own micro-benchmark run, the security model and a setup for Traefik and nginx.

v0.1.0 was released on 2026-11-21, v0.2.0 the same afternoon. Nobody has audited it yet, and most of the alternatives below have years of production use behind them.

## Why another proxy for Keycloak

Keycloak used to ship its own proxy, Keycloak Gatekeeper, later renamed Louketo. In August 2020 the Keycloak team [announced its end of life](https://www.keycloak.org/2020/08/sunsetting-louketo-project.adoc) and recommended [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) instead; the last release is 1.0.0 from July 2020 and the [repository](https://github.com/louketo/louketo-proxy) is archived. Since then most Keycloak setups use one of these:

| Project | Language | Stars | Latest release | Keycloak focus |
| --- | --- | ---: | --- | --- |
| [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) | Go | 15,392 | v7.15.6 (2026-11-05) | Generic, with `keycloak` and `keycloak_oidc` providers |
| [Pomerium](https://github.com/pomerium/pomerium) | Go | 5,113 | v0.34.1 (2026-11-11) | Generic OIDC, full identity-aware proxy |
| [Ory Oathkeeper](https://github.com/ory/oathkeeper) | Go | 3,610 | v26.2.0 (2026-03-20) | Generic; JWKS URLs configured by hand |
| [Vouch Proxy](https://github.com/vouch/vouch-proxy) | Go | 3,290 | v0.50.0 | Generic, nginx `auth_request` |
| [traefik-forward-auth](https://github.com/thomseddon/traefik-forward-auth) | Go | 2,396 | v2.3.0 (2024-05-06) | Generic OIDC |
| [gogatekeeper](https://github.com/gogatekeeper/gatekeeper) | Go | 324 | 5.1.0 (2026-11-18) | Yes, the community fork of Keycloak Gatekeeper |
| **gocloak-auth-proxy** | Go | new | v0.2.0 (2026-11-21) | Yes, built on gocloak v15 |

(Stars as of 2026-11-21.)

oauth2-proxy is the default answer and a good one. It supports a dozen identity providers, which also means its configuration and code have to cover a dozen identity providers. gogatekeeper is the closest relative: Keycloak-specific, with forward-auth, PKCE, role and group rules, UMA (marked as not production ready in [its docs](https://gogatekeeper.github.io/gatekeeper/)) and OPA. gocloak-auth-proxy is narrower than both: only Keycloak, few dependencies, and a hot path on which a valid request never waits for the network.

## How a request is verified

For a request with `Authorization: Bearer <JWT>` the proxy goes through these steps:

1. Strip every identity header the client sent: `X-Auth-Request-*`, `X-Forwarded-*`, `Forwarded`, `X-Real-IP`, `Authorization` after reading it, configured custom headers, and their `_` variants (more on that below).
2. Normalize the path and apply the ACL: public paths, optional-auth paths, CORS preflight, route rules. Encoded traversal (`..`, `%2f`, `%2e`, `%5c`, `%23`, `%00`) is rejected.
3. Parse the JWT header and check the algorithm against the allowlist.
4. Look up the signing key by `kid` in an in-memory JWKS snapshot and verify the signature.
5. Check `iss`, `aud`, `exp`, `nbf`, `typ` (only `Bearer`) and the authorization rules: realm and client roles, groups, scopes, `acr`, `amr`, `email_verified`, `azp`, Keycloak organization.
6. Optionally call Keycloak's token introspection or UMA endpoint.
7. Answer with identity headers (forward-auth) or forward the request upstream (reverse proxy).

Steps 1 to 5 need no network call. The JWKS snapshot lives behind a Go `atomic.Pointer`, so readers never take a lock. When a token arrives with an unknown `kid`, for example right after a key rotation in Keycloak, the proxy refreshes the key set once, no matter how many requests are waiting for it, with a rate limit and exponential backoff so a flood of forged `kid` values cannot turn into a flood of requests against Keycloak. A snapshot expires after twice the refresh interval (bounded to one minute through 24 hours). After that `/readyz` returns 503 and Kubernetes stops sending traffic, instead of the proxy accepting tokens against stale keys forever.

### Which tokens it refuses

The algorithm allowlist defaults to `RS256,ES256` and accepts only asymmetric algorithms: RS256/384/512, PS256/384/512, ES256/384/512 and EdDSA with Ed25519. `none` and the HMAC family `HS*` are rejected at configuration time and at verification time. That closes the classic algorithm confusion attack where a token signed with HS256, using the public RSA key as the HMAC secret, passes a naive verifier. The proxy also refuses tokens with `crit`, `b64`, `jku`, `x5u` or `jwk` headers, because those let a token tell the verifier where to fetch its key. [RFC 8725](https://www.rfc-editor.org/rfc/rfc8725), the JWT best current practices, recommends both.

The relevant standards, if you want to dig deeper: [RFC 7519](https://www.rfc-editor.org/rfc/rfc7519) (JWT), [RFC 7515](https://www.rfc-editor.org/rfc/rfc7515) (JWS), [RFC 7517](https://www.rfc-editor.org/rfc/rfc7517) (JWK), [RFC 7662](https://www.rfc-editor.org/rfc/rfc7662) (token introspection), [RFC 7636](https://www.rfc-editor.org/rfc/rfc7636) (PKCE), [OpenID Connect Back-Channel Logout](https://openid.net/specs/openid-connect-backchannel-1_0.html) and Keycloak's [UMA 2.0 docs](https://www.keycloak.org/docs/latest/authorization_services/index.html#_service_uma_authorization_process).

### Header and path confusion

The JWT library takes care of the cryptography. Most auth proxy vulnerabilities come from somewhere else: the proxy and the backend disagree about a header or a path. oauth2-proxy's advisory list from the last 16 months is a good catalog of what goes wrong:

| Advisory | Severity | What happened |
| --- | --- | --- |
| [CVE-2025-54576](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-7rh7-c77v-6434) | critical | `skip_auth_routes` matched against the URL including the query string |
| [CVE-2025-64484](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-vjrc-mh2v-45x6) | high | Header smuggling: identity headers spelled with underscores passed through, and WSGI/CGI backends read them as the dash version |
| [CVE-2026-40575](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-7x63-xv5r-3p2x) | critical | Authentication bypass through a spoofed `X-Forwarded-Uri` |
| [CVE-2026-41059](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-pxq7-h93f-9jrg) | high | Fragment confusion in `skip_auth_routes` and `skip_auth_regex` |
| [CVE-2026-34457](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-5hvv-m4w4-gf6v) | critical | A health-check User-Agent match skipped authentication in `auth_request` mode |

All of them are fixed in current releases. I list them because they are exactly the cases gocloak-auth-proxy has tests for: it strips identity headers in both spellings (`X-Auth-Request-User` and `X_Auth_Request_User`), never trusts `X-Forwarded-*` from the client, rejects encoded delimiters and fragments in paths, and has no User-Agent-based exceptions. Tests only cover the cases someone thought of. oauth2-proxy's bugs were found because many people run it and researchers study it. gocloak-auth-proxy has not had that scrutiny yet, and reviews are welcome.

## Benchmarks

### Head to head (v0.2.0)

v0.2.0 brings its benchmark suite into the repository: `make bench-compare` runs [`bench/run_compare.sh`](https://github.com/Nerzal/gocloak-auth-proxy/blob/main/bench/run_compare.sh). All proxies ran on the same Linux host (Intel Xeon 6985P-C) with `GOMAXPROCS=2`, 32 concurrent connections for 5 seconds, a 2048-bit RS256 bearer token, a local mock JWKS and a local mock upstream, with zero errors in every run.

Two token modes matter for reading the numbers. "Warm" sends the same token on every request. "Cold" rotates through 2,000 different tokens, and for gocloak-auth-proxy the token cache is switched off (`TOKEN_CACHE_SIZE=0`), so every request pays for a full signature check.

![Throughput, latency and memory of gocloak-auth-proxy v0.2.0 against oauth2-proxy and reference proxies in Rust, Java and Python](/img/gocloak/auth-proxy/benchmark-overview.svg)

| Proxy | Tokens | Forward-auth RPS | p50 | Reverse proxy RPS | p50 | Memory under load |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| gocloak-auth-proxy v0.2.0 | warm | 25,169 | 1.08 ms | 11,248 | 2.51 ms | 15.3 to 16.1 MB |
| gocloak-auth-proxy v0.2.0 | cold | 15,002 | 1.99 ms | 7,583 | 3.90 ms | 15.7 to 16.2 MB |
| Rust reference (Axum, `jsonwebtoken`) | cold | 21,616 | 1.32 ms | 10,629 | 2.86 ms | 3.8 to 6.3 MB |
| oauth2-proxy v7.15.6 | warm | 6,023 | 4.47 ms | 2,245 | 13.39 ms | 26.7 to 27.8 MB |
| Java 17 reference (`HttpServer`) | cold | 6,839 | 3.71 ms | 1,978 | 14.23 ms | 104.9 to 114.4 MB |
| Python 3.11 reference (Uvicorn, PyJWT) | cold | 5,811 | 5.14 ms | 734 | 32.95 ms | 14.7 MB (master process) |

The Rust, Java and Python proxies are not products. They are small reference implementations in [`bench/competitors/`](https://github.com/Nerzal/gocloak-auth-proxy/tree/main/bench/competitors), written for this benchmark to show what each runtime does with the same job. oauth2-proxy is the only established product in the run; gogatekeeper is no longer part of it.

Compared fairly, with a full signature check on every request, gocloak-auth-proxy does 2.5 times the forward-auth throughput of oauth2-proxy and 3.4 times in reverse-proxy mode. With the cache it reaches 4.2 and 5 times. The Rust reference is faster than gocloak-auth-proxy without the cache (21,616 against 15,002 forward-auth requests per second) and needs a quarter of the memory; only with the cache does the Go proxy get ahead. The chart's "#1" badge counts the warm run. That is a fair description of production, where a client sends the same token until it expires, but it is not the same workload as the cold runs of the reference proxies.

### What v0.2.0 changed

![Bytes and allocations per token verification from v0.1.0 to v0.2.0](/img/gocloak/auth-proxy/pprof-progression.svg)

Two changes came out of profiling. The JWS verifier now reads the claims with the streaming `jsontext` package from `encoding/json/v2` instead of decoding them into maps. For a cold RS256 verification that cuts the bytes from 6,412 to 1,728 (-73 %) and the allocations from 79 to 33 (-58 %); for EdDSA with custom claim headers from 8,540 to 624 bytes (-93 %) and from 104 to 24 allocations (-77 %). The second change is a sharded cache of verified tokens, keyed by the SHA-256 of the token. A hit takes 463 ns and allocates nothing. It still checks `exp` and `nbf` on every hit, and whether the signing key is still in the current JWKS snapshot, so a key rotation in Keycloak also invalidates cached tokens. Reading an OIDC session cookie got 40 % faster on top.

The micro-benchmarks from the v0.2.0 README (Go 1.27.4, gocloak v15.1.0, Intel Xeon 6985P-C):

| Benchmark | Time per op | Bytes per op | Allocs per op |
| --- | ---: | ---: | ---: |
| `BenchmarkPolicy` | 128 ns | 0 | 0 |
| `BenchmarkIntrospectorCacheHit` | 192 ns | 0 | 0 |
| `BenchmarkVerifyCached` | 463 ns | 0 | 0 |
| `BenchmarkForwardAuth` | 1.62 µs | 2,336 | 17 |
| `BenchmarkReadSession` | 2.76 µs | 1,328 | 3 |
| `BenchmarkVerify/RS256` | 30.0 µs | 1,728 | 33 |
| `BenchmarkVerifyEdDSA` | 45.5 µs | 624 | 24 |
| `BenchmarkVerify/ES256` | 67.7 µs | 1,536 | 44 |

These come from a different machine than my v0.1.0 run below, so compare the allocation columns, not the times.

### The v0.1.0 comparison

The v0.1.0 comparison came from the project README. All three proxies ran on the same Linux host (Intel Xeon 6985P-C) with `GOMAXPROCS=2`, against a local mock Keycloak JWKS and a local mock upstream, with a 2048-bit RS256 bearer token on every request, 32 concurrent connections, access logging off and zero errors in every run. The load scripts and the competitor configurations were not in the repository at that point, so this run cannot be reproduced one to one.

{{< diagram src="gocloak-auth-proxy-throughput.svg" caption="Forward-auth is the mode Traefik and nginx use. The gap is largest there because the proxy only verifies and answers; in reverse-proxy mode it also forwards the request body upstream." >}}

| Proxy | Forward-auth RPS | p50 | Reverse proxy RPS | p50 |
| --- | ---: | ---: | ---: | ---: |
| gocloak-auth-proxy v0.1.0 | 15,825 | 1.80 ms | 8,737 | 3.36 ms |
| gogatekeeper v5.1.0 | 5,801 | 5.04 ms | 4,754 | 6.22 ms |
| oauth2-proxy v7.15.6 | 6,625 | 4.09 ms | 2,851 | 10.55 ms |

{{< diagram src="gocloak-auth-proxy-footprint.svg" caption="Binary size and idle memory from the README. Dependencies are the require entries in each project's go.mod at the release tag, direct and indirect." >}}

At the v0.1.0 tag, gocloak-auth-proxy's go.mod has 12 require entries (2 direct, 10 indirect; the README still says 8). gogatekeeper 5.1.0 has 104 and oauth2-proxy v7.15.6 has 73. Fewer dependencies does not make code correct, but every module is code you have to trust and update.

In forward-auth mode a valid request costs one signature verification and a few map lookups, as the micro-benchmarks below show. A benchmark against mock services measures the proxy alone; in production the upstream will usually dominate.

### Micro-benchmarks on my machine

I ran `make bench` on v0.1.0 on my machine (AMD Ryzen AI 9 HX 370, Windows 11, Go 1.26.2):

| Benchmark | Time per op | Bytes per op | Allocs per op | What it covers |
| --- | ---: | ---: | ---: | --- |
| `BenchmarkIntrospectorCacheHit` | 55 ns | 0 | 0 | Introspection cache hit, SHA-256 keyed |
| `BenchmarkPolicy` | 90 ns | 0 | 0 | Path normalization, ACL, route role check |
| `BenchmarkForwardAuth` | 1.75 µs | 2,416 | 25 | Header scrubbing and identity headers (mock verifier) |
| `BenchmarkReadSession` | 7.3 µs | 3,024 | 10 | AES-256-GCM session cookie decryption and decode |
| `BenchmarkVerify/RS256` | 38.3 µs | 7,704 | 113 | Full RS256 verification with claims and roles |
| `BenchmarkVerify/ES256` | 51.4 µs | 7,352 | 125 | Same with ES256 (P-256) |
| `BenchmarkVerifyEdDSA` | 85.0 µs | 10,576 | 176 | Ed25519 plus custom claim headers |

The v0.1.0 README's numbers came from Go 1.27 on Linux and show fewer allocations (79 for RS256, for example), so the toolchain matters here; compare runs only on the same setup. The picture is the same on both: signature verification is about 95 percent of the CPU time of a request, and everything around it is small change. RS256 is the fastest algorithm to verify, which is convenient because it is Keycloak's default.

## Setting it up

### 1. A client in Keycloak

For forward-auth and reverse-proxy mode the proxy only needs the issuer URL and an audience; it does not need a client secret. Keycloak puts `account` into `aud` by default, so add an *Audience* mapper to a client scope of the clients that call your API, with your API's name (for example `my-api`) as the included audience.

For browser SSO, create a confidential client with the standard flow enabled and `https://app.example.com/oauth2/callback` as the redirect URI.

### 2. Run it

There are static binaries for Linux and macOS (amd64 and arm64) with checksums and GitHub build provenance, and a multi-arch distroless image on GHCR. On Windows use the container or `go install`.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
docker run --rm -p 8080:8080 \
  -e ISSUER=https://keycloak.example.com/realms/myrealm \
  -e AUDIENCE=my-api \
  -e REQUIRED_REALM_ROLES=reader \
  ghcr.io/nerzal/gocloak-auth-proxy:v0.2.0

# or the binary, with provenance check
VERSION=0.2.0; OS=linux; ARCH=amd64
curl -fsSLO "https://github.com/Nerzal/gocloak-auth-proxy/releases/download/v${VERSION}/gocloak-auth-proxy_${VERSION}_${OS}_${ARCH}.tar.gz"
gh attestation verify "gocloak-auth-proxy_${VERSION}_${OS}_${ARCH}.tar.gz" -R Nerzal/gocloak-auth-proxy
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
docker run --rm -p 8080:8080 `
  -e ISSUER=https://keycloak.example.com/realms/myrealm `
  -e AUDIENCE=my-api `
  -e REQUIRED_REALM_ROLES=reader `
  ghcr.io/nerzal/gocloak-auth-proxy:v0.2.0

# or build it with Go 1.27+
go install github.com/Nerzal/gocloak-auth-proxy/cmd/gocloak-auth-proxy@latest
```

{{< /os-tab >}}
{{< /os-tabs >}}

Without `UPSTREAM_URL` the proxy runs in forward-auth mode on `/auth`. `/healthz` and `/readyz` are public, and Prometheus metrics go to a separate port if you set `METRICS_ADDR`. Docker is at [docs.docker.com](https://docs.docker.com/get-started/get-docker/), the GitHub CLI for `gh attestation` at [cli.github.com](https://cli.github.com/).

Test it with a token from Keycloak:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
TOKEN=$(curl -s https://keycloak.example.com/realms/myrealm/protocol/openid-connect/token \
  -d grant_type=client_credentials -d client_id=my-client -d client_secret="$CLIENT_SECRET" \
  | jq -r .access_token)
curl -i -H "Authorization: Bearer $TOKEN" http://localhost:8080/auth
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
$token = (Invoke-RestMethod -Method Post `
  -Uri https://keycloak.example.com/realms/myrealm/protocol/openid-connect/token `
  -Body @{ grant_type = "client_credentials"; client_id = "my-client"; client_secret = $env:CLIENT_SECRET }).access_token
Invoke-WebRequest -Uri http://localhost:8080/auth -Headers @{ Authorization = "Bearer $token" } |
  Select-Object StatusCode, Headers
```

{{< /os-tab >}}
{{< /os-tabs >}}

A 200 with `X-Auth-Request-User`, `-Email`, `-Groups` and `-Roles` headers means it works. A 401 means the token was rejected; the JSON log on stderr says why, without logging the token.

### 3. Traefik

```yaml
http:
  middlewares:
    keycloak-auth:
      forwardAuth:
        address: "http://auth-proxy:8080/auth"
        trustForwardHeader: false
        authResponseHeaders:
          - "X-Auth-Request-User"
          - "X-Auth-Request-Email"
          - "X-Auth-Request-Groups"
          - "X-Auth-Request-Roles"
```

`trustForwardHeader: false` matters. With `true`, Traefik passes the client's own `X-Forwarded-*` headers to the auth service. The proxy strips them anyway, but there is no reason to send them.

### 4. nginx

```nginx
location = /_auth {
    internal;
    proxy_pass http://auth_proxy/auth;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header Authorization $http_authorization;
}

location / {
    auth_request /_auth;
    auth_request_set $auth_user $upstream_http_x_auth_request_user;
    auth_request_set $auth_roles $upstream_http_x_auth_request_roles;

    # do not forward client headers, including spoofed identity headers
    proxy_pass_request_headers off;
    proxy_set_header Content-Type $http_content_type;
    proxy_set_header Accept $http_accept;
    proxy_set_header X-Auth-Request-User $auth_user;
    proxy_set_header X-Auth-Request-Roles $auth_roles;
    proxy_set_header Authorization "";
    proxy_pass http://application;
}
```

`proxy_pass_request_headers off` looks drastic, but it is the only reliable way to make sure the backend never sees an `X_Auth_Request_User` the client made up. Add back the headers your app needs explicitly.

### 5. Route rules, step-up and SSO

In reverse-proxy mode, `ROUTE_RULES` sets requirements per method and path. This requires the `admin` realm role, authentication level `aal2` and an MFA login for every `POST` under `/admin`:

```bash
ROUTE_RULES='POST:/admin/*=realm:admin,acr:aal2,amr:mfa'
```

For browser SSO set `OIDC_ENABLED=true`, `CLIENT_ID`, `CLIENT_SECRET`, `OIDC_REDIRECT_URL` and a cookie secret of at least 32 characters:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
export OIDC_COOKIE_SECRET="$(openssl rand -base64 32)"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
$bytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$env:OIDC_COOKIE_SECRET = [Convert]::ToBase64String($bytes)
```

{{< /os-tab >}}
{{< /os-tabs >}}

The session lives in AES-256-GCM encrypted cookies, split into chunks because Keycloak tokens with many roles easily exceed the 4 KB cookie limit. The default cookie name has the `__Host-` prefix, which browsers only accept with `Secure`, without `Domain` and with `Path=/`. Refresh tokens are rotated once even when several tabs ask at the same moment, `/oauth2/logout` is CSRF protected, and Keycloak can end sessions through back-channel logout. The proxy strips its own cookies before forwarding, so the upstream never sees the session.

If you run Keycloak behind your own CA or with mutual TLS, `KEYCLOAK_CA_FILE` and `KEYCLOAK_CLIENT_CERT_FILE`/`KEYCLOAK_CLIENT_KEY_FILE` cover that. In my [Neuroclip post about Kubernetes behind Keycloak](/blog/neuroclip-5-shipping-kubernetes/) I describe the same pattern from the application side: the app knows nothing about OIDC, and the proxy in front handles it.

## Which one should you use?

- Several identity providers, or GitHub and Google login next to Keycloak: oauth2-proxy.
- Identity-aware access for a whole company, with device posture and a policy language: Pomerium.
- Keycloak only, and you want OPA policies, Redis-backed sessions and a project with years of history: gogatekeeper.
- Keycloak only, forward-auth in Traefik or nginx with the lowest latency and a small dependency tree, and you are fine with v0.2.0: gocloak-auth-proxy.

Reports from real traffic, and especially about where it breaks, are welcome as issues or private security reports in the [repository](https://github.com/Nerzal/gocloak-auth-proxy).
