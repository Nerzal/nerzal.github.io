---
draft: false
title: "Token Cost Minimization in Agentic AI — Part 2: code-review-graph, MCP and Hooks"
seo_title: "code-review-graph: Fewer Tokens via MCP and Git Hooks"
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
description: "code-review-graph gives coding agents a Tree-sitter code graph over MCP instead of reading whole files. Install, Claude Code and git hooks, auto-updates, real benchmark numbers and limits."
images: ["img/token-cost-agentic-ai.png"]
featured_image: "img/token-cost-agentic-ai.png"
toc: true
---

> **Series: Token Cost Minimization in Agentic AI.** [Part 1: where the tokens go, Caveman and Ponytail](/blog/token-cost-1-caveman-ponytail/) · Part 2: code-review-graph and hooks (you are here) · [Part 3: Headroom, auto-updates and the combined setup](/blog/token-cost-3-headroom-stack/)

{{< tldr >}}
- code-review-graph v2.4.0 parses a repository with Tree-sitter into a local SQLite graph and answers agent questions over MCP, typically in 2,000 to 4,000 tokens.
- Install code-review-graph with `uv tool install code-review-graph`, then run `code-review-graph install` and `code-review-graph build` in the repository root.
- A Claude Code `PostToolUse` hook and four git hooks (`pre-commit`, `post-checkout`, `post-merge`, `post-rewrite`) keep the graph fresh, and all of them end with `|| true`.
- code-review-graph's headline 63× reduction compares against reading every file; against grep plus the top three files, the vendor's median reduction is 6.65×.
- After `uv tool upgrade code-review-graph`, run `code-review-graph install` again and check with `doctor`, because older 2.3.x copies can break the 2.4.0 schema.
{{< /tldr >}}

In [Part 1](/blog/token-cost-1-caveman-ponytail/) we saw that the biggest share of an agent's token bill is **input**: everything the agent reads, re-sent on every turn as history. The most common input in a coding session is source code. To answer "what breaks if I rename this function?", an agent typically greps for the name, opens the three or four best-matching files in full and maybe follows a few imports. Every one of those files then stays in the context for the rest of the session.

