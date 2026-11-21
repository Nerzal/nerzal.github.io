---
draft: false
title: "Token Cost Minimization in Agentic AI — Part 1: Where the Tokens Go, Caveman and Ponytail"
seo_title: "Cut Claude Code Token Costs: Caveman and Ponytail Tested"
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
description: "Where a coding agent's token bill really comes from, and what the Claude Code plugins Caveman and Ponytail save: install, configuration, vendor benchmarks vs. independent tests."
images: ["img/token-cost-agentic-ai.png"]
featured_image: "img/token-cost-agentic-ai.png"
toc: true
---

> **Series: Token Cost Minimization in Agentic AI.** Part 1: where the tokens go, Caveman and Ponytail (you are here) · [Part 2: code-review-graph and hooks](/blog/token-cost-2-code-review-graph/) · [Part 3: Headroom, auto-updates and the combined setup](/blog/token-cost-3-headroom-stack/)

{{< tldr >}}
- Most tokens in a coding-agent session are input and cache reads; one Caveman user measured output at 0.3 % of all tokens across 662 Claude Code sessions.
- Caveman v4.1.0 shortens the agent's replies, yet in LemonCrow's independent A/B test output dropped 44.1 % while total cost rose 0.06 %.
- Caveman's rules add about 1,160 input tokens per request, and `/caveman-compress` shrank five memory-file fixtures from 6,198 to 4,138 tokens (−33.2 %).
- Ponytail v5.3.3 makes the agent write less code: the author's benchmark shows −53 % lines and −26 % cost, while JetBrains measured −10.3 % cost on v4.8.4.
- Install Ponytail as a Claude Code plugin, because JetBrains found a bare `SKILL.md` in a skills folder was used zero times in ten sessions.
{{< /tldr >}}

