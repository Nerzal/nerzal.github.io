---
draft: false
title: "Building Level Time — Part 4: A Sister Addon Over a Public API — Level Time Goals and the Prize Wheel"
seo_title: "WoW Addon Public API in Lua: Level Time Goals Case Study"
date: 2026-12-02T08:00:00+01:00
tags:
  [
    "lua",
    "wow-addon",
    "api-design",
    "animation",
    "testing",
    "gopher-lua",
    "software-architecture",
    "level-time",
  ]
categories: ["Software Engineering"]
series: ["Building Level Time"]
description: "How a second WoW addon builds on Level Time's global API: why it is separate, API design lessons learned the hard way, and the prize wheel animation in Lua."
images: ["img/level-time/goals-logo.png"]
featured_image: "img/level-time/goal-bingo.png"
toc: true
---

> **Building Level Time** — Part 4 of 4. [Part 1: addon architecture](/blog/level-time-1-addon-architecture/) · [Part 2: testing Lua with Go](/blog/level-time-2-testing-lua-with-go/) · [Part 3: the release pipeline](/blog/level-time-3-release-pipeline/) · Part 4 (this post). Product page: [Level Time](/page/level-time/).

In the first three parts I described how Level Time is built, how I test its Lua from Go and how it gets released. This part is about what happens when a second addon wants to stand on the shoulders of the first one: **Level Time Goals**, a sister addon for streamers that lives in the same repository (`StreamGoal/`) and ships as its own CurseForge project.

