---
draft: false
title: "Neuroclip bauen — Teil 5: Ausliefern — CI, signierte Images und Kubernetes hinter Keycloak"
seo_title: "Signierte Docker-Images mit cosign, GitOps und Keycloak"
date: 2026-12-06T08:00:00+01:00
tags:
  [
    "go",
    "github-actions",
    "docker",
    "cosign",
    "sigstore",
    "kubernetes",
    "gitops",
    "keycloak",
    "oidc",
    "trivy",
    "devops",
  ]
categories: ["Software Engineering"]
series: ["Building Neuroclip"]
description: "So liefert Neuroclip aus: Tests, Lizenzprüfung, SBOM, Schwachstellen-Scan, keyless cosign-Signatur, ein GitOps-Pull-Request und Keycloak-SSO vor der App."
images: ["img/neuroclip/og.png"]
featured_image: "img/neuroclip/speicher-1440.jpg"
toc: true
---

> **Neuroclip bauen** ist eine Serie über ein Tool, das ich für Streamer schreibe: ein Go-Server, ein React-Dashboard und ein paar Python-Helfer. [Teil 1: Architektur](/de/blog/neuroclip-1-architecture/) · [Teil 2: VOD zum Short](/de/blog/neuroclip-2-vod-to-short-pipeline/) · [Teil 3: die OBS-Regie](/de/blog/neuroclip-3-obs-regie/) · [Teil 4: Facecam-Upscaling](/de/blog/neuroclip-4-facecam-upscaling/) · **Teil 5: Ausliefern (dieser Beitrag)**. Das Produkt selbst steht auf der [Neuroclip-Seite](/de/page/neuroclip/). Status: Early Access, Single-User-Beta.

Ein Tool, das nur auf meinem Streaming-PC läuft, ist ein Hobby. Ein Tool, das zusätzlich als gehostetes Dashboard läuft, braucht eine Auslieferung, der ich nachts um 2 Uhr vertrauen kann. In diesem Beitrag geht es um die Form dieser Pipeline: was die CI prüft, wie Images gescannt und **signiert** werden, warum ein Deploy ein Pull Request ist und kein `kubectl apply`, und wie die App hinter Keycloak landet, obwohl der Go-Server von OIDC nichts weiß.

Neuroclip ist ein kommerzielles Produkt im Early Access, deshalb bleibt dieser Beitrag auf der Ebene von Ideen und allgemeinen Techniken. Workflow-Dateien, Manifeste und Cluster-Interna lasse ich bewusst weg. Die Beispiele unten sind generisch und funktionieren für jedes Projekt.

{{< diagram src="neuroclip-5-pipeline.svg" caption="Vom Push zum Cluster: Die App wird über einen geprüften Pull Request ausgerollt, die statische Website folgt einem beweglichen Tag von selbst." >}}

## Die Pipeline im Überblick

