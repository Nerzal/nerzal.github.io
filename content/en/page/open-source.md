---
title: "Open Source"
date: 2023-01-03T00:00:00+00:00
draft: false
description: "Maintainer of Gocloak, the Go client library for the Keycloak REST API, plus gocloak-mcp (a read-only Keycloak MCP server) and gocloak-auth-proxy."
metric: "3 projects · 1200+ GitHub stars"
---

## Gocloak — Keycloak REST Client for Go

[Gocloak](https://github.com/Nerzal/gocloak) is a full-featured Go client library for the [Keycloak](https://www.keycloak.org/) REST API. Keycloak is an open-source Identity and Access Management (IAM) solution widely used to secure applications with Single Sign-On (SSO), OAuth 2.0, and OpenID Connect (OIDC).

Gocloak covers the complete Keycloak Admin REST API and provides a clean, idiomatic Go interface for tasks such as:

- Managing realms, clients, roles, and users
- Token introspection and refresh
- Group and role mapping
- Fine-grained permission management via Keycloak's Authorization Services

The library is actively maintained and used in production by teams integrating Keycloak into Go-based microservice architectures. Contributions, issue reports, and feature requests are welcome.

**Repository:** [github.com/Nerzal/gocloak](https://github.com/Nerzal/gocloak)

## gocloak-mcp: Keycloak for AI agents

[gocloak-mcp](https://github.com/Nerzal/gocloak-mcp) is a read-only [Model Context Protocol](https://modelcontextprotocol.io/) server for Keycloak, built on gocloak v15. It lets Claude, Cursor or VS Code answer questions about users, clients, roles and events without any tool that could change your realm. It installs with `brew install --cask nerzal/tap/gocloak-mcp`. The background is in [my release post](/blog/gocloak-mcp-first-mcp-server-homebrew/).

## gocloak-auth-proxy

[gocloak-auth-proxy](https://github.com/Nerzal/gocloak-auth-proxy) is a Keycloak authentication proxy for Traefik and nginx forward-auth, as a reverse proxy, or for browser SSO with OIDC and PKCE. It verifies JWTs locally against a cached JWKS. Benchmarks and the security model are in [the auth proxy post](/blog/gocloak-auth-proxy-keycloak/).

## TinyGo

I am also a contributor to [TinyGo](https://tinygo.org/), the Go compiler targeting microcontrollers and WebAssembly. TinyGo enables Go developers to write code for embedded systems with minimal resource usage.

**Repository:** [github.com/tinygo-org/tinygo](https://github.com/tinygo-org/tinygo)
