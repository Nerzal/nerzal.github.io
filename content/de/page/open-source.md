---
title: "Open Source"
date: 2023-01-03T00:00:00+00:00
draft: false
description: "Maintainer von Gocloak, der Go-Client-Bibliothek für die Keycloak REST API, dazu gocloak-mcp (ein read-only Keycloak MCP-Server) und gocloak-auth-proxy."
metric: "3 Projekte · 1200+ GitHub Stars"
---

## Gocloak — Keycloak REST-Client für Go

[Gocloak](https://github.com/Nerzal/gocloak) ist eine vollständige Go-Client-Bibliothek für die [Keycloak](https://www.keycloak.org/) REST API. Keycloak ist eine Open-Source-Lösung für Identity und Access Management (IAM), die häufig eingesetzt wird, um Anwendungen mit Single Sign-On (SSO), OAuth 2.0 und OpenID Connect (OIDC) abzusichern.

Gocloak deckt die gesamte Keycloak Admin REST API ab und bietet eine saubere, idiomatische Go-Schnittstelle für Aufgaben wie:

- Verwaltung von Realms, Clients, Rollen und Benutzern
- Token-Introspektion und -Erneuerung
- Gruppen- und Rollen-Mapping
- Feingranulares Berechtigungsmanagement über Keycloaks Authorization Services

Die Bibliothek wird aktiv gepflegt und produktiv von Teams eingesetzt, die Keycloak in Go-basierte Microservice-Architekturen integrieren. Beiträge, Fehlerberichte und Feature-Requests sind willkommen.

**Repository:** [github.com/Nerzal/gocloak](https://github.com/Nerzal/gocloak)

## gocloak-mcp: Keycloak für KI-Agenten

[gocloak-mcp](https://github.com/Nerzal/gocloak-mcp) ist ein read-only [Model Context Protocol](https://modelcontextprotocol.io/) Server für Keycloak auf Basis von gocloak v15. Claude, Cursor oder VS Code können damit Fragen zu Benutzern, Clients, Rollen und Events beantworten, ohne dass es ein einziges Tool gibt, das deinen Realm verändern könnte. Installation: `brew install --cask nerzal/tap/gocloak-mcp`. Die Hintergründe stehen in [meinem Release-Artikel](/de/blog/gocloak-mcp-first-mcp-server-homebrew/).

## gocloak-auth-proxy

[gocloak-auth-proxy](https://github.com/Nerzal/gocloak-auth-proxy) ist ein Authentifizierungs-Proxy für Keycloak: Forward-Auth für Traefik und nginx, Reverse-Proxy oder Browser-SSO mit OIDC und PKCE. JWTs prüft er lokal gegen ein gecachtes JWKS. Benchmarks und Sicherheitsmodell stehen im [Artikel zum Auth-Proxy](/de/blog/gocloak-auth-proxy-keycloak/).

## TinyGo

Ich bin außerdem Contributor bei [TinyGo](https://tinygo.org/), dem Go-Compiler für Mikrocontroller und WebAssembly. TinyGo ermöglicht Go-Entwicklern, Code für eingebettete Systeme mit minimalem Ressourcenverbrauch zu schreiben.

**Repository:** [github.com/tinygo-org/tinygo](https://github.com/tinygo-org/tinygo)