It is also a story about an API that I did not design as an API at first. I will be honest about that, because the interesting lessons are in the gap between what a comment promises and what the code actually guarantees. Level Time and Level Time Goals are early projects, built in public on [GitHub](https://github.com/Noobygames/wow-statistics), and the wheel animation at the end has not yet been fully verified in the game client (more on that below).

## What Level Time Goals does

Level Time Goals lets a streamer set goals and show them as cards on screen, so viewers see what the streamer is working on and how far along they are. When a goal is reached, a big alert appears. According to the [addon description](https://www.curseforge.com/wow/addons/streamer-goals), the goal types include:

- reaching a level, killing enemies, looting or owning items, earning or owning gold
- turning in quests, reaching profession ranks, exploring areas, defeating bosses, reputation, battleground wins
- rules that can fail ("no death until level 30", "no auction house")
- checklists with sub-goals, and free-text goals you tick off by clicking

On top of single goals there are **bingo cards** (3×3 or 5×5, fields tick themselves) and a **wheel of fortune** ("Glücksrad" in the German client) that picks your next goal from a pool, with a limited number of rerolls and an optional spin on every level-up.

![A 3×3 bingo card in Level Time Goals with two completed fields](/img/level-time/goal-bingo.png)

*A 3×3 bingo card from Level Time Goals (German client). Each field is a goal that tracks itself; green fields are done.*

## Why a separate addon

Goals could have been a tab inside Level Time. I decided against it for three reasons.

1. **Optional for users.** Most Level Time users want statistics, timers and tables, not streamer overlays. A separate addon means they never load that code, never see its settings and never pay for it in memory or update cost.
2. **Separate release cadence.** Goals changes fast: new goal kinds, pack content, wheel tweaks. Level Time should not need a release (and a new round of in-game verification) because a bingo field label changed. In [part 3](/blog/level-time-3-release-pipeline/) I described how one tag publishes an addon; Goals has its own CurseForge project (ID `1744370` in its `.toc`) and its own zip.
3. **It keeps the core lean and honest.** If a sister addon can be built on the core without copying anything, that is a decent proof that the core's building blocks are actually reusable. If I had to copy a module into Goals, the module belonged somewhere else.

The coupling is declared in `StreamGoal/StreamGoal.toc`:

```text
## Interface: 120105, 11509, 20506, 16001
## Title: Level Time Goals
## Dependencies: LevelTimer
## SavedVariables: StreamGoalDB
```

`## Dependencies: LevelTimer` is a hard dependency in the sense of the [TOC format](https://warcraft.wiki.gg/wiki/TOC_format): the client loads Level Time first, and Goals is not enabled without it. Goals also has its own saved variables, `StreamGoalDB`, so its data lives independently of Level Time's.

## The public API Level Time exposes

Here is the honest part. When I wrote the sister addon, the "API" was one line in `Core/LevelTimer.lua`:

```lua
-- Interface for sister addons: the namespace with all building blocks
-- (Card, Widgets, TableView, Alerts, Journal, Format, ...), events,
-- login and level-up. (comment translated and shortened)
LevelTimerAPI = ns
```

That is the whole export: **the addon's private namespace table `ns` is published as a global called `LevelTimerAPI`**. Every addon gets `(addonName, ns)` as varargs when its files load, and normally that table is the private meeting point of the addon's own files. By assigning it to a global, I made the whole table reachable from other addons. Because Goals declares the dependency, Level Time's files are fully loaded by the time Goals' first file runs, so the table is complete.

Goals binds it once, at the top of its `Core.lua`:

```lua
local _, ns = ...          -- Goals' own namespace

local LT = LevelTimerAPI   -- Level Time's namespace
ns.LT = LT
ns.L = LT.L                -- localisation shared with Level Time
```

From then on everything in Goals goes through `ns.LT`. A short, simplified tour of the surface it actually uses:

```lua
-- lifecycle
LT.OnLogin(callback)            -- run once the saved data of this character is loaded
LT.OnLevelStarted(callback)     -- callback(newLevel) after a level-up
LT.RegisterEvent(event, handler)
LT.SafeCall(fn, ...)            -- protected call that reports errors, never breaks others

-- building blocks
LT.Card.Create(name)            -- the card widget, same look as Level Time alerts
LT.Alerts.Show(...)             -- the big on-screen notice
LT.TableView.Create(definition) -- sortable, filterable tables (history tab)
LT.Frames.Register({ id, frame, label, default, store, preview })
LT.Theme.RGB("accent")          -- theme tokens, so a theme switch recolours Goals too
```

{{< diagram src="level-time-4-api.svg" caption="One table crosses the boundary. Level Time fills LevelTimerAPI, sister addons read it; the dependency in the .toc guarantees the load order." >}}

### How callbacks stay safe

The most important design decision in that surface is not the global, it is how events are delivered. Level Time runs level-ups in two phases (`OnLevelCompleted` with the old level, then `OnLevelStarted` with the new one) and runs every callback through `ns.RunCallbacks`:

```lua
-- Simplified from Lib/Lifecycle.lua
local function runAll(callbacks, ...)
  for index = 1, #callbacks do
    ns.SafeCall(callbacks[index], ...)
  end
end
```

Each callback is protected with [`xpcall`](https://www.lua.org/manual/5.1/manual.html#pdf-xpcall), so a bug in Goals' level-up handler cannot stop Level Time's own handler from running, and vice versa. That is the single most valuable property of the API for a plugin ecosystem: **a consumer's failure stays the consumer's failure.**

### What the API is not

Reading my own code critically, here is what the "public API" does **not** have:

- **No version number.** There is no `LevelTimerAPI.version` and no compatibility check. Both addons are released from one repository, so I have been relying on "they are always updated together".
- **No stable/internal split.** Everything in `ns` is reachable, including things that were never meant for other addons.
- **No documented contract.** The contract is a comment and the project's `CLAUDE.md`, which says: use these building blocks, do not copy them, and *if something is missing, add it to Level Time*.

That last rule is the one that actually worked. It turned the API surface into something that grows by need, driven by a real consumer, instead of by speculation.

## API design lessons

Even though the surface is informal, building Goals on it taught me what I would formalise first.

**1. Decide what is stable, and say so.** Publishing the whole namespace is the cheapest possible API and the most expensive one to maintain: every renamed helper is a potential breaking change for a consumer. With one consumer under my own control, that is tolerable. With a third-party consumer it would not be. The next step would be a small, explicit table such as `LevelTimerAPI.v1` exposing only the functions I commit to.

**2. Detect features, not versions.** Level Time's own conventions already say to guard any client API that may not exist on every game flavor (`if GetPVPSessionStats then ...`), and events unknown to a client are safe because `ns.RegisterEvent` returns `false` instead of raising an error. The same attitude applies between addons. A defensive consumer would look like this (the pattern I would use for a third-party addon, not what Goals does today):

```lua
local LT = LevelTimerAPI
if not LT or type(LT.OnLevelStarted) ~= "function" then
  print("MyAddon: Level Time is missing or too old, feature disabled.")
  return
end
```

Goals can skip that check because of the hard `## Dependencies` line; an addon that lists Level Time under `## OptionalDeps` has to do it.

**3. Never reach into internals.** The rule is "use the building blocks, do not copy them". The mirror image is "do not reach around them": if Goals needed a value that Level Time kept in a local variable, the right fix is a new function in Level Time, not a hack in Goals. That keeps the dependency arrow pointing one way only.

**4. Isolate failure and state.** Goals has its own namespace, its own SavedVariables (`StreamGoalDB`, which exists only from login on) and its own debug area (`LT.Debug("goal:" .. area, ...)`). When something breaks, the log tells me which addon it came from.

**5. Shared infrastructure beats shared copies.** Localisation is a good example. Goals merges its `SG_*` strings into Level Time's locale tables, so `LT.L` and shared widgets such as the table headers resolve them in whatever language Level Time runs. The consumer needs no second language system; the price is that both addons must agree on the placeholder format, which a test checks in all four languages.

![A Level Time card showing loot roll counters](/img/level-time/lt-rolls-example.png)

*A Level Time card (here showing loot roll counters, from an earlier version). Goals' cards, wheel result and alerts reuse this same card building block through the API instead of drawing their own.*

## The wheel: animation in a constrained UI

The wheel of fortune is the part I had the most fun with. In the game it is a real spinning wheel with 12 coloured slices, a fixed pointer at the top and a hub, drawn from textures that a Go tool in the repository generates (`make artwork`, `tools/artwork -wheel`). Everything below is from `StreamGoal/Wheel.lua` and `StreamGoal/WheelDisplay.lua`.

### The outcome is decided before the animation

The first design decision: **the result is chosen before anything spins.** `Wheel.lua` picks the entry, then hands the animation a target slice:

```lua
-- Simplified from Wheel.lua
local items = Wheel.Pool()                 -- enabled entries, shuffled
local chosen = pick(items)                 -- first entry that passes validation
local titles, target = slicesFor(items, chosen)
WheelDisplay.Spin(titles, target, function()
  finish(items, chosen, rerollsLeft)       -- create the goal after the wheel stops
end)
```

The animation is therefore pure presentation. That has three practical benefits: the result does not depend on frame rate, turning the animation off (`wheelAnimation = false`) still gives the same kind of result instantly, and tests can assert the outcome without simulating pixels.

### Rotation maths

Each slice is its own texture, rotated around its centre with `Texture:SetRotation` (see the [API reference](https://warcraft.wiki.gg/wiki/API_TextureBase_SetRotation)). The wheel angle `r` rotates all slices, slice `i` sits at `r + (i - 1) * step`, and a slice is under the pointer when that angle is a multiple of 2π. Two pure functions do the geometry (simplified):

```lua
local TWO_PI = 2 * math.pi

-- Which slice is under the pointer for this rotation?
function SliceAt(rotation, count)
  local step = TWO_PI / count
  local position = (-rotation / step) % count
  return math.floor(position + 0.5) % count + 1
end

-- Final rotation: at least `turns` full turns beyond `start`,
-- pointer on slice `index`, `offset` = distance from the slice centre
function TargetRotation(start, index, count, turns, offset)
  local step = TWO_PI / count
  local wanted = -(index - 1 + offset) * step
  local minimum = start + turns * TWO_PI
  return wanted + math.ceil((minimum - wanted) / TWO_PI) * TWO_PI
end
```

`turns` is 3 plus a random fraction, and the landing point is nudged by up to ±0.175 of a slice (`LANDING_SPREAD = 0.35`) so the pointer does not always rest dead-centre on a slice. The target slice itself stays fixed; the randomness is cosmetic.

### OnUpdate easing

The animation runs in an [`OnUpdate`](https://warcraft.wiki.gg/wiki/UIHANDLER_OnUpdate) script, which the client calls every frame with the seconds elapsed since the last frame. The easing is a cubic ease-out: fast start, soft stop.

```lua
-- progress 0..1 -> eased 0..1
function Ease(progress)
  local rest = 1 - math.max(0, math.min(1, progress))
  return 1 - rest * rest * rest
end

local function update(_, elapsed)
  local spin = state.spin
  if not spin then return end                  -- idle: do nothing
  spin.elapsed = spin.elapsed + elapsed
  local progress = spin.elapsed / SPIN_SECONDS -- 4 seconds
  applyRotation(spin.from + (spin.to - spin.from) * Ease(progress))
  if progress < 1 then return end
  state.spin = nil                             -- landed
  SafeCall(spin.onStop)
end
```

{{< diagram src="level-time-4-ease.svg" caption="The cubic ease-out curve used for the spin: more than half of the rotation happens in the first quarter of the four seconds, and the wheel settles into its target with zero speed." >}}

Because the rotation is computed from the *elapsed time* and not by adding a fixed step per frame, the spin takes four seconds whether the game runs at 30 or 144 frames per second. A slow frame produces a bigger jump, not a longer animation.

### Frame budget

An `OnUpdate` handler that runs forever is a classic addon performance trap, because it executes every frame for every player. The wheel keeps its cost low in three ways:

- the script only runs while the wheel frame is visible, and when no spin is running the handler returns on its first line
- it is registered through `LT.SetUpdateScript(frame, "StreamGoalWheel", update)`, a Level Time helper that wraps the handler so the built-in profiler can measure it by name
- text does not rotate with the slices (font strings cannot be rotated in every client), so the label under the wheel is only updated when the slice under the pointer changes, via a text-if-changed helper

The tick sound while slices pass the pointer uses the same "slice under pointer changed" check, so it costs nothing between ticks.

### What is still open

I want to be upfront: `ROADMAP.md` marks the wheel as implemented, with the note that it still needs checking in the real game (an item in my manual check list). The tests prove the logic, not the rendering. Whether `SetRotation` on textures looks right in all four supported clients is something only a login can tell me; the repository even has a debug check (`/lt debug check`) that asks the client whether it can rotate those textures. The viewer-voting idea from the roadmap is open for a plain reason: addons cannot read Twitch chat.

## Testing the wheel with the Go harness

Everything above is testable because the maths are pure functions and the animation is driven by `elapsed`. In [part 2](/blog/level-time-2-testing-lua-with-go/) I described the harness: a Go program using [gopher-lua](https://github.com/yuin/gopher-lua) that loads the addon in `.toc` order against a fake WoW API. For the sister addon, the stub does the same for Goals' `.toc` when a scenario name starts with `streamgoal_`: it loads Level Time first, then Goals into its own namespace, exactly like the client would.

The wheel scenario (`tests/streamgoal_wheel_test.lua`, shortened) looks like this:

```lua
-- pure functions
for _, case in ipairs({ { 0, 1 }, { 1.3, 7 }, { 5.9, 12 }, { -2, 4 } }) do
  for _, offset in ipairs({ -0.4, 0, 0.4 }) do
    local target = WheelDisplay.TargetRotation(case[1], case[2], SLICES, 3, offset)
    expectTrue("at least three turns", target >= case[1] + 3 * 2 * math.pi)
    expect("lands on slice " .. case[2], WheelDisplay.SliceAt(target), case[2])
  end
end
expect("ease start", WheelDisplay.Ease(0), 0)
expect("ease end", WheelDisplay.Ease(1), 1)
expectTrue("fast start", WheelDisplay.Ease(0.25) > 0.5)

-- full flow
SlashCmdList.STREAMGOAL("wheel")
expect("spinning", Wheel.IsSpinning(), true)
wow.update(0.5)                              -- advance the fake clock
expectTrue("rotating", WheelDisplay.Rotation() > 0)
finishSpin()                                 -- wow.update(0.1) until it stops
expect("pointer on the result",
  WheelDisplay.SliceTitle(WheelDisplay.SliceUnderPointer()), Goals.Title(first))
```

`wow.update(seconds)` advances the fake clock and calls the `OnUpdate` scripts with that elapsed time, so a four-second spin takes a few dozen synchronous calls and no real waiting. The same scenario covers rerolls counting down, the spin on level-up and the "animation off" path. To run all addon tests:

```bash
# Linux / macOS (needs Go and make)
git clone https://github.com/Noobygames/wow-statistics.git
cd wow-statistics
make test-addon
```

```powershell
# Windows (PowerShell, needs Go; make is optional)
git clone https://github.com/Noobygames/wow-statistics.git
cd wow-statistics
go -C tools/addontest test -count=1 ./...
```

Install Go from [go.dev/doc/install](https://go.dev/doc/install). The PowerShell variant is exactly what the Makefile target runs.

## Lessons from the sister addon

- A second consumer is the best API review you can get. Every time Goals needed something, the question "does this belong in the core?" had a concrete answer.
- Publishing a whole namespace is fast, and fine while you control both sides. Write down the day it stops being fine.
- Decide outcomes first, animate second. It keeps randomness testable and animation optional.
- Time-based animation, an idle early return and a profiler hook make `OnUpdate` code cheap enough to ship.

## What's next

This closes the series for now. If you want to try the addons, start at the [Level Time page](/page/level-time/) or [Level Time Goals on CurseForge](https://www.curseforge.com/wow/addons/streamer-goals), and tell me what breaks via [GitHub issues](https://github.com/Noobygames/wow-statistics/issues). For the same "keep the boundary small" thinking applied to services instead of addons, see my post on [bounded contexts](/blog/bounded-context/).
