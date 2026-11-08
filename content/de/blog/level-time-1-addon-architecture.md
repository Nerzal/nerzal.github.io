---
draft: false
title: "Level Time bauen — Teil 1: Anatomie eines WoW-Addons — Events, Tracking, Historie, UI"
seo_title: "WoW-Addon-Architektur: Events, SavedVariables, Multi-Client"
date: 2026-11-11T08:00:00+01:00
tags:
  [
    "lua",
    "wow",
    "world-of-warcraft",
    "addon",
    "architektur",
    "savedvariables",
    "spieleentwicklung",
    "open-source",
  ]
categories: ["Software Engineering"]
series: ["Building Level Time"]
description: "So ist ein WoW-Addon aufgebaut: TOC, Event-Frames, SavedVariables, ein Load-on-Demand-Archiv und eine Codebasis für Retail, Classic Era, TBC und Forever."
images: ["img/level-time/logo.png"]
featured_image: "img/level-time/lt-tiles.png"
toc: true
---

> **Serie: Level Time bauen.** Teil 1 (dieser Beitrag): Addon-Architektur · [Teil 2: Lua mit Go testen](/de/blog/level-time-2-testing-lua-with-go/) · [Teil 3: die Release-Pipeline](/de/blog/level-time-3-release-pipeline/) · [Teil 4: Goals und die öffentliche API](/de/blog/level-time-4-goals-public-api/) · Produktseite: [Level Time](/de/page/level-time/)

