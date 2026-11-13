---
draft: false
title: "Level Time bauen — Teil 2: Ein Lua-WoW-Addon mit Go und gopher-lua testen"
seo_title: "WoW-Addon (Lua) mit Go und gopher-lua testen"
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
description: "WoW hat keinen Test-Runner. So laufen 286 Addon-Szenarien mit go test: gopher-lua-VM, selbstgebaute WoW-API-Attrappe und Layout-Tests in vier Sprachen."
images: ["img/level-time/logo.png"]
featured_image: "img/level-time/logo.png"
toc: true
---

> **Level Time bauen — Teil 2 von 4.** [Level Time](/de/page/level-time/) ist mein World-of-Warcraft-Addon, das die Levelzeit misst. Diese Serie erzählt die Technik dahinter. Teil 1: [Addon-Architektur](/de/blog/level-time-1-addon-architecture/). **Teil 2 (dieser Artikel): Lua mit Go testen.** Teil 3: [Die Release-Pipeline](/de/blog/level-time-3-release-pipeline/). Teil 4: [Ziele und die öffentliche API](/de/blog/level-time-4-goals-public-api/).

Ein World-of-Warcraft-Addon läuft im Spielclient. Es gibt kein `npm test`, kein `go test`, kein `pytest` und keine Möglichkeit, den Lua-Code des Addons einfach so zu starten. Die einzige eingebaute Rückkopplung lautet: Datei ändern, `/reload` tippen, herumklicken, den Chat lesen.

Für ein Addon mit 200 Zeilen reicht das. Level Time ist längst größer: Zeitfenster, Statistiken, eine Historie mit Tabellen und Diagrammen, ein Einstellungsfenster mit Suche, Speedrun-Vergleiche und ein Schwester-Addon. Ab dieser Größe ist „ich habe geklickt und es sah gut aus“ keine Teststrategie mehr.

