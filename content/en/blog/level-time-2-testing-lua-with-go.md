---
draft: false
title: "Building Level Time — Part 2: Testing a Lua WoW Addon from Go with gopher-lua"
seo_title: "Testing a Lua WoW Addon from Go with gopher-lua"
date: 2026-11-18T08:00:00+01:00
tags:
  [
    "go",
    "lua",
    "gopher-lua",
    "testing",
    "wow-addon",
    "world-of-warcraft",
    "github-actions",
    "ci",
    "learning-in-public",
  ]
categories: ["Software Engineering"]
series: ["Building Level Time"]
description: "WoW has no test runner. How I run 286 addon scenarios with go test: a gopher-lua VM, a hand-built WoW API stub and layout checks in four languages."
images: ["img/level-time/logo.png"]
featured_image: "img/level-time/logo.png"
toc: true
---

> **Building Level Time, part 2 of 4.** [Level Time](/page/level-time/) is my World of Warcraft addon for tracking leveling time. This series is the engineering story behind it. Part 1: [Addon architecture](/blog/level-time-1-addon-architecture/). **Part 2 (this post): testing Lua from Go.** Part 3: [The release pipeline](/blog/level-time-3-release-pipeline/). Part 4: [Goals and the public API](/blog/level-time-4-goals-public-api/).

{{< tldr >}}
- Level Time's test harness in `tools/addontest` runs the addon's Lua code with `go test` inside gopher-lua, a pure-Go Lua 5.1 VM, with no game client and no Lua installation.
- Each of the 286 scenario files gets a fresh `lua.NewState()` and its own Go subtest, so `go test -run 'TestScenarios/session'` runs a single scenario.
- The `tools/addontest` harness loads the addon files in `.toc` order and fakes the WoW API with a stub whose unknown frame methods are no-ops.
- Level Time's layout tests check the options and history windows in German, English, French and Spanish, using a crude text width of 6 per byte.
- Always pass `-count=1` to `go test`, because Go's test cache knows nothing about the Lua files gopher-lua loads.
{{< /tldr >}}

A World of Warcraft addon runs inside a game client. There is no `npm test`, no `go test`, no `pytest`, and no way to start the addon's Lua code on its own. The only built-in feedback loop is: edit a file, type `/reload`, click around, read the chat window.

That loop is fine for a 200-line addon. Level Time is not that anymore. It has a timer window, statistics, a history with tables and charts, an options window with search, speedrun comparisons and a sibling addon. At that size, "I clicked around and it looked fine" stops being a test strategy.

