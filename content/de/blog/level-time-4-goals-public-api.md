---
draft: false
title: "Level Time bauen — Teil 4: Ein Schwester-Addon über eine öffentliche API — Level Time Goals und das Glücksrad"
seo_title: "WoW-Addon-API in Lua: Level Time Goals als Fallstudie"
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
description: "Wie ein zweites WoW-Addon auf der globalen API von Level Time aufbaut: warum getrennt, welche API-Lehren ich gezogen habe und wie das Glücksrad in Lua dreht."
images: ["img/level-time/goals-logo.png"]
featured_image: "img/level-time/goal-bingo.png"
toc: true
---

> **Level Time bauen** — Teil 4 von 4. [Teil 1: Addon-Architektur](/de/blog/level-time-1-addon-architecture/) · [Teil 2: Lua mit Go testen](/de/blog/level-time-2-testing-lua-with-go/) · [Teil 3: die Release-Pipeline](/de/blog/level-time-3-release-pipeline/) · Teil 4 (dieser Artikel). Produktseite: [Level Time](/de/page/level-time/).

In den ersten drei Teilen habe ich beschrieben, wie Level Time aufgebaut ist, wie ich sein Lua mit Go teste und wie es veröffentlicht wird. In diesem Teil geht es darum, was passiert, wenn ein zweites Addon auf den Schultern des ersten stehen soll: **Level Time Goals**, ein Schwester-Addon für Streamer, das im selben Repository liegt (`StreamGoal/`) und als eigenes CurseForge-Projekt erscheint.