Coding agents like [Claude Code](https://code.claude.com/docs/en/overview), Codex or Cursor are billed per token, or they burn through a plan's usage limit per token. A long agent session easily reads millions of tokens. A whole ecosystem of tools now promises to cut that bill by "50 to 90 percent".

This series looks at four of the most popular ones, one by one:

| Tool | What it shrinks | Where it runs |
| --- | --- | --- |
| [Caveman](https://github.com/JuliusBrussee/caveman) | The agent's replies, memory files, subagent reports | Skill/plugin in the agent (plus an optional proxy since v4) |
| [Ponytail](https://github.com/DietrichGebert/ponytail) | The amount of code the agent writes | Skill/plugin in the agent |
| [code-review-graph](https://github.com/tirth8205/code-review-graph) | How much source code the agent reads | Local MCP server plus hooks |
| [Headroom](https://github.com/headroomlabs-ai/headroom) | Tool output, logs and JSON before they reach the model | Local proxy between agent and API |

For every tool I cover the mechanism, installation, configuration, the published numbers and the costs nobody puts on the landing page. I keep **vendor-measured** numbers and **independently measured** numbers strictly apart. All versions and numbers were checked on 2026-11-13.

## Where the tokens of an agent session go

Before we compare tools, we need a model of the bill. One agent turn is one API request. That request contains:

1. **The system prompt, tool definitions and rules files.** Claude Code's own system prompt, every MCP tool schema, `CLAUDE.md`, active skills. This is sent on *every* request.
2. **The conversation history.** Every earlier message, every tool result, every reply. With [prompt caching](https://docs.claude.com/en/docs/build-with-claude/prompt-caching) most of it is billed as a cheap *cache read*, but it is still billed on every turn.
3. **Fresh tool results.** The file the agent just read, the `grep` hits, 400 lines of test output.
4. **The output.** The reply text, the code, the tool calls. Output tokens are the most expensive kind: Headroom's README puts Opus-class output at five times the input price.

{{< diagram src="token-cost-where-tools-act.svg" caption="Every turn re-sends the whole context. The four tools attack different parts of it: memory files, fresh tool output, the number of file reads, and the output." >}}

Two consequences follow, and they explain almost every benchmark in this series:

- **Output is expensive per token but small in volume.** In agent sessions, the bulk of tokens is input and cache reads. One Caveman user measured output at **0.3 % of all tokens** across 662 Claude Code sessions (reported in Caveman's [HONEST-NUMBERS.md](https://github.com/JuliusBrussee/caveman/blob/main/docs/HONEST-NUMBERS.md)). A tool that only shortens replies can cut output by a lot and still barely move the bill.
- **Everything you add to the prompt costs on every turn.** A 1,000-token skill that saves 300 output tokens per reply only pays off if the replies are long enough. A shorter reply, on the other hand, also saves input later, because it is re-read as history on every following turn.

Keep this model in mind. Counting removed tokens says little; for every tool I ask "**does the provider bill for the same task go down?**"

## Caveman: say less, read less

[Caveman](https://github.com/JuliusBrussee/caveman) (Apache-2.0, current release **v4.1.0** from 2026-11-08) started in April 2026 as a joke skill that made Claude talk like a caveman. The README example puts it best: "The reason your React component is re-rendering is likely because…" (63 tokens) becomes "New object ref each render, so React re-renders. Wrap the prop in `useMemo`." (20 tokens).

### How it saves tokens

Today Caveman is a family of mechanisms. The ones relevant for Claude Code users:

- **The caveman voice** (`/caveman`, `/ultracave`, `/megacave`). A skill whose rules are modeled on [ASD-STE100](https://www.asd-ste100.org/), the controlled English of aircraft maintenance manuals: answer first, one idea per sentence, no greeting, no recap. Code, commands, paths and error messages stay byte-for-byte. Negations (*not*, *never*, *only*) and numbers are never dropped. Security warnings and irreversible actions get full sentences. Your own prompts are never rewritten.
- **`/caveman-compress <file>`** rewrites a memory file like `CLAUDE.md` into caveman style and keeps the original as `CLAUDE.original.md`. Since memory files are sent on every request (point 1 above), this saves input on every turn of every session.
- **cavecrew** ships subagents (`cavecrew-investigator`, `cavecrew-builder`, `cavecrew-reviewer`) whose final reports are caveman-compressed. Subagent reports land in the main conversation as tool results, so a shorter report keeps the main context smaller for the rest of the session.
- **Since v4** the `@caveman-ai/cli` installer adds a local layer with more "rocks": compression of logs, JSON and test output before the model reads them ("Read less"), an *Auto* model router, reusable scripts ("Blocks") and a compressed web reader. These overlap with Headroom, which I cover in [Part 3](/blog/token-cost-3-headroom-stack/).

### Installation

If you only want the plugin with the voice, `caveman-compress` and cavecrew, install it as a Claude Code plugin:

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

Inside a running Claude Code session the same works as slash commands: `/plugin marketplace add JuliusBrussee/caveman`, then `/plugin install caveman@caveman`. The plugin auto-starts in every interactive session, subagents included.

The full v4 installer needs Node.js 22.13 or newer and configures every agent it finds (Claude Code, Codex, Gemini CLI, OpenCode and more):

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
npx @caveman-ai/cli@latest
caveman status      # what is on, which agents it reaches
caveman doctor      # one problem per line, with the fix
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
npx @caveman-ai/cli@latest
caveman status      # what is on, which agents it reaches
caveman doctor      # one problem per line, with the fix
```

{{< /os-tab >}}
{{< /os-tabs >}}

If you don't have Node.js yet, install the LTS release from [nodejs.org](https://nodejs.org/) or with your package manager (`winget install OpenJS.NodeJS.LTS` on Windows, `brew install node` on macOS).

### Configuration and daily use

| Command | Effect |
| --- | --- |
| `/caveman`, `/caveman lite\|full\|ultra` | Switch the voice or its intensity |
| `stop caveman` or `/caveman off` | Back to normal replies |
| `/caveman-compress CLAUDE.md` | Compress a memory file, backup in `CLAUDE.original.md` |
| `/caveman-stats` | Token usage of the current session, read from the Claude Code session log |
| `caveman off browse` (CLI) | Disable a single v4 component; `caveman status` lists them |
| `caveman telemetry off` (CLI) | Disable the CLI's usage statistics |

Two privacy notes from the README: the skill alone sends nothing anywhere, but `/caveman-compress` sends the file to your model provider to rewrite it. The v4 CLI sends **usage statistics by default** (commands, token counts, OS, IP; no prompts or code); turn them off with `caveman telemetry off` or `DO_NOT_TRACK=1`. The optional *Auto* router sends your latest prompt and attached context to Caveman Cloud once you sign in and pick it.

### The numbers

Caveman's own README is unusually candid, and its [HONEST-NUMBERS.md](https://github.com/JuliusBrussee/caveman/blob/main/docs/HONEST-NUMBERS.md) page lists where Caveman loses. The chart separates the project's own eval from outside A/B tests:

{{< diagram src="token-cost-caveman-measurements.svg" caption="Output-token reduction only. Blue: Caveman's own eval (10 questions, Opus 5.5, against a plain “Answer concisely.” instruction). Amber: outside A/B tests listed in HONEST-NUMBERS.md. LemonCrow saw output drop 44 % while the total cost rose 0.06 %." >}}

| Measurement | Who measured | Setup | Result |
| --- | --- | --- | --- |
| Voice vs. "Answer concisely." | Caveman (vendor) | 10 dev questions, Opus 5.5, single run, v3.1.0 rules | `/caveman` −3 %, `/ultracave` −35 % output at the median |
| Rules overhead | Caveman (vendor) | — | about 1,160 input tokens per request |
| `/caveman-compress` | Caveman (vendor) | 5 memory-file fixtures | 6,198 → 4,138 tokens (−33.2 %), 22.8–49.1 % per file |
| Read-less proxy, whole sessions | Caveman (vendor) | 54 Claude Code runs, 6 file types, Aug 2026 engine | −33.2 % input; HTML got 9.9 % *worse* |
| JetBrains | Independent | 86 real coding tasks, paired A/B | −8.5 % output tokens, no measurable quality loss (p = 0.82) |
| LemonCrow ([#727](https://github.com/JuliusBrussee/caveman/issues/727)) | Independent | 20 prompts × 5 reps × 3 runs, 300 runs per arm | output −44.1 %, **total cost +0.06 %** |
| edubraqd ([#733](https://github.com/JuliusBrussee/caveman/issues/733)) | Independent | 10 questions in pt-BR, Haiku 4.5, on top of a "be terse" `CLAUDE.md` | output −8 %; across 662 sessions net bill effect within ±0.2 % |

A caveat on the JetBrains row: the [JetBrains AI blog post](https://blog.jetbrains.com/ai/2026/07/speak-to-ai-agents-like-cavemen-tosave-tokens/) refused automated access when I researched this article, so the figures come from Caveman's own summary and from press coverage of the post ([InfoWorld](https://www.infoworld.com/article/4193775/talk-like-a-caveman-prompts-save-tokens-but-far-less-than-promised.html), [The New Stack](https://thenewstack.io/caveman-mode-token-savings/)). The coverage also reports that JetBrains saw roughly 10 % expected cost savings, often swamped by single-run variance.

**The voice reliably shortens replies, but replies are a small part of an agent bill.** Modern models already answer fairly briefly when told "be concise"; against that baseline the default `/caveman` level adds only 3 %. The vendor itself writes that agent sessions are "mostly code and tool calls, which the voice leaves alone", and that is why v4 moved on to compressing input.

### Costs and when it does not help

- **Fixed input overhead.** The rules cost about 1,160 tokens on every request. For short Q&A, that can exceed the savings; issue [#145](https://github.com/JuliusBrussee/caveman/issues/145) documents a net loss.
- **Per-request billing.** GitHub Copilot bills premium *requests*, not tokens. A shorter answer is still one request; Caveman saves nothing there ([#506](https://github.com/JuliusBrussee/caveman/issues/506)).
- **Retries and re-injection.** One Cursor A/B in [#550](https://github.com/JuliusBrussee/caveman/issues/550) showed 4.3 M tokens with Caveman vs. 1 M without. It was not reproducible, but it shows that rule re-injection and retries can swamp output savings.
- **Readability.** Terse is fine for a status update and annoying for an explanation you want to learn from. Switch it off when you are learning something new.
- **`caveman-compress` changes a file humans also read.** Your team's `CLAUDE.md` turns into telegram style. Keep the `.original.md` backup under version control, or compress a separate, agent-only file.

The vendor's own rule of thumb is the right one: compare the provider-billed totals for the same task with and without Caveman, and turn it off for workloads where it loses.

## Ponytail: write less code

[Ponytail](https://github.com/DietrichGebert/ponytail) (MIT, current release **v5.3.3** from 2026-10-29) puts "the lazy senior developer" into the agent: the one with the long ponytail who looks at your fifty lines and replaces them with one. It is a single prompt, [`skills/ponytail/SKILL.md`](https://github.com/DietrichGebert/ponytail/blob/main/skills/ponytail/SKILL.md), plus hooks and commands around it.

### How it saves tokens

Ponytail compresses nothing; it changes *what* the agent decides to build. Before writing code, the agent climbs a ladder and stops at the first rung that holds:

1. Does this need to exist at all?
2. Is it already in this codebase?
3. Does the standard library do it?
4. Is there a native platform feature?
5. Is there an installed dependency?
6. Can it be one line?
7. Only then: the minimum code that works, plus one small test if it has logic.

Explicitly excluded from cutting: validation at trust boundaries, error handling that prevents data loss, security and accessibility. The README's example: asked for a date picker, an agent without the skill wrote a calendar by hand (335 lines); with Ponytail 5 it reused the repo's `Input` component with `type="date"` (10 lines).

Less code means fewer output tokens, fewer files to read back, a shorter diff to review and fewer turns. The token savings are a side effect of [YAGNI](https://martinfowler.com/bliki/Yagni.html), which is also why I like it beyond the bill.

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

The README's canonical form is the two slash commands `/plugin marketplace add DietrichGebert/ponytail` and `/plugin install ponytail@ponytail` inside Claude Code. For Codex it is `codex plugin marketplace add DietrichGebert/ponytail` and `codex plugin add ponytail@ponytail`, then trust the two hooks under `/hooks`. Other agents (Cursor, Copilot, Windsurf, Gemini …) get [`AGENTS.md`](https://github.com/DietrichGebert/ponytail/blob/main/AGENTS.md) or the skill file, see [INSTALL.md](https://github.com/DietrichGebert/ponytail/blob/main/INSTALL.md).

**Install it as a plugin, not as a loose skill file.** JetBrains found that a bare `SKILL.md` copied into a skills folder was used "zero times in ten sessions"; the plugin's session-start hook is what activates it reliably. The README also warns: only install from `DietrichGebert/ponytail` on GitHub or `@dietrichgebert/ponytail` on npm, as copies circulate.

### Configuration and daily use

| Command | Effect |
| --- | --- |
| `/ponytail lite\|full\|ultra\|off` | Intensity; `full` is the default |
| `/ponytail-review` | Review the current diff: bugs, security, load, missing tests, what to cut |
| `/ponytail-audit` | The same check for the whole repository, ranked |
| `/ponytail-debt` | Collects every `shortcut:` comment into a debt ledger |
| `/ponytail-gain` | Shows the benchmark scoreboard |
| `/ponytail band [on\|off]` | Status band above the prompt (cost, tokens, agent time; Claude Code ≥ 2.1.290) |

No config file is needed. An optional `~/.config/ponytail/config.json` or the `PONYTAIL_DEFAULT_MODE` environment variable sets the default level.

### The numbers

{{< diagram src="token-cost-ponytail-benchmark.svg" caption="Blue: the author's Ponytail 5 benchmark (Opus 5.5, 39 tasks, 5 runs each, Oct 2026). Amber: JetBrains' independent test of the older v4.8.4 (Sonnet 5, 80 paired tasks, Jul 2026). Different versions, models and tasks, so read them as a range, not a contradiction." >}}

**Vendor benchmark** ([2026-10-07-agentic.md](https://github.com/DietrichGebert/ponytail/blob/main/benchmarks/results/2026-10-07-agentic.md)): headless Claude Code sessions with Opus 5.5, 39 tasks (12 features in the real [full-stack-fastapi-template](https://github.com/fastapi/full-stack-fastapi-template), 18 surgical tasks with hidden checks, 9 small apps and examples), 5 runs per task and arm, 585 sessions. Results are geometric means of per-task median ratios with 95 % bootstrap intervals:

| vs. no skill | Ponytail 5 | 95 % interval |
| --- | --- | --- |
| Lines of code | −53 % | −63 … −41 % |
| Output tokens | −45 % | −54 … −35 % |
| Cost | −26 % | −36 … −16 % |
| Time | −41 % | −49 … −32 % |
| Hidden checks passed | 87/90 (no skill: 86/90) | — |

The method is careful (fresh temp folder per session, `CLAUDE.md` and auto memory off, blind judges with self-tests). Its limits, stated by the author: Bash was disabled for every arm, so it measures what the agent *writes*, not how it debugs; and it is the author measuring his own tool.

**Independent test** (JetBrains AI blog, July 2026, Ponytail 4.8.4, Sonnet 5 at medium effort, 80 paired tasks from SkillsBench, as summarized by [Capital & Compute](https://capitalandcompute.net/blog/does-ponytail-cut-claude-code-costs/)): **−15.4 % lines of code** and **−10.3 % cost** for a typical task (p = 0.004, cheaper on 46 tasks, dearer on 34). Token reductions on history and input were not statistically significant. Quality: 65 tasks equal, 9 slightly worse, 6 slightly better, which JetBrains calls "a null result, not a clean bill of health".

The gap between −26 % and −10 % cost has the same root as with Caveman: Ponytail cuts output and turns, but most of the bill is input and cache reads. Clean feature work on a real repo benefits most; mixed, exploration-heavy work less.

### Costs and when it does not help

- **The rules cost input.** Every request carries the skill. On tiny tasks the overhead can exceed the savings; a GitHub issue ([#121](https://github.com/DietrichGebert/ponytail/issues/121)) found single-task cost changes from −13 % to +55 % depending on the model.
- **"Less code" is a judgment call.** Sometimes the 120-line class *is* what you need. You will occasionally argue with it. Use `/ponytail lite` or `off` for scaffolding work where you want breadth.
- **Debugging is not measured.** The vendor benchmark disabled the shell, so there are no numbers for long debugging sessions.
- **It guarantees nothing.** The hidden-check results show it does not make code *less* safe; they do not show it makes code *more* safe.

## Caveman and Ponytail together

Both are prompt-level and target the output side, so they overlap: Ponytail already demands short replies that end with "what was skipped and the risks". Running both means paying for two rule sets on every request. My take: **Ponytail first**, because writing less code also shrinks reviews, history and future reads. Add the caveman voice only if your replies are still long, and measure. `caveman-compress` for memory files and cavecrew for subagent reports are independent of that decision and combine fine.

Both tools only reduce what the agent *writes*. The bigger part of the bill is what it *reads*. That is the topic of [Part 2: code-review-graph](/blog/token-cost-2-code-review-graph/), which replaces broad file reading with targeted graph queries, and [Part 3: Headroom](/blog/token-cost-3-headroom-stack/), which compresses tool output before the model sees it.

## Sources

- Caveman: [README](https://github.com/JuliusBrussee/caveman), [HONEST-NUMBERS.md](https://github.com/JuliusBrussee/caveman/blob/main/docs/HONEST-NUMBERS.md), [release v4.1.0](https://github.com/JuliusBrussee/caveman/releases/tag/v4.1.0)
- Ponytail: [README](https://github.com/DietrichGebert/ponytail), [benchmark 2026-10-07](https://github.com/DietrichGebert/ponytail/blob/main/benchmarks/results/2026-10-07-agentic.md)
- JetBrains AI blog: [Caveman test](https://blog.jetbrains.com/ai/2026/07/speak-to-ai-agents-like-cavemen-tosave-tokens/), [Ponytail test](https://blog.jetbrains.com/ai/2026/07/ponytail-skill-claude-tested/)
- Anthropic: [prompt caching](https://docs.claude.com/en/docs/build-with-claude/prompt-caching), [Claude Code plugins](https://code.claude.com/docs/en/plugins)