So I did what I do for every other piece of software: I wrote a test harness. It lives in `tools/addontest` in the [wow-statistics repository](https://github.com/Noobygames/wow-statistics) and it is a small Go program that runs the addon's Lua code inside a Lua VM, with a hand-written fake of the WoW API. This post shows how it works, what it can check, and, equally important, what it cannot.

---

## Why test an addon outside the game?

Three problems pushed me there.

1. **No runner in the client.** WoW offers `/run`, `/dump` and the error popup, but nothing that executes a suite of assertions and reports pass or fail.
2. **Slow, manual reload cycles.** Every check means a reload, a login state that matches the situation (the right level, XP, combat state) and manual clicking. Reproducing "what happens at the exact moment I level up with a pending timer" by hand is tedious and unreliable.
3. **Regressions in code nobody looks at.** Level Time is localized (German, English, French, Spanish) and runs on several game versions. A change to one module can break a window in a language I did not have open.

The harness catches the large class of bugs that are pure logic (counters, state machines, migrations, event handling, layout arithmetic) in about the time it takes to run `go test`. I still play the game to check everything else.

---

## The architecture at a glance

{{< diagram src="level-time-2-harness.svg" caption="One Lua VM per scenario: the scenario drives a fake WoW API, the real addon code reacts, assertions collect failures that Go reports." >}}

The pieces:

- **`tools/addontest/addon_test.go`**: the Go entry point, about 70 lines.
- **[gopher-lua](https://github.com/yuin/gopher-lua)**: a Lua 5.1 virtual machine written in pure Go. No cgo and no external Lua installation, so `go test` works on any machine with Go.
- **`tests/wow_stub.lua`** plus `tests/stub/*.lua`: the fake WoW API, split by area (UI, chat, units, addons, player, comfort, economy, social).
- **`tests/*_test.lua`**: the scenarios. At the time of writing there are 286 of them.
- **The addon itself**, loaded unchanged from the repository.

---

## The Go side: one VM per scenario

The Go runner globs every `tests/*_test.lua` and turns each file into a Go subtest. This is a simplified version of the real code (error handling shortened, and the real messages are German like the codebase comments):

```go
func TestScenarios(t *testing.T) {
    root, _ := filepath.Abs("../..")
    scenarios, _ := filepath.Glob(filepath.Join(root, "tests", "*_test.lua"))

    for _, scenario := range scenarios {
        name := strings.TrimSuffix(filepath.Base(scenario), "_test.lua")
        t.Run(name, func(t *testing.T) {
            runScenario(t, root, scenario)
        })
    }
}

func runScenario(t *testing.T, root, scenario string) {
    L := lua.NewState() // fresh Lua 5.1 state: no shared globals between scenarios
    defer L.Close()

    L.SetGlobal("ADDON_DIR", lua.LString(filepath.ToSlash(root)))
    L.SetGlobal("SCENARIO", lua.LString(strings.TrimSuffix(filepath.Base(scenario), "_test.lua")))

    // 1. build the fake client and load the addon
    if err := L.DoFile(filepath.Join(root, "tests", "wow_stub.lua")); err != nil {
        t.Fatalf("loading addon: %v", err)
    }
    // 2. run the scenario
    if err := L.DoFile(scenario); err != nil {
        t.Fatalf("scenario aborted: %v", err)
    }
    // 3. collect failures
    failures := L.GetGlobal("TEST_FAILURES").(*lua.LTable)
    failures.ForEach(func(_, failure lua.LValue) { t.Error(failure.String()) })
}
```

Three design decisions are hiding in there:

- **A fresh `lua.NewState()` per scenario.** Real addons keep state in globals (`LevelTimerStatsDB`, frames registered by name). Sharing a VM between tests would let one scenario leak into the next. With a new state per scenario, every test starts from a just-loaded client.
- **`t.Run` per file.** Each scenario is addressable: `go test -run 'TestScenarios/session'` runs just `tests/session_test.lua`. Go's subtests give me filtering and readable failure output for free.
- **Lua assertions do not abort.** The Lua side records failures in a global table instead of raising an error, so one run reports every broken expectation, not just the first.

There is also a safety net. Every event handler and callback in the addon runs through `ns.SafeCall`, a wrapper around `xpcall` that forwards errors to the client's error handler (`geterrorhandler()`). In the real game this means one broken module cannot stop the others. In the harness, the fake error handler collects those errors into `wow.errors`, and Go turns each one into a test failure. A scenario that deliberately provokes an error clears the list afterwards.

---

## Loading the addon in `.toc` order

A WoW addon is not a program with a `main`. It is a folder with a `.toc` file that lists the Lua files; the client executes them in that order and passes each file two values through `...`: the addon name and a private namespace table. See the [TOC format on warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/TOC_format) for the details.

```text
## Interface: 120105, 11509, 20506, 16001
## SavedVariables: LevelTimerDB, LevelTimerStatsDB, LevelTimerDebugLog

Core\Client.lua
Core\Database.lua
Tracking\Stats.lua
UI\TimerWindow.lua
```

(Excerpt; the real file lists many more files, grouped by comments.) The harness does the same thing and uses the `.toc` as the single source of truth instead of keeping a second file list in the test code:

```lua
addon = {}
for line in io.lines(ADDON_DIR .. "/LevelTimer.toc") do
  line = line:gsub("\r", ""):gsub("\\", "/")  -- .toc paths use backslashes
  if line ~= "" and not line:match("^#") then
    local chunk, err = loadfile(ADDON_DIR .. "/" .. line)
    if not chunk then error(err, 0) end
    chunk("LevelTimer", addon)  -- same arguments the client passes: name, namespace
  end
end
```

Two details matter here. First, a file that is missing from the `.toc` is also missing in the test, which catches the classic "works on my machine, never loads in the client" mistake. Second, `chunk("LevelTimer", addon)` mimics the client's `local addonName, ns = ...` convention, and the harness keeps a reference to that namespace so scenarios can reach into modules (`addon.Stats`, `addon.Database`, and so on).

---

## The WoW API stub

The stub is where most of the work lives. It consists of `tests/wow_stub.lua` plus the area files under `tests/stub/`. Its core ideas:

### Frames that accept anything

WoW UI code calls hundreds of frame methods. Faking all of them is not realistic, so the stub's frame objects use a metatable: **known methods behave like the client, unknown methods are no-ops**.

```lua
local frameMethods = {
  SetText   = function(self, text) self._text = tostring(text) end,
  GetText   = function(self) return self._text end,
  SetWidth  = function(self, width) self._width = width end,
  GetWidth  = function(self) return self._width end,
  SetPoint  = function(self, ...) table.insert(self._points, { ... }) end,
  SetScript = function(self, name, handler) self._scripts[name] = handler end,
  RegisterEvent = function(self, event) self._events[event] = true end,
  -- ...
}

return setmetatable(frame, {
  __index = function(_, key)
    local method = frameMethods[key]
    if method == false then return nil end -- false = "method does not exist in this client"
    return method or noop
  end,
})
```

(Simplified. The real table has a few dozen entries.) So `frame:SetBackdropBorderColor(...)` is silently accepted until a test needs to see its effect, and then I add one line. The `false` value is a deliberate escape hatch: setting `frameMethods.RegisterUnitEvent = false` makes the method *missing*, which lets a scenario exercise the fallback for a client that lacks it.

Note what `SetPoint` does: it does not lay anything out. It **records** the anchor in `frame._points`. That is what makes layout tests possible later.

### Events and time under test control

The addon is event-driven, so the stub needs a way to fire events and to move time:

```lua
function wow.fire(event, ...)
  for _, frame in ipairs(frames) do
    if frame._events[event] and frame._scripts.OnEvent then
      frame._scripts.OnEvent(frame, event, ...)
    end
  end
end

function wow.advance(seconds)            -- GetTime() and time() both move
  wow.state.now   = wow.state.now   + seconds
  wow.state.clock = wow.state.clock + seconds
end

C_Timer = { After = function(_, callback) table.insert(wow.timers, callback) end }

function wow.runTimers() -- run everything scheduled so far, delay ignored
  local due = wow.timers
  wow.timers = {}
  for _, callback in ipairs(due) do callback() end
end
```

Controlling time is what makes this testable: nothing sleeps. `C_Timer.After` callbacks are only queued, and `wow.runTimers()` executes them on demand. A scenario about "income appears after the repair bill is paid" runs in microseconds and is fully deterministic. `wow.update(seconds)` does the same for `OnUpdate` handlers, which is how repeating tasks and the timer window tick.

The game state itself is one table, `wow.state` (name, level, XP, money, buffs, combat flag, zone and more), which API functions such as `UnitLevel` and `GetTime` read from. A scenario changes the state and then fires the event the client would have fired.

### Namespaces and client flavors

Modern WoW API lives in namespaces such as `C_Timer`, `C_Spell`, `C_Container` or `C_UnitAuras` ([overview on warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)). The stub defines the ones the addon uses, in the matching area file. The project rule is simple: when the addon starts using a new API function, it gets added to the stub in the same change.

Level Time supports several client flavors (Retail, Classic Era, WoW Forever). The scenario *file name* picks the flavor: `era_*` scenarios load as Classic Era (interface 11509), `forever_*` as WoW Forever (16001), everything else as Retail. That is one line in the stub that reads the `SCENARIO` global set by the Go runner.

---

## A real scenario

Here is a trimmed and simplified scenario in the style of `tests/session_test.lua`: sessions count in parallel to the level and survive a `/reload`.

```lua
local Stats = addon.Stats

-- simulate a login at level 10 with 500 XP and one hour played
wow.login({ level = 10, xp = 500, xpMax = 1000, playedSeconds = 3600 })

-- kill a wolf: the client sends a chat event and the XP bar moves
wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 100 experience.")
wow.state.xp = 600
wow.fire("PLAYER_XP_UPDATE", "player")
wow.advance(1200) -- twenty minutes pass

expect("level counts the kill",   Stats.Get(Stats.LEVEL, Stats.PVE_KILLS), 1)
expect("session counts the kill", Stats.Get(Stats.SESSION, Stats.PVE_KILLS), 1)
expectNear("session time",        Stats.GetSeconds(Stats.SESSION), 1200)
expect("level XP matches UnitXP", Stats.GetXp(Stats.LEVEL), 600)

-- /reload: PLAYER_LOGOUT, then login again
wow.logout()
wow.login({ level = 10 })
expectTrue("session survives the reload", addon.character.currentSession ~= nil)
```

(The real scenario uses German chat strings, because the addon parses localized combat-log text, and it checks more.) Every helper used here (`wow.login`, `wow.fire`, `wow.advance`, `wow.logout`, `expect`) is defined in the stub. After the login, the test looks at **saved state** (`addon.character`, which is what ends up in the SavedVariables) and at **UI state** (frame text, visibility, anchors), the same two things a player would eventually observe.

The assertion helpers are deliberately tiny:

```lua
TEST_FAILURES = {}

function expect(description, actual, expected)
  if actual ~= expected then
    table.insert(TEST_FAILURES,
      string.format("%s: expected %s, got %s", description, tostring(expected), tostring(actual)))
  end
end
```

Plain Lua, no framework. `expectNear` and `expectTrue` follow the same shape. The failure message carries the description, so a red Go subtest reads like a sentence.

---

## Lua 5.1 versus the Lua in WoW

[gopher-lua implements Lua 5.1](https://github.com/yuin/gopher-lua), and so does the WoW client, which is why I picked it. That makes the *language* match: `unpack` as a global (not `table.unpack`), no integer type, no `goto`, no `//` operator. Code that parses on one parses on the other. The [Lua 5.1 reference manual](https://www.lua.org/manual/5.1/) is the common ground.

But "same language version" does not mean "same runtime". The differences that matter in practice:

- **WoW adds globals that stock Lua lacks.** Examples are `strsplit`, `wipe`, `tinsert`, `hooksecurefunc` and `geterrorhandler`. If the addon uses one, the stub must define it. If I forget, the test fails loudly with "attempt to call a nil value", which is a cheap reminder.
- **gopher-lua has its own quirks.** Two are documented in the project's `CLAUDE.md` because they cost me time. First, `tonumber(s:match(...))` raises an error when `match` finds nothing, because `tonumber()` then receives no argument at all; the fix is the extra parentheses in `tonumber((s:match(...)))`. Second, after a `pcall` error, number locals of the test's main chunk that closures captured stopped updating, so counters in tests live in tables.
- **WoW restricts parts of the environment.** The client removes or sandboxes some standard library functions, and newer game APIs can return "secret" values that addons must not compare or branch on in certain situations. A stock Lua VM allows all of it, and the stub only models what I added to it.

The practical rule: if a gopher-lua quirk bites, I fix it in the test or write code that is valid in both runtimes. I never branch the addon's behavior on "am I in a test".

---

## Layout tests in four languages

The layout tests catch more bugs than I expected. Level Time ships in German, English, French and Spanish (`deDE`, `enUS`, `frFR`, `esES`). French and Spanish strings are noticeably longer, and an options window that fits in English can push a checkbox label into its neighbor in French.

{{< diagram src="level-time-2-layout-flow.svg" caption="The layout test switches the language, builds the real window, reads the recorded anchors and measured text widths from the stub and asserts that nothing overlaps or leaves the window." >}}

Because `SetPoint` records anchors and `SetText` stores the string, the stub can answer "where is this widget and how wide is its label" without a renderer. The scenario `tests/layout_fit_test.lua` loops over the languages and, for pairs of toggles that share a row, asserts that the right one starts behind the end of the left one and still fits in the window. A shortened version:

```lua
local function checkOptions(language)
  addon.Set("language", language)
  SlashCmdList.LEVELTIMER("config") -- open the real options window

  for _, pair in ipairs({
    { "SHOW_XP_BAR", "AUTO_INSTANCE_TAB" },
    { "ALERT_TOGGLE_RARE", "ALERT_TOGGLE_ELITE" },
  }) do
    local left, right = findByLabel(L[pair[1]]), findByLabel(L[pair[2]])
    local leftEnd = anchorX(left) + left:GetWidth()
      + addon.Widgets.CHECKBOX_LABEL_GAP + left.label:GetStringWidth()

    expectTrue(language .. ": " .. pair[2] .. " starts behind " .. pair[1],
      anchorX(right) > leftEnd)
    expectTrue(language .. ": " .. pair[2] .. " fits the window",
      anchorX(right) + right:GetWidth() + right.label:GetStringWidth() <= options:GetWidth())
  end

  SlashCmdList.LEVELTIMER("config") -- close it again
end

checkOptions("deDE")
checkOptions("frFR")
checkOptions("esES")
```

The same file covers the history window (sub-tabs must wrap into extra rows instead of leaving the content area, checked in all four languages), button widths against their text, and table toolbars. A second scenario does the same for the Level Time Goals window. A third, `tests/locales_test.lua`, checks that every language has every key and that the `%s` and `%d` placeholders match the English string, which prevents a whole class of runtime format errors.

### How text width is measured, honestly

This is not pixel-accurate layout testing, because the stub does not know any font. Its text measurement is:

```lua
GetStringWidth = function(self) return #self._text * 6 end,
```

Width equals the string length in **bytes** times 6. That is a crude approximation: a real font has proportional glyphs (an "i" is narrower than an "m"), the font and size are configurable in Level Time, and UTF-8 umlauts count as two bytes here although they render as one glyph.

It still catches real bugs because the *relative* behavior is right. French and Spanish strings are longer, so they get wider in the stub too, and a layout that hard-codes a width for the English text fails the test. The addon's own layout code helps: the widths of the options columns are computed from the measured label widths (`fitWidth`) instead of being fixed, so the test verifies that the *rule* holds for every language. It does not prove that the result looks good with the real font.

What it can never tell me is "this text is clipped by two pixels in French with the default font". That still takes a look in the game.

---

## The performance profiler (and how it is tested)

Level Time has an in-game profiler, `/lt debug perf`. It is part of the addon (`Core/Profiler.lua`), not of the Go tooling, and the harness tests it like any other module. I mention it because it shows a nice property of the stub approach: even tooling that depends on client functions can be tested.

What it measures:

- the time of every **event handler**, every `ns.Every` background task, every callback dispatched through `ns.SafeCall` (counters, XP and journal listeners, login, settings apply) and the `OnUpdate` scripts of the windows;
- per entry the **sum and maximum in milliseconds**, the number of calls and the memory growth, using `debugprofilestop()` and `collectgarbage("count")`.

How it works: while the profiler is off, nothing is wrapped, so it costs nothing. When you switch it on, the core swaps the dispatchers for measuring versions, and `/lt debug perf report 10` prints the top entries to chat. The stub makes this testable by defining `debugprofilestop` in terms of the fake clock plus a number the test controls (`wow.profileMs`). The scenario registers a handler that "takes" 5 ms:

```lua
addon.RegisterEvent("PLAYER_REGEN_ENABLED", function()
  wow.profileMs = wow.profileMs + 5 -- pretend this handler is slow
end)

SlashCmdList.LEVELTIMER("debug perf on")
wow.fire("PLAYER_REGEN_ENABLED")
wow.fire("PLAYER_REGEN_ENABLED")

-- ...look up the entry for this handler in addon.Profiler.Results()...
expect("two calls", found.count, 2)
expectNear("sum", found.ms, 10)
expectNear("maximum", found.max, 5)

SlashCmdList.LEVELTIMER("debug perf off")
expect("dispatcher restored", addon.SafeCall, plainSafeCall)
```

Note what this test proves: the accounting is right (sums, maxima, call counts) and switching off restores the original functions. It does **not** measure how fast the addon is. The Go harness runs on a developer machine or a CI runner, not inside the game client, so timings from it would mean nothing. Real numbers come from playing with the profiler switched on, which is also how I find hot spots.

---

## Running the tests in CI

The workflow is `.github/workflows/test.yml`, and it is short:

```yaml
name: Test

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version: "1.27"
          cache-dependency-path: tools/*/go.sum
      - run: make vet
      - run: make test
```

It runs on every pull request and every push to `main`. `make vet` runs `go vet` on all Go tools, and `make test` runs the addon scenarios plus the tests of the other tools (installer, artwork, speedrun records, flights). Since gopher-lua is pure Go, there is nothing to install besides Go itself. In [Part 3](/blog/level-time-3-release-pipeline/) the release workflow runs the tests before anything gets packaged.

---

## Run it yourself

You need a supported Go release (1.26 or newer). Installation instructions are on [go.dev/doc/install](https://go.dev/doc/install). Then clone the repository and run the tests.

{{< os-tabs >}}
{{< os-tab "Linux" >}}

```bash
git clone https://github.com/Noobygames/wow-statistics.git
cd wow-statistics

# all addon scenarios (-count=1 disables Go's test cache, see below)
go -C tools/addontest test -count=1 ./...

# only one scenario
go -C tools/addontest test -count=1 -run 'TestScenarios/session' ./...

# everything CI runs (needs make)
make vet && make test
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
git clone https://github.com/Noobygames/wow-statistics.git
Set-Location wow-statistics

# all addon scenarios
go -C tools/addontest test -count=1 ./...

# only one scenario
go -C tools/addontest test -count=1 -run 'TestScenarios/session' ./...
```

{{< /os-tab >}}
{{< /os-tabs >}}

`make` is usually not installed on Windows. The `go -C` commands above are what the Makefile target `test-addon` calls. The `-C` flag (change directory before running) needs Go 1.20 or later.

**Always pass `-count=1`.** Go's test cache knows nothing about the Lua files that gopher-lua loads. Without `-count=1` you can edit an addon file, rerun, and get a stale cached result. It is a documented rule in the repository for exactly that reason.

Adding a feature then means adding or extending a scenario in `tests/`. A new API function means adding it to the matching `tests/stub/*.lua` file.

---

## Honest limits: what the stub cannot catch

A green suite means the logic does what the scenarios say. It does not mean the addon works in the game. Concretely, the harness cannot tell me:

- **That an API exists in a given client.** The stub defines `C_Spell.GetSpellName` because I told it to. If the real client of some flavor does not have it, has a different signature, or returns a "secret" value, the test stays green and the player gets a Lua error. I mitigate this by checking the Blizzard UI source per flavor and by writing nil-safe code, but the stub itself cannot know. The [WoW API pages on warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API) are my reference for what exists where.
- **Real rendering.** Textures, fonts, scaling, strata (which frame is on top), animations and sounds are not simulated. Animations only keep a "playing" flag.
- **Timing and ordering of real events.** The stub fires events when a test says so. The real client may fire them in another order, at another time, or in bursts. Event races are my biggest blind spot.
- **Protected frames and combat lockdown, beyond what is explicitly modeled.** The stub throws on `SetAttribute` while its combat-lockdown flag is set, but it does not emulate Blizzard's full secure-frame rules.
- **Performance.** See above: it proves the accounting, not the speed.
- **My own wrong assumptions.** If I misunderstand what an event delivers, I will write the same misunderstanding into both the addon and the stub, and the test will agree with the bug.

Wrong assumptions are the main cost of any hand-written fake. The countermeasure is a manual checklist in the repository (`ManualToCheck.md`) of things that still need to be tried in the game, plus the discipline to treat "tested in the stub" and "verified in the game" as two different statuses.

---

## Key takeaways

- A pure-Go Lua VM turns an addon into something `go test` can run, with no game and no Lua installation.
- A fresh VM per scenario plus Go subtests gives isolation and a one-command filter.
- A stub with no-op defaults keeps the cost of faking an API low: only fake what a test needs to observe.
- Control time (`wow.advance`, `wow.runTimers`) and events (`wow.fire`) explicitly; nothing should sleep.
- Record layout inputs (anchors, text, sizes) and test the *rules* in every language, rather than chasing pixels.
- Know your blind spots and keep a manual in-game checklist.

---

## What's next

In [Part 3](/blog/level-time-3-release-pipeline/) I show how a tag turns into a release on GitHub, CurseForge, Wago and WoWInterface with the [BigWigs packager](https://github.com/BigWigsMods/packager), and how the tests gate it. If you play Classic and want to see what all this code is for, the [Level Time page](/page/level-time/) has screenshots and the download link. The tooling mindset also connects to my posts on [Go in Docker](/blog/go-docker/) and [checking static linking](/blog/check-static-linking/).
