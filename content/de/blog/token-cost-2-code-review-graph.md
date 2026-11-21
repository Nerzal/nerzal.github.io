---
draft: false
title: "Token-Kosten in agentischer KI senken — Teil 2: code-review-graph, MCP und Hooks"
seo_title: "code-review-graph: Weniger Tokens mit MCP und Git-Hooks"
date: 2026-11-22T08:00:00+01:00
tags:
  [
    "ai",
    "claude-code",
    "mcp",
    "tree-sitter",
    "git-hooks",
    "token-optimization",
    "agentic-ai",
    "code-review",
  ]
categories: ["AI"]
series: ["Token Cost Minimization in Agentic AI"]
description: "code-review-graph gibt Coding-Agenten einen Tree-sitter-Codegraphen per MCP, statt ganze Dateien zu lesen. Installation, Claude-Code- und Git-Hooks, Auto-Updates, echte Benchmark-Zahlen und Grenzen."
images: ["img/token-cost-agentic-ai.png"]
featured_image: "img/token-cost-agentic-ai.png"
toc: true
---

> **Serie: Token-Kosten in agentischer KI senken.** [Teil 1: Wohin die Tokens fließen, Caveman und Ponytail](/de/blog/token-cost-1-caveman-ponytail/) · Teil 2: code-review-graph und Hooks (du bist hier) · [Teil 3: Headroom, Auto-Updates und das kombinierte Setup](/de/blog/token-cost-3-headroom-stack/)

{{< tldr >}}
- code-review-graph v2.4.0 parst ein Repository mit Tree-sitter in einen lokalen SQLite-Graphen und beantwortet Fragen des Agenten per MCP, typischerweise mit 2.000 bis 4.000 Tokens.
- Installiert wird code-review-graph mit `uv tool install code-review-graph`, danach im Wurzelverzeichnis des Repositorys `code-review-graph install` und `code-review-graph build` ausführen.
- Ein `PostToolUse`-Hook in Claude Code und vier Git-Hooks (`pre-commit`, `post-checkout`, `post-merge`, `post-rewrite`) halten den Graphen aktuell, und alle enden mit `|| true`.
- Die Schlagzeile „63×“ von code-review-graph vergleicht mit dem Lesen aller Dateien; gegen grep plus die drei besten Dateien liegt die vom Hersteller gemessene Reduktion im Median bei 6,65×.
- Nach `uv tool upgrade code-review-graph` erneut `code-review-graph install` ausführen und mit `doctor` prüfen, weil ältere 2.3.x-Kopien das Schema von 2.4.0 beschädigen können.
{{< /tldr >}}

In [Teil 1](/de/blog/token-cost-1-caveman-ponytail/) haben wir gesehen, dass der größte Teil der Token-Rechnung eines Agenten **Eingabe** ist: alles, was der Agent liest und was in jedem Turn als Verlauf erneut gesendet wird. Die häufigste Eingabe in einer Coding-Session ist Quellcode. Um „Was geht kaputt, wenn ich diese Funktion umbenenne?“ zu beantworten, greppt ein Agent typischerweise nach dem Namen, öffnet die drei oder vier besten Treffer komplett und folgt vielleicht noch ein paar Imports. Jede dieser Dateien bleibt danach für den Rest der Session im Kontext.

