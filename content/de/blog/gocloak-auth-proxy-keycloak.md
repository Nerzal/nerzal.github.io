---
draft: false
title: "gocloak-auth-proxy: ein schneller, Keycloak-nativer Auth-Proxy in Go"
seo_title: "gocloak-auth-proxy: Keycloak Forward-Auth für Traefik und nginx"
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
series: ["Das gocloak-Universum"]
description: "gocloak-auth-proxy prüft Keycloak-JWTs lokal für Forward-Auth in Traefik und nginx, als Reverse-Proxy oder mit OIDC-Browser-SSO. Benchmarks gegen oauth2-proxy, gogatekeeper und Referenz-Proxys in Rust, Java und Python, das Sicherheitsmodell und eine Anleitung zur Einrichtung."
images: ["img/gocloak/gocloak-auth-proxy-og.jpg"]
featured_image: "img/gocloak/gocloak-auth-proxy-og.jpg"
toc: true
---

> **Serie: Das gocloak-Universum.** [Teil 1: gocloak-mcp](/de/blog/gocloak-mcp-first-mcp-server-homebrew/) · Teil 2: gocloak-auth-proxy (du bist hier) · [Teil 3: gocloak-Performance](/de/blog/gocloak-performance-json-v2-http-clients/) · [Teil 4: die finalen Benchmark-Zahlen](/de/blog/gocloak-performance-final-benchmarks/) · [Teil 5: pprof](/de/blog/gocloak-pprof-profiling/)

**Update, 21. November 2026:** gocloak-auth-proxy v0.2.0 ist erschienen, mit schnellerem Token-Verifier, einem Cache für geprüfte Tokens und einer Benchmark-Suite im Repository. Ich habe seine Zahlen und Charts in den Benchmark-Teil aufgenommen und die Installationsbefehle aktualisiert; die Zahlen von v0.1.0 bleiben zum Vergleich stehen.

