---
draft: false
title: "Building Level Time — Part 3: Release Pipeline with a Go Installer, BigWigs Packager and CurseForge"
seo_title: "WoW Addon Release Pipeline: BigWigs Packager + CurseForge"
date: 2026-11-25T08:00:00+01:00
tags:
  [
    "wow-addon",
    "lua",
    "go",
    "github-actions",
    "bigwigs-packager",
    "curseforge",
    "release-automation",
    "ci-cd",
  ]
categories: ["Software Engineering"]
series: ["Building Level Time"]
description: "Push a tag, get a release: shipping a WoW addon to CurseForge with GitHub Actions and the BigWigs packager, plus a small Go installer for local builds."
images: ["img/level-time/logo.png"]
featured_image: "img/level-time/logo.png"
toc: true
---

> **Series: Building Level Time** — Part 3 of 4. [Part 1: Addon architecture](/blog/level-time-1-addon-architecture/) · [Part 2: Testing Lua with Go](/blog/level-time-2-testing-lua-with-go/) · **Part 3: Release pipeline** · [Part 4: Goals and the public API](/blog/level-time-4-goals-public-api/) · Product page: [Level Time](/page/level-time/)

Writing an addon is one thing. Getting it to players without clicking through several upload forms is another. For [Level Time](/page/level-time/), a World of Warcraft addon that tracks time, XP and kills per level, I wanted one rule: **I push a git tag and everything else happens by itself.**

