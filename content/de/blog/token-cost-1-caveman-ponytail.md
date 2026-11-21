---
draft: false
title: "Token-Kosten in agentischer KI senken — Teil 1: Wohin die Tokens fließen, Caveman und Ponytail"
seo_title: "Claude Code Token-Kosten senken: Caveman und Ponytail im Test"
date: 2026-11-13T08:00:00+01:00
tags:
  [
    "ai",
    "claude-code",
    "llm",
    "token-optimization",
    "agentic-ai",
    "caveman",
    "ponytail",
    "developer-tools",
  ]
categories: ["AI"]
series: ["Token Cost Minimization in Agentic AI"]
description: "Woher die Token-Rechnung eines Coding-Agenten wirklich kommt und was die Claude-Code-Plugins Caveman und Ponytail sparen: Installation, Konfiguration, Hersteller-Benchmarks vs. unabhängige Tests."
images: ["img/token-cost-agentic-ai.png"]
featured_image: "img/token-cost-agentic-ai.png"
toc: true
---

> **Serie: Token-Kosten in agentischer KI senken.** Teil 1: Wohin die Tokens fließen, Caveman und Ponytail (du bist hier) · [Teil 2: code-review-graph und Hooks](/de/blog/token-cost-2-code-review-graph/) · [Teil 3: Headroom, Auto-Updates und das kombinierte Setup](/de/blog/token-cost-3-headroom-stack/)

{{< tldr >}}
- Der Großteil der Tokens einer Coding-Agenten-Session ist Eingabe und Cache Reads; ein Caveman-Nutzer hat über 662 Claude-Code-Sessions einen Ausgabe-Anteil von 0,3 % gemessen.
- Caveman v4.1.0 kürzt die Antworten des Agenten, doch im unabhängigen A/B-Test von LemonCrow sank die Ausgabe um 44,1 %, während die Gesamtkosten um 0,06 % stiegen.
- Die Caveman-Regeln kosten etwa 1.160 Eingabe-Tokens pro Request, und `/caveman-compress` verkleinerte fünf Memory-Datei-Fixtures von 6.198 auf 4.138 Tokens (−33,2 %).
- Ponytail v5.3.3 lässt den Agenten weniger Code schreiben: Der Benchmark des Autors zeigt −53 % Codezeilen und −26 % Kosten, JetBrains maß bei v4.8.4 −10,3 % Kosten.
- Ponytail gehört als Claude-Code-Plugin installiert, denn laut JetBrains wurde eine nackte `SKILL.md` im Skills-Ordner in zehn Sessions kein einziges Mal benutzt.
{{< /tldr >}}