[code-review-graph](https://github.com/tirth8205/code-review-graph) (MIT, aktuelles Release **v2.4.0** vom 11.11.2026) ersetzt einen großen Teil dieses Lesens durch eine Abfrage gegen einen lokalen Codegraphen.

## Wie es Tokens spart

Das Werkzeug parst dein Repository mit [Tree-sitter](https://tree-sitter.github.io/tree-sitter/), dem inkrementellen Parser hinter dem Syntax-Highlighting vieler Editoren, und speichert das Ergebnis als Graph in einer lokalen SQLite-Datei (`.code-review-graph/graph.db`):

- **Knoten:** Dateien, Funktionen, Klassen, Imports, Tests.
- **Kanten:** Aufrufe, Imports, Vererbung, „Test deckt Funktion ab“.

Der Graph wird dem Agenten über das [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) bereitgestellt, den offenen Standard, um Werkzeuge an LLM-Clients anzubinden. Der Agent stellt dann gezielte Fragen, statt Dateien zu lesen:

| Frage | MCP-Tool |
| --- | --- |
| Wer ruft `parseConfig` auf? | `query_graph_tool` mit `callers_of` |
| Was geht kaputt, wenn sich diese Datei ändert? | `get_impact_radius_tool` |
| Was berührt mein aktueller Diff, und wie riskant ist er? | `detect_changes_tool`, `get_review_context_tool` |
| Wo liegt der Code für „Authentifizierung“? | `semantic_search_nodes_tool` |
| Wie ist das Projekt aufgebaut? | `get_architecture_overview_tool`, `list_communities_tool` |

Eine typische Antwort umfasst 2.000 bis 4.000 Tokens: Namen, Fundstellen, Kanten und auf Wunsch die relevanten Code-Ausschnitte. Der Agent liest nur, was der Graph nennt. Die Sprachabdeckung ist breit: Python, JavaScript/TypeScript, Go, Rust, Java, C/C++, C#, Ruby, Kotlin, Swift, PHP, Shell, PowerShell, Terraform, Notebooks und viele mehr, dazu framework-spezifische Kanten für Spring und Laravel.

Alles bleibt auf deinem Rechner; Embeddings für die semantische Suche sind optional und können lokal laufen.

## Installation

Du brauchst Python 3.10 oder neuer. Das README empfiehlt [uv](https://docs.astral.sh/uv/), das die CLI in eine eigene isolierte Umgebung installiert. Falls uv noch fehlt:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

{{< /os-tab >}}
{{< /os-tabs >}}

Dann code-review-graph installieren, die gefundenen KI-Werkzeuge einrichten und im Wurzelverzeichnis des Repositorys den Graphen bauen:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
uv tool install code-review-graph
cd ~/src/my-project
code-review-graph install --dry-run   # jede Änderung vorab als Diff zeigen
code-review-graph install             # MCP-Eintrag, Hooks, Skills, Anweisungen
code-review-graph build               # erster vollständiger Parse
code-review-graph detect-changes --brief
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
uv tool install code-review-graph
Set-Location $HOME\src\my-project
code-review-graph install --dry-run   # jede Änderung vorab als Diff zeigen
code-review-graph install             # MCP-Eintrag, Hooks, Skills, Anweisungen
code-review-graph build               # erster vollständiger Parse
code-review-graph detect-changes --brief
```

{{< /os-tab >}}
{{< /os-tabs >}}

Danach Claude Code (bzw. den Editor) neu starten. `install` erkennt Claude Code, Codex, Cursor, Windsurf, Zed, Continue, OpenCode, Gemini CLI, Copilot, Kiro und weitere; `--platform claude-code` beschränkt es auf eines. `code-review-graph doctor` prüft das Setup, ohne etwas zu ändern, und `code-review-graph uninstall --dry-run` zeigt, wie man es wieder loswird.

Laut README dauert ein kalter Build eines Repositorys mit rund 3.000 Dateien etwa 40 Sekunden.

### Was `install` schreibt

Für Claude Code, im Repository:

- `.mcp.json`: den MCP-Server-Eintrag.
- `.claude/settings.json`: zwei Claude-Code-Hooks (siehe unten).
- Skills und einen Block mit Graph-Anweisungen in `CLAUDE.md` (überspringen mit `--no-instructions`).
- Git-Hooks in `.git/hooks/`.
- `.code-review-graph/` mit der Datenbank, automatisch in `.gitignore` eingetragen.

Der generische MCP-Eintrag sieht so aus, wenn das Werkzeug mit `uv tool` installiert wurde:

```json
{
  "mcpServers": {
    "code-review-graph": {
      "type": "stdio",
      "command": "uvx",
      "args": ["code-review-graph", "serve"]
    }
  }
}
```

`.mcp.json` und `.claude/` bleiben absichtlich für Git sichtbar, damit ein Team sie committen kann. Wer das nicht will: `install --gitignore` trägt genau die Dateien, die dieser Lauf erzeugt hat, in einen markierten Block in `.gitignore` ein. Für rechnerweite Ausnahmen ist eine [globale .gitignore](/de/blog/global-gitignore/) der sauberere Ort.

Unter Windows ergänzt das README eine Warnung: den MCP-Befehl in der Claude-Code-Konfiguration nicht in `cmd /c` verpacken, sondern direkt auf die ausführbare Datei zeigen.

## Wo man es einbindet: Hooks, die den Graphen aktuell halten

Ein Codegraph ist nur nützlich, wenn er zum Code passt. Ein veralteter Graph ist schlimmer als keiner: Der Agent vertraut einer Aufruferliste, die es nicht mehr gibt. Deshalb ist die Update-Strategie der wichtigste Teil des Setups. Es gibt vier Stellen zum Einhängen, von der inneren Schleife bis zur CI.

### 1. Claude-Code-Hooks: Update nach jeder Änderung

[Claude-Code-Hooks](https://code.claude.com/docs/en/hooks) sind Shell-Befehle, die Claude Code bei Lebenszyklus-Ereignissen ausführt. Konfiguriert werden sie in `settings.json` (benutzerweit in `~/.claude/settings.json`, pro Projekt in `.claude/settings.json`, persönlich pro Projekt in `.claude/settings.local.json`). `code-review-graph install` schreibt zwei davon:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "command -v code-review-graph >/dev/null 2>&1 && code-review-graph hook-update; cat >/dev/null || true",
            "timeout": 30
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "cat >/dev/null || true; command -v code-review-graph >/dev/null 2>&1 || exit 0; code-review-graph status --repo \"$(git rev-parse --show-toplevel)\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Was die einzelnen Teile tun und warum:

- **`PostToolUse` mit Matcher `Edit|Write`** läuft, nachdem der Agent eine Datei geändert hat. `hook-update` parst nur Dateien neu, deren SHA-256-Hash sich geändert hat. Das README misst etwa 2,5 Sekunden für eine Änderung an zwei Dateien in einem Repository mit rund 3.000 Dateien, davon 1,4 Sekunden Prozessstart. Die nächste Graph-Abfrage in derselben Session sieht also schon den neuen Code.
- **`SessionStart`** gibt den Graph-Status (Anzahl Knoten, letztes Update, Commit) in die Session aus. Die Ausgabe eines `SessionStart`-Hooks landet im Kontext, der Agent weiß also ab dem ersten Turn, dass ein Graph existiert und wie aktuell er ist. Das kostet ein paar Dutzend Tokens pro Session.
- **`cat >/dev/null`** liest und verwirft das JSON-Ereignis, das Claude Code auf die Standardeingabe des Hooks schreibt. So verarbeitet der Hook seine Eingabe sauber, obwohl er sie nicht braucht.
- **`command -v … || exit 0` und `|| true`** machen den Hook auf Rechnern ohne das Werkzeug zur No-op, etwa bei Teammitgliedern, die das Repository nur geklont haben. Ein fehlschlagender Hook darf den Agenten nie blockieren.
- **`timeout`** begrenzt den Hook. Dauert ein Update länger, macht Claude Code weiter.

Unter Windows führt Claude Code Hook-Befehle über Git Bash aus, die POSIX-Syntax oben funktioniert also unverändert.

**Optional: Steering.** `code-review-graph install --steering` fügt für Claude Code einen dritten Hook hinzu, der neben jedes `Grep`, `Glob` und `Read` Graph-Kontext (Aufrufer, Aufgerufene, Tests) legt. Das lenkt das Modell zum Graphen, kostet aber laut README etwa 0,12 Sekunden und bis zu rund 220 Tokens pro Aufruf (gemessen an Flask). In einer Session mit 200 Lesevorgängen sind das bis zu 44.000 zusätzliche Tokens. Ich lasse es aus und verlasse mich auf die Anweisungen in `CLAUDE.md`; einschalten, wenn der Agent den Graphen ignoriert.

### 2. Git-Hooks: Update bei Commit, Checkout, Merge und Rebase

Nicht nur der Agent ändert Code. Du wechselst Branches, pullst und rebasest. `install` schreibt deshalb vier Git-Hooks, jeweils in einem markierten Block, damit sie neben eigenem Hook-Code existieren können:

| Git-Hook | Wann | Was er ausführt |
| --- | --- | --- |
| `pre-commit` | vor jedem Commit | `update`, dann `detect-changes --brief` (kurzes Risiko-Review im Terminal) |
| `post-checkout` | nach einem Branch-Wechsel (nicht bei Datei-Checkouts) | `update --quiet` |
| `post-merge` | nach `git merge` / `git pull` | `update --quiet` |
| `post-rewrite` | nach `git rebase` | `update --quiet` |

Der wesentliche Teil des erzeugten `post-merge`-Hooks, vereinfacht:

```bash
#!/bin/sh
# >>> code-review-graph sync hook >>>
if command -v code-review-graph >/dev/null 2>&1; then
    root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    code-review-graph update --quiet --repo "$root" || true
fi
# <<< code-review-graph sync hook <<<
```

Alle Hooks enden mit `|| true`, also **blockiert der Graph nie einen Commit.** Außerdem überspringen sie verknüpfte [Git-Worktrees](https://git-scm.com/docs/git-worktree), solange `CRG_HOOK_WORKTREES=1` nicht gesetzt ist, weil jeder Worktree einen eigenen Graphen bräuchte. Wer mehrere Agenten parallel in Worktrees laufen lässt, sollte die Variable setzen, sonst fragen die Agenten in den Worktrees einen Graphen des Haupt-Checkouts ab.

Verwaltet dein Team Hooks mit [pre-commit](https://pre-commit.com/), [Husky](https://typicode.github.io/husky/) oder [Lefthook](https://lefthook.dev/), gehört `.git/hooks/` möglicherweise diesem Werkzeug. Dann denselben Aufruf `code-review-graph update --quiet` dort als lokalen Hook eintragen.

### 3. Watch-Modus und Daemon: für Editoren ohne Hooks

Editoren wie Windsurf oder Zed bekommen keine Agenten-Hooks. Für sie, und für Repositories, die man außerhalb eines Agenten bearbeitet, gibt es einen Watcher:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
code-review-graph watch                       # ein Repo, im Vordergrund
crg-daemon add ~/src/project-a --alias proj-a  # oder: mehrere Repos im Hintergrund
crg-daemon add ~/src/project-b
crg-daemon start
crg-daemon status
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
code-review-graph watch                             # ein Repo, im Vordergrund
crg-daemon add $HOME\src\project-a --alias proj-a   # oder: mehrere Repos im Hintergrund
crg-daemon add $HOME\src\project-b
crg-daemon start
crg-daemon status
```

{{< /os-tab >}}
{{< /os-tabs >}}

Der Daemon speichert seine Liste in `~/.code-review-graph/watch.toml` und startet tote Watcher alle 30 Sekunden neu. Ohne Not nicht mit den Hooks auf demselben Repository kombinieren; beides funktioniert, aber man bezahlt jedes Update doppelt.

### 4. CI: ein Risiko-Kommentar an jedem Pull Request

Dieselbe Analyse läuft als GitHub Action. Sie baut den Graphen auf dem Runner und schreibt einen dauerhaften Kommentar mit risikobewerteten Funktionen, betroffenen Abläufen und Testlücken:

```yaml
# .github/workflows/code-review-graph.yml
on:
  pull_request:
permissions:
  contents: read
  pull-requests: write
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: tirth8205/code-review-graph@v2.4.0
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

Der optionale Input `fail-on-risk` macht daraus ein Merge-Gate. Wer eine harte Sperre will, setzt sie hier und nicht im lokalen `pre-commit`-Hook.

### Komfort: Make-Targets

Hat dein Projekt ein Makefile, lohnen sich drei Targets wie `code-graph-build`, `code-graph-update` und `code-graph-changes` um `code-review-graph build`, `update` und `detect-changes --brief`. Menschen finden sie neben den anderen Build-Befehlen, und Agenten, die das Makefile lesen, entdecken sie ohne zusätzliche Anweisungen.

## Die Zahlen

Das Projekt veröffentlicht einen reproduzierbaren Benchmark ([REPRODUCING.md](https://github.com/tirth8205/code-review-graph/blob/staging/docs/REPRODUCING.md)): sechs Open-Source-Repositories auf festgelegten Commits, je fünf Beispielfragen, feste Seeds, lokale Embeddings.

{{< diagram src="token-cost-crg-reduction.svg" caption="Vom Hersteller gemessen. Die ersten sechs Balken vergleichen eine Graph-Antwort mit dem Lesen des ganzen Repositorys, eine Obergrenze, die kein echter Agent bezahlt. Der letzte Balken ist die realistische Basis: greppen und die drei besten Dateien lesen. Median 6,65×." >}}

| Repository | Gesamter Code | Graph-Antwort (Ø) | Reduktion |
| --- | --- | --- | --- |
| fastapi | 948.793 | 2.653 | 357,6× |
| flask | 143.594 | 2.196 | 65,4× |
| code-review-graph | 208.821 | 3.190 | 65,5× |
| gin | 166.868 | 2.766 | 60,3× |
| httpx | 142.356 | 2.661 | 53,5× |
| express | 136.052 | 3.936 | 34,6× |

*Erfasst am 02.08.2026 mit crg 2.3.7. Quelle: [README](https://github.com/tirth8205/code-review-graph).*

Der Schlagzeilenwert „63× im Median“ vergleicht mit dem Lesen **aller Dateien**. Das README nennt diese Basis selbst „an upper bound no real agent pays“. Die ehrlichere Zahl liefert der Benchmark `agent_baseline`, erfasst am 22.09.2026: ein einfaches grep, die drei Dateien mit den meisten Treffern, gezählt gegen die Graph-Abfrage. Dagegen liegt die Reduktion über 18 Fragen in 6 Repositories im Median bei **6,65×** (Mittel 14,8×, Spanne 4,2× bis 72,6×). Das Verhältnis wächst mit der Größe des Repositorys, weil die Graph-Antwort konstant bei 2.400 bis 4.000 Tokens bleibt, während grep-Ergebnisse mit der Codebasis wachsen.

Die Impact-Analyse hat auch eine Präzisionsseite: durchschnittlicher F1-Wert 0,69 gegen eine aus dem Graphen abgeleitete Ground Truth, Präzision 0,55. Sie ist bewusst konservativ und markiert Dateien, die betroffen sein *könnten*.

Einen unabhängigen Benchmark von code-review-graph habe ich nicht gefunden. Die Artikel Dritter, die ich gefunden habe ([DEV Community](https://dev.to/emperorakashi20/how-code-review-graph-cuts-claude-code-token-usage-by-49x-and-whether-its-actually-worth-it-4kn1) zum Beispiel), wiederholen oder diskutieren die Zahlen des Projekts.

### Eigene Messung: dieser Blog

Um zu sehen, was in einem Repository passiert, das größtenteils kein Code ist, habe ich mir den Graphen des Hugo-Repositorys dieses Blogs angesehen (code-review-graph 2.4.0, `status` und `detect-changes --brief`, 13.11.2026):

- **Indiziert:** 63 Dateien, 275 Knoten, 587 Kanten. Sprachen: Bash, HTML-Templates, JavaScript, JSON, YAML. Die Markdown-Beiträge, also der Großteil des Repositorys, sind nicht Teil des Graphen.
- **`detect-changes --brief`** auf einem Arbeitsverzeichnis mit 131 geänderten Dateien meldete „Full context would be: 452,279 tokens · Graph context used: 2,306 tokens · Saved ~99 %“.

Diese 99 % sind eine *Schätzung* des Werkzeugs, und ihre Basis ist „jede geänderte Datei vollständig lesen“. Darunter waren gelöschte, generierte Bild-Caches, die kein Agent je öffnen würde. In diesem Repository ist der Graph für Fragen zu Layouts, Shortcodes und JavaScript wirklich nützlich. Fürs Schreiben von Beiträgen reicht dem Agenten ein simples `grep`, und die MCP-Tools sind nur zusätzliches Schema im Kontext.

## Kosten und wann es nicht hilft

- **Nur Retrieval.** Alle Zahlen messen die Tokens, die nötig sind, um eine Antwort zu *finden*. Öffnet der Agent danach die Dateien, die der Graph genannt hat, zahlt er die Graph-Antwort *zusätzlich* zu diesen Lesevorgängen. `semantic_search_nodes_tool(include_source=True)` liefert den Code gleich mit den Fundstellen, um das zu vermeiden; eine Ende-zu-Ende-Messung ist laut README noch offen.
- **Kleine Änderungen.** Bei einer Änderung an einer Datei kann der Graph-Kontext größer sein als das bloße Lesen der Datei. Der formale Benchmark `token_efficiency` meldet für kleine Commits Verhältnisse unter 1.
- **Tool-Schemas kosten Eingabe.** Der MCP-Server stellt rund 30 Tools bereit. Ihre Definitionen sind ebenfalls Kontext, es sei denn, der Client lädt Tool-Schemas erst bei Bedarf.
- **Veraltete Graphen führen in die Irre.** Ohne Hooks oder Watcher bekommt der Agent selbstbewusst falsche Antworten. Entweder die Hooks oben einrichten oder es nicht nutzen.
- **Versionsdrift.** MCP-Eintrag, Git-Hooks und Daemon können jeweils eine andere Kopie ausführen. Nach `uv tool upgrade code-review-graph` erneut `code-review-graph install` ausführen und mit `doctor` prüfen. Seit 2.4.0 nutzt der Graph Schema 15; ältere 2.3.x-Kopien verweigern ihn oder können ihn beschädigen.
- **Kleine Repositories oder solche ohne viel Code** profitieren wenig, wie meine Messung zeigt.

## Aktualisieren

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
uv tool upgrade code-review-graph
code-review-graph doctor              # jede Kopie, jeder MCP-Eintrag und Hook samt Version
code-review-graph install --dry-run   # sehen, was sich ändert
code-review-graph install
code-review-graph build               # einmal, damit Fixes alle Dateien erreichen
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
uv tool upgrade code-review-graph
code-review-graph doctor              # jede Kopie, jeder MCP-Eintrag und Hook samt Version
code-review-graph install --dry-run   # sehen, was sich ändert
code-review-graph install
code-review-graph build               # einmal, damit Fixes alle Dateien erreichen
```

{{< /os-tab >}}
{{< /os-tabs >}}

Man kann das genauso planen wie den Headroom-Update-Job in [Teil 3](/de/blog/token-cost-3-headroom-stack/#headroom-automatisch-aktuell-halten). Ich würde es nicht tun: Wegen des Problems mit mehreren Kopien sollte auf ein Upgrade `install` und ein Neustart des Editors folgen, und diesen Schritt mache ich lieber bewusst.

Im [letzten Teil](/de/blog/token-cost-3-headroom-stack/) kommt Headroom dazu, ein Proxy, der alles komprimiert, was der Agent liest und *kein* Quellcode ist (Logs, JSON, Testausgaben). Wir lassen es sich selbst aktualisieren, mit Desktop-Benachrichtigungen, und setzen alle vier Werkzeuge zu einem Setup zusammen.

## Quellen

- [code-review-graph README](https://github.com/tirth8205/code-review-graph), [USAGE.md](https://github.com/tirth8205/code-review-graph/blob/staging/docs/USAGE.md), [REPRODUCING.md](https://github.com/tirth8205/code-review-graph/blob/staging/docs/REPRODUCING.md)
- [Tree-sitter](https://tree-sitter.github.io/tree-sitter/), [Model Context Protocol](https://modelcontextprotocol.io/)
- [Claude-Code-Hooks-Referenz](https://code.claude.com/docs/en/hooks), [Claude-Code-Einstellungen](https://code.claude.com/docs/en/settings)
- [githooks-Dokumentation](https://git-scm.com/docs/githooks)