[code-review-graph](https://github.com/tirth8205/code-review-graph) (MIT, current release **v2.4.0** from 2026-11-11) replaces much of that reading with a query against a local code graph.

## How it saves tokens

The tool parses your repository with [Tree-sitter](https://tree-sitter.github.io/tree-sitter/), the incremental parser behind syntax highlighting in many editors, and stores the result as a graph in one local SQLite file (`.code-review-graph/graph.db`):

- **Nodes:** files, functions, classes, imports, tests.
- **Edges:** calls, imports, inheritance, "test covers function".

The graph is exposed to the agent through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/), the open standard for connecting tools to LLM clients. The agent then asks targeted questions instead of reading files:

| Question | MCP tool |
| --- | --- |
| Who calls `parseConfig`? | `query_graph_tool` with `callers_of` |
| What breaks if this file changes? | `get_impact_radius_tool` |
| What does my current diff touch, and how risky is it? | `detect_changes_tool`, `get_review_context_tool` |
| Where is the code for "authentication"? | `semantic_search_nodes_tool` |
| How is the project structured? | `get_architecture_overview_tool`, `list_communities_tool` |

A typical answer is 2,000 to 4,000 tokens: names, locations, edges and, on request, the relevant source snippets. The agent reads only what the graph names. Language coverage is broad: Python, JavaScript/TypeScript, Go, Rust, Java, C/C++, C#, Ruby, Kotlin, Swift, PHP, shell, PowerShell, Terraform, notebooks and many more, plus framework-aware edges for Spring and Laravel.

Everything stays on your machine; embeddings for semantic search are optional and can run locally.

## Installation

You need Python 3.10 or newer. The README recommends [uv](https://docs.astral.sh/uv/), which installs the CLI into its own isolated environment. If you don't have uv yet:

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

Then install code-review-graph, set up the AI tools it finds, and build the graph from the repository root:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
uv tool install code-review-graph
cd ~/src/my-project
code-review-graph install --dry-run   # preview every change as a diff
code-review-graph install             # MCP entry, hooks, skills, instructions
code-review-graph build               # first full parse
code-review-graph detect-changes --brief
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
uv tool install code-review-graph
Set-Location $HOME\src\my-project
code-review-graph install --dry-run   # preview every change as a diff
code-review-graph install             # MCP entry, hooks, skills, instructions
code-review-graph build               # first full parse
code-review-graph detect-changes --brief
```

{{< /os-tab >}}
{{< /os-tabs >}}

Restart Claude Code (or your editor) afterwards. `install` detects Claude Code, Codex, Cursor, Windsurf, Zed, Continue, OpenCode, Gemini CLI, Copilot, Kiro and more; `--platform claude-code` limits it to one. `code-review-graph doctor` checks the setup without changing anything, and `code-review-graph uninstall --dry-run` shows how to get rid of it again.

According to the README, a cold build of a ~3,000-file repository takes about 40 seconds.

### What `install` writes

For Claude Code, in the repository:

- `.mcp.json`: the MCP server entry.
- `.claude/settings.json`: two Claude Code hooks (see below).
- Skills and a block of graph instructions in `CLAUDE.md` (skip with `--no-instructions`).
- Git hooks in `.git/hooks/`.
- `.code-review-graph/` with the database, added to `.gitignore` automatically.

The generic MCP entry looks like this when the tool was installed with `uv tool`:

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

`.mcp.json` and `.claude/` stay visible to git on purpose, so a team can commit them. If you don't want that, `install --gitignore` adds exactly the files that run created to a marked block in `.gitignore`. For machine-wide ignores, a [global .gitignore](/blog/global-gitignore/) is the cleaner place.

On Windows, the README adds one warning: don't wrap the MCP command in `cmd /c` in the Claude Code config; point it at the executable directly.

## Where to integrate it: hooks that keep the graph fresh

A code graph is only useful if it matches the code. A stale graph is worse than none: the agent trusts a caller list that no longer exists. That makes the update strategy the most important part of the setup. There are four places to hook in, from the inner loop to CI.

### 1. Claude Code hooks: update after every edit

[Claude Code hooks](https://code.claude.com/docs/en/hooks) are shell commands that Claude Code runs on lifecycle events. They are configured in `settings.json` (user-wide in `~/.claude/settings.json`, per project in `.claude/settings.json`, personal per project in `.claude/settings.local.json`). `code-review-graph install` writes two of them:

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

What each piece does, and why:

- **`PostToolUse` with matcher `Edit|Write`** runs after the agent changed a file. `hook-update` re-parses only files whose SHA-256 hash changed. The README measures about 2.5 seconds for a two-file edit on a ~3,000-file repository, 1.4 seconds of which is process start-up. So the next graph query within the same session already sees the new code.
- **`SessionStart`** prints the graph status (node count, last update, commit) into the session. Hook output on `SessionStart` is added to the context, so the agent knows from the first turn that a graph exists and how fresh it is. That costs a few dozen tokens per session.
- **`cat >/dev/null`** reads and discards the JSON event that Claude Code writes to the hook's standard input, so the hook consumes its input cleanly even though it does not need it.
- **`command -v … || exit 0` and `|| true`** make the hook a no-op on a machine where the tool is not installed, for example a teammate who cloned the repository. A failing hook should never block the agent.
- **`timeout`** caps the hook. If an update takes longer, Claude Code moves on.

On Windows, Claude Code runs hook commands through Git Bash, so the POSIX syntax above works unchanged.

**Optional: steering.** `code-review-graph install --steering` adds a third hook for Claude Code that puts graph context (callers, callees, tests) beside every `Grep`, `Glob` and `Read`. It nudges the model towards the graph, but it costs about 0.12 seconds and up to about 220 tokens per call (README, measured on Flask). In a session with 200 reads, that is up to 44,000 extra tokens. I leave it off and rely on the instructions in `CLAUDE.md`; enable it if you see the agent ignore the graph.

### 2. Git hooks: update on commit, checkout, merge and rebase

The agent is not the only one changing code. You switch branches, pull and rebase. `install` therefore writes four git hooks, each wrapped in a marked block so it coexists with your own hook code:

| Git hook | When | What it runs |
| --- | --- | --- |
| `pre-commit` | before each commit | `update`, then `detect-changes --brief` (short risk review in the terminal) |
| `post-checkout` | after a branch switch (not file checkouts) | `update --quiet` |
| `post-merge` | after `git merge` / `git pull` | `update --quiet` |
| `post-rewrite` | after `git rebase` | `update --quiet` |

The essential part of the generated `post-merge` hook, simplified:

```bash
#!/bin/sh
# >>> code-review-graph sync hook >>>
if command -v code-review-graph >/dev/null 2>&1; then
    root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    code-review-graph update --quiet --repo "$root" || true
fi
# <<< code-review-graph sync hook <<<
```

All hooks end with `|| true`, so **the graph never blocks a commit**. They also skip linked [git worktrees](https://git-scm.com/docs/git-worktree) unless you set `CRG_HOOK_WORKTREES=1`, because each worktree would need its own graph. If you run several agents in parallel worktrees, set that variable, or the agents in the worktrees query a graph of the main checkout.

If your team uses a hook manager such as [pre-commit](https://pre-commit.com/), [Husky](https://typicode.github.io/husky/) or [Lefthook](https://lefthook.dev/), it may own `.git/hooks/`. Add the same `code-review-graph update --quiet` call as a local hook there instead.

### 3. Watch mode and the daemon: for editors without hooks

Editors like Windsurf or Zed don't get agent hooks. For them, and for repositories you edit outside of any agent, there is a watcher:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
code-review-graph watch                       # one repo, foreground
crg-daemon add ~/src/project-a --alias proj-a  # or: several repos in the background
crg-daemon add ~/src/project-b
crg-daemon start
crg-daemon status
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
code-review-graph watch                             # one repo, foreground
crg-daemon add $HOME\src\project-a --alias proj-a   # or: several repos in the background
crg-daemon add $HOME\src\project-b
crg-daemon start
crg-daemon status
```

{{< /os-tab >}}
{{< /os-tabs >}}

The daemon stores its list in `~/.code-review-graph/watch.toml` and restarts dead watchers every 30 seconds. Don't combine it with the hooks on the same repository without need; both work, but you pay for every update twice.

### 4. CI: a risk comment on every pull request

The same analysis runs as a GitHub Action. It builds the graph on the runner and posts one sticky comment with risk-scored functions, affected flows and test gaps:

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

The optional `fail-on-risk` input turns it into a merge gate. If you want a hard gate, put it here rather than in the local `pre-commit` hook.

### Convenience: make targets

If your project has a Makefile, wrap `code-review-graph build`, `update` and `detect-changes --brief` in three targets such as `code-graph-build`, `code-graph-update` and `code-graph-changes`. Humans find them next to the other build commands, and agents that read the Makefile discover them without extra instructions.

## The numbers

The project publishes a reproducible benchmark ([REPRODUCING.md](https://github.com/tirth8205/code-review-graph/blob/staging/docs/REPRODUCING.md)): six open-source repositories at pinned commits, five sample questions each, fixed seeds, local embeddings.

{{< diagram src="token-cost-crg-reduction.svg" caption="Vendor-measured. The first six bars compare a graph answer with reading the whole repository, an upper bound no real agent pays. The last bar is the realistic baseline: grep and read the top three files. Median 6.65×." >}}

| Repository | Whole corpus | Graph answer (avg) | Reduction |
| --- | --- | --- | --- |
| fastapi | 948,793 | 2,653 | 357.6× |
| flask | 143,594 | 2,196 | 65.4× |
| code-review-graph | 208,821 | 3,190 | 65.5× |
| gin | 166,868 | 2,766 | 60.3× |
| httpx | 142,356 | 2,661 | 53.5× |
| express | 136,052 | 3,936 | 34.6× |

*Captured 2026-08-02 with crg 2.3.7. Source: [README](https://github.com/tirth8205/code-review-graph).*

The headline "63× median" compares against reading **every file**. The README itself says that baseline is "an upper bound no real agent pays". The more honest figure is the `agent_baseline` benchmark, captured 2026-09-22: a simple grep, the top three files by match count, token-counted against the graph query. Against that, the median reduction across 18 questions on 6 repositories is **6.65×** (mean 14.8×, range 4.2× to 72.6×). The ratio grows with repository size, because the graph answer stays flat at 2,400 to 4,000 tokens while grep results grow with the code base.

Impact analysis has a precision side too: average F1 0.69 against graph-derived ground truth, precision 0.55. It is conservative by design and flags files that *might* be affected.

I found no independent benchmark of code-review-graph. The third-party articles I found ([DEV Community](https://dev.to/emperorakashi20/how-code-review-graph-cuts-claude-code-token-usage-by-49x-and-whether-its-actually-worth-it-4kn1), for example) repeat or discuss the project's own numbers.

### My own measurement: this blog

To see what happens on a repository that is mostly not code, I looked at the graph of this blog's Hugo repository (code-review-graph 2.4.0, `status` and `detect-changes --brief`, 2026-11-13):

- **Indexed:** 63 files, 275 nodes, 587 edges. Languages: bash, HTML templates, JavaScript, JSON, YAML. The Markdown posts, which are most of the repository, are not part of the graph.
- **`detect-changes --brief`** on a working tree with 131 changed files printed "Full context would be: 452,279 tokens · Graph context used: 2,306 tokens · Saved ~99 %".

That 99 % is the tool's *estimate*, and its baseline is "read every changed file in full", which included deleted, generated image caches no agent would ever open. On this repository the graph is genuinely useful for questions about layouts, shortcodes and JavaScript. For writing posts, a plain `grep` is all the agent needs, and the MCP tools are just extra schema in the context.

## Costs and when it does not help

- **Retrieval only.** All numbers measure the tokens needed to *locate* an answer. If the agent then opens the files the graph named, it pays the graph answer *on top* of those reads. `semantic_search_nodes_tool(include_source=True)` returns code with the locations to avoid that; an end-to-end measurement is, per the README, open work.
- **Small edits.** For a one-file change, graph context can be bigger than simply reading the file. The formal `token_efficiency` benchmark reports ratios below 1 for small commits.
- **Tool schemas cost input.** The MCP server exposes around 30 tools. Their definitions are context, too, unless your client loads tool schemas on demand.
- **Stale graphs mislead.** Without hooks or a watcher, the agent gets confident wrong answers. Set up the hooks above, or don't use it.
- **Version drift.** The MCP entry, the git hooks and the daemon can each run a different copy. After `uv tool upgrade code-review-graph`, run `code-review-graph install` again and check with `doctor`. Since 2.4.0 the graph uses schema 15, and older 2.3.x copies refuse or can break it.
- **Small or non-code repositories** gain little, as my measurement shows.

## Updating

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
uv tool upgrade code-review-graph
code-review-graph doctor              # every copy, MCP entry and hook, and their versions
code-review-graph install --dry-run   # see what changes
code-review-graph install
code-review-graph build               # once, so fixes reach all files
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
uv tool upgrade code-review-graph
code-review-graph doctor              # every copy, MCP entry and hook, and their versions
code-review-graph install --dry-run   # see what changes
code-review-graph install
code-review-graph build               # once, so fixes reach all files
```

{{< /os-tab >}}
{{< /os-tabs >}}

You can schedule this exactly like the Headroom update job in [Part 3](/blog/token-cost-3-headroom-stack/#keeping-headroom-up-to-date-automatically). I would not: because of the multi-copy issue, an upgrade should be followed by `install` and an editor restart, and that is a step I prefer to do consciously.

In the [last part](/blog/token-cost-3-headroom-stack/) we add Headroom, a proxy that compresses everything the agent reads that is *not* source code (logs, JSON, test output), make it update itself with desktop notifications, and put all four tools together into one setup.

## Sources

- [code-review-graph README](https://github.com/tirth8205/code-review-graph), [USAGE.md](https://github.com/tirth8205/code-review-graph/blob/staging/docs/USAGE.md), [REPRODUCING.md](https://github.com/tirth8205/code-review-graph/blob/staging/docs/REPRODUCING.md)
- [Tree-sitter](https://tree-sitter.github.io/tree-sitter/), [Model Context Protocol](https://modelcontextprotocol.io/)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks), [Claude Code settings](https://code.claude.com/docs/en/settings)
- [githooks documentation](https://git-scm.com/docs/githooks)