In [Teil 1](/de/blog/gocloak-mcp-first-mcp-server-homebrew/) habe ich über gocloak v15 und den darauf aufbauenden Keycloak MCP-Server geschrieben. Zur selben Zeit ging ein zweites Projekt online: [gocloak-auth-proxy](https://github.com/Nerzal/gocloak-auth-proxy), ein Authentifizierungs-Proxy, der vor deinen Services sitzt und nur Requests mit gültigem Keycloak-Token durchlässt.

Er läuft in drei Modi:

- Forward-Auth: Traefiks `forwardAuth` oder nginx' `auth_request` fragen den Proxy unter `/auth`, ob ein Request durchdarf. Der Proxy antwortet mit 200 und Identity-Headern oder mit 401/403.
- Reverse-Proxy: Der Proxy leitet geprüfte Requests selbst an einen Upstream weiter.
- Browser-SSO: OIDC Authorization Code Flow mit PKCE, verschlüsseltem Session-Cookie und Logout, für Web-Apps, die sich nicht selbst um OIDC kümmern sollen.

Im projekteigenen Benchmark beantwortete v0.2.0 mit vollständiger Signaturprüfung bei jedem Request 15.002 Forward-Auth-Requests pro Sekunde, 2,5-mal so viele wie oauth2-proxy auf derselben Maschine, und mit Token-Cache 25.169. Unten findest du diese Zahlen samt Einschränkungen, meinen eigenen Micro-Benchmark-Lauf, das Sicherheitsmodell und ein Setup für Traefik und nginx.

v0.1.0 ist am 2026-11-21 erschienen, v0.2.0 am Nachmittag desselben Tages. Niemand hat den Code bisher auditiert, und die meisten Alternativen weiter unten haben Jahre im Produktionseinsatz hinter sich.

## Warum noch ein Proxy für Keycloak

Keycloak hatte früher einen eigenen Proxy, Keycloak Gatekeeper, später in Louketo umbenannt. Im August 2020 [kündigte das Keycloak-Team das Ende an](https://www.keycloak.org/2020/08/sunsetting-louketo-project.adoc) und empfahl stattdessen [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy). Das letzte Release ist 1.0.0 vom Juli 2020, das [Repository](https://github.com/louketo/louketo-proxy) ist archiviert. Seitdem setzen die meisten Keycloak-Setups auf eines dieser Projekte:

| Projekt | Sprache | Stars | Letztes Release | Keycloak-Fokus |
| --- | --- | ---: | --- | --- |
| [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) | Go | 15.392 | v7.15.6 (2026-11-05) | Generisch, mit den Providern `keycloak` und `keycloak_oidc` |
| [Pomerium](https://github.com/pomerium/pomerium) | Go | 5.113 | v0.34.1 (2026-11-11) | Generisches OIDC, vollständiger Identity-Aware Proxy |
| [Ory Oathkeeper](https://github.com/ory/oathkeeper) | Go | 3.610 | v26.2.0 (2026-03-20) | Generisch; JWKS-URLs werden von Hand konfiguriert |
| [Vouch Proxy](https://github.com/vouch/vouch-proxy) | Go | 3.290 | v0.50.0 | Generisch, nginx `auth_request` |
| [traefik-forward-auth](https://github.com/thomseddon/traefik-forward-auth) | Go | 2.396 | v2.3.0 (2024-05-06) | Generisches OIDC |
| [gogatekeeper](https://github.com/gogatekeeper/gatekeeper) | Go | 324 | 5.1.0 (2026-11-18) | Ja, der Community-Fork von Keycloak Gatekeeper |
| **gocloak-auth-proxy** | Go | neu | v0.2.0 (2026-11-21) | Ja, gebaut auf gocloak v15 |

(Stars mit Stand 2026-11-21.)

oauth2-proxy ist die Standardantwort, und zwar eine gute. Er unterstützt ein Dutzend Identity Provider, was eben auch heißt, dass Konfiguration und Code ein Dutzend Identity Provider abdecken müssen. gogatekeeper ist der nächste Verwandte: Keycloak-spezifisch, mit Forward-Auth, PKCE, Rollen- und Gruppenregeln, UMA (laut [Doku](https://gogatekeeper.github.io/gatekeeper/) nicht produktionsreif) und OPA. gocloak-auth-proxy ist schmaler als beide: nur Keycloak, wenige Dependencies und ein Hot Path, auf dem ein gültiger Request nie aufs Netzwerk wartet.

## Wie ein Request geprüft wird

Bei einem Request mit `Authorization: Bearer <JWT>` durchläuft der Proxy diese Schritte:

1. Alle Identity-Header entfernen, die der Client mitgeschickt hat: `X-Auth-Request-*`, `X-Forwarded-*`, `Forwarded`, `X-Real-IP`, `Authorization` nach dem Auslesen, konfigurierte eigene Header und jeweils ihre Varianten mit `_` (mehr dazu weiter unten).
2. Den Pfad normalisieren und die ACL anwenden: öffentliche Pfade, Pfade mit optionaler Authentifizierung, CORS-Preflight, Route-Regeln. Kodierte Traversal-Sequenzen (`..`, `%2f`, `%2e`, `%5c`, `%23`, `%00`) werden abgelehnt.
3. Den JWT-Header parsen und den Algorithmus gegen die Allowlist prüfen.
4. Den Signaturschlüssel per `kid` in einem JWKS-Snapshot im Speicher nachschlagen und die Signatur prüfen.
5. `iss`, `aud`, `exp`, `nbf`, `typ` (nur `Bearer`) und die Autorisierungsregeln prüfen: Realm- und Client-Rollen, Gruppen, Scopes, `acr`, `amr`, `email_verified`, `azp`, Keycloak-Organisation.
6. Optional den Token-Introspection- oder UMA-Endpoint von Keycloak aufrufen.
7. Mit Identity-Headern antworten (Forward-Auth) oder den Request an den Upstream weiterleiten (Reverse-Proxy).

Die Schritte 1 bis 5 brauchen keinen Netzwerkaufruf. Der JWKS-Snapshot liegt hinter einem Go-`atomic.Pointer`, Leser nehmen also nie einen Lock. Kommt ein Token mit unbekannter `kid` an, zum Beispiel direkt nach einer Schlüsselrotation in Keycloak, lädt der Proxy das Key Set genau einmal neu, egal wie viele Requests darauf warten. Dazu gibt es ein Rate Limit und exponentielles Backoff, damit eine Flut gefälschter `kid`-Werte nicht zu einer Flut von Requests gegen Keycloak wird. Ein Snapshot läuft nach dem doppelten Refresh-Intervall ab (begrenzt auf eine Minute bis 24 Stunden). Danach liefert `/readyz` 503 und Kubernetes schickt keinen Traffic mehr, statt dass der Proxy endlos Tokens gegen veraltete Schlüssel akzeptiert.

### Welche Tokens er ablehnt

Die Algorithmus-Allowlist steht standardmäßig auf `RS256,ES256` und akzeptiert nur asymmetrische Algorithmen: RS256/384/512, PS256/384/512, ES256/384/512 und EdDSA mit Ed25519. `none` und die HMAC-Familie `HS*` werden sowohl beim Konfigurieren als auch beim Prüfen abgelehnt. Damit ist der klassische Algorithm-Confusion-Angriff erledigt, bei dem ein mit HS256 signiertes Token, das den öffentlichen RSA-Schlüssel als HMAC-Secret nutzt, einen naiven Verifier passiert. Außerdem lehnt der Proxy Tokens mit den Headern `crit`, `b64`, `jku`, `x5u` oder `jwk` ab, weil ein Token damit dem Verifier vorschreiben kann, wo er seinen Schlüssel holen soll. [RFC 8725](https://www.rfc-editor.org/rfc/rfc8725), die JWT Best Current Practices, empfiehlt beides.

Die relevanten Standards, falls du tiefer einsteigen willst: [RFC 7519](https://www.rfc-editor.org/rfc/rfc7519) (JWT), [RFC 7515](https://www.rfc-editor.org/rfc/rfc7515) (JWS), [RFC 7517](https://www.rfc-editor.org/rfc/rfc7517) (JWK), [RFC 7662](https://www.rfc-editor.org/rfc/rfc7662) (Token Introspection), [RFC 7636](https://www.rfc-editor.org/rfc/rfc7636) (PKCE), [OpenID Connect Back-Channel Logout](https://openid.net/specs/openid-connect-backchannel-1_0.html) und Keycloaks [UMA-2.0-Doku](https://www.keycloak.org/docs/latest/authorization_services/index.html#_service_uma_authorization_process).

### Verwirrung um Header und Pfade

Um die Kryptografie kümmert sich die JWT-Library. Die meisten Schwachstellen in Auth-Proxys entstehen woanders: Proxy und Backend sind sich über einen Header oder einen Pfad uneinig. Die Advisory-Liste von oauth2-proxy aus den letzten 16 Monaten ist ein guter Katalog dessen, was schiefgehen kann:

| Advisory | Schweregrad | Was passiert ist |
| --- | --- | --- |
| [CVE-2025-54576](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-7rh7-c77v-6434) | critical | `skip_auth_routes` wurde gegen die URL samt Query-String abgeglichen |
| [CVE-2025-64484](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-vjrc-mh2v-45x6) | high | Header-Smuggling: Identity-Header mit Unterstrichen gingen durch, und WSGI/CGI-Backends lasen sie als Variante mit Bindestrich |
| [CVE-2026-40575](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-7x63-xv5r-3p2x) | critical | Authentifizierung umgangen über einen gefälschten `X-Forwarded-Uri` |
| [CVE-2026-41059](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-pxq7-h93f-9jrg) | high | Fragment-Verwechslung in `skip_auth_routes` und `skip_auth_regex` |
| [CVE-2026-34457](https://github.com/oauth2-proxy/oauth2-proxy/security/advisories/GHSA-5hvv-m4w4-gf6v) | critical | Ein Healthcheck-Abgleich auf den User-Agent übersprang im `auth_request`-Modus die Authentifizierung |

Alle sind in aktuellen Releases behoben. Ich liste sie auf, weil gocloak-auth-proxy genau für diese Fälle Tests hat: Er entfernt Identity-Header in beiden Schreibweisen (`X-Auth-Request-User` und `X_Auth_Request_User`), vertraut `X-Forwarded-*` vom Client nie, lehnt kodierte Trennzeichen und Fragmente in Pfaden ab und kennt keine Ausnahmen anhand des User-Agents. Tests decken nur die Fälle ab, an die jemand gedacht hat. Die Bugs in oauth2-proxy wurden gefunden, weil viele ihn betreiben und Forscher ihn untersuchen. gocloak-auth-proxy hatte diese Prüfung noch nicht, Reviews sind willkommen.

## Benchmarks

### Direkter Vergleich (v0.2.0)

v0.2.0 bringt seine Benchmark-Suite ins Repository: `make bench-compare` startet [`bench/run_compare.sh`](https://github.com/Nerzal/gocloak-auth-proxy/blob/main/bench/run_compare.sh). Alle Proxys liefen auf demselben Linux-Host (Intel Xeon 6985P-C) mit `GOMAXPROCS=2`, 32 gleichzeitigen Verbindungen über 5 Sekunden, einem 2048-Bit-RS256-Bearer-Token, einem lokalen Mock-JWKS und einem lokalen Mock-Upstream, mit null Fehlern in jedem Lauf.

Zum Lesen der Zahlen sind zwei Token-Modi wichtig. "Warm" schickt bei jedem Request dasselbe Token. "Cold" rotiert durch 2.000 verschiedene Tokens, und bei gocloak-auth-proxy ist der Token-Cache abgeschaltet (`TOKEN_CACHE_SIZE=0`), jeder Request bezahlt also eine vollständige Signaturprüfung.

![Durchsatz, Latenz und Speicher von gocloak-auth-proxy v0.2.0 gegen oauth2-proxy und Referenz-Proxys in Rust, Java und Python](/img/gocloak/auth-proxy/benchmark-overview.svg)

| Proxy | Tokens | Forward-Auth RPS | p50 | Reverse-Proxy RPS | p50 | Speicher unter Last |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| gocloak-auth-proxy v0.2.0 | warm | 25.169 | 1,08 ms | 11.248 | 2,51 ms | 15,3 bis 16,1 MB |
| gocloak-auth-proxy v0.2.0 | cold | 15.002 | 1,99 ms | 7.583 | 3,90 ms | 15,7 bis 16,2 MB |
| Rust-Referenz (Axum, `jsonwebtoken`) | cold | 21.616 | 1,32 ms | 10.629 | 2,86 ms | 3,8 bis 6,3 MB |
| oauth2-proxy v7.15.6 | warm | 6.023 | 4,47 ms | 2.245 | 13,39 ms | 26,7 bis 27,8 MB |
| Java-17-Referenz (`HttpServer`) | cold | 6.839 | 3,71 ms | 1.978 | 14,23 ms | 104,9 bis 114,4 MB |
| Python-3.11-Referenz (Uvicorn, PyJWT) | cold | 5.811 | 5,14 ms | 734 | 32,95 ms | 14,7 MB (Master-Prozess) |

Die Proxys in Rust, Java und Python sind keine Produkte. Es sind kleine Referenzimplementierungen in [`bench/competitors/`](https://github.com/Nerzal/gocloak-auth-proxy/tree/main/bench/competitors), geschrieben für diesen Benchmark, um zu zeigen, was jede Runtime mit derselben Aufgabe macht. oauth2-proxy ist das einzige etablierte Produkt im Lauf; gogatekeeper ist nicht mehr dabei.

Fair verglichen, mit vollständiger Signaturprüfung bei jedem Request, schafft gocloak-auth-proxy im Forward-Auth-Modus den 2,5-fachen Durchsatz von oauth2-proxy und im Reverse-Proxy-Modus den 3,4-fachen. Mit Cache sind es das 4,2- und 5-Fache. Die Rust-Referenz ist schneller als gocloak-auth-proxy ohne Cache (21.616 gegen 15.002 Forward-Auth-Requests pro Sekunde) und braucht ein Viertel des Speichers; erst mit Cache liegt der Go-Proxy vorn. Das "#1"-Badge im Chart zählt den Warm-Lauf. Das beschreibt Produktion ganz gut, wo ein Client dasselbe Token bis zum Ablauf schickt, ist aber nicht dieselbe Last wie die Cold-Läufe der Referenz-Proxys.

### Was v0.2.0 geändert hat

![Bytes und Allokationen pro Token-Prüfung von v0.1.0 bis v0.2.0](/img/gocloak/auth-proxy/pprof-progression.svg)

Zwei Änderungen kamen aus dem Profiling. Der JWS-Verifier liest die Claims jetzt mit dem Streaming-Paket `jsontext` aus `encoding/json/v2`, statt sie in Maps zu dekodieren. Bei einer kalten RS256-Prüfung sinken die Bytes damit von 6.412 auf 1.728 (-73 %) und die Allokationen von 79 auf 33 (-58 %); bei EdDSA mit eigenen Claim-Headern von 8.540 auf 624 Bytes (-93 %) und von 104 auf 24 Allokationen (-77 %). Die zweite Änderung ist ein geshardeter Cache geprüfter Tokens, mit dem SHA-256 des Tokens als Schlüssel. Ein Treffer dauert 463 ns und allokiert nichts. Er prüft bei jedem Treffer weiterhin `exp` und `nbf` und ob der Signaturschlüssel noch im aktuellen JWKS-Snapshot steht. Eine Schlüsselrotation in Keycloak macht also auch gecachte Tokens ungültig. Das Lesen eines OIDC-Session-Cookies wurde zusätzlich 40 % schneller.

Die Micro-Benchmarks aus dem README von v0.2.0 (Go 1.27.4, gocloak v15.1.0, Intel Xeon 6985P-C):

| Benchmark | Zeit pro Op | Bytes pro Op | Allocs pro Op |
| --- | ---: | ---: | ---: |
| `BenchmarkPolicy` | 128 ns | 0 | 0 |
| `BenchmarkIntrospectorCacheHit` | 192 ns | 0 | 0 |
| `BenchmarkVerifyCached` | 463 ns | 0 | 0 |
| `BenchmarkForwardAuth` | 1,62 µs | 2.336 | 17 |
| `BenchmarkReadSession` | 2,76 µs | 1.328 | 3 |
| `BenchmarkVerify/RS256` | 30,0 µs | 1.728 | 33 |
| `BenchmarkVerifyEdDSA` | 45,5 µs | 624 | 24 |
| `BenchmarkVerify/ES256` | 67,7 µs | 1.536 | 44 |

Sie stammen von einer anderen Maschine als mein Lauf mit v0.1.0 weiter unten, vergleiche also die Allokationsspalten, nicht die Zeiten.

### Der Vergleich von v0.1.0

Der Vergleich für v0.1.0 stammt aus dem README des Projekts. Alle drei Proxys liefen auf demselben Linux-Host (Intel Xeon 6985P-C) mit `GOMAXPROCS=2`, gegen ein lokales Mock-Keycloak-JWKS und einen lokalen Mock-Upstream, mit einem 2048-Bit-RS256-Bearer-Token bei jedem Request, 32 gleichzeitigen Verbindungen, abgeschaltetem Access-Log und null Fehlern in jedem Lauf. Die Lastskripte und die Konfigurationen der Konkurrenz lagen damals noch nicht im Repository, eins zu eins nachstellen lässt sich dieser Lauf also nicht.

{{< diagram src="gocloak-auth-proxy-throughput.svg" caption="Forward-Auth ist der Modus, den Traefik und nginx nutzen. Dort ist der Abstand am größten, weil der Proxy nur prüft und antwortet; im Reverse-Proxy-Modus leitet er zusätzlich den Request-Body an den Upstream weiter." >}}

| Proxy | Forward-Auth RPS | p50 | Reverse-Proxy RPS | p50 |
| --- | ---: | ---: | ---: | ---: |
| gocloak-auth-proxy v0.1.0 | 15.825 | 1,80 ms | 8.737 | 3,36 ms |
| gogatekeeper v5.1.0 | 5.801 | 5,04 ms | 4.754 | 6,22 ms |
| oauth2-proxy v7.15.6 | 6.625 | 4,09 ms | 2.851 | 10,55 ms |

{{< diagram src="gocloak-auth-proxy-footprint.svg" caption="Binary-Größe und Speicherverbrauch im Leerlauf aus dem README. Dependencies sind die require-Einträge in der go.mod jedes Projekts am Release-Tag, direkt und indirekt." >}}

Am Tag v0.1.0 hat die go.mod von gocloak-auth-proxy 12 require-Einträge (2 direkte, 10 indirekte; das README nennt noch 8). gogatekeeper 5.1.0 hat 104, oauth2-proxy v7.15.6 hat 73. Weniger Dependencies machen Code nicht korrekt, aber jedes Modul ist Code, dem du vertrauen und den du aktualisieren musst.

Im Forward-Auth-Modus kostet ein gültiger Request eine Signaturprüfung und ein paar Map-Lookups, wie die Micro-Benchmarks unten zeigen. Ein Benchmark gegen Mock-Services misst nur den Proxy; in Produktion dominiert meist der Upstream.

### Micro-Benchmarks auf meiner Maschine

Ich habe `make bench` für v0.1.0 auf meinem Rechner laufen lassen (AMD Ryzen AI 9 HX 370, Windows 11, Go 1.26.2):

| Benchmark | Zeit pro Op | Bytes pro Op | Allocs pro Op | Was er abdeckt |
| --- | ---: | ---: | ---: | --- |
| `BenchmarkIntrospectorCacheHit` | 55 ns | 0 | 0 | Treffer im Introspection-Cache, SHA-256 als Schlüssel |
| `BenchmarkPolicy` | 90 ns | 0 | 0 | Pfadnormalisierung, ACL, Rollenprüfung pro Route |
| `BenchmarkForwardAuth` | 1,75 µs | 2.416 | 25 | Header-Bereinigung und Identity-Header (Mock-Verifier) |
| `BenchmarkReadSession` | 7,3 µs | 3.024 | 10 | Entschlüsseln und Dekodieren des AES-256-GCM-Session-Cookies |
| `BenchmarkVerify/RS256` | 38,3 µs | 7.704 | 113 | Vollständige RS256-Prüfung mit Claims und Rollen |
| `BenchmarkVerify/ES256` | 51,4 µs | 7.352 | 125 | Dasselbe mit ES256 (P-256) |
| `BenchmarkVerifyEdDSA` | 85,0 µs | 10.576 | 176 | Ed25519 plus eigene Claim-Header |

Die Zahlen im README von v0.1.0 stammen von Go 1.27 unter Linux und zeigen weniger Allokationen (zum Beispiel 79 für RS256), die Toolchain spielt hier also eine Rolle; vergleiche Läufe nur auf demselben Setup. Das Bild ist auf beiden gleich: Die Signaturprüfung macht etwa 95 Prozent der CPU-Zeit eines Requests aus, alles drumherum fällt kaum ins Gewicht. RS256 ist der am schnellsten zu prüfende Algorithmus, was praktisch ist, weil er der Standard in Keycloak ist.

## Einrichtung

### 1. Ein Client in Keycloak

Für Forward-Auth und den Reverse-Proxy-Modus braucht der Proxy nur die Issuer-URL und eine Audience, ein Client-Secret ist nicht nötig. Keycloak schreibt standardmäßig `account` in `aud`. Füge deshalb einem Client-Scope der Clients, die deine API aufrufen, einen *Audience*-Mapper hinzu, mit dem Namen deiner API (zum Beispiel `my-api`) als Included Audience.

Für Browser-SSO legst du einen Confidential Client mit aktiviertem Standard Flow und `https://app.example.com/oauth2/callback` als Redirect-URI an.

### 2. Starten

Es gibt statische Binaries für Linux und macOS (amd64 und arm64) mit Checksummen und GitHub Build Provenance sowie ein Multi-Arch-Distroless-Image auf GHCR. Unter Windows nimmst du den Container oder `go install`.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
docker run --rm -p 8080:8080 \
  -e ISSUER=https://keycloak.example.com/realms/myrealm \
  -e AUDIENCE=my-api \
  -e REQUIRED_REALM_ROLES=reader \
  ghcr.io/nerzal/gocloak-auth-proxy:v0.2.0

# oder das Binary, mit Provenance-Prüfung
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

# oder mit Go 1.27+ bauen
go install github.com/Nerzal/gocloak-auth-proxy/cmd/gocloak-auth-proxy@latest
```

{{< /os-tab >}}
{{< /os-tabs >}}

Ohne `UPSTREAM_URL` läuft der Proxy im Forward-Auth-Modus unter `/auth`. `/healthz` und `/readyz` sind öffentlich, und Prometheus-Metriken landen auf einem eigenen Port, wenn du `METRICS_ADDR` setzt. Docker bekommst du unter [docs.docker.com](https://docs.docker.com/get-started/get-docker/), die GitHub CLI für `gh attestation` unter [cli.github.com](https://cli.github.com/).

Teste ihn mit einem Token aus Keycloak:

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

Eine 200 mit den Headern `X-Auth-Request-User`, `-Email`, `-Groups` und `-Roles` heißt, dass es funktioniert. Eine 401 heißt, dass das Token abgelehnt wurde; das JSON-Log auf stderr sagt dir warum, ohne das Token zu loggen.

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

`trustForwardHeader: false` ist wichtig. Mit `true` reicht Traefik die `X-Forwarded-*`-Header des Clients an den Auth-Service durch. Der Proxy entfernt sie zwar ohnehin, aber es gibt keinen Grund, sie mitzuschicken.

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

    # keine Client-Header weiterleiten, auch keine gefälschten Identity-Header
    proxy_pass_request_headers off;
    proxy_set_header Content-Type $http_content_type;
    proxy_set_header Accept $http_accept;
    proxy_set_header X-Auth-Request-User $auth_user;
    proxy_set_header X-Auth-Request-Roles $auth_roles;
    proxy_set_header Authorization "";
    proxy_pass http://application;
}
```

`proxy_pass_request_headers off` wirkt drastisch, ist aber der einzige verlässliche Weg, damit das Backend nie ein vom Client erfundenes `X_Auth_Request_User` zu sehen bekommt. Die Header, die deine App braucht, fügst du explizit wieder hinzu.

### 5. Route-Regeln, Step-up und SSO

Im Reverse-Proxy-Modus legt `ROUTE_RULES` Anforderungen pro Methode und Pfad fest. Diese Regel verlangt für jeden `POST` unter `/admin` die Realm-Rolle `admin`, das Authentifizierungslevel `aal2` und einen MFA-Login:

```bash
ROUTE_RULES='POST:/admin/*=realm:admin,acr:aal2,amr:mfa'
```

Für Browser-SSO setzt du `OIDC_ENABLED=true`, `CLIENT_ID`, `CLIENT_SECRET`, `OIDC_REDIRECT_URL` und ein Cookie-Secret mit mindestens 32 Zeichen:

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

Die Session liegt in AES-256-GCM-verschlüsselten Cookies, aufgeteilt in Chunks, weil Keycloak-Tokens mit vielen Rollen das Cookie-Limit von 4 KB schnell überschreiten. Der Standardname des Cookies hat das Präfix `__Host-`, das Browser nur mit `Secure`, ohne `Domain` und mit `Path=/` akzeptieren. Refresh-Tokens werden genau einmal rotiert, auch wenn mehrere Tabs gleichzeitig anfragen, `/oauth2/logout` ist gegen CSRF geschützt, und Keycloak kann Sessions per Back-Channel-Logout beenden. Der Proxy entfernt seine eigenen Cookies vor dem Weiterleiten, der Upstream sieht die Session also nie.

Wenn du Keycloak hinter einer eigenen CA oder mit Mutual TLS betreibst, decken `KEYCLOAK_CA_FILE` und `KEYCLOAK_CLIENT_CERT_FILE`/`KEYCLOAK_CLIENT_KEY_FILE` das ab. In meinem [Neuroclip-Artikel über Kubernetes hinter Keycloak](/de/blog/neuroclip-5-shipping-kubernetes/) beschreibe ich dasselbe Muster aus Sicht der Anwendung: Die App weiß nichts von OIDC, das übernimmt der Proxy davor.

## Welchen solltest du nehmen?

- Mehrere Identity Provider, oder GitHub- und Google-Login neben Keycloak: oauth2-proxy.
- Identity-Aware Access für ein ganzes Unternehmen, mit Device Posture und einer Policy-Sprache: Pomerium.
- Nur Keycloak, und du willst OPA-Policies, Sessions in Redis und ein Projekt mit jahrelanger Geschichte: gogatekeeper.
- Nur Keycloak, Forward-Auth in Traefik oder nginx mit möglichst niedriger Latenz und kleinem Dependency-Baum, und v0.2.0 ist für dich in Ordnung: gocloak-auth-proxy.

Erfahrungen mit echtem Traffic, vor allem dazu, wo er kaputtgeht, sind als Issues oder vertrauliche Security-Reports im [Repository](https://github.com/Nerzal/gocloak-auth-proxy) willkommen.
