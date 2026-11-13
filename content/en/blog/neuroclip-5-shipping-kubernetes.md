---
draft: false
title: "Building Neuroclip — Part 5: Shipping it — CI, signed images and Kubernetes behind Keycloak"
seo_title: "Signed Docker Images with cosign, GitOps and Keycloak"
date: 2026-12-13T08:00:00+01:00
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
description: "How Neuroclip ships: tests, license checks, SBOM, vulnerability scan, keyless cosign signing, a GitOps pull request and Keycloak SSO in front of the app."
images: ["img/neuroclip/og.png"]
featured_image: "img/neuroclip/speicher-1440.jpg"
toc: true
---

> **Building Neuroclip** is a series about a tool I write for streamers: a Go server, a React dashboard and a few Python helpers. [Part 1: architecture](/blog/neuroclip-1-architecture/) · [Part 2: VOD to short](/blog/neuroclip-2-vod-to-short-pipeline/) · [Part 3: the OBS Regie](/blog/neuroclip-3-obs-regie/) · [Part 4: facecam upscaling](/blog/neuroclip-4-facecam-upscaling/) · **Part 5: shipping it (this post)**. The product itself is on the [Neuroclip page](/page/neuroclip/). Status: early access, single-user beta.

A tool that only runs on my streaming PC is a hobby. A tool that also runs as a hosted dashboard needs a delivery pipeline I can trust at 2 a.m. This post covers the shape of that pipeline: what CI checks, how images are scanned and **signed**, why a deploy is a pull request instead of a `kubectl apply`, and how the app ends up behind Keycloak even though the Go server knows nothing about OIDC.

Neuroclip is a commercial product in early access, so this post stays on the level of ideas and general techniques. Workflow files, manifests and cluster internals are deliberately left out. The examples below are generic and work for any project.

{{< diagram src="neuroclip-5-pipeline.svg" caption="From push to cluster: the app is promoted through a reviewed pull request, the static website follows a moving tag by itself." >}}

## The pipeline at a glance