Die Pipeline läuft auf [GitHub Actions](https://docs.github.com/de/actions/writing-workflows/about-workflows) und hat eine einfache Form: **testen, bauen, scannen, signieren, GitOps-Pull-Request öffnen, Cluster**. Die Stufen sind bewusst eine Kette. Ein roter Test erzeugt kein Image, ein roter Scan keine Signatur, und ohne signiertes Image gibt es keinen Deploy-Pull-Request.

Ein Geständnis zur ersten Stufe: Die CI läuft nur unter Linux. Neuroclips eigentliche Heimat ist ein Windows-Streaming-PC, und Tests, die Windows, eine GPU, OBS oder einen Browser brauchen, überspringen sich auf einem normalen Linux-Runner selbst. Die volle Suite läuft lokal. Die ehrliche Zusammenfassung lautet also „Linux in der CI, Windows auf meinem Rechner“, keine Matrix. Wenn du etwas Ähnliches baust, mach solche Skips sichtbar, sonst bedeutet ein grüner CI-Lauf leise weniger, als du denkst. Pinne außerdem alles Umgebungsabhängige wie Locale und Zeitzone in den Tests: Ein Test, der von den Defaults des Runners abhängt, ist ein flaky Test, der auf das nächste Runner-Image-Update wartet.

## Lizenzprüfung ohne Fremdtool

Neuroclip soll verkäuflich bleiben, das heißt: **kein Copyleft-Code im Binary oder im Frontend-Bundle**. Go linkt statisch und ein Bundler packt das ganze Dashboard in wenige Dateien, deshalb würde selbst eine LGPL-Abhängigkeit praktisch in das gelinkt, was ich ausliefere.

Die Idee ist klein: Das Toolchain fragen, welche Abhängigkeiten tatsächlich im Artefakt landen (bei Go `go list -deps`, bei npm der Produktions-Abhängigkeitsbaum), die Lizenz jeder Abhängigkeit lesen und den Build bei starkem Copyleft wie AGPL, GPL oder SSPL scheitern lassen. Copyleft auf Dateiebene wie MPL-2.0 kann erlaubt sein. Dafür habe ich zwei kurze Skripte geschrieben, statt einen Scanner einzubauen.

Der Preis ist offensichtlich: Lizenztexte zu klassifizieren ist eine Heuristik, deshalb wird alles Unerkennbare zur manuellen Prüfung ausgegeben, statt geraten zu werden. Für ein Ein-Personen-Projekt nehme ich lieber ein kurzes Skript, das ich lesen kann, als eine Abhängigkeit, der ich vertrauen muss. Das passt zur Zero-Dependency-Gewohnheit aus [Teil 1](/de/blog/neuroclip-1-architecture/). Wenn du eine geprüfte, allgemeine Lösung brauchst, gibt es dedizierte Lizenz-Scanner; meins beantwortet nur eine Frage.

## Das Image bauen

Der Server ruft **ffmpeg** auf (siehe [Teil 2](/de/blog/neuroclip-2-vod-to-short-pipeline/)) und optional headless Chromium für Exporte. Damit scheiden `scratch` und distroless als letzte Stufe aus; das Image ist ein Multi-Stage-Build, der in einem schlanken Debian-Userland endet. Die Grundlagen stehen in meinem älteren Beitrag zu [Multi-Stage-Go-Builds mit Docker](/de/blog/go-docker/). Ein paar Prinzipien gelten:

- **Statisches Binary.** Ohne cgo entsteht ein statisch gelinktes Binary, was auch die Lizenzprüfung voraussetzt. Wie du das nachprüfst, steht in [meinem Beitrag zur Prüfung statischen Linkens](/de/blog/check-static-linking/).
- **Nicht als root.** Der Prozess läuft als unprivilegierter Nutzer ohne Login-Shell. Das Image enthält keine Geheimnisse und keine Nutzerdaten; beides kommt erst zur Laufzeit hinein.
- **Sichere Defaults.** Der Server lauscht nur auf Loopback, solange du Fernzugriff nicht ausdrücklich freischaltest, und startet dann nicht ohne Authentifizierungs-Geheimnis. Mir ist ein Absturz beim Start lieber als ein unauthentifiziertes Dashboard an einem öffentlichen Port.
- **Kompromisse bleiben lokal.** Einen Browser in einem abgesicherten Container zu betreiben, heißt oft, auf dessen eigene Sandbox zu verzichten. Das ist nur vertretbar, weil er mein eigenes HTML rendert, nie beliebige URLs. Übernimm so eine Einstellung nicht in einen Container, der im Web surft.

## Scannen und signieren

Der Build pusht nur ein unveränderliches Tag (den vollen Commit-SHA). Die freundlichen Tags werden **nach** Scan und Signatur verschoben. Vier Bausteine der Supply Chain spielen mit:

1. **SBOM:** eine Software-Stückliste, ans Image gehängt, mit den enthaltenen Paketen.
2. **Provenance:** eine Attestierung, *wie* das Image gebaut wurde, im Format von [SLSA Provenance](https://slsa.dev/spec/v1.0/provenance). BuildKit kann beides erzeugen; siehe die [Docker-Doku zu Attestations](https://docs.docker.com/build/metadata/attestations/).
3. **[Trivy](https://trivy.dev/)** scannt das gepushte Image auf bekannte Schwachstellen. Ich lasse nur **behebbare kritische** Funde scheitern. Bei allem zu scheitern würde die Pipeline wegen Dingen rot färben, die ich nicht beheben kann, und eine Pipeline, die man zu ignorieren lernt, ist schlechter als keine. Fremde Actions sind per Commit-SHA gepinnt, nicht per Tag, weil ein Tag verschoben werden kann.
4. **[cosign](https://docs.sigstore.dev/cosign/signing/overview/)** signiert den *Digest* des Images, nicht ein bewegliches Tag.

Beachte die Reihenfolge: Eine Signatur bedeutet „dieses Image hat den Scan bestanden“. Scheitert der Scan, liegt das Image zwar unter seinem SHA-Tag in der Registry, ist aber unsigniert, und kein späterer Schritt befördert es.

### Keyless-Signieren in zwei Minuten

Die Signatur ist **keyless**. In den Repository-Secrets liegt kein privater Signaturschlüssel, der leaken oder rotiert werden müsste. Stattdessen:

1. Der CI-Job darf ein OIDC-Token anfordern, GitHub stellt ihm also ein kurzlebiges Token aus, das grob sagt: „das ist Workflow X von Repository Y auf Ref Z“.
2. cosign tauscht dieses Token bei Sigstores Zertifizierungsstelle gegen ein Zertifikat, das nur Minuten gilt und diese Identität enthält.
3. Signatur und Zertifikat werden in einem öffentlichen Transparenzlog festgehalten und neben dem Image in der Registry abgelegt.

Die Verifikation fragt dann nicht „hast du meinen öffentlichen Schlüssel?“, sondern „wurde das vom Workflow *dieses Repositorys* signiert, ausgestellt vom OIDC-Provider von GitHub?“. Das ist die richtige Frage für CI-gebaute Artefakte. Den ganzen Ablauf beschreibt die [Sigstore-Dokumentation](https://docs.sigstore.dev/cosign/signing/overview/).

### cosign installieren und ein Image prüfen

{{< os-tabs >}}
{{< os-tab "Linux" >}}

```bash
# braucht Go; Alternativen sind dein Paketmanager oder das Release-Binary
go install github.com/sigstore/cosign/v3/cmd/cosign@latest
cosign version
```

{{< /os-tab >}}
{{< os-tab "macOS" >}}

```bash
# Homebrew (https://brew.sh/)
brew install cosign
cosign version
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
winget install sigstore.cosign
cosign version
```

{{< /os-tab >}}
{{< /os-tabs >}}

Weitere Installationswege stehen in der [cosign-Installationsanleitung](https://docs.sigstore.dev/cosign/system_config/installation/). Danach prüfst du jedes keyless signierte Image aus GitHub Actions gegen seine Workflow-Identität. Ersetze die Platzhalter durch deine Werte:

{{< os-tabs >}}
{{< os-tab "Linux" >}}

```bash
cosign verify ghcr.io/OWNER/IMAGE:TAG \
  --certificate-identity-regexp '^https://github.com/OWNER/REPOSITORY/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
cosign verify ghcr.io/OWNER/IMAGE:TAG `
  --certificate-identity-regexp '^https://github.com/OWNER/REPOSITORY/' `
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

{{< /os-tab >}}
{{< /os-tabs >}}

Der Identitäts-Regexp oben ist absichtlich locker (jeder Workflow dieses Repositorys). Zieh ihn auf den exakten Workflow-Pfad und Branch fest, wenn nur diese Kombination zählen soll. Bei Erfolg bekommst du JSON mit den Zertifikatsdetails; bei jeder Abweichung beendet sich cosign mit einem Fehlercode ungleich null, so lässt es sich in Skripten als Schranke nutzen. Meine eigenen Images liegen in einer privaten Registry, du kannst den Befehl also nicht dagegen laufen lassen.

## GitOps: Die CI öffnet einen Pull Request, sie deployt nicht

Die CI spricht nie mit dem Cluster. Sobald ein signiertes Image existiert, öffnet die Pipeline in einem privaten Infrastruktur-Repository einen Pull Request, der genau eine Sache ändert: die Image-Referenz, festgenagelt auf den Commit-SHA. Der Pull Request verlinkt den CI-Lauf und nennt das signierte Image, das Review hat also eine Spur. Der Cluster fährt immer einen gepinnten SHA, nie `latest`. Ein üblicher Weg, so eine Änderung auszudrücken, steht in der [Kustomize-Dokumentation](https://kubectl.docs.kubernetes.io/references/kustomize/).

Warum ein Pull Request für die App? Sie hält Nutzerdaten, Sitzungszustand und Zugriff auf Plattform-Konten, und eine neue Version bedeutet einen kurzen Ausfall. Ich will jede Version ansehen, bevor sie live geht, deshalb bleiben **Merge und Apply manuell**. Die Zugangsdaten der CI sind ein Token, das auf genau dieses eine Repository beschränkt ist.

### Die Website ist das Gegenteil

Die statische Marketing-Seite hat keinen Zustand und wird ohne Ausfall ausgerollt, ein Review pro Änderung wäre nur Reibung. Nach Build, Scan und Signatur verschiebt die CI ein Tag, und ein Image-Updater im Cluster ([Keel](https://keel.sh/)) bemerkt den neuen Digest und rollt ihn aus. Zwei Deploy-Stile für zwei Risikoprofile: geprüft für die App mit Zustand, automatisch für die statische Seite. Nur ein gescanntes und signiertes Image kann dieses Tag je bekommen.

## SSO vor der App: Keycloak statt eigenem Login

Das ist der Teil, den ich am befriedigendsten finde: Der Go-Server kann kein OIDC und muss es auch nicht können. Ein Reverse Proxy davor übernimmt das.

{{< diagram src="neuroclip-5-auth-path.svg" caption="Der Request-Pfad: Der Browser spricht nie direkt mit der App; ein authentifizierender Proxy prüft den Login gegen Keycloak und bürgt für die Anfrage." >}}

1. Der Browser ruft den App-Hostnamen auf (`app.neuroclip.de`). Ein [Traefik](https://doc.traefik.io/traefik/)-Ingress terminiert TLS.
2. Der Verkehr geht an einen authentifizierenden Proxy, [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/), der den OpenID-Connect-Authorization-Code-Flow mit PKCE gegen [Keycloak](https://www.keycloak.org/documentation) fährt und nur Nutzer durchlässt, die eine bestimmte Rolle haben.
3. Bei authentifizierten Anfragen leitet der Proxy an die App weiter und weist ihr nach, dass die Anfrage legitim ist. Die App ist nie erreichbar, ohne durch den Proxy zu gehen.

Die Entwurfsentscheidungen, die zählen, ohne Konfigurationsdetails:

- Der Keycloak-Client ist **vertraulich**, nutzt nur den Authorization-Code-Flow mit PKCE und hat genau eine Redirect-URI ohne Wildcard.
- Zugriff gibt eine Rolle, und im Realm ist ein zweiter Faktor Pflicht, weil die App Zugriff auf Plattform-Konten hält.
- Sitzungs-Cookies sind `Secure`, `HttpOnly` und `SameSite`.
- Alles, womit ein Client seine Identität belegen will, muss der Proxy überschreiben und darf es nie durchreichen.
- Die App prüft `Host` und `Origin` als zweite Verteidigungslinie gegen CSRF.
- Der Container läuft ohne root, mit schreibgeschütztem Root-Dateisystem und ohne Kubernetes-API-Zugangsdaten, weil er sie nie braucht.

Ich pflege [Gocloak](/de/page/open-source/), einen Go-Client für die Keycloak-REST-API, Keycloak ist also vertrautes Terrain. Standard-OIDC vor die App zu setzen, statt Login einzubauen, war trotzdem die bessere Entscheidung: Authentifizierung außerhalb der App hält den Go-Code klein, und die sicherheitskritische Logik pflegen Leute, deren Vollzeitjob das ist. Wenn du den Host darunter härtest, ist meine [Ubuntu-Server-Härtung-Serie](/de/blog/ubuntu-server-hardening-1-essentials/) die passende Ergänzung.

Eine ehrliche Statusnotiz: Dieses Setup ist das vereinbarte Design, wurde aber zum Zeitpunkt des Schreibens **noch nicht Ende-zu-Ende erprobt**. Lies diesen Abschnitt als Design, und Early Access als das Etikett, das es verdient.

## Die statische Website: kleine Angriffsfläche per Design

Die Marketing-Seite ist reines HTML und CSS, ausgeliefert von einem unprivilegierten Webserver-Container. Sie setzt auf jeder Antwort strenge Security-Header: HSTS, eine restriktive Content-Security-Policy, die Skripte auf den Hauptseiten verbietet, `nosniff` und eine strenge Referrer-Policy. Sie setzt keine Cookies, macht keine Drittanbieter-Anfragen und nutzt selbst gehostete Schriften, also gibt es nichts für ein Cookie-Banner. Ein klassischer Stolperstein: In nginx werden `add_header`-Direktiven nicht in eine Location vererbt, die eigene definiert, gemeinsame Header müssen also in jede Location eingebunden werden. Was jeder Header tut, steht bei [MDN zu CSP](https://developer.mozilla.org/de/docs/Web/HTTP/CSP) und in [RFC 6797 (HSTS)](https://www.rfc-editor.org/rfc/rfc6797).

## Was ich ändern würde

- Einen echten Windows-Job ergänzen, sobald plattformspezifische Tests von den GPU- und OBS-gebundenen getrennt sind.
- Ein Staging-Deployment ergänzen, damit der manuelle Merge etwas hat, wogegen er prüfen kann.
- Die Verifikations-Identität auf den exakten Workflow und Branch festziehen.

## Wie es weitergeht

Damit ist die Serie vorerst abgeschlossen: von der [Architektur](/de/blog/neuroclip-1-architecture/) über [Pipeline](/de/blog/neuroclip-2-vod-to-short-pipeline/), [Regie](/de/blog/neuroclip-3-obs-regie/) und [Upscaling](/de/blog/neuroclip-4-facecam-upscaling/) bis zum Ausliefern. Wenn du streamst und Neuroclip ausprobieren willst, erklärt die [Neuroclip-Seite](/de/page/neuroclip/), wie du auf die Early-Access-Liste kommst.