Coding-Agenten wie [Claude Code](https://code.claude.com/docs/en/overview), Codex oder Cursor werden pro Token abgerechnet oder verbrauchen pro Token das Nutzungslimit eines Abos. Eine lange Agenten-Session liest schnell Millionen Tokens. Inzwischen gibt es ein ganzes Ökosystem an Werkzeugen, die versprechen, diese Rechnung um „50 bis 90 Prozent“ zu senken.

Diese Serie schaut sich vier der populärsten nacheinander an:

| Werkzeug | Was es verkleinert | Wo es läuft |
| --- | --- | --- |
| [Caveman](https://github.com/JuliusBrussee/caveman) | Antworten des Agenten, Memory-Dateien, Berichte von Subagenten | Skill/Plugin im Agenten (seit v4 plus optionaler Proxy) |
| [Ponytail](https://github.com/DietrichGebert/ponytail) | Die Menge an Code, die der Agent schreibt | Skill/Plugin im Agenten |
| [code-review-graph](https://github.com/tirth8205/code-review-graph) | Wie viel Quellcode der Agent liest | Lokaler MCP-Server plus Hooks |
| [Headroom](https://github.com/headroomlabs-ai/headroom) | Tool-Ausgaben, Logs und JSON, bevor sie beim Modell ankommen | Lokaler Proxy zwischen Agent und API |

Für jedes Werkzeug geht es um den Mechanismus, die Installation, die Konfiguration, die veröffentlichten Zahlen und die Kosten, die auf keiner Landingpage stehen. Zahlen, die der **Hersteller gemessen** hat, und **unabhängig gemessene** Zahlen halte ich strikt auseinander. Alle Versionen und Zahlen habe ich am 13.11.2026 geprüft.

## Wohin die Tokens einer Agenten-Session fließen

Bevor wir Werkzeuge vergleichen, brauchen wir ein Modell der Rechnung. Ein Agenten-Turn ist ein API-Request. Dieser Request enthält:

1. **Systemprompt, Tool-Definitionen und Regeldateien.** Claude Codes eigener Systemprompt, jedes MCP-Tool-Schema, `CLAUDE.md`, aktive Skills. Das wird mit *jedem* Request gesendet.
2. **Den Gesprächsverlauf.** Jede frühere Nachricht, jedes Tool-Ergebnis, jede Antwort. Mit [Prompt Caching](https://docs.claude.com/en/docs/build-with-claude/prompt-caching) wird das meiste davon als günstiger *Cache Read* abgerechnet, aber eben in jedem Turn.
3. **Frische Tool-Ergebnisse.** Die Datei, die der Agent gerade gelesen hat, die `grep`-Treffer, 400 Zeilen Testausgabe.
4. **Die Ausgabe.** Antworttext, Code, Tool-Aufrufe. Ausgabe-Tokens sind die teuerste Sorte: Laut Headroom-README kostet Ausgabe bei Modellen der Opus-Klasse das Fünffache der Eingabe.

{{< diagram src="token-cost-where-tools-act.svg" caption="Jeder Turn sendet den ganzen Kontext erneut. Die vier Werkzeuge greifen an verschiedenen Stellen an: Memory-Dateien, frische Tool-Ausgaben, Anzahl der Datei-Lesevorgänge und die Ausgabe." >}}

Daraus folgen zwei Dinge, die fast jeden Benchmark in dieser Serie erklären:

- **Ausgabe ist pro Token teuer, aber mengenmäßig klein.** In Agenten-Sessions besteht der Großteil der Tokens aus Eingabe und Cache Reads. Ein Caveman-Nutzer hat über 662 Claude-Code-Sessions einen Ausgabe-Anteil von **0,3 % aller Tokens** gemessen (berichtet in Cavemans [HONEST-NUMBERS.md](https://github.com/JuliusBrussee/caveman/blob/main/docs/HONEST-NUMBERS.md)). Ein Werkzeug, das nur Antworten kürzt, kann die Ausgabe stark senken und die Rechnung trotzdem kaum bewegen.
- **Alles, was man dem Prompt hinzufügt, kostet in jedem Turn.** Ein Skill mit 1.000 Tokens, der pro Antwort 300 Ausgabe-Tokens spart, lohnt sich nur bei ausreichend langen Antworten. Eine kürzere Antwort spart dafür später auch Eingabe, weil sie in jedem folgenden Turn als Verlauf erneut gelesen wird.

Dieses Modell sollte man im Kopf behalten. Die Zahl entfernter Tokens sagt wenig; bei jedem Werkzeug frage ich: „**Sinkt die Rechnung des Anbieters für dieselbe Aufgabe?**“

## Caveman: weniger sagen, weniger lesen

[Caveman](https://github.com/JuliusBrussee/caveman) (Apache-2.0, aktuelles Release **v4.1.0** vom 08.11.2026) begann im April 2026 als Scherz-Skill, der Claude wie einen Höhlenmenschen reden ließ. Das Beispiel aus dem README zeigt es am besten: „The reason your React component is re-rendering is likely because…“ (63 Tokens) wird zu „New object ref each render, so React re-renders. Wrap the prop in `useMemo`.“ (20 Tokens).

### Wie es Tokens spart

Heute ist Caveman eine Familie von Mechanismen. Für Nutzer von Claude Code relevant sind:

- **Die Caveman-Stimme** (`/caveman`, `/ultracave`, `/megacave`). Ein Skill, dessen Regeln sich an [ASD-STE100](https://www.asd-ste100.org/) orientieren, dem kontrollierten Englisch aus Wartungshandbüchern der Luftfahrt: Antwort zuerst, ein Gedanke pro Satz, keine Begrüßung, keine Zusammenfassung. Code, Befehle, Pfade und Fehlermeldungen bleiben Byte für Byte erhalten. Verneinungen (*not*, *never*, *only*) und Zahlen fallen nie weg. Sicherheitswarnungen und irreversible Aktionen bekommen ganze Sätze. Deine eigenen Prompts werden nie umgeschrieben.
- **`/caveman-compress <datei>`** schreibt eine Memory-Datei wie `CLAUDE.md` im Caveman-Stil neu und behält das Original als `CLAUDE.original.md`. Da Memory-Dateien mit jedem Request gesendet werden (Punkt 1 oben), spart das Eingabe in jedem Turn jeder Session.
- **cavecrew** liefert Subagenten (`cavecrew-investigator`, `cavecrew-builder`, `cavecrew-reviewer`), deren Abschlussberichte im Caveman-Stil komprimiert sind. Berichte von Subagenten landen als Tool-Ergebnis im Hauptgespräch. Ein kürzerer Bericht hält den Hauptkontext also für den Rest der Session kleiner.
- **Seit v4** installiert der `@caveman-ai/cli`-Installer eine lokale Schicht mit weiteren „Rocks“: Komprimierung von Logs, JSON und Testausgaben, bevor das Modell sie liest („Read less“), einen *Auto*-Modell-Router, wiederverwendbare Skripte („Blocks“) und einen komprimierten Web-Reader. Das überschneidet sich mit Headroom, das ich in [Teil 3](/de/blog/token-cost-3-headroom-stack/) behandle.

### Installation

Wer nur das Plugin mit Stimme, `caveman-compress` und cavecrew möchte, installiert es als Claude-Code-Plugin:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman@caveman
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman@caveman
```

{{< /os-tab >}}
{{< /os-tabs >}}

In einer laufenden Claude-Code-Session funktioniert dasselbe als Slash-Befehle: `/plugin marketplace add JuliusBrussee/caveman`, danach `/plugin install caveman@caveman`. Das Plugin startet automatisch in jeder interaktiven Session, Subagenten eingeschlossen.

Der vollständige v4-Installer braucht Node.js 22.13 oder neuer und richtet jeden gefundenen Agenten ein (Claude Code, Codex, Gemini CLI, OpenCode und weitere):

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
npx @caveman-ai/cli@latest
caveman status      # was ist aktiv, welche Agenten werden erreicht
caveman doctor      # ein Problem pro Zeile, mit Lösung
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
npx @caveman-ai/cli@latest
caveman status      # was ist aktiv, welche Agenten werden erreicht
caveman doctor      # ein Problem pro Zeile, mit Lösung
```

{{< /os-tab >}}
{{< /os-tabs >}}

Falls Node.js noch fehlt: das LTS-Release von [nodejs.org](https://nodejs.org/) installieren oder über den Paketmanager (`winget install OpenJS.NodeJS.LTS` unter Windows, `brew install node` unter macOS).

### Konfiguration und Alltag

| Befehl | Wirkung |
| --- | --- |
| `/caveman`, `/caveman lite\|full\|ultra` | Stimme bzw. Intensität umschalten |
| `stop caveman` oder `/caveman off` | Zurück zu normalen Antworten |
| `/caveman-compress CLAUDE.md` | Memory-Datei komprimieren, Backup in `CLAUDE.original.md` |
| `/caveman-stats` | Token-Verbrauch der aktuellen Session, gelesen aus dem Claude-Code-Session-Log |
| `caveman off browse` (CLI) | Einzelne v4-Komponente abschalten; `caveman status` listet sie |
| `caveman telemetry off` (CLI) | Nutzungsstatistik der CLI abschalten |

Zwei Datenschutz-Hinweise aus dem README: Der Skill allein sendet nichts, aber `/caveman-compress` schickt die Datei zum Umschreiben an deinen Modell-Anbieter. Die v4-CLI sendet **standardmäßig Nutzungsstatistiken** (Befehle, Token-Zahlen, Betriebssystem, IP; keine Prompts, kein Code); abschalten mit `caveman telemetry off` oder `DO_NOT_TRACK=1`. Der optionale *Auto*-Router schickt deinen letzten Prompt samt angehängtem Kontext an Caveman Cloud, sobald du dich anmeldest und ihn auswählst.

### Die Zahlen

Cavemans eigenes README ist ungewöhnlich offen, und die Seite [HONEST-NUMBERS.md](https://github.com/JuliusBrussee/caveman/blob/main/docs/HONEST-NUMBERS.md) listet, wo Caveman verliert. Das Diagramm trennt die Eval des Projekts von externen A/B-Tests:

{{< diagram src="token-cost-caveman-measurements.svg" caption="Nur Reduktion der Ausgabe-Tokens. Blau: Cavemans eigene Eval (10 Fragen, Opus 5.5, gegen eine schlichte „Answer concisely.“-Anweisung). Orange: externe A/B-Tests aus HONEST-NUMBERS.md. Bei LemonCrow sank die Ausgabe um 44 %, die Gesamtkosten stiegen um 0,06 %." >}}

| Messung | Wer hat gemessen | Aufbau | Ergebnis |
| --- | --- | --- | --- |
| Stimme vs. „Answer concisely.“ | Caveman (Hersteller) | 10 Entwicklerfragen, Opus 5.5, ein Durchlauf, Regeln v3.1.0 | `/caveman` −3 %, `/ultracave` −35 % Ausgabe im Median |
| Overhead der Regeln | Caveman (Hersteller) | — | etwa 1.160 Eingabe-Tokens pro Request |
| `/caveman-compress` | Caveman (Hersteller) | 5 Memory-Datei-Fixtures | 6.198 → 4.138 Tokens (−33,2 %), 22,8–49,1 % pro Datei |
| Read-less-Proxy, ganze Sessions | Caveman (Hersteller) | 54 Claude-Code-Läufe, 6 Dateitypen, Engine von 08/2026 | −33,2 % Eingabe; HTML wurde 9,9 % *schlechter* |
| JetBrains | Unabhängig | 86 echte Coding-Aufgaben, gepaarter A/B-Test | −8,5 % Ausgabe-Tokens, kein messbarer Qualitätsverlust (p = 0,82) |
| LemonCrow ([#727](https://github.com/JuliusBrussee/caveman/issues/727)) | Unabhängig | 20 Prompts × 5 Wiederholungen × 3 Läufe, 300 Läufe pro Arm | Ausgabe −44,1 %, **Gesamtkosten +0,06 %** |
| edubraqd ([#733](https://github.com/JuliusBrussee/caveman/issues/733)) | Unabhängig | 10 Fragen auf pt-BR, Haiku 4.5, zusätzlich zu einer `CLAUDE.md`, die schon knappe Antworten verlangt | Ausgabe −8 %; über 662 Sessions Nettoeffekt auf die Rechnung innerhalb ±0,2 % |

Ein Vorbehalt zur JetBrains-Zeile: Der [Beitrag im JetBrains-AI-Blog](https://blog.jetbrains.com/ai/2026/07/speak-to-ai-agents-like-cavemen-tosave-tokens/) hat während meiner Recherche automatisierte Zugriffe abgelehnt. Die Zahlen stammen daher aus Cavemans eigener Zusammenfassung und aus der Presseberichterstattung über den Beitrag ([InfoWorld](https://www.infoworld.com/article/4193775/talk-like-a-caveman-prompts-save-tokens-but-far-less-than-promised.html), [The New Stack](https://thenewstack.io/caveman-mode-token-savings/)). Dort heißt es außerdem, JetBrains habe etwa 10 % erwartete Kostenersparnis gesehen, oft überlagert von der Streuung einzelner Läufe.

**Die Stimme kürzt Antworten zuverlässig, aber Antworten sind ein kleiner Teil der Agenten-Rechnung.** Moderne Modelle antworten bereits recht knapp, wenn man „be concise“ sagt; gegen diese Basis bringt die Standardstufe `/caveman` nur noch 3 %. Der Hersteller schreibt selbst, dass Agenten-Sessions „mostly code and tool calls, which the voice leaves alone“ sind. Genau deshalb komprimiert v4 inzwischen die Eingabe.

### Kosten und wann es nicht hilft

- **Fester Eingabe-Overhead.** Die Regeln kosten etwa 1.160 Tokens pro Request. Bei kurzen Fragen und Antworten kann das die Ersparnis übersteigen; Issue [#145](https://github.com/JuliusBrussee/caveman/issues/145) dokumentiert einen Nettoverlust.
- **Abrechnung pro Request.** GitHub Copilot rechnet Premium-*Requests* ab, keine Tokens. Eine kürzere Antwort bleibt ein Request; Caveman spart dort nichts ([#506](https://github.com/JuliusBrussee/caveman/issues/506)).
- **Retries und erneutes Einspeisen der Regeln.** Ein Cursor-A/B in [#550](https://github.com/JuliusBrussee/caveman/issues/550) zeigte 4,3 Mio. Tokens mit Caveman gegenüber 1 Mio. ohne. Das war nicht reproduzierbar, zeigt aber, dass erneut eingespeiste Regeln und Retries die Ersparnis bei der Ausgabe überrollen können.
- **Lesbarkeit.** Telegrammstil ist gut für Statusmeldungen und lästig bei Erklärungen, aus denen man lernen will. Beim Einarbeiten in Neues lieber abschalten.
- **`caveman-compress` verändert eine Datei, die auch Menschen lesen.** Die `CLAUDE.md` des Teams wird zum Telegramm. Das `.original.md`-Backup gehört unter Versionskontrolle, oder man komprimiert eine separate Datei nur für den Agenten.

Die Faustregel des Herstellers ist die richtige: Die vom Anbieter abgerechneten Summen für dieselbe Aufgabe mit und ohne Caveman vergleichen und es für Workloads abschalten, bei denen es verliert.

## Ponytail: weniger Code schreiben

[Ponytail](https://github.com/DietrichGebert/ponytail) (MIT, aktuelles Release **v5.3.3** vom 29.10.2026) setzt „den faulen Senior-Entwickler“ in den Agenten: den mit dem langen Pferdeschwanz, der sich deine fünfzig Zeilen ansieht und sie durch eine ersetzt. Technisch ist es ein einziger Prompt, [`skills/ponytail/SKILL.md`](https://github.com/DietrichGebert/ponytail/blob/main/skills/ponytail/SKILL.md), plus Hooks und Befehle drumherum.

### Wie es Tokens spart

Ponytail komprimiert nichts; es ändert, *was* der Agent zu bauen beschließt. Bevor er Code schreibt, steigt er eine Leiter hinauf und bleibt auf der ersten Sprosse stehen, die trägt:

1. Muss das überhaupt existieren?
2. Gibt es das schon in dieser Codebasis?
3. Kann es die Standardbibliothek?
4. Gibt es ein natives Plattform-Feature?
5. Gibt es eine bereits installierte Abhängigkeit?
6. Geht es in einer Zeile?
7. Erst dann: der minimale Code, der funktioniert, plus ein kleiner Test, wenn er Logik enthält.

Ausdrücklich nie gekürzt werden: Validierung an Vertrauensgrenzen, Fehlerbehandlung gegen Datenverlust, Sicherheit und Barrierefreiheit. Das Beispiel aus dem README: Gefragt nach einem Datepicker hat ein Agent ohne Skill einen Kalender von Hand gebaut (335 Zeilen); mit Ponytail 5 hat er die vorhandene `Input`-Komponente mit `type="date"` wiederverwendet (10 Zeilen).

Weniger Code bedeutet weniger Ausgabe-Tokens, weniger Dateien zum Zurücklesen, einen kürzeren Diff im Review und weniger Turns. Die Token-Ersparnis ist ein Nebeneffekt von [YAGNI](https://martinfowler.com/bliki/Yagni.html), und deshalb mag ich es auch jenseits der Rechnung.

### Installation

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail
```

{{< /os-tab >}}
{{< /os-tabs >}}

Die Standardform im README sind die beiden Slash-Befehle `/plugin marketplace add DietrichGebert/ponytail` und `/plugin install ponytail@ponytail` in Claude Code. Für Codex lauten sie `codex plugin marketplace add DietrichGebert/ponytail` und `codex plugin add ponytail@ponytail`; danach unter `/hooks` den beiden Hooks vertrauen. Andere Agenten (Cursor, Copilot, Windsurf, Gemini …) bekommen [`AGENTS.md`](https://github.com/DietrichGebert/ponytail/blob/main/AGENTS.md) oder die Skill-Datei, siehe [INSTALL.md](https://github.com/DietrichGebert/ponytail/blob/main/INSTALL.md).

**Als Plugin installieren, nicht als lose Skill-Datei.** JetBrains hat festgestellt, dass eine nackte `SKILL.md` im Skills-Ordner „zero times in ten sessions“ benutzt wurde; erst der Session-Start-Hook des Plugins aktiviert es zuverlässig. Das README warnt außerdem: nur aus `DietrichGebert/ponytail` auf GitHub oder `@dietrichgebert/ponytail` auf npm installieren, es kursieren Kopien.

### Konfiguration und Alltag

| Befehl | Wirkung |
| --- | --- |
| `/ponytail lite\|full\|ultra\|off` | Intensität; `full` ist Standard |
| `/ponytail-review` | Review des aktuellen Diffs: Bugs, Sicherheit, Last, fehlende Tests, was weg kann |
| `/ponytail-audit` | Dieselbe Prüfung für das ganze Repository, priorisiert |
| `/ponytail-debt` | Sammelt alle `shortcut:`-Kommentare in einer Schuldenliste |
| `/ponytail-gain` | Zeigt die Benchmark-Anzeigetafel |
| `/ponytail band [on\|off]` | Statusleiste über dem Prompt (Kosten, Tokens, Agentenzeit; Claude Code ≥ 2.1.290) |

Eine Konfigurationsdatei ist nicht nötig. Optional setzt `~/.config/ponytail/config.json` oder die Umgebungsvariable `PONYTAIL_DEFAULT_MODE` die Standardstufe.

### Die Zahlen

{{< diagram src="token-cost-ponytail-benchmark.svg" caption="Blau: der Ponytail-5-Benchmark des Autors (Opus 5.5, 39 Aufgaben, je 5 Läufe, Okt. 2026). Orange: JetBrains’ unabhängiger Test der älteren v4.8.4 (Sonnet 5, 80 gepaarte Aufgaben, Juli 2026). Unterschiedliche Versionen, Modelle und Aufgaben, also als Spanne lesen, nicht als Widerspruch." >}}

**Hersteller-Benchmark** ([2026-10-07-agentic.md](https://github.com/DietrichGebert/ponytail/blob/main/benchmarks/results/2026-10-07-agentic.md)): headless Claude-Code-Sessions mit Opus 5.5, 39 Aufgaben (12 Features im echten [full-stack-fastapi-template](https://github.com/fastapi/full-stack-fastapi-template), 18 chirurgische Aufgaben mit versteckten Prüfungen, 9 kleine Apps und Beispiele), 5 Läufe pro Aufgabe und Arm, 585 Sessions. Die Ergebnisse sind geometrische Mittel der Median-Verhältnisse pro Aufgabe mit 95-%-Bootstrap-Intervallen:

| vs. ohne Skill | Ponytail 5 | 95-%-Intervall |
| --- | --- | --- |
| Codezeilen | −53 % | −63 … −41 % |
| Ausgabe-Tokens | −45 % | −54 … −35 % |
| Kosten | −26 % | −36 … −16 % |
| Zeit | −41 % | −49 … −32 % |
| Versteckte Prüfungen bestanden | 87/90 (ohne Skill: 86/90) | — |

Die Methode ist sorgfältig (frischer Temp-Ordner pro Session, `CLAUDE.md` und Auto-Memory aus, blinde Bewertungen mit Selbsttests). Ihre Grenzen nennt der Autor selbst: Bash war in allen Armen deaktiviert, gemessen wird also, was der Agent *schreibt*, nicht wie er debuggt; und es ist der Autor, der sein eigenes Werkzeug misst.

**Unabhängiger Test** (JetBrains-AI-Blog, Juli 2026, Ponytail 4.8.4, Sonnet 5 mit mittlerem Effort, 80 gepaarte Aufgaben aus SkillsBench, zusammengefasst von [Capital & Compute](https://capitalandcompute.net/blog/does-ponytail-cut-claude-code-costs/)): **−15,4 % Codezeilen** und **−10,3 % Kosten** für eine typische Aufgabe (p = 0,004, günstiger bei 46 Aufgaben, teurer bei 34). Die Token-Reduktion bei Verlauf und Eingabe war statistisch nicht signifikant. Qualität: 65 Aufgaben gleich, 9 etwas schlechter, 6 etwas besser, was JetBrains „a null result, not a clean bill of health“ nennt.

Die Lücke zwischen −26 % und −10 % Kosten hat dieselbe Ursache wie bei Caveman: Ponytail senkt Ausgabe und Turns, aber der Großteil der Rechnung ist Eingabe und Cache Reads. Saubere Feature-Arbeit in einem echten Repository profitiert am meisten, gemischte Arbeit mit viel Erkunden weniger.

### Kosten und wann es nicht hilft

- **Die Regeln kosten Eingabe.** Jeder Request trägt den Skill mit. Bei winzigen Aufgaben kann der Overhead die Ersparnis übersteigen; ein GitHub-Issue ([#121](https://github.com/DietrichGebert/ponytail/issues/121)) fand je nach Modell Kostenänderungen von −13 % bis +55 % für eine einzelne Aufgabe.
- **„Weniger Code“ ist eine Ermessensfrage.** Manchmal *ist* die 120-Zeilen-Klasse genau das Richtige. Man diskutiert gelegentlich mit ihm. Für Scaffolding, bei dem man Breite will, `/ponytail lite` oder `off` nutzen.
- **Debugging ist nicht gemessen.** Der Hersteller-Benchmark hat die Shell deaktiviert; für lange Debugging-Sessions gibt es keine Zahlen.
- **Es garantiert nichts.** Die versteckten Prüfungen zeigen, dass Code damit nicht *unsicherer* wird; sie zeigen nicht, dass er *sicherer* wird.

## Caveman und Ponytail zusammen

Beide arbeiten auf Prompt-Ebene und zielen auf die Ausgabe, also überschneiden sie sich: Ponytail verlangt bereits kurze Antworten, die mit „was übersprungen wurde und welche Risiken bestehen“ enden. Beide gleichzeitig bedeutet, zwei Regelwerke in jedem Request zu bezahlen. Meine Einschätzung: **zuerst Ponytail**, weil weniger geschriebener Code auch Reviews, Verlauf und künftige Lesevorgänge verkleinert. Die Caveman-Stimme nur dazunehmen, wenn die Antworten danach noch zu lang sind, und messen. `caveman-compress` für Memory-Dateien und cavecrew für Subagenten-Berichte sind davon unabhängig und lassen sich gut kombinieren.

Beide Werkzeuge reduzieren nur, was der Agent *schreibt*. Der größere Teil der Rechnung ist, was er *liest*. Darum geht es in [Teil 2: code-review-graph](/de/blog/token-cost-2-code-review-graph/), das breites Datei-Lesen durch gezielte Graph-Abfragen ersetzt, und in [Teil 3: Headroom](/de/blog/token-cost-3-headroom-stack/), das Tool-Ausgaben komprimiert, bevor das Modell sie sieht.

## Quellen

- Caveman: [README](https://github.com/JuliusBrussee/caveman), [HONEST-NUMBERS.md](https://github.com/JuliusBrussee/caveman/blob/main/docs/HONEST-NUMBERS.md), [Release v4.1.0](https://github.com/JuliusBrussee/caveman/releases/tag/v4.1.0)
- Ponytail: [README](https://github.com/DietrichGebert/ponytail), [Benchmark 2026-10-07](https://github.com/DietrichGebert/ponytail/blob/main/benchmarks/results/2026-10-07-agentic.md)
- JetBrains-AI-Blog: [Caveman-Test](https://blog.jetbrains.com/ai/2026/07/speak-to-ai-agents-like-cavemen-tosave-tokens/), [Ponytail-Test](https://blog.jetbrains.com/ai/2026/07/ponytail-skill-claude-tested/)
- Anthropic: [Prompt Caching](https://docs.claude.com/en/docs/build-with-claude/prompt-caching), [Claude-Code-Plugins](https://code.claude.com/docs/en/plugins)