In this post I walk through the whole path from `git tag` to a file on CurseForge: the GitHub Actions workflow, the [BigWigs packager](https://github.com/BigWigsMods/packager), the `.pkgmeta` file, the `.toc` files that serve several game clients, a trick for shipping a second addon from the same repository, and the small Go installer I use to test builds in my own WoW folders.

Everything here is taken from the repository's `release.yml`, `.pkgmeta`, `Makefile` and `tools/installer`. Comments in the repo are in German; I translated the relevant ones.

---

## The goal: a tag is a release

The workflow triggers on tags matching `v*`. Nothing else publishes. Regular pushes to `main` and pull requests run a separate `Test` workflow (`make vet` and `make test`), so a broken test is usually found long before I tag.

{{< diagram src="level-time-3-pipeline.svg" caption="From tag to release. The test job gates the release job; the packager runs twice because Level Time and Level Time Goals are separate CurseForge projects." >}}

The release workflow, trimmed to its skeleton:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version: "1.27"
      - run: make test

  release:
    needs: test          # no green tests, no release
    runs-on: ubuntu-latest
    permissions:
      contents: write    # needed to create the GitHub release
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # the packager needs history for version and changelog
      - uses: BigWigsMods/packager@v2
```

Three details matter here.

**`needs: test`.** The release job only starts when the test job passes. The tests are the Lua scenarios I describe in [Part 2: Testing Lua with Go](/blog/level-time-2-testing-lua-with-go/), plus the tests of the installer and the other Go tools. A tag on a red commit therefore produces no release. See the GitHub docs on [`needs`](https://docs.github.com/en/actions/using-jobs/using-jobs-in-a-workflow#defining-prerequisite-jobs).

**`fetch-depth: 0`.** `actions/checkout` fetches a single commit by default. The packager derives the version from the git history and builds the changelog from commit messages, so it needs the full history and the tags.

**`contents: write`.** Creating a release needs write permission on repository contents. I grant it to the release job only, not to the test job. See [Automatic token authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token).

---

## The BigWigs packager

The packager is a bash script maintained by the BigWigs team and widely used in the addon ecosystem. It does a handful of jobs that are tedious by hand:

1. Copy the addon files into a clean folder, skipping everything in the `ignore` list.
2. Replace keywords such as `@project-version@` in the files.
3. Generate a changelog from the git history.
4. Zip the result.
5. Upload to the platforms the project has configured, and create a GitHub release.

The action `BigWigsMods/packager@v2` wraps the script. Which platforms it uploads to is decided by two things per platform: an ID in the `.toc` file and an API token in the environment. The workflow header documents the contract:

| Platform | `.toc` line | Secret |
| --- | --- | --- |
| CurseForge | `## X-Curse-Project-ID` | `CF_API_KEY` |
| Wago | `## X-Wago-ID` | `WAGO_API_TOKEN` |
| WoWInterface | `## X-WoWI-ID` | `WOWI_API_TOKEN` |

If an ID or token is missing, that platform is skipped. If everything is missing you still get the GitHub release, which is a nice property: the pipeline degrades gracefully instead of failing. Currently my `.toc` files carry a CurseForge project ID only (1721235 for Level Time, 1744370 for Level Time Goals). The tokens are repository secrets passed in as environment variables; their values never appear in the repo.

### Naming the upload

By default the packager names the file after the tag, such as `v2.26.0`. I prefer the same name everywhere, so the workflow passes `-n`:

```yaml
- uses: BigWigsMods/packager@v2
  with:
    args: -n "{package-name}-{project-version}:{package-name}-{project-version}.zip"
```

The format is `{file name}:{label}`. Both parts expand to `LevelTimer-v2.26.0`, so the zip and the CurseForge display name match the files from the days when I uploaded by hand. The placeholders are described in the [packager README](https://github.com/BigWigsMods/packager#usage).

---

## `.pkgmeta`: what goes in the zip

The packager ships the repository minus what `.pkgmeta` ignores. That is a deny-list, and it has a consequence I want to be upfront about: **every new non-addon file in the repo must be added to `ignore`**, or it ends up in the zip. This is the full file, with the comments translated:

```yaml
# Config for the BigWigs packager (.github/workflows/release.yml).
package-as: LevelTimer

# Load-on-demand archive: its own addon folder next to LevelTimer/
move-folders:
  LevelTimer/LevelTimer_Archive: LevelTimer_Archive

ignore:
  - tests
  - StreamGoal
  - tools
  - curseforge
  - Makefile
  - README.md
  - ROADMAP.md
  - ManualToCheck.md
  - image.png
```

Walking through it:

- **`package-as`** sets the folder name inside the zip. The repository is called `wow-statistics`, but WoW expects the addon folder to match the `.toc` file name, so the folder must be `LevelTimer`.
- **`move-folders`** is the interesting part. Level Time has a second, load-on-demand addon, `LevelTimer_Archive`, a journal archive that is only loaded when needed. WoW only sees addons that sit directly in `Interface/AddOns/`. Since the archive lives in a subfolder of the repository, the packager first puts it at `LevelTimer/LevelTimer_Archive/` and `move-folders` lifts it to the top level of the zip. The archive's own `.toc` carries `## LoadOnDemand: 1` and `## Dependencies: LevelTimer`.
- **`ignore`** excludes tests, Go tools, CurseForge texts and project docs. Also `StreamGoal`, which is a separate addon with its own package (next section).

For the full list of directives see the [`.pkgmeta` documentation](https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File).

---

## One `.toc`, several game clients

World of Warcraft exists in several flavors: Retail, Classic Era and others. They share the addon format but not the full API. The `.toc` header of Level Time lists several interface versions in one line:

```text
## Interface: 120105, 11509, 20506, 16001
## Title: Level Time
## Version: @project-version@
## Author: Nerzal
## X-Curse-Project-ID: 1721235
## SavedVariables: LevelTimerDB, LevelTimerStatsDB, LevelTimerDebugLog
```

The comma-separated `## Interface` list lets one `.toc` serve several clients, as described on the [TOC format page of the WoW wiki](https://warcraft.wiki.gg/wiki/TOC_format). The project notes in the repo state the rule that follows from it: an API call must either exist on all listed clients or be guarded, because there is no per-flavor build. In Lua that is a plain `if GetPVPSessionStats then ...` check. The structure behind this is part of [Part 1](/blog/level-time-1-addon-architecture/).

The `## Version: @project-version@` line is the placeholder the packager replaces with the tag. The Go installer replaces the same token, so a locally installed build reports a version too.

---

## Two addons, one repository

Level Time Goals is a second addon, lives in the `StreamGoal/` folder, depends on Level Time (`## Dependencies: LevelTimer`) and has its own CurseForge project (ID 1744370). I cover how it works in [Part 4](/blog/level-time-4-goals-public-api/). For the pipeline it poses a problem: the packager expects the addon to sit at the **root of a git repository**, and its `-t` flag even requires a `.git` there.

My solution is a second packager run against a throwaway clone whose root *is* `StreamGoal/`:

```yaml
- name: Split StreamGoal history
  run: |
    git clone -q . sg-repo
    cd sg-repo
    git filter-branch -f --subdirectory-filter StreamGoal --tag-name-filter cat -- --all
    git checkout -q "$GITHUB_REF_NAME"

- uses: BigWigsMods/packager@v2
  env:
    GITHUB_OAUTH: ""   # otherwise a second GitHub release is created for the same tag
  with:
    args: -t sg-repo -n "{package-name}-{project-version}:{package-name}-{project-version}.zip"
```

[`git filter-branch --subdirectory-filter`](https://git-scm.com/docs/git-filter-branch) rewrites the clone so the contents of `StreamGoal/` become the repository root, and only commits that touched that folder remain. `--tag-name-filter cat` rewrites tags along with the history. A nice side effect is that the changelog for Level Time Goals then contains only commits that actually changed that addon.

Two points of honesty:

- `git filter-branch` is flagged by Git itself as discouraged. [`git filter-repo`](https://github.com/newren/git-filter-repo) is the recommended successor, but it is an extra dependency and the clone is disposable, so I have kept the built-in command so far.
- Blanking `GITHUB_OAUTH` for the second run is deliberate. The first run already created the GitHub release for the tag; without that line the second run would try to create another one.

The version token works in both runs because both `.toc` files contain `@project-version@`.

---

## Changelog and versioning

I use plain semantic-style tags: `v2.25.0`, `v2.25.1`, `v2.26.0`. Patch for fixes, minor for features. For a tag build the packager's project version is the tag name.

The changelog is generated by the packager from the git history. There is no hand-written `CHANGELOG.md` in the repository, so the quality of the release notes is the quality of my commit messages. That is a trade-off: it costs no maintenance, but it rewards disciplined commits. The listing text on CurseForge (description and logo) lives separately in the `curseforge/` folder and is edited by hand, because it describes the addon rather than a single release.

Local builds use the same idea: the `Makefile` computes `VERSION` with `git describe --tags --always --dirty`, so a local zip is named something like `LevelTimer-v2.26.0-3-gabc1234-dirty.zip` and cannot be confused with a real release.

---

## The Go installer

The release pipeline covers the public path. For my own testing I need the opposite: a fast way to put the working copy into my WoW folders, for every game version I have installed. Copying by hand gets old after the third time, and an old file left behind in the addon folder can silently load stale code. So `tools/installer` is a small Go program, using only the standard library, tested with `go test` like everything else in the repository.

{{< diagram src="level-time-3-installer.svg" caption="The installer plans before it writes. The plan is a diff against what is already installed, and nothing under WTF is ever touched." >}}

What it does, in order:

1. **Reads the file list from the `.toc`.** There is one place that says which files belong to the addon (the `.toc`), plus everything under `Media/`. No second list to keep in sync. `LoadAddons` also discovers every sub-folder that contains `<folder>/<folder>.toc`, so Level Time Goals and the archive are picked up automatically.
2. **Finds the WoW folder.** Priority: the `-wow` flag, then the `WOW_DIR` environment variable, then auto-detection. Auto-detection scans typical locations on Windows (drive letters `C:` to `Z:`, folders such as `World of Warcraft`, `Games\World of Warcraft`, `Program Files (x86)\World of Warcraft`) and macOS (`/Applications/World of Warcraft`). **On Linux there is no auto-detection**, so you pass `-wow` or set `WOW_DIR`.
3. **Finds the flavors.** Every sub-folder named like `_retail_` or `_classic_era_` counts. You may even point `-wow` at a flavor folder and it steps up one level.
4. **Builds a plan** per addon and flavor by comparing bytes: new file (`+`), changed (`~`), unchanged, or stale (`-`), meaning it was installed earlier but is no longer in the `.toc`.
5. **Shows the plan and asks.** `-dry-run` stops here, `-yes` skips the question and by default updates the flavors that are already installed.
6. **Applies it.** Each file is written to a temporary file and renamed, so the game never reads a half-written file. Then it writes `.install-manifest.json` into the addon folder with the version, the file list and applied migrations.

The manifest is what makes stale-file cleanup safe. The installer only deletes files it knows it installed earlier. For old manual installs without a manifest it removes only code files (`.lua`, `.toc`, `.xml`) that are no longer referenced by the current `.toc`.

### The one rule it must never break

SavedVariables are where players' data lives: history, settings, everything. They sit under the `WTF` folder. The installer therefore refuses any path that contains a `WTF` component, checked once for the target and again for every file it writes (`ensureNotConfigPath`, `safeJoin`). It also rejects relative paths that would escape the addon folder. A tool that overwrites your save data on a typo would be worse than no tool.

After an install the output tells you whether `/reload` in game is enough, or whether the client must restart because the `.toc` changed. WoW only reads `.toc` files at startup.

### Using it

The `Makefile` wraps the common cases.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# Interactive wizard: choose flavors, review the plan, confirm
make install

# Update every already-installed flavor without questions
make update

# Show what would change, write nothing
make dry-run

# Explicit WoW path (required on Linux)
make install ARGS="-flavors retail -wow '$HOME/Games/World of Warcraft'"
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

You can use `make` if you have it, but the Go tool itself only needs Go:

```powershell
# Interactive wizard from the repository root
go -C tools/installer run . -src "$PWD" -version dev

# Dry run for one flavor with an explicit path
go -C tools/installer run . -src "$PWD" -version dev -dry-run -yes `
  -flavors retail -wow "D:\Games\World of Warcraft"
```

{{< /os-tab >}}
{{< /os-tabs >}}

To install Go see [go.dev/doc/install](https://go.dev/doc/install). The `-C` flag of the `go` command needs Go 1.20 or newer, and CI uses Go 1.27.

The same program builds the manual download. `make package` runs it in `-package` mode and writes `dist/LevelTimer-<version>.zip` (with the archive addon inside) and `dist/StreamGoal-<version>.zip`. That is a handy local rehearsal of what the packager will produce, but the official release zip comes from the packager, not from this path.

If you are interested in how I handle Go tooling elsewhere, [Dockerizing Go applications](/blog/go-docker/) covers a different corner of that toolbox.

---

## Other Go tools in the repository

The `tools/` folder holds more programs. A line each, because they are not part of the release path itself:

- **`tools/addontest`** is the test harness from [Part 2](/blog/level-time-2-testing-lua-with-go/).
- **`tools/artwork`** draws the CurseForge logo and the in-game icon and textures (`make artwork`), so the visuals are reproducible code rather than binary files nobody can edit.
- **`tools/records`** fetches speedrun records from speedrun.com and regenerates `Speedrun/SpeedrunRecords.lua` (`make records`, needs internet).
- **`tools/flights`** reads the flight times that the addon measured itself from the SavedVariables of every flavor (read-only) and generates `Assist/FlightTimesData.lua` (`make flights`). The project notes say to run it before a release to ship the newest measurements.

---

## How to cut a release

The checklist I follow. Replace the version with your next one.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# 1. Be on a clean, up-to-date main
git switch main && git pull --ff-only

# 2. Run what CI will run
make vet && make test

# 3. Tag and push the tag; this triggers the Release workflow
git tag v2.27.0
git push origin v2.27.0

# 4. Watch the run
gh run watch
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
git switch main; git pull --ff-only

# Same checks as CI
make vet; if ($?) { make test }

git tag v2.27.0
git push origin v2.27.0

gh run watch
```

{{< /os-tab >}}
{{< /os-tabs >}}

The [GitHub CLI](https://cli.github.com/) (`gh`) is optional; the Actions tab shows the same run. If the tests are green, the release job packages, creates the GitHub release and uploads to CurseForge. CurseForge may review a new file for a short while before it appears publicly; that part is out of my hands.

If a release goes wrong, there is no rollback button in the pipeline. I fix forward with a new patch tag (`v2.27.1`) instead of moving an existing tag, because moved tags confuse packager, GitHub and CurseForge alike.

---

## Lessons learned

- **Make the default path the right path.** One tag, one command. The fewer manual steps, the fewer forgotten ones.
- **Gate releases on tests.** `needs: test` costs one line.
- **Allow-list or deny-list is a real decision.** The packager is deny-list based. It is convenient until you forget to ignore a new file. My local `make package` is allow-list based (only what the `.toc` names) and works as a cross-check.
- **Build tools that cannot hurt users, even yourself.** The WTF guard in the installer exists because I know I will mistype a path one day.

---

## What's next

In the last part, [Part 4: Goals and the public API](/blog/level-time-4-goals-public-api/), I show how Level Time Goals plugs into Level Time through an exported API and why the two addons are separate. If you want to try the result, the [Level Time page](/page/level-time/) links to CurseForge and GitHub.