Level Time ist ein World-of-Warcraft-Addon, das ich in Lua schreibe und mit etwas Go-Tooling pflege. Es ist öffentlich auf [CurseForge](https://www.curseforge.com/wow/addons/level-time) und auf [GitHub](https://github.com/Noobygames/wow-statistics). Diese Serie erzählt die Ingenieursgeschichte dahinter: wie das Addon aufgebaut ist, wie ich Lua aus Go heraus teste, wie ein Release entsteht und wie ein zweites Addon an das erste andockt.

Der erste Teil dreht sich um die Form des Ganzen. Ein Addon ist ein Programm, das im Prozess eines anderen läuft, in einer Sprachversion, die jemand anderes gewählt hat, auf vier verschiedenen Spielclients, mit einer Persistenz, die nur aus „der Client schreibt deine globalen Tabellen in eine Datei“ besteht. Wenn du noch nie eins geschrieben hast, ist dieser Beitrag eine Führung. Wenn doch, findest du vielleicht trotzdem ein paar Muster zum Klauen.

## Was Level Time macht und für wen

Level Time erfasst Spielzeit, XP pro Stunde, Kills, Tode, Quests und Gold für dein **aktuelles Level**, deine **aktuelle Session** und die **Instanz**, in der du bist. Dazu gibt es eine Historie über jedes Level, jede Session und jeden Lauf aller deiner Charaktere. So lässt sich beantworten: „Wie lange hat Level 34 gedauert, und war das schneller als bei meinem letzten Charakter?“

![Level Time im Layout „Kacheln“: ein Raster aus Statistik-Kacheln mit Spielzeit, XP pro Stunde, Kills und Toden](/img/level-time/lt-tiles.png)

*Das Layout „Kacheln“. Level Time hat insgesamt sieben Layouts.*

Drei Gruppen sind die Hauptzielgruppe:

- **Leveler**, die wissen wollen, ob ihre Route wirklich effizient ist. Für sie sind XP/h, Zeit bis zum Level-Up und die Historien-Diagramme gedacht.
- **Speedrunner**, die LiveSplit-artige Splits pro Level, den Vergleich mit der persönlichen Bestzeit und einen Export nach LiveSplit wollen.
- **Streamer**, die Anzeigen brauchen, die im Stream gut aussehen: ein Layout nur mit Text ohne Hintergrund, einen Chroma-Key-Hintergrund für OBS, verborgene Namen und eine Recap-Karte.

Alles ist konfigurierbar, die meisten Extras sind standardmäßig aus, und das Addon läuft mit einem Download auf Retail, Classic Era, TBC Anniversary und WoW Forever. Es wird aktiv weiterentwickelt; ich beschreibe den Stand des Repositorys beim Schreiben, kein fertiges Produkt.

## Wie ein WoW-Addon funktioniert

Wer Browser-Erweiterungen oder Spiele-Mods kennt, findet das Modell vertraut, nur mit ein paar ungewöhnlichen Einschränkungen.

### Die TOC-Datei

Ein Addon ist ein Ordner unter `Interface/AddOns/`. Zwingend nötig ist nur eine `.toc`-Datei, die wie der Ordner heißt. Sie ist ein einfaches Textmanifest, beschrieben in der [TOC-Format-Referenz](https://warcraft.wiki.gg/wiki/TOC_format). Oben stehen Metadaten als `## Schlüssel: Wert`, danach die Liste der zu ladenden Dateien, **in genau dieser Reihenfolge**. Hier der Anfang der TOC von Level Time (gekürzt):

```text
## Interface: 120105, 11509, 20506, 16001
## Title: Level Time
## Notes: Statistics per level and per session ...
## SavedVariables: LevelTimerDB, LevelTimerStatsDB, LevelTimerDebugLog
## SavedVariablesPerCharacter: LevelTimerCharDB

Locales\Core.lua
Locales\enUS.lua
Lib\Migrate.lua
Core\Database.lua
Lib\Lifecycle.lua
Core\LevelTimer.lua
Core\Client.lua
...
Tracking\Stats.lua
```

Es gibt kein Modulsystem, kein `require`, keinen Bundler. Die Ladereihenfolge in der TOC **ist** der Abhängigkeitsgraph. Benutzt Datei B etwas aus Datei A, muss A davor stehen, und wer eine neue Datei nicht in die TOC einträgt, bekommt sie stillschweigend nie geladen. Was das für die Struktur bedeutet, kommt weiter unten.

### Alles teilt sich einen Namensraum

Jede Datei wird mit zwei versteckten Argumenten ausgeführt: dem Addon-Namen und einer Tabelle, die alle Dateien dieses Addons teilen. Diese Tabelle ist der vorgesehene Weg, Code zu teilen, ohne die globale Umgebung zu verschmutzen:

```lua
-- first line of nearly every file in the addon
local _, ns = ...

local Stats = {}
ns.Stats = Stats          -- now every later file can use ns.Stats
```

Das ist das ganze Modulsystem. `ns.Stats`, `ns.Journal`, `ns.Format` und so weiter sind nur Tabellen an einer gemeinsamen Tabelle. Level Time macht diese Tabelle außerdem global als `LevelTimerAPI` verfügbar, womit das Schwester-Addon aus [Teil 4](/de/blog/level-time-4-goals-public-api/) arbeitet.

### Events statt Threads

Das Spiel führt deinen Lua-Code in **einem Thread** aus, innerhalb seiner eigenen Frame-Schleife. Es gibt keine Threads, kein `sleep`, kein blockierendes I/O. Alles Langlaufende friert die gesamte Spieloberfläche ein, also ist die Arbeitseinheit ein kleiner Callback.

Ausgelöst werden Callbacks durch **Events**. Du erzeugst einen versteckten *Frame* (das UI-Primitiv, das Events empfangen kann), registrierst die Event-Namen, die dich interessieren, und setzt ein `OnEvent`-Skript. Die [Event-Liste](https://warcraft.wiki.gg/wiki/Events) im Wiki ist dein Freund; `PLAYER_XP_UPDATE`, `PLAYER_LEVEL_UP`, `PLAYER_DEAD` und `TIME_PLAYED_MSG` sind die, von denen Level Time lebt.

Für periodische Arbeit gibt es das `OnUpdate`-Skript ([Referenz](https://warcraft.wiki.gg/wiki/UIHANDLER_OnUpdate)), das **in jedem gerenderten Frame** mit der vergangenen Zeit feuert. Bei 144 FPS sind das 144 Aufrufe pro Sekunde, also gilt: In `OnUpdate` nichts tun, solange keine Drosselung sagt, dass es Zeit ist.

### SavedVariables

Die Persistenz ist herrlich grob. Du deklarierst globale Variablennamen in der TOC; der Client lädt sie vor `PLAYER_LOGIN` aus einer Datei und schreibt sie beim Logout oder `/reload` zurück:

```lua
-- Variables listed in "## SavedVariables" are plain globals.
-- They are nil on the very first run, so always default them.
LevelTimerDB = LevelTimerDB or {}
```

Die Details stehen im Wiki: [Variablen zwischen Spielsitzungen speichern](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions). Zwei Folgen sind für das Design wichtig:

1. Die **gesamte Tabelle wird serialisiert** bei jedem Logout und geparst bei jedem Login. Größe ist Ladezeit.
2. Es gibt kein Schema, keine Transaktion, keine Versionierung. Änderst du das Datenlayout, schreibst **du** die Migration.

Beides hat Level Time geprägt, wie die Abschnitte zum Journalarchiv und zu den Migrationen zeigen.

### Lua 5.1 und die Sandbox

Der Client bettet Lua 5.1 ein ([Handbuch](https://www.lua.org/manual/5.1/)), mit eingeschränkter Standardbibliothek und einer großen API obendrauf, dokumentiert auf [warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API). Neuere Retail-Versionen verbergen außerdem manche Werte komplett vor Addons („Secret Values“), dazu mehr im Multi-Client-Abschnitt.

## Das Modullayout

Das Repository ist nach Fachgebieten gegliedert, nicht nach technischen Schichten:

| Ordner | Aufgabe |
| --- | --- |
| `Locales/` | Texte in Englisch, Deutsch, Französisch und Spanisch |
| `Core/` | Datenbank, Client-Erkennung, Slash-Befehle, Profiler, Debug-Werkzeuge |
| `Lib/` | fachfreie Helfer: Formatierung, Serializer, Widgets, der Event-/Lifecycle-Kern |
| `Tracking/` | Zähler und Event-Erzeuger: Kills, Tode, Quests, Geld, XP, Beute, das Journal |
| `History/` | Levelhistorie, Analyse, Prognose, Ziele, persönliche Rekorde |
| `Speedrun/` | Läufe, Splits, Rekorde, LiveSplit-Export |
| `Assist/` | optionale Komfortfunktionen, Erinnerungen, Warnungen |
| `UI/` | Fenster, Stat-Zeilen, Hinweise, Optionen, Layouts |

Weil die TOC-Reihenfolge die Abhängigkeitsreihenfolge ist, entscheiden die Ordner nicht darüber, was wovon abhängen darf; das tut die Disziplin. Meine Regel ist dieselbe wie in meinem Beitrag zu [Bounded Contexts](/de/blog/bounded-context/): Datenmodule wissen nichts von der UI, und UI-Module fragen Datenmodule nach Werten, nie umgekehrt.

{{< diagram src="level-time-1-dataflow.svg" caption="Von Client-Events bis zu den Pixeln. Durchgezogene Pfeile schieben Daten vorwärts, gestrichelte sind lesender Zugriff. Die UI bekommt keine geschobenen Updates, sie fragt Getter ab." >}}

### Der Kern: ein Event-Frame, viele Listener

Die wichtigste Datei ist `Lib/Lifecycle.lua`. Statt dass jedes Modul einen eigenen Frame anlegt, gibt es **einen** Event-Frame und eine Registry davor. Module rufen `ns.RegisterEvent(event, handler)` auf, und beliebig viele Module können dasselbe Event abonnieren. Die Handler laufen in Registrierungsreihenfolge, also in TOC-Reihenfolge. Hier eine vereinfachte Version der Idee:

```lua
-- simplified from Lib/Lifecycle.lua
local eventFrame = CreateFrame("Frame")
local handlersByEvent = {}

function ns.RegisterEvent(event, handler)
  if not handlersByEvent[event] then
    -- pcall: a client that does not know this event throws, we return false instead
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
      return false
    end
    handlersByEvent[event] = {}
  end
  table.insert(handlersByEvent[event], handler)
  return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  for _, handler in ipairs(handlersByEvent[event]) do
    ns.SafeCall(handler, ...)
  end
end)
```

Zwei Details machen daraus mehr als einen bequemen Wrapper.

**Isolation.** `ns.SafeCall` packt jeden Handler, jeden Login-Callback und jede wiederkehrende Aufgabe in `xpcall`. Ein Fehler in einem Modul landet im Fehler-Handler des Clients (BugSack, das Standard-Fehlerfenster), und der nächste Handler läuft trotzdem. Bei einem Addon mit einigen hundert über die Zeit gewachsenen Dateien darf ein kaputtes Feature nicht den Level-Timer mitreißen.

**Portabilität.** Kennt ein Client ein Event nicht, wirft `RegisterEvent` einen Fehler. Der Wrapper macht daraus den Rückgabewert `false`, und das Feature, das das Event brauchte, bleibt einfach aus. Das ist der erste von mehreren Mechanismen des „leisen Abschaltens“ im Multi-Client-Abschnitt.

Für die anderen wiederkehrenden Bedürfnisse gibt es Geschwister dieser Funktion: `ns.RegisterUnitEvent` (`UNIT_AURA` nur für den Spieler statt für jede Namensplakette und jedes Gruppenmitglied), `ns.Every(seconds, fn, enabled)` (eine wiederkehrende Aufgabe auf **einem** gemeinsamen `OnUpdate`-Frame; Aufgaben, deren Feature aus ist, kosten nichts), `ns.OnLogin`, `ns.OnLogout` und ein Level-Up in zwei Phasen. Module registrieren `ns.RegisterApply(fn)`-Callbacks, die ihren Zustand aus der Einstellungstabelle neu aufbauen, sobald sich eine Einstellung ändert; deshalb wirkt ein Sprachwechsel sofort.

## Tracking: Zähler und ein Journal

`Tracking/` macht aus rohen Events zwei Arten von Daten.

**Zähler.** `Stats` führt jeden Zähler in *Bereichen* (Scopes). Ein Zähler existiert einmal für das aktuelle Level und einmal für die aktuelle Session, und `Stats.Increment` zählt immer in beiden. Der Instanz-Bereich funktioniert genauso für den Dungeon, in dem du bist. Ein Erzeuger wie der Kill-Zähler kennt die Bereiche nicht:

```lua
-- simplified from Tracking/KillCounter.lua
local function countKill(name, xp)
  local classification = Classification.Of(name)
  Stats.Increment(Stats.PVE_KILLS)
  Stats.Increment(Stats.XP_KILLS, xp or 0)
  if Classification.IsElite(classification) then
    Stats.Increment(Stats.ELITE_KILLS)
  end
  Journal.AddKill(name, classification, xp)
end
```

Die UI kann dann `Stats.Get(scope, counter)` fragen und per Tab zwischen „Level 34“, „Session“ und „Instanz“ wechseln, ohne dass sich ein Erzeuger ändert.

**Das Journal.** Zähler sagen, wie viele; das Journal sagt, *was*. Jeder Kill, Tod, jede Quest, jeder Beutegegenstand, Instanzlauf und Beinahe-Tod wird ein Eintrag mit Zeitstempel, Level und Zone. Die Tabellen und Diagramme des Historienfensters entstehen daraus.

Manche Erzeuger sind nicht trivial. Auf aktuellen Retail- und WoW-Forever-Clients ist der Kampflogtext für XP-Gewinne manchmal ein *Secret Value*: das Addon kann ihn weiterreichen, aber nicht lesen. Der Kill-Zähler wartet dann kurz, ordnet die Kill-Meldung nahen XP-Änderungen zu und verbucht einen Kill ohne Namen. Im Code ist das als Kompromiss dokumentiert: Die Summe stimmt, die Verteilung auf gleichzeitige Kills nicht.

## Historie: Schnappschüsse im richtigen Moment

`History/` verarbeitet Zähler und Journal. Das wichtigste Muster ist das **Level-Up in zwei Phasen**. Direkt auf `PLAYER_LEVEL_UP` zu hören, ließe jedes Modul raten, ob seine Werte schon zurückgesetzt sind. Stattdessen liefert der Kern:

1. `ns.OnLevelCompleted(fn(oldLevel))`, solange die alten Werte noch intakt sind,
2. dann wird `ns.level` aktualisiert,
3. dann `ns.OnLevelStarted(fn(newLevel))` für Rücksetzungen.

Das Historienmodul macht in Phase eins den Schnappschuss des beendeten Levels:

```lua
-- simplified from History/History.lua
ns.OnLevelCompleted(function(completedLevel)
  ns.character.levelHistory[completedLevel] = {
    level = completedLevel,
    seconds = Stats.GetSeconds(Stats.LEVEL),
    counters = Stats.Snapshot(Stats.LEVEL),
    completedAt = time(),
    totalPlayed = PlayedTime.GetTotalSeconds(),
  }
end)
```

Alles andere (Analyse-Reihen, Prognose bis zum Max-Level, persönliche Rekorde, Speedrun-Splits) wird aus `levelHistory`, dem Journal und den Zählern berechnet. Die Spielzeit pro Level stammt aus der `/played`-Antwort des Servers, weshalb ein mitten im Level installiertes Level Time trotzdem die richtige Zeit zeigt.

## UI: Abfragen schlägt Schieben

Datenmodule bieten Getter an; Fenster lesen sie. Das Hauptfenster bekommt nie „Wert X hat sich geändert“-Aufrufe. Stattdessen markiert jede Änderung es als schmutzig (dirty), und ein gedrosseltes `OnUpdate` zeichnet neu:

```lua
-- simplified from UI/TimerWindow.lua
local UPDATE_INTERVAL = 0.25
local dirty, sinceUpdate = true, 0

Stats.OnIncrement(function() dirty = true end)
ns.RegisterEvent("PLAYER_XP_UPDATE", function() dirty = true end)

ns.SetUpdateScript(window, "TimerWindow", function(_, elapsed)
  sinceUpdate = sinceUpdate + elapsed
  if sinceUpdate < UPDATE_INTERVAL then return end
  sinceUpdate = 0
  if dirty or secondChanged() then
    dirty = false
    refresh()
  end
end)
```

Vier Prüfungen pro Sekunde, ein Neuzeichnen nur, wenn sich etwas geändert hat oder eine Sekunde vergangen ist (der Spielzeit-Zähler), und Text wird nur gesetzt, wenn er sich unterscheidet. Eine Event-Flut bei einem großen Pull kostet jeweils einen Flag-Schreibzugriff, nicht jeweils einen Layout-Durchlauf.

Die sieben Layouts (Tabelle, Leiste, kompakt, nur Text, Uhr, XP-Balken, Kacheln) sind in einer kleinen Registry angemeldet (`Layouts.Register(id, { Build, Render, Measure })`). `Build` läuft nur bei geänderter Struktur, `Render` bei jedem Takt und meldet, ob sich ein Text geändert hat. Ein neues Layout ist eine Datei, und die Stat-Zeilen sind eine gemeinsame Liste (`ns.STAT_LINES`), aus der sowohl die Fensterzeilen als auch die Options-Schalter erzeugt werden.

![Das kompakte Layout von Level Time: Spielzeit, XP-Balken und einige gewählte Werte](/img/level-time/lt-compact.png)

*Kompakt: Zeit, XP-Balken und bis zu drei Werte deiner Wahl.*

![Das Layout „nur Text“: umrandeter Text ohne Fensterhintergrund](/img/level-time/lt-text-only.png)

*Nur Text: ohne Hintergrund, mit Umrandung. Gemacht für Stream-Overlays.*

![Das horizontale Infoleisten-Layout von Level Time](/img/level-time/lt-horizontal-bar.png)

*Die einzeilige Infoleiste. Manche Screenshots dieser Serie zeigen Fenster aus der Zeit vor dem neuesten Release.*

## Das Journalarchiv: ein Load-on-Demand-Addon

Hier das Problem, das das SavedVariables-Design erzeugt. Ein lange gespielter Charakter sammelt ein Journal aus Kills, Toden, Beute und Quests, das zehntausende Einträge erreichen kann (der Code begrenzt Kills auf 250.000), und ohne Archiv sind alle davon Lua-Tabellen in `LevelTimerStatsDB`. Alles in einer SavedVariable wird beim **Login** geparst und beim **Logout** serialisiert, egal ob du je die Historie öffnest. Für ein Feature, das die meisten Spieler selten öffnen, ist das ein schlechter Tausch.

WoW hat dafür genau ein Feature: **Load-on-Demand-Addons**. Eine TOC mit `## LoadOnDemand: 1` wird beim Login nicht geladen. Ihre Dateien **und ihre SavedVariables** werden erst gelesen, wenn anderer Code `LoadAddOn` aufruft ([`C_AddOns.LoadAddOn`](https://warcraft.wiki.gg/wiki/API_C_AddOns.LoadAddOn)). Der Client schreibt die Datei außerdem nur in Sitzungen zurück, in denen das Addon geladen war. Level Time liefert deshalb ein zweites, winziges Addon mit:

```text
## Title: Level Time (Archive)
## Dependencies: LevelTimer
## LoadOnDemand: 1
## SavedVariables: LevelTimerArchiveDB

Archive.lua
```

`Archive.lua` enthält keinerlei Logik; die Datei existiert nur, damit der Client etwas hat, woran er die SavedVariable hängen kann. Die Logik steckt im Hauptaddon (`Tracking/JournalArchive.lua`). Das Design in Kürze:

- Neue Journaleinträge landen in einem **Eingang** (Inbox) in den normalen Charakterdaten. Konstanten im Code: `INBOX_MAX = 3000`, `KEEP_RECENT = 500`.
- Beim Login wird das Archiv-Addon geladen, wenn ein Eingang mehr als `INBOX_MAX` Einträge hat, und alles bis auf die neuesten `KEEP_RECENT` Einträge je Log zieht dorthin um. Auch das Öffnen des Historienfensters (oder eines Diagramms, das Archiveinträge liest) lädt es. Danach bleibt es für die Sitzung geladen.
- Archivierte Einträge speichert `RecordCodec` kompakt: eine Textzeile pro Eintrag mit den Feldern in fester Reihenfolge, Zeichenketten (Namen, Zonen, Item-Links) einmal in einem Wörterbuch pro Charakter und in der Zeile nur als Nummer. Der Kommentar im Quelltext nennt für eine Kill-Zeile rund 30 Byte statt 100 bis 150 als Lua-Tabelle; ich habe das nicht unabhängig nachgemessen.
- Fehlt das Archiv-Addon oder ist es deaktiviert, schlägt das Laden einmal fehl, der Zustand wird `unavailable`, und alles bleibt im Eingang. Der Eingang ist begrenzt (`INBOX_LIMIT = 20000` plus etwas Spielraum), damit er nicht ewig wächst.

```lua
-- simplified from Tracking/JournalArchive.lua
local function loadAddOn(name)
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if not load then return false end
  local ok, loaded = pcall(load, name)
  return ok and loaded and true or false
end
```

Beachte den Fallback `C_AddOns.LoadAddOn` oder `LoadAddOn`: Neuere Clients haben die Funktion in einen Namensraum verschoben, ältere kennen nur die globale. Dieses Muster begegnet dir ständig.

Das Ergebnis: Login und Logout kosten gleich viel, egal wie groß die Historie wird, und wer das Journal nie öffnet, zahlt auch nie dafür.

{{< diagram src="level-time-1-layout.svg" caption="Eine TOC-Zeile bedient vier Clients. Das Archiv ist ein zweiter Addon-Ordner: nur Speicher, bei Bedarf geladen, mit eigener SavedVariable." >}}

## Ein Download, vier Clients

Retail, Classic Era, TBC Anniversary und WoW Forever unterscheiden sich in der API-Verfügbarkeit, in UI-Vorlagen und sogar darin, welche Werte Addons lesen dürfen. Level Time liefert **nicht** vier Builds aus, sondern nutzt drei Mechanismen.

**1. Eine TOC mit mehreren Interface-Versionen.** Die Zeile `## Interface: 120105, 11509, 20506, 16001` nennt je Client eine Interface-Nummer; der Client lädt das Addon, wenn seine eigene Nummer in der Liste steht. Die Dateiliste ist für alle gleich. Die Interface-Nummern kommen aus [`GetBuildInfo`](https://warcraft.wiki.gg/wiki/API_GetBuildInfo), dessen vierter Rückgabewert dieselbe Nummer ist.

**2. Client-Erkennung aus dieser Nummer.** `Core/Client.lua` hat gut fünfzig Zeilen:

```lua
-- simplified from Core/Client.lua
function Client.GetInterfaceVersion()
  return select(4, GetBuildInfo())
end

function Client.IsForever()
  local version = Client.GetInterfaceVersion()
  return version >= 16000 and version <= 16999
end

function Client.IsRetail()
  return Client.GetInterfaceVersion() >= 100000
end
```

Das braucht man für Features, die es nur in einem Client gibt. Die Timer für Lagerfeuer und Schlafsack sind zum Beispiel WoW-Forever-Features: Ihre Optionen erscheinen in den anderen Clients gar nicht. Die Paketierung nutzt dieselbe Zuordnung, sodass Code und Release übereinstimmen.

**3. Feature-Erkennung für alles andere.** Die meisten Unterschiede lauten nicht „welcher Client ist das“, sondern „existiert diese Funktion“. Der Code fragt die API statt der Version:

```lua
-- simplified from Tracking/Experience.lua
local function isAtMaxLevel()
  if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
    return GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
  end
  if IsPlayerAtEffectiveMaxLevel then
    return IsPlayerAtEffectiveMaxLevel()
  end
  return GetMaxPlayerLevel ~= nil and ns.level >= GetMaxPlayerLevel()
end
```

Drei Clients, drei Wege, dieselbe Frage zu stellen, eine Funktion. Dieselbe Idee deckt Events ab (`RegisterEvent` gibt `false` zurück), Unit-Events (`RegisterUnitEvent` nutzen, wenn der Frame es hat, sonst manuell filtern) und Secret Values (`issecretvalue` wird geprüft, bevor ein Wert verglichen wird). Reparaturen über die Gildenbank prüfen die API (`CanGuildBankRepair`) **und** den Client.

Die ehrliche Kehrseite: Nichts prüft das automatisch für mich. Mein Test-Harness (Thema von [Teil 2](/de/blog/level-time-2-testing-lua-with-go/)) fälscht die API und kann das Addon als verschiedene Clients laden, aber er prüft Logik, nicht ob eine Funktion in einem Client wirklich existiert. Tests im Spiel auf jedem Client bleiben nötig, und das Projekt führt dafür eine manuelle Checkliste.

## SavedVariables-Schema und Migrationen

Da der Client mir kein Schema gibt, habe ich ein minimales gebaut. `Lib/Migrate.lua` hat 33 Zeilen:

```lua
-- simplified from Lib/Migrate.lua
function Migrate.Run(data, migrations, targetVersion)
  local version = data.schemaVersion or 1
  if version >= targetVersion then return end
  for nextVersion = version + 1, targetVersion do
    if migrations[nextVersion] then
      migrations[nextVersion](data)
    end
  end
  data.schemaVersion = targetVersion
end

function Migrate.ApplyDefaults(data, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(data[key]) ~= "table" then data[key] = {} end
      Migrate.ApplyDefaults(data[key], value)
    elseif data[key] == nil then
      data[key] = value
    end
  end
  return data
end
```

Jede gespeicherte Tabelle trägt eine `schemaVersion`; eine Tabelle von Migrationen ist nach *Zielversion* geschlüsselt. Es gibt getrennte Versionslinien für die Account-Einstellungen (`LevelTimerDB`, derzeit Schema 7) und die Statistiken je Charakter (`LevelTimerStatsDB`, derzeit Schema 5). `ApplyDefaults` ergänzt danach alles, was noch fehlt, weshalb eine ganz neue Einstellung gar keine Migration braucht.

Zwei Entscheidungen verdienen eine Erklärung:

- **Die Version sinkt nie.** Nach einem Downgrade auf eine ältere Addon-Version würde eine nicht wiederholbare Migration beim nächsten Upgrade sonst ein zweites Mal laufen.
- **Ein defekter Charakter darf den Rest nicht blockieren.** Beim Login wird jeder gespeicherte Charakter innerhalb von `xpcall` migriert; ein Fehler wird gemeldet und der Eintrag übersprungen, die anderen laden normal.

Ein Beispiel, wie eine Migration in der Praxis aussieht: Version 2 machte aus einer alten absoluten Einstellung `fontSize` die relative `scale`, angewendet auf die Einstellungen *und* auf jede gespeicherte Profilkopie.

Die Daten liegen an drei Orten: `LevelTimerDB` (Account-Einstellungen und Profile), `LevelTimerStatsDB` (Statistiken, ein Eintrag je `Name-Realm`) und die Archivdatei. Eine vierte Variable, `LevelTimerCharDB`, ist ein veralteter Speicher pro Charakter, der nur noch einmal gelesen wird, um alte Daten in die accountweite Tabelle zu übernehmen.

## Performance-Regeln, die ich auf die harte Tour gelernt habe

Ein Addon teilt sich das Frame-Budget mit dem Spiel und mit jedem anderen Addon. Die Regeln in den Entwicklernotizen von Level Time stammen alle aus echten Profilen, nicht aus Theorie:

- **Kein eigenes `OnUpdate` je Modul.** `ns.Every` bündelt alle Hintergrundaufgaben auf einem Frame, und eine Aufgabe kann ein `enabled`-Prädikat tragen, damit ein ausgeschaltetes Feature nichts kostet.
- **Schmale Event-Abonnements.** `UNIT_*`-Events laufen über `RegisterUnitEvent` nur für den Spieler. Sehr häufige Events (das Kampflog) bekommen einen eigenen Frame mit der billigsten Vorabprüfung zuerst.
- **Pro Takt zwischenspeichern.** Mehrere Zeilen eines Fensters fragen im selben Refresh denselben teuren Wert ab (Prognose, XP-Quellen). `TickCache.Memo` rechnet ihn einmal je Takt und vergisst ihn danach.
- **Kein Müll in heißen Pfaden.** `ns.SafeCall` vermeidet eine Closure je Aufruf; Text wird nur gesetzt, wenn er sich unterscheidet.
- **Messen.** `/lt debug perf` schaltet einen eingebauten Profiler ein, der Gesamtzeit, Aufrufzahl und Maximum je Handler, Aufgabe, Listener und Fenster-`OnUpdate` meldet. Der Trick: Ausgeschaltet kostet er nichts, denn das Einschalten tauscht die Verteiler gegen gemessene Varianten aus und das Ausschalten wieder zurück.

Benchmark-Zahlen habe ich hier bewusst nicht veröffentlicht; der Profiler existiert, damit jeder, ich eingeschlossen, auf dem eigenen Rechner messen kann.

## Was ich anders machen würde

- **Die TOC als Abhängigkeitsgraph ist fragil.** Eine vergessene Zeile ist ein stiller Fehler, und beim Verschieben von Dateien ist ein Client-Neustart nötig. Ein Test, der Dateien in TOC-Reihenfolge lädt (was mein Harness tut), fängt das erste Problem ab.
- **Dirty-Flag-Polling ist einfach, aber nicht gratis.** Für ein Fenster mit 20 Zeilen ist es richtig. Für ein hochfrequentes Overlay würde ich anders bündeln.
- **Feature-Erkennung streut.** `if Foo and Foo.Bar` landet in vielen Dateien. Die wiederkehrenden hinter kleine Helfer zu legen (wie `Client.lua` und `Auras.lua`) zahlt sich jedes Mal aus.

## Wie es weitergeht

Ein Addon mit so vielen beweglichen Teilen und vier Client-Varianten lässt sich nicht durch Herumklicken testen. In [Teil 2](/de/blog/level-time-2-testing-lua-with-go/) zeige ich, wie ich das ganze Addon samt TOC-Reihenfolge in einem Go-Test mit gopher-lua und einer nachgebauten WoW-API laufen lasse, einschließlich Layout-Tests in vier Sprachen.

Wenn du das Addon einfach ausprobieren willst: Die [Level-Time-Seite](/de/page/level-time/) hat Screenshots und Installationslinks, und der Code liegt auf [GitHub](https://github.com/Noobygames/wow-statistics).