Also habe ich gemacht, was ich bei jeder anderen Software auch mache: einen Test-Harness gebaut. Er liegt unter `tools/addontest` im [wow-statistics-Repository](https://github.com/Noobygames/wow-statistics) und ist ein kleines Go-Programm, das den Lua-Code des Addons in einer Lua-VM ausführt, zusammen mit einer handgeschriebenen Attrappe der WoW-API. Dieser Artikel zeigt, wie das funktioniert, was sich damit prüfen lässt und, mindestens genauso wichtig, was nicht.

---

## Warum ein Addon außerhalb des Spiels testen?

Drei Probleme haben mich dahin gebracht.

1. **Kein Runner im Client.** WoW bietet `/run`, `/dump` und das Fehlerfenster, aber nichts, was eine Reihe von Prüfungen ausführt und „bestanden“ oder „durchgefallen“ meldet.
2. **Langsame, manuelle Reload-Zyklen.** Jede Prüfung braucht einen Reload, einen passenden Login-Zustand (richtiges Level, XP, Kampfstatus) und Klickarbeit. „Was passiert genau im Moment des Level-Ups, wenn noch ein Timer läuft?“ von Hand nachzustellen ist mühsam und unzuverlässig.
3. **Regressionen in Code, den niemand ansieht.** Level Time ist lokalisiert (Deutsch, Englisch, Französisch, Spanisch) und läuft auf mehreren Spielversionen. Eine Änderung an einem Modul kann ein Fenster in einer Sprache zerlegen, die ich gerade nicht offen hatte.

Der Harness soll das Spielen nicht ersetzen. Er soll die große Klasse von Fehlern abfangen, die reine Logik sind (Zähler, Zustandsautomaten, Migrationen, Event-Behandlung, Layout-Rechnung), und zwar in der Zeit, die `go test` braucht.

---

## Die Architektur im Überblick

{{< diagram src="level-time-2-harness.svg" caption="Eine Lua-VM pro Szenario: Das Szenario steuert eine nachgebaute WoW-API, der echte Addon-Code reagiert, Prüfungen sammeln Fehler, die Go meldet." >}}

Die Bausteine:

- **`tools/addontest/addon_test.go`**: der Go-Einstiegspunkt, rund 70 Zeilen.
- **[gopher-lua](https://github.com/yuin/gopher-lua)**: eine Lua-5.1-VM, komplett in Go geschrieben. Kein cgo und keine externe Lua-Installation, `go test` läuft also auf jedem Rechner mit Go.
- **`tests/wow_stub.lua`** plus `tests/stub/*.lua`: die nachgebaute WoW-API, nach Bereichen aufgeteilt (UI, Chat, Einheiten, Addons, Spieler, Komfort, Wirtschaft, Soziales).
- **`tests/*_test.lua`**: die Szenarien. Zum Zeitpunkt des Schreibens sind es 286.
- **Das Addon selbst**, unverändert aus dem Repository geladen.

---

## Die Go-Seite: eine VM pro Szenario

Der Go-Runner sammelt jede `tests/*_test.lua` und macht aus jeder Datei einen Go-Subtest. Das ist eine vereinfachte Fassung des echten Codes (Fehlerbehandlung gekürzt, die echten Meldungen sind wie die Kommentare im Code auf Deutsch):

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

Drei Entwurfsentscheidungen stecken darin:

- **Ein frisches `lua.NewState()` pro Szenario.** Echte Addons halten Zustand in Globals (`LevelTimerStatsDB`, Frames mit Namen). Würden Tests eine VM teilen, würde ein Szenario ins nächste durchsickern. Mit neuem Zustand startet jeder Test wie ein gerade geladener Client.
- **`t.Run` pro Datei.** Jedes Szenario ist einzeln ansprechbar: `go test -run 'TestScenarios/session'` führt nur `tests/session_test.lua` aus. Go-Subtests liefern Filter und lesbare Fehlerausgabe geschenkt.
- **Lua-Prüfungen brechen nicht ab.** Die Lua-Seite merkt Fehlschläge in einer globalen Tabelle, statt einen Fehler zu werfen. Ein Lauf meldet so jede verletzte Erwartung, nicht nur die erste.

Dazu kommt ein Sicherheitsnetz. Jeder Event-Handler und jeder Callback im Addon läuft über `ns.SafeCall`, einen Wrapper um `xpcall`, der Fehler an den Fehlerhandler des Clients (`geterrorhandler()`) weitergibt. Im echten Spiel heißt das: Ein kaputtes Modul stoppt die anderen nicht. Im Harness sammelt der nachgebaute Fehlerhandler diese Fehler in `wow.errors`, und Go macht aus jedem einen Testfehler. Ein Szenario, das absichtlich einen Fehler auslöst, leert die Liste danach.

---

## Das Addon in `.toc`-Reihenfolge laden

Ein WoW-Addon ist kein Programm mit `main`. Es ist ein Ordner mit einer `.toc`-Datei, die die Lua-Dateien auflistet. Der Client führt sie in dieser Reihenfolge aus und übergibt jeder Datei über `...` zwei Werte: den Addon-Namen und eine private Namespace-Tabelle. Details zum Format stehen im [TOC-Format auf warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/TOC_format).

```text
## Interface: 120105, 11509, 20506, 16001
## SavedVariables: LevelTimerDB, LevelTimerStatsDB, LevelTimerDebugLog

Core\Client.lua
Core\Database.lua
Tracking\Stats.lua
UI\TimerWindow.lua
```

(Ausschnitt; die echte Datei listet viel mehr Dateien, durch Kommentare gruppiert.) Der Harness macht dasselbe und nutzt die `.toc` als einzige Quelle der Wahrheit, statt im Testcode eine zweite Dateiliste zu pflegen:

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

Zwei Details sind wichtig. Erstens: Fehlt eine Datei in der `.toc`, fehlt sie auch im Test, und der Klassiker „bei mir läuft es, im Client wird es nie geladen“ fliegt auf. Zweitens: `chunk("LevelTimer", addon)` ahmt die Client-Konvention `local addonName, ns = ...` nach. Der Harness behält den Namespace, damit Szenarien an Module herankommen (`addon.Stats`, `addon.Database` und so weiter).

---

## Die WoW-API-Attrappe

Hier steckt die meiste Arbeit. Die Attrappe besteht aus `tests/wow_stub.lua` und den Bereichsdateien unter `tests/stub/`. Die Kernideen:

### Frames, die alles annehmen

WoW-UI-Code ruft Hunderte Frame-Methoden auf. Alle nachzubauen ist unrealistisch, deshalb benutzen die Frame-Objekte der Attrappe eine Metatabelle: **Bekannte Methoden verhalten sich wie im Client, unbekannte tun nichts.**

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

(Vereinfacht. Die echte Tabelle hat einige Dutzend Einträge.) Ein `frame:SetBackdropBorderColor(...)` wird also stillschweigend akzeptiert, bis ein Test die Wirkung sehen will, und dann kommt eine Zeile dazu. Der Wert `false` ist ein bewusster Notausgang: Mit `frameMethods.RegisterUnitEvent = false` fehlt die Methode, und ein Szenario kann so den Rückfall für einen Client ohne diese Methode prüfen.

Beachte, was `SetPoint` tut: Es legt nichts aus. Es **merkt sich** den Anker in `frame._points`. Genau das macht Layout-Tests später möglich.

### Events und Zeit unter Testkontrolle

Das Addon ist ereignisgesteuert, die Attrappe braucht also Wege, Events auszulösen und die Zeit zu verschieben:

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

Die Zeit ist der Schlüssel zur Testbarkeit: Nichts schläft. `C_Timer.After`-Callbacks werden nur eingereiht, und `wow.runTimers()` führt sie auf Abruf aus. Ein Szenario wie „die Einnahme erscheint, nachdem die Reparatur bezahlt wurde“ läuft in Mikrosekunden und ist vollständig deterministisch. `wow.update(seconds)` macht dasselbe für `OnUpdate`-Handler; so ticken wiederkehrende Aufgaben und das Zeitfenster.

Der Spielzustand selbst ist eine Tabelle, `wow.state` (Name, Level, XP, Geld, Buffs, Kampfstatus, Zone und mehr), aus der API-Funktionen wie `UnitLevel` und `GetTime` lesen. Ein Szenario ändert den Zustand und löst dann das Event aus, das der Client ausgelöst hätte.

### Namespaces und Client-Varianten

Die moderne WoW-API liegt in Namespaces wie `C_Timer`, `C_Spell`, `C_Container` oder `C_UnitAuras` ([Überblick auf warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)). Die Attrappe definiert die, die das Addon nutzt, in der passenden Bereichsdatei. Die Projektregel ist einfach: Sobald das Addon eine neue API-Funktion benutzt, kommt sie in derselben Änderung in die Attrappe.

Level Time unterstützt mehrere Client-Varianten (Retail, Classic Era, WoW Forever). Der *Dateiname* des Szenarios wählt die Variante: `era_*`-Szenarien laden als Classic Era (Interface 11509), `forever_*` als WoW Forever (16001), alles andere als Retail. Das ist eine Zeile in der Attrappe, die die vom Go-Runner gesetzte Global `SCENARIO` liest.

---

## Ein echtes Szenario

Hier ein gekürztes, vereinfachtes Szenario im Stil von `tests/session_test.lua`: Sessions zählen parallel zum Level und überstehen ein `/reload`.

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

(Das echte Szenario nutzt deutsche Chattexte, weil das Addon lokalisierten Kampflog-Text auswertet, und prüft mehr.) Alle Helfer hier (`wow.login`, `wow.fire`, `wow.advance`, `wow.logout`, `expect`) stammen aus der Attrappe. Nach dem Login schaut der Test auf den **gespeicherten Zustand** (`addon.character`, also das, was in den SavedVariables landet) und auf den **UI-Zustand** (Frame-Text, Sichtbarkeit, Anker), also genau auf die zwei Dinge, die ein Spieler irgendwann sieht.

Die Prüf-Helfer sind absichtlich winzig:

```lua
TEST_FAILURES = {}

function expect(description, actual, expected)
  if actual ~= expected then
    table.insert(TEST_FAILURES,
      string.format("%s: expected %s, got %s", description, tostring(expected), tostring(actual)))
  end
end
```

Reines Lua, kein Framework. `expectNear` und `expectTrue` haben dieselbe Form. Die Fehlermeldung trägt die Beschreibung, ein roter Go-Subtest liest sich dadurch wie ein Satz.

---

## Lua 5.1 gegen das Lua in WoW

[gopher-lua implementiert Lua 5.1](https://github.com/yuin/gopher-lua), und der WoW-Client auch, deshalb habe ich es gewählt. Die *Sprache* passt damit zusammen: `unpack` als Global (nicht `table.unpack`), kein Integer-Typ, kein `goto`, kein `//`-Operator. Was auf der einen Seite parst, parst auch auf der anderen. Gemeinsame Grundlage ist das [Lua-5.1-Referenzhandbuch](https://www.lua.org/manual/5.1/).

Aber „gleiche Sprachversion“ heißt nicht „gleiche Laufzeit“. Die Unterschiede, die in der Praxis zählen:

- **WoW bringt Globals mit, die Standard-Lua nicht hat.** Beispiele sind `strsplit`, `wipe`, `tinsert`, `hooksecurefunc` und `geterrorhandler`. Nutzt das Addon eine davon, muss die Attrappe sie definieren. Vergesse ich das, scheitert der Test laut mit „attempt to call a nil value“, eine billige Erinnerung.
- **gopher-lua hat eigene Macken.** Zwei stehen in der `CLAUDE.md` des Projekts, weil sie mich Zeit gekostet haben. Erstens: `tonumber(s:match(...))` wirft einen Fehler, wenn `match` nichts findet, weil `tonumber()` dann gar kein Argument bekommt; die Lösung sind die zusätzlichen Klammern in `tonumber((s:match(...)))`. Zweitens: Nach einem `pcall`-Fehler aktualisierten sich Zahl-Locals im Hauptteil des Tests, die Closures erfasst hatten, nicht mehr. Zähler in Tests liegen deshalb in Tabellen.
- **WoW schränkt die Umgebung ein.** Der Client entfernt oder kapselt einige Funktionen der Standardbibliothek, und neuere Spiel-APIs können „geheime“ Werte liefern, die Addons in bestimmten Situationen nicht vergleichen oder verzweigen dürfen. Eine normale Lua-VM erlaubt das alles, und die Attrappe bildet nur nach, was ich ihr beigebracht habe.

Die Praxisregel: Beißt eine gopher-lua-Macke, behebe ich sie im Test oder schreibe Code, der in beiden Laufzeiten gültig ist. Das Verhalten des Addons hängt nie davon ab, ob gerade ein Test läuft.

---

## Layout-Tests in vier Sprachen

Das ist der Teil, der mehr findet, als ich erwartet hätte. Level Time gibt es auf Deutsch, Englisch, Französisch und Spanisch (`deDE`, `enUS`, `frFR`, `esES`). Französische und spanische Texte sind spürbar länger, und ein Einstellungsfenster, das auf Englisch passt, kann auf Französisch ein Schalter-Label in den Nachbarn schieben.

{{< diagram src="level-time-2-layout-flow.svg" caption="Der Layout-Test wechselt die Sprache, baut das echte Fenster, liest gemerkte Anker und gemessene Textbreiten aus der Attrappe und prüft, dass nichts überlappt oder aus dem Fenster ragt." >}}

Weil `SetPoint` Anker merkt und `SetText` den String speichert, kann die Attrappe „wo steht dieses Element und wie breit ist sein Label“ ohne Renderer beantworten. Das Szenario `tests/layout_fit_test.lua` läuft über die Sprachen und prüft bei Schalterpaaren, die sich eine Zeile teilen, dass der rechte hinter dem Ende des linken beginnt und noch ins Fenster passt. Eine gekürzte Fassung:

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

Dieselbe Datei deckt das Historienfenster ab (Unterreiter müssen in zusätzliche Zeilen umbrechen, statt den Inhaltsbereich zu verlassen, geprüft in allen vier Sprachen), Button-Breiten gegen ihren Text und Tabellen-Werkzeugleisten. Ein zweites Szenario macht dasselbe für das Fenster von Level Time Goals. Ein drittes, `tests/locales_test.lua`, prüft, dass jede Sprache jeden Schlüssel hat und dass die Platzhalter `%s` und `%d` zum englischen Text passen. Das verhindert eine ganze Klasse von Format-Fehlern zur Laufzeit.

### Wie die Textbreite gemessen wird, ehrlich gesagt

Man könnte das „pixelgenaue Layout-Tests“ nennen. Das sind sie nicht, und das sollte man genau sagen. Die Attrappe kennt keine Schrift. Ihre Textmessung ist:

```lua
GetStringWidth = function(self) return #self._text * 6 end,
```

Die Breite ist die Stringlänge in **Bytes** mal 6. Das ist eine grobe Näherung: Eine echte Schrift hat proportionale Glyphen (ein „i“ ist schmaler als ein „m“), Schrift und Größe sind in Level Time einstellbar, und UTF-8-Umlaute zählen hier als zwei Bytes, obwohl sie als ein Zeichen gezeichnet werden.

Warum findet das trotzdem echte Fehler? Weil das *relative* Verhalten stimmt. Französische und spanische Texte sind länger, also werden sie in der Attrappe auch breiter, und ein Layout, das für den englischen Text eine feste Breite annimmt, fällt durch. Der Layout-Code des Addons hilft dabei: Die Breiten der Einstellungsspalten werden aus den gemessenen Label-Breiten berechnet (`fitWidth`), statt fest zu sein. Der Test prüft also, dass die *Regel* in jeder Sprache hält. Er beweist nicht, dass das Ergebnis mit der echten Schrift gut aussieht.

Was er nie sagen kann, ist „dieser Text ist auf Französisch mit der Standardschrift um zwei Pixel abgeschnitten“. Dafür muss man ins Spiel schauen.

---

## Der Performance-Profiler (und wie er getestet wird)

Level Time hat einen Profiler im Spiel, `/lt debug perf`. Er gehört zum Addon (`Core/Profiler.lua`), nicht zum Go-Tooling, und der Harness testet ihn wie jedes andere Modul. Ich erwähne ihn, weil er eine schöne Eigenschaft des Attrappen-Ansatzes zeigt: Auch Werkzeuge, die von Client-Funktionen abhängen, lassen sich testen.

Was er misst:

- die Zeit jedes **Event-Handlers**, jeder `ns.Every`-Hintergrundaufgabe, jedes über `ns.SafeCall` verteilten Callbacks (Zähler, XP- und Journal-Listener, Login, Einstellungen anwenden) und der `OnUpdate`-Skripte der Fenster;
- je Eintrag **Summe und Maximum in Millisekunden**, Anzahl der Aufrufe und Speicherzuwachs, über `debugprofilestop()` und `collectgarbage("count")`.

So funktioniert er: Solange der Profiler aus ist, wird nichts umhüllt, er kostet also nichts. Schaltet man ihn ein, tauscht der Kern die Verteiler gegen messende Varianten aus, und `/lt debug perf report 10` gibt die Spitzenreiter im Chat aus. Die Attrappe macht das testbar, indem sie `debugprofilestop` aus der Fake-Uhr plus einer vom Test gesteuerten Zahl (`wow.profileMs`) ableitet. Das Szenario registriert einen Handler, der „5 ms braucht“:

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

Beachte, was dieser Test beweist: Die Buchführung stimmt (Summen, Maxima, Aufrufzahlen), und das Ausschalten stellt die Originalfunktionen wieder her. Er misst **nicht**, wie schnell das Addon ist. Der Go-Harness läuft auf einem Entwicklerrechner oder CI-Runner, nicht im Spielclient, seine Zeiten wären bedeutungslos. Echte Zahlen kommen vom Spielen mit eingeschaltetem Profiler, und so finde ich auch die Hotspots.

---

## Die Tests in der CI

Der Workflow heißt `.github/workflows/test.yml` und ist kurz:

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
          go-version: "1.23"
          cache-dependency-path: tools/*/go.sum
      - run: make vet
      - run: make test
```

Er läuft bei jedem Pull Request und jedem Push auf `main`. `make vet` führt `go vet` für alle Go-Werkzeuge aus, `make test` die Addon-Szenarien plus die Tests der anderen Werkzeuge (Installer, Artwork, Speedrun-Rekorde, Flüge). Da gopher-lua reines Go ist, muss außer Go nichts installiert werden. In [Teil 3](/de/blog/level-time-3-release-pipeline/) führt der Release-Workflow die Tests aus, bevor irgendetwas verpackt wird.

---

## Selbst ausprobieren

Du brauchst Go 1.23 oder neuer. Die Installationsanleitung steht auf [go.dev/doc/install](https://go.dev/doc/install). Dann das Repository klonen und die Tests starten.

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

`make` ist unter Windows meist nicht installiert. Die `go -C`-Befehle oben sind genau das, was das Makefile-Ziel `test-addon` aufruft. Die Option `-C` (vor dem Ausführen das Verzeichnis wechseln) braucht Go 1.20 oder neuer.

**Immer `-count=1` angeben.** Der Test-Cache von Go weiß nichts von den Lua-Dateien, die gopher-lua lädt. Ohne `-count=1` kannst du eine Addon-Datei ändern, neu starten und ein veraltetes Ergebnis aus dem Cache bekommen. Genau deshalb steht das als feste Regel im Repository.

Ein neues Feature bedeutet dann: ein Szenario in `tests/` anlegen oder erweitern. Eine neue API-Funktion kommt in die passende `tests/stub/*.lua`.

---

## Ehrliche Grenzen: Was die Attrappe nicht findet

Eine grüne Suite heißt: Die Logik tut, was die Szenarien sagen. Sie heißt nicht, dass das Addon im Spiel funktioniert. Konkret kann mir der Harness nicht sagen:

- **Ob eine API in einem bestimmten Client existiert.** Die Attrappe definiert `C_Spell.GetSpellName`, weil ich es ihr gesagt habe. Fehlt die Funktion im echten Client einer Variante, hat sie eine andere Signatur oder liefert einen „geheimen“ Wert, bleibt der Test grün und der Spieler bekommt einen Lua-Fehler. Ich mildere das, indem ich den Blizzard-UI-Quelltext je Variante prüfe und nil-sicher schreibe, aber die Attrappe selbst weiß es nicht. Die [WoW-API-Seiten auf warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API) sind meine Referenz dafür, was wo existiert.
- **Echtes Rendering.** Texturen, Schriften, Skalierung, Strata (welcher Frame oben liegt), Animationen und Sounds werden nicht simuliert. Animationen merken sich nur ein „läuft“-Flag.
- **Zeitpunkt und Reihenfolge echter Events.** Die Attrappe löst Events aus, wenn ein Test es sagt. Der echte Client kann sie in anderer Reihenfolge, zu anderer Zeit oder gebündelt senden. Event-Races sind mein größter blinder Fleck.
- **Geschützte Frames und Kampfsperre, über das ausdrücklich Modellierte hinaus.** Die Attrappe wirft bei `SetAttribute`, solange ihr Kampfsperren-Flag gesetzt ist, bildet aber Blizzards vollständige Regeln für sichere Frames nicht nach.
- **Performance.** Siehe oben: Er beweist die Buchführung, nicht die Geschwindigkeit.
- **Meine eigenen falschen Annahmen.** Wenn ich falsch verstehe, was ein Event liefert, schreibe ich dasselbe Missverständnis in Addon und Attrappe, und der Test stimmt dem Fehler zu.

Das Letzte sind die eigentlichen Kosten jeder handgeschriebenen Attrappe. Das Gegenmittel ist eine manuelle Checkliste im Repository (`ManualToCheck.md`) mit Dingen, die weiter im Spiel probiert werden müssen, und die Disziplin, „in der Attrappe getestet“ und „im Spiel geprüft“ als zwei verschiedene Status zu behandeln.

---

## Das Wichtigste in Kürze

- Eine reine Go-Lua-VM macht aus einem Addon etwas, das `go test` ausführen kann, ohne Spiel und ohne Lua-Installation.
- Eine frische VM pro Szenario plus Go-Subtests liefert Isolation und einen Filter mit einem Befehl.
- Eine Attrappe mit No-Op-Standard hält den Aufwand fürs Nachbauen niedrig: Nur nachbauen, was ein Test beobachten muss.
- Zeit (`wow.advance`, `wow.runTimers`) und Events (`wow.fire`) ausdrücklich steuern; nichts darf schlafen.
- Layout-Eingaben (Anker, Text, Größen) aufzeichnen und die *Regeln* in jeder Sprache testen, statt Pixeln hinterherzujagen.
- Die eigenen blinden Flecken kennen und eine manuelle Checkliste für das Spiel pflegen.

---

## Wie geht es weiter?

In [Teil 3](/de/blog/level-time-3-release-pipeline/) zeige ich, wie aus einem Tag mit dem [BigWigs-Packager](https://github.com/BigWigsMods/packager) ein Release auf GitHub, CurseForge, Wago und WoWInterface wird und wie die Tests davor als Tor dienen. Wenn du Classic spielst und sehen willst, wofür der ganze Code da ist: Die [Level-Time-Seite](/de/page/level-time/) hat Screenshots und den Download-Link. Zum Werkzeug-Denken passen auch meine Artikel zu [Go in Docker](/de/blog/go-docker/) und zum [Prüfen von statischem Linking](/de/blog/check-static-linking/).