The pipeline runs on [GitHub Actions](https://docs.github.com/en/actions/writing-workflows/about-workflows) and has a simple shape: **test, build, scan, sign, open a GitOps pull request, cluster**. The stages form a chain on purpose. A red test never produces an image, a red scan never produces a signature, and without a signed image there is no deploy pull request.

A confession about the first stage: CI runs on Linux only. Neuroclip's real home is a Windows streaming PC, and tests that need Windows, a GPU, OBS or a browser skip themselves on a plain Linux runner. The full suite runs locally. So the honest summary is "Linux in CI, Windows on my machine", not a matrix. If you build something similar, make such skips visible, otherwise a green CI run quietly means less than you think. Also pin anything environment-dependent, such as locale and time zone, in tests: a test that depends on the runner's defaults is a flaky test waiting for a runner image update.

## License checks without a third-party tool

I want Neuroclip to stay sellable, which means **no copyleft code in the binary or in the frontend bundle**. Go links statically and a bundler puts the whole dashboard into a few files, so even an LGPL dependency would end up effectively "linked" into what I ship.

The idea is small: ask the toolchain which dependencies actually end up in the artifact (for Go, `go list -deps`; for npm, the production dependency tree), read each dependency's license, and fail the build on strong-copyleft families such as AGPL, GPL or SSPL. File-level copyleft like MPL-2.0 can be allowed. I wrote two short scripts for this instead of adding a scanner.

The trade-off is obvious: classifying license texts is a heuristic, so anything unrecognisable is printed for manual review instead of being guessed. For a one-person project I prefer a short script I can read over a dependency I have to trust. That fits the zero-dependency habit from [Part 1](/blog/neuroclip-1-architecture/). If you need a vetted, general solution, dedicated license scanners exist; mine only answers one question.

## Building the image

The server shells out to **ffmpeg** (see [Part 2](/blog/neuroclip-2-vod-to-short-pipeline/)) and, optionally, to headless Chromium for exports. That rules out `scratch` or distroless as the final stage, so the image is a multi-stage build ending in a slim Debian userland. For the basics, see my older post on [multi-stage Go builds with Docker](/blog/go-docker/). A few principles apply:

- **Static binary.** Building without cgo gives a statically linked binary, which is also what the license check assumes. How to verify that claim is covered in [my post on checking static linking](/blog/check-static-linking/).
- **Non-root.** The process runs as an unprivileged user with no login shell. The image contains no secrets and no user data; both arrive at runtime.
- **Safe defaults.** The server listens on loopback unless you opt in to remote access, and in that case it refuses to start without an authentication secret. I would rather have a crash at startup than an unauthenticated dashboard on a public port.
- **Trade-offs stay local.** Running a browser inside a locked-down container often means giving up its own sandbox. That is only defensible because it renders my own HTML, never arbitrary URLs. Do not copy such a setting into a container that browses the web.

## Scanning and signing

The build pushes only an immutable tag (the full commit SHA). Friendly tags are moved **after** scan and signature. Four supply-chain building blocks are in play:

1. **SBOM:** a software bill of materials, attached to the image, listing the packages inside.
2. **Provenance:** an attestation of *how* the image was built, in the format of [SLSA provenance](https://slsa.dev/spec/v1.0/provenance). BuildKit can generate both; see the [Docker docs on attestations](https://docs.docker.com/build/metadata/attestations/).
3. **[Trivy](https://trivy.dev/)** scans the pushed image for known vulnerabilities. I only fail on **fixable critical** findings. Failing on everything would turn the pipeline red for issues I cannot fix, and a pipeline people learn to ignore is worse than none. Third-party actions are pinned by commit SHA, not by tag, because a tag can be moved.
4. **[cosign](https://docs.sigstore.dev/cosign/signing/overview/)** signs the image *digest*, not a movable tag.

Note the order: a signature means "this image passed the scan". If the scan fails, the image exists in the registry under its SHA tag but is unsigned, and no later step promotes it.

### Keyless signing in two minutes

The signature is **keyless**. There is no private signing key in the repository secrets to leak or rotate. Instead:

1. The CI job is allowed to request an OIDC token, so GitHub issues it a short-lived token that says, roughly, "this is workflow X of repository Y on ref Z".
2. cosign exchanges that token with Sigstore's certificate authority for a certificate that lives for minutes and contains this identity.
3. The signature and the certificate are recorded in a public transparency log and stored next to the image in the registry.

Verification then does not ask "do you have my public key?" but "was this signed by *this repository's workflow*, issued by GitHub's OIDC provider?". That is the right question for CI-built artifacts. The [Sigstore documentation](https://docs.sigstore.dev/cosign/signing/overview/) describes the full flow.

### Install cosign and verify an image

{{< os-tabs >}}
{{< os-tab "Linux" >}}

```bash
# needs Go; alternatives are your package manager or the release binary
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

Other install options are listed in the [cosign installation guide](https://docs.sigstore.dev/cosign/system_config/installation/). Then verify any keyless-signed image from GitHub Actions against its workflow identity. Replace the placeholders with your own values:

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

The identity regexp above is intentionally loose (any workflow of that repository). Tighten it to the exact workflow path and branch if only that combination should count. On success you get JSON with the certificate details; on any mismatch cosign exits non-zero, which makes it usable as a gate in scripts. My own images live in a private registry, so you cannot run this against them.

## GitOps: CI opens a pull request, it does not deploy

CI never talks to the cluster. After a signed image exists, the pipeline opens a pull request in a private infrastructure repository that changes exactly one thing: the image reference, pinned to the commit SHA. The pull request links the CI run and names the signed image, so the review has a paper trail. The cluster always runs a pinned SHA, never `latest`. See the [Kustomize documentation](https://kubectl.docs.kubernetes.io/references/kustomize/) for one common way to express such a change.

Why a pull request for the app? It holds user data, session state and access to platform accounts, and a new version means a short outage. I want to look at every version before it goes live, so **merge and apply stay manual**. The credential CI uses is a token scoped to that one repository.

### The website is the opposite

The static marketing site is stateless and rolls out without downtime, so a review per change would only be friction. After build, scan and signature, CI moves a tag, and an image updater in the cluster ([Keel](https://keel.sh/)) notices the new digest and rolls it out. Two deploy styles for two risk profiles: reviewed for the stateful app, automatic for the static site. Only an image that was scanned and signed can ever receive that tag.

## SSO in front of the app: Keycloak, not custom login

Here is the part I find most satisfying: the Go server cannot do OIDC and does not need to. A reverse proxy in front of it does.

{{< diagram src="neuroclip-5-auth-path.svg" caption="The request path: the browser never talks to the app directly; an authenticating proxy checks the login against Keycloak and vouches for the request." >}}

1. The browser requests the app hostname (`app.neuroclip.de`). A [Traefik](https://doc.traefik.io/traefik/) ingress terminates TLS.
2. Traffic goes to an authenticating proxy, [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/), which runs the OpenID Connect authorization-code flow with PKCE against [Keycloak](https://www.keycloak.org/documentation) and only lets users through who hold a specific role.
3. For authenticated requests the proxy forwards to the app and proves to it that the request is legitimate. The app is never reachable without going through the proxy.

The design choices that matter, without the configuration details:

- The Keycloak client is **confidential**, uses only the authorization-code flow with PKCE, and has exactly one redirect URI with no wildcard.
- Access is granted by a role, and a second factor is mandatory in the realm, because the app holds access to platform accounts.
- Session cookies are `Secure`, `HttpOnly` and `SameSite`.
- Anything a client sends to prove its identity must be overwritten by the proxy, never passed through.
- The app validates `Host` and `Origin` as a second line of defence against CSRF.
- The container runs non-root with a read-only root filesystem and without Kubernetes API credentials, because it never needs them.

I maintain [Gocloak](/page/open-source/), a Go client for the Keycloak REST API, so Keycloak is familiar ground. Putting standard OIDC in front of the app instead of building login into it was still the better call: authentication outside the app keeps the Go code small, and the security-critical logic is maintained by people whose full-time job it is. If you harden the host underneath, my [Ubuntu server hardening series](/blog/ubuntu-server-hardening-1-essentials/) is the companion read.

An honest status note: this setup is the agreed design, but it was **not yet exercised end to end** at the time of writing. Treat this section as design, and early access as the label it deserves.

## The static website: small attack surface by design

The marketing site is plain HTML and CSS served by an unprivileged web server container. It sets a strict set of security headers on every response: HSTS, a restrictive Content-Security-Policy that forbids scripts on the main pages, `nosniff` and a strict referrer policy. It sets no cookies, makes no third-party requests and uses self-hosted fonts, so there is nothing to put in a cookie banner. One classic pitfall: in nginx, `add_header` directives are not inherited into a location that defines its own, so shared headers need to be included in every location. For more on what each header does, see [MDN on CSP](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) and [RFC 6797 (HSTS)](https://www.rfc-editor.org/rfc/rfc6797).

## What I would change

- Add a real Windows job once platform-specific tests are separated from the GPU- and OBS-bound ones.
- Add a staging deployment so the manual merge step has something to validate against.
- Tighten the verification identity to the exact workflow and branch.

## What's next

This closes the series for now: from the [architecture](/blog/neuroclip-1-architecture/) through the [pipeline](/blog/neuroclip-2-vod-to-short-pipeline/), [Regie](/blog/neuroclip-3-obs-regie/) and [upscaling](/blog/neuroclip-4-facecam-upscaling/) to shipping. If you stream and want to try Neuroclip, the [Neuroclip page](/page/neuroclip/) explains how to get on the early access list.