Es ist auch die Geschichte einer API, die ich anfangs gar nicht als API entworfen habe. Das sage ich offen, denn die interessanten Lehren stecken in der Lücke zwischen dem, was ein Kommentar verspricht, und dem, was der Code tatsächlich garantiert. Level Time und Level Time Goals sind junge Projekte, öffentlich auf [GitHub](https://github.com/Noobygames/wow-statistics) gebaut, und die Rad-Animation am Ende ist im Spielclient noch nicht vollständig geprüft (dazu unten mehr).

## Was Level Time Goals kann

Mit Level Time Goals setzt ein Streamer Ziele und zeigt sie als Karten auf dem Bildschirm, sodass Zuschauer sehen, woran er arbeitet und wie weit er ist. Wird ein Ziel erreicht, erscheint eine große Einblendung. Laut [Addon-Beschreibung](https://www.curseforge.com/wow/addons/streamer-goals) gibt es unter anderem diese Zielarten:

- ein Level erreichen, Gegner besiegen, Items looten oder besitzen, Gold verdienen oder besitzen
- Quests abgeben, Berufsstufen erreichen, Gebiete entdecken, Bosse besiegen, Ruf, Schlachtfeldsiege
- Regeln, an denen man scheitern kann („kein Tod bis Level 30“, „kein Auktionshaus“)
- Checklisten mit Unterzielen und Freitext-Ziele, die man per Klick abhakt

Zusätzlich zu einzelnen Zielen gibt es **Bingo-Karten** (3×3 oder 5×5, die Felder haken sich selbst ab) und ein **Glücksrad**, das dein nächstes Ziel aus einem Pool zieht – mit begrenzten Neuwürfen und optional bei jedem Level-Up.

![Eine 3×3-Bingo-Karte in Level Time Goals mit zwei erledigten Feldern](/img/level-time/goal-bingo.png)

*Eine 3×3-Bingo-Karte aus Level Time Goals (deutscher Client). Jedes Feld ist ein Ziel, das sich selbst verfolgt; grüne Felder sind erledigt.*

## Warum ein eigenes Addon

Goals hätte auch ein Reiter in Level Time sein können. Ich habe mich aus drei Gründen dagegen entschieden.

1. **Optional für Nutzer.** Die meisten Level-Time-Nutzer wollen Statistiken, Timer und Tabellen, keine Streamer-Overlays. Ein eigenes Addon heißt: Sie laden den Code nie, sehen die Einstellungen nie und zahlen weder Speicher noch Update-Kosten dafür.
2. **Eigener Release-Rhythmus.** Goals ändert sich schnell: neue Zielarten, Pack-Inhalte, Rad-Feinheiten. Level Time soll keinen Release (und keine neue Runde Prüfung im Spiel) brauchen, nur weil ein Bingo-Feldtext sich ändert. In [Teil 3](/de/blog/level-time-3-release-pipeline/) habe ich beschrieben, wie ein Tag ein Addon veröffentlicht; Goals hat ein eigenes CurseForge-Projekt (ID `1744370` in der `.toc`) und ein eigenes Zip.
3. **Der Kern bleibt schlank und ehrlich.** Wenn ein Schwester-Addon auf dem Kern aufbauen kann, ohne etwas zu kopieren, ist das ein ordentlicher Beleg, dass die Bausteine des Kerns wirklich wiederverwendbar sind. Hätte ich ein Modul in Goals kopieren müssen, gehörte es woanders hin.

Die Kopplung steht in `StreamGoal/StreamGoal.toc`:

```text
## Interface: 120105, 11509, 20506, 16001
## Title: Level Time Goals
## Dependencies: LevelTimer
## SavedVariables: StreamGoalDB
```

`## Dependencies: LevelTimer` ist eine harte Abhängigkeit im Sinne des [TOC-Formats](https://warcraft.wiki.gg/wiki/TOC_format): Der Client lädt Level Time zuerst, und Goals wird ohne Level Time nicht aktiviert. Goals hat außerdem eigene gespeicherte Variablen, `StreamGoalDB`, seine Daten leben also unabhängig von denen von Level Time.

## Die öffentliche API von Level Time

Jetzt der ehrliche Teil. Als ich das Schwester-Addon geschrieben habe, bestand die „API“ aus einer Zeile in `Core/LevelTimer.lua`:

```lua
-- Interface for sister addons: the namespace with all building blocks
-- (Card, Widgets, TableView, Alerts, Journal, Format, ...), events,
-- login and level-up. (comment translated and shortened)
LevelTimerAPI = ns
```

Das ist der ganze Export: **Die private Namespace-Tabelle `ns` des Addons wird als Global namens `LevelTimerAPI` veröffentlicht.** Jedes Addon bekommt beim Laden seiner Dateien `(addonName, ns)` als Varargs, und diese Tabelle ist normalerweise der private Treffpunkt der eigenen Dateien. Indem ich sie einem Global zuweise, ist die ganze Tabelle für andere Addons erreichbar. Weil Goals die Abhängigkeit deklariert, sind die Dateien von Level Time vollständig geladen, wenn die erste Datei von Goals läuft – die Tabelle ist also komplett.

Goals bindet sie einmal ganz oben in seiner `Core.lua`:

```lua
local _, ns = ...          -- Goals' own namespace

local LT = LevelTimerAPI   -- Level Time's namespace
ns.LT = LT
ns.L = LT.L                -- localisation shared with Level Time
```

Danach läuft in Goals alles über `ns.LT`. Eine kurze, vereinfachte Tour durch die Fläche, die tatsächlich genutzt wird:

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

{{< diagram src="level-time-4-api.svg" caption="Eine Tabelle überschreitet die Grenze. Level Time füllt LevelTimerAPI, Schwester-Addons lesen sie; die Abhängigkeit in der .toc garantiert die Ladereihenfolge." >}}

### Wie Callbacks sicher bleiben

Die wichtigste Entwurfsentscheidung in dieser Fläche ist nicht das Global, sondern wie Ereignisse zugestellt werden. Level Time führt Level-Ups in zwei Phasen aus (`OnLevelCompleted` mit dem alten Level, dann `OnLevelStarted` mit dem neuen) und lässt jeden Callback durch `ns.RunCallbacks` laufen:

```lua
-- Simplified from Lib/Lifecycle.lua
local function runAll(callbacks, ...)
  for index = 1, #callbacks do
    ns.SafeCall(callbacks[index], ...)
  end
end
```

Jeder Callback ist per [`xpcall`](https://www.lua.org/manual/5.1/manual.html#pdf-xpcall) geschützt: Ein Fehler im Level-Up-Handler von Goals kann den Handler von Level Time nicht aufhalten – und umgekehrt. Das ist die wertvollste Eigenschaft der API für ein Plugin-Ökosystem: **Der Fehler eines Konsumenten bleibt der Fehler des Konsumenten.**

### Was die API nicht ist

Mit kritischem Blick auf meinen eigenen Code: Das hat die „öffentliche API“ **nicht**:

- **Keine Versionsnummer.** Es gibt kein `LevelTimerAPI.version` und keine Kompatibilitätsprüfung. Beide Addons kommen aus einem Repository, ich verlasse mich also darauf, dass sie immer zusammen aktualisiert werden.
- **Keine Trennung stabil/intern.** Alles in `ns` ist erreichbar, auch Dinge, die nie für andere Addons gedacht waren.
- **Kein dokumentierter Vertrag.** Der Vertrag besteht aus einem Kommentar und der `CLAUDE.md` des Projekts. Dort steht: Nutze diese Bausteine, kopiere sie nicht, und *wenn etwas fehlt, ergänze es in Level Time*.

Diese letzte Regel hat tatsächlich funktioniert. Sie macht aus der API-Fläche etwas, das nach Bedarf wächst, getrieben von einem echten Konsumenten statt von Spekulation.

## Lehren für das API-Design

Auch wenn die Fläche informell ist: Goals darauf zu bauen hat mir gezeigt, was ich zuerst formalisieren würde.

**1. Entscheide, was stabil ist, und sag es.** Den ganzen Namespace zu veröffentlichen ist die billigste API und die teuerste in der Pflege: Jede umbenannte Hilfsfunktion ist ein möglicher Breaking Change für einen Konsumenten. Mit einem Konsumenten unter eigener Kontrolle ist das erträglich, mit einem Drittanbieter nicht. Der nächste Schritt wäre eine kleine, explizite Tabelle wie `LevelTimerAPI.v1`, die nur Funktionen enthält, auf die ich mich festlege.

**2. Features erkennen, nicht Versionen.** Die Konventionen von Level Time sagen schon: Jede Client-API, die nicht in jedem Spiel-Flavor existiert, wird abgesichert (`if GetPVPSessionStats then ...`), und dem Client unbekannte Events sind harmlos, weil `ns.RegisterEvent` `false` zurückgibt statt einen Fehler zu werfen. Dieselbe Haltung gilt zwischen Addons. Ein defensiver Konsument sähe so aus (das Muster, das ich für ein Drittanbieter-Addon nutzen würde – nicht das, was Goals heute tut):

```lua
local LT = LevelTimerAPI
if not LT or type(LT.OnLevelStarted) ~= "function" then
  print("MyAddon: Level Time is missing or too old, feature disabled.")
  return
end
```

Goals kann diese Prüfung wegen der harten `## Dependencies`-Zeile weglassen; ein Addon, das Level Time unter `## OptionalDeps` listet, muss sie machen.

**3. Nie in Interna greifen.** Die Regel lautet „Bausteine nutzen, nicht kopieren“. Das Spiegelbild: nicht um sie herumgreifen. Braucht Goals einen Wert, den Level Time in einer lokalen Variable hält, ist die richtige Lösung eine neue Funktion in Level Time, kein Hack in Goals. So zeigt der Abhängigkeitspfeil nur in eine Richtung.

**4. Fehler und Zustand isolieren.** Goals hat einen eigenen Namespace, eigene SavedVariables (`StreamGoalDB`, die erst ab dem Login existieren) und einen eigenen Debug-Bereich (`LT.Debug("goal:" .. area, ...)`). Geht etwas schief, sagt mir das Log, aus welchem Addon es kommt.

**5. Gemeinsame Infrastruktur schlägt gemeinsame Kopien.** Lokalisierung ist ein gutes Beispiel. Goals hängt seine `SG_*`-Texte in die Sprachtabellen von Level Time ein, sodass `LT.L` und gemeinsame Widgets wie die Tabellenköpfe sie in der Sprache auflösen, in der Level Time läuft. Der Konsument braucht kein zweites Sprachsystem; der Preis ist, dass beide Addons sich auf das Platzhalterformat einigen müssen, was ein Test in allen vier Sprachen prüft.

![Eine Level-Time-Karte mit Loot-Würfel-Zählern](/img/level-time/lt-rolls-example.png)

*Eine Level-Time-Karte (hier mit Zählern für Loot-Würfe, aus einer früheren Version). Die Karten, das Rad-Ergebnis und die Einblendungen von Goals nutzen genau diesen Karten-Baustein über die API, statt eigene zu zeichnen.*

## Das Glücksrad: Animation in einer eingeschränkten Oberfläche

Das Glücksrad ist der Teil, an dem ich am meisten Spaß hatte. Im Spiel ist es ein echtes drehendes Rad mit 12 farbigen Stücken, einem festen Zeiger oben und einer Nabe, gezeichnet aus Texturen, die ein Go-Werkzeug im Repository erzeugt (`make artwork`, `tools/artwork -wheel`). Alles Folgende stammt aus `StreamGoal/Wheel.lua` und `StreamGoal/WheelDisplay.lua`.

### Das Ergebnis steht vor der Animation fest

Die erste Entwurfsentscheidung: **Das Ergebnis wird gewählt, bevor sich irgendetwas dreht.** `Wheel.lua` wählt den Eintrag und übergibt der Animation ein Zielstück:

```lua
-- Simplified from Wheel.lua
local items = Wheel.Pool()                 -- enabled entries, shuffled
local chosen = pick(items)                 -- first entry that passes validation
local titles, target = slicesFor(items, chosen)
WheelDisplay.Spin(titles, target, function()
  finish(items, chosen, rerollsLeft)       -- create the goal after the wheel stops
end)
```

Die Animation ist damit reine Darstellung. Das hat drei praktische Vorteile: Das Ergebnis hängt nicht von der Framerate ab, die abgeschaltete Animation (`wheelAnimation = false`) liefert sofort dieselbe Art von Ergebnis, und Tests können das Ergebnis prüfen, ohne Pixel zu simulieren.

### Rotationsmathematik

Jedes Stück ist eine eigene Textur, die per `Texture:SetRotation` um ihre Mitte gedreht wird (siehe [API-Referenz](https://warcraft.wiki.gg/wiki/API_TextureBase_SetRotation)). Der Raddrehwinkel `r` dreht alle Stücke, Stück `i` liegt bei `r + (i - 1) * step`, und ein Stück steht unter dem Zeiger, wenn dieser Winkel ein Vielfaches von 2π ist. Zwei reine Funktionen erledigen die Geometrie (vereinfacht):

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

`turns` ist 3 plus ein zufälliger Bruchteil, und der Landepunkt wird um bis zu ±0,175 Stückbreiten verschoben (`LANDING_SPREAD = 0.35`), damit der Zeiger nicht immer exakt in der Mitte eines Stücks steht. Das Zielstück selbst bleibt fest; der Zufall ist nur Optik.

### Auslaufen per OnUpdate

Die Animation läuft in einem [`OnUpdate`](https://warcraft.wiki.gg/wiki/UIHANDLER_OnUpdate)-Skript, das der Client jeden Frame mit den seit dem letzten Frame vergangenen Sekunden aufruft. Die Kurve ist ein kubisches Ease-out: schneller Start, weicher Halt.

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

{{< diagram src="level-time-4-ease.svg" caption="Die kubische Ease-out-Kurve der Drehung: Mehr als die Hälfte der Rotation passiert im ersten Viertel der vier Sekunden, und das Rad kommt mit Geschwindigkeit null am Ziel an." >}}

Weil die Rotation aus der *vergangenen Zeit* berechnet wird und nicht durch einen festen Schritt pro Frame, dauert die Drehung vier Sekunden – egal ob das Spiel mit 30 oder 144 Bildern pro Sekunde läuft. Ein langsamer Frame erzeugt einen größeren Sprung, keine längere Animation.

### Frame-Budget

Ein `OnUpdate`-Handler, der ewig läuft, ist eine klassische Performance-Falle, weil er jeden Frame bei jedem Spieler ausgeführt wird. Das Rad hält die Kosten auf drei Wegen niedrig:

- das Skript läuft nur, solange der Rad-Rahmen sichtbar ist, und ohne laufende Drehung kehrt der Handler schon in der ersten Zeile zurück
- es wird über `LT.SetUpdateScript(frame, "StreamGoalWheel", update)` registriert, einen Helfer von Level Time, der den Handler so umhüllt, dass der eingebaute Profiler ihn unter seinem Namen messen kann
- Text dreht sich nicht mit den Stücken (FontStrings lassen sich nicht in jedem Client drehen), deshalb wird die Zeile unter dem Rad nur aktualisiert, wenn das Stück unter dem Zeiger wechselt, über einen Text-nur-bei-Änderung-Helfer

Der Tick-Ton beim Vorbeidrehen der Stücke nutzt dieselbe Prüfung „Stück unter dem Zeiger hat gewechselt“ und kostet zwischen den Ticks nichts.

### Was noch offen ist

Ich sage es offen: Die `ROADMAP.md` führt das Rad als umgesetzt, mit dem Hinweis, dass es noch im echten Spiel geprüft werden muss (ein Punkt auf meiner manuellen Prüfliste). Die Tests beweisen die Logik, nicht die Darstellung. Ob `SetRotation` auf Texturen in allen vier unterstützten Clients richtig aussieht, kann mir nur ein Login sagen; im Repository gibt es sogar einen Debug-Check (`/lt debug check`), der den Client fragt, ob er diese Texturen drehen kann. Die Idee der Zuschauer-Abstimmung aus der Roadmap ist aus einem schlichten Grund offen: Addons können den Twitch-Chat nicht lesen.

## Das Rad mit dem Go-Harness testen

All das ist testbar, weil die Mathematik aus reinen Funktionen besteht und die Animation von `elapsed` getrieben wird. In [Teil 2](/de/blog/level-time-2-testing-lua-with-go/) habe ich das Harness beschrieben: ein Go-Programm mit [gopher-lua](https://github.com/yuin/gopher-lua), das das Addon in `.toc`-Reihenfolge gegen eine nachgebaute WoW-API lädt. Für das Schwester-Addon macht der Stub dasselbe mit der `.toc` von Goals, wenn ein Szenarioname mit `streamgoal_` beginnt: Er lädt zuerst Level Time, dann Goals in einen eigenen Namespace – genau wie der Client.

Das Rad-Szenario (`tests/streamgoal_wheel_test.lua`, gekürzt) sieht so aus:

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

`wow.update(seconds)` schiebt die Fake-Uhr vor und ruft die `OnUpdate`-Skripte mit dieser vergangenen Zeit auf, eine Drehung von vier Sekunden braucht also ein paar Dutzend synchrone Aufrufe und keine echte Wartezeit. Dasselbe Szenario deckt auch das Herunterzählen der Neuwürfe, die Drehung beim Level-Up und den Pfad „Animation aus“ ab. So lässt du alle Addon-Tests laufen:

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# Linux / macOS (needs Go and make)
git clone https://github.com/Noobygames/wow-statistics.git
cd wow-statistics
make test-addon
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# Windows (PowerShell, needs Go; make is optional)
git clone https://github.com/Noobygames/wow-statistics.git
cd wow-statistics
go -C tools/addontest test -count=1 ./...
```

{{< /os-tab >}}
{{< /os-tabs >}}

Go installierst du über [go.dev/doc/install](https://go.dev/doc/install). Die PowerShell-Variante ist genau das, was das Makefile-Ziel ausführt.

## Lehren aus dem Schwester-Addon

- Ein zweiter Konsument ist das beste API-Review, das man bekommen kann. Jedes Mal, wenn Goals etwas brauchte, hatte die Frage „gehört das in den Kern?“ eine konkrete Antwort.
- Den ganzen Namespace zu veröffentlichen ist schnell und in Ordnung, solange man beide Seiten kontrolliert. Schreib auf, ab wann es das nicht mehr ist.
- Erst das Ergebnis festlegen, dann animieren. So bleibt der Zufall testbar und die Animation optional.
- Zeitbasierte Animation, ein früher Rücksprung im Leerlauf und ein Profiler-Haken machen `OnUpdate`-Code billig genug zum Ausliefern.

## Wie geht es weiter?

Damit ist die Serie vorerst abgeschlossen. Wenn du die Addons ausprobieren willst, starte auf der [Level-Time-Seite](/de/page/level-time/) oder bei [Level Time Goals auf CurseForge](https://www.curseforge.com/wow/addons/streamer-goals) und sag mir per [GitHub Issues](https://github.com/Noobygames/wow-statistics/issues), was kaputt geht. Dasselbe Denken „die Grenze klein halten“, angewendet auf Services statt Addons, findest du in meinem Beitrag über [Bounded Contexts](/de/blog/bounded-context/).
