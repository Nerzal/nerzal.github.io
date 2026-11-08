---
title: "Level Time & Level Time Goals"
seo_title: "Level Time: WoW-Leveling-Tracker & Speedrun-Addon"
date: 2026-11-08T07:00:00+01:00
draft: false
toc: true
description: "Level Time ist ein kostenloses WoW-Addon für Level-Statistiken, XP pro Stunde, Speedrun-Splits und Stream-Tools. Dazu Level Time Goals für Stream-Ziele."
metric: "2 Addons · Retail, Classic & mehr"
featured_image: "img/level-time/logo.png"
images: ["img/level-time/logo.png"]
---


**Level Time** ist ein World-of-Warcraft-Addon, das zeigt, wie dein Leveln wirklich läuft: Spielzeit, XP pro Stunde, Kills, Tode, Quests und Gold für dein aktuelles Level, deine aktuelle Sitzung und die Instanz, in der du gerade bist, samt Verlauf für alle deine Charaktere. Ich entwickle es als „Nerzal“ im Spiel und als Open-Source-Projekt auf [GitHub](https://github.com/Noobygames/wow-statistics). Das Begleit-Addon **Level Time Goals** zeigt Ziele als Karten auf deinem Bildschirm. Beide sind kostenlos auf CurseForge.

<div class="product-cta">
<strong>Download:</strong>
<a href="https://www.curseforge.com/wow/addons/level-time">Level Time auf CurseForge</a> ·
<a href="https://www.curseforge.com/wow/addons/streamer-goals">Level Time Goals auf CurseForge</a> ·
<a href="https://github.com/Noobygames/wow-statistics">Quellcode auf GitHub</a>
</div>

## Für wen ist Level Time?

- **Leveler**, die ihre echten XP pro Stunde, die Zeit bis zum nächsten Level und den Nutzen einzelner Zonen oder Aktivitäten kennen wollen.
- **Speedrunner**, die LiveSplit-artige Splits, Gold-Splits, einen Vergleich mit der persönlichen Bestzeit und einen LiveSplit-Export wollen.
- **Streamer**, die eine Overlay-taugliche Anzeige, einen Chroma-Key-Hintergrund für OBS, versteckte Namen und Ziele auf dem Bildschirm brauchen.

## Das Live-Fenster

Ein kleines, verschiebbares Fenster zeigt jeweils einen Bereich: das aktuelle Level, die Sitzung oder die Instanz. Die Spielzeit wird mit dem `/played` des Servers abgeglichen und stimmt daher auch, wenn du das Addon mitten im Level installierst. Jede Zeile lässt sich ein- oder ausschalten, und es gibt sieben Layouts: Tabelle, Infoleiste, kompakt, nur Text, Uhr, XP-Leiste und Kacheln.

![Level-Time-Kachel-Layout mit Leveling-Werten als Raster](/img/level-time/lt-tiles.png)

*Das Kachel-Layout.*

![Level-Time-Kompaktlayout mit Spielzeit, XP-Leiste und wenigen Werten](/img/level-time/lt-compact.png)

*Das kompakte Layout: Zeit, XP-Leiste und bis zu drei Werte deiner Wahl.*

![Level-Time-Layout nur Text ohne Hintergrund](/img/level-time/lt-text-only.png)

*Nur Text: ohne Hintergrund, mit Kontur, gemacht für Stream-Overlays.*

![Level-Time-Infoleiste als einzelne horizontale Zeile](/img/level-time/lt-horizontal-bar.png)

*Die Infoleiste zeigt alles in einer Zeile.*

![Schmale Level-Time-XP-Leiste](/img/level-time/lt-xp-bar.png)

*Eine schmale XP-Leiste, mit Text immer, beim Darüberfahren oder nie.*

Fährst du mit der Maus über die XP-Leiste, siehst du genaue Zahlen: aktuelle und benötigte XP, fehlende XP, Erholungs-XP und die XP abgabebereiter Quests.

![Level-Time-XP-Leisten-Tooltip mit genauen XP-Werten](/img/level-time/lt-xp-tooltip.png)

*Der Tooltip der XP-Leiste.*

Dazu kommen Themes, Schriften, Leistentexturen, Sichtbarkeitsregeln (zum Beispiel im Kampf oder auf Maximallevel ausgeblendet) und ein Bearbeitungsmodus (`/lt edit`), um jede Anzeige mit Raster und Einrasten zu platzieren.

## Verlauf und Diagramme

Den Verlauf öffnest du mit `/lt history` oder per Shift-Klick auf den Minimap-Button. Er listet Level, Sitzungen, Kills, Tode mit Ursache, Quests, Beute, Instanzen, Zonen, Ruf und Geld für jeden Charakter und zeigt Diagramme wie Zeit und XP/h pro Level, Kills pro Tag, Todesursachen und eine Heatmap, wann du spielst. Persönliche Rekorde, ein Charaktervergleich und CSV-Export sind dabei.

## Speedrun-Splits

Für Leveling-Runs gibt es eine LiveSplit-artige Split-Liste mit Gold-Splits, Vergleich mit deiner persönlichen Bestzeit oder deinen anderen Charakteren, einer Prognose für die nächste Spanne und speedrun.com-Rekorden als mitgelieferter Momentaufnahme. Du kannst eigene Splits setzen, Runs importieren und teilen und als `.lss` nach LiveSplit exportieren.

## Timer, Warnungen und Erinnerungen

Level Time zählt für Essen (Gut genährt), Lagerfeuer und Schlafsack-Erholung herunter und zeigt Flugzeiten an. Warnungen und Erinnerungen gibt es für seltene und Elite-Kills, epische Beute, fehlende Nahrung oder Klassenbuffs, volle Taschen, niedrige Haltbarkeit und Pausen. Das meiste davon ist standardmäßig aus; die Timer für Lagerfeuer und Schlafsack gibt es nur auf WoW Forever.

![Level-Time-Timer auf dem Bildschirm](/img/level-time/lt-timers.png)

*Timer auf dem Bildschirm.*

![Level-Time-Lagerfeuer-Countdown](/img/level-time/lt-camp-timer.png)

*Lagerfeuer-Countdown (WoW Forever).*

![Level-Time-Essens-Timer bis Gut genährt](/img/level-time/lt-eating-timer.png)

*Essens-Countdown bis Gut genährt.*

![Level-Time-Schlafsack-Erholungs-Countdown](/img/level-time/lt-sleeping-bag.png)

*Schlafsack-Countdown (WoW Forever).*

![Level-Time-Hinweiskarte zu einem fehlenden Buff](/img/level-time/lt-hints.png)

*Hinweise und Erinnerungen erscheinen als Karten.*

## Komfortfunktionen

Inspiriert von Leatrix Plus, aber mit eigenem Code und standardmäßig alles aus: Automatisierung (Reparieren, Müll verkaufen, Quests), Social- und Chat-Optionen, Oberflächen-Anpassungen, Blizzard-Fenster ausblenden, Flugzeiten und Zähler für Bedarf, Gier und Passen bei Beuteverteilung. Jede Änderung an Spieleinstellungen ist umkehrbar: Schaltest du eine Funktion aus, wird dein vorheriger Wert wiederhergestellt.

![Level-Time-Würfelzähler neben den Beute-Fenstern](/img/level-time/lt-rolls-example.png)

*Zähler für Beutewürfe.*

## Gemacht fürs Streaming

Der Stream-Modus (`/lt stream`) schaltet große Warnungen ein und versteckt Namen in einem Schritt. Ein Chroma-Key-Hintergrund hilft bei OBS, und eine Sitzungs-Zusammenfassung (`/lt recap`) fasst Zeit, Level, XP, Kills und Tode zusammen.

## Level Time Goals

**Level Time Goals** lässt dich Ziele für deinen Stream setzen und zeigt sie als Karten auf dem Bildschirm, damit Zuschauer sehen, woran du arbeitest und wie weit du bist. Wird ein Ziel erreicht, erscheint eine große Meldung. Es braucht Level Time, installiere also beide.

<img src="/img/level-time/goals-logo.png" alt="Level-Time-Goals-Logo" width="128" height="128">

Zieltypen sind unter anderem ein Level erreichen, Kills, Beute, Gold, Quests, Berufe, Erkundung, Bosse, Ruf, Schlachtfeld-Siege, Regeln, die scheitern können (etwa „kein Tod"), Checklisten und freier Text. Ziele können Fristen, tägliche oder wöchentliche Wiederholungen, Belohnungen und Punkte haben. Außerdem gibt es **Bingo** mit 3x3- oder 5x5-Karten, deren Felder sich selbst abhaken, oder ein **Glücksrad**, das dein nächstes Ziel auswählt. Mit `/sg` geht es los.

![Level-Time-Goals-Bingokarte](/img/level-time/goal-bingo.png)

*Eine Ziel-Bingokarte.*

## Unterstützte Spielversionen

Ein Download funktioniert auf Retail, Classic Era, TBC Anniversary und WoW Forever. Funktionen, die eine Spielversion nicht bieten kann, bleiben unauffällig aus. Retail und WoW Forever verbergen einige Werte vor Addons, daher sind manche Funktionen, etwa die Erkennung von Beinahe-Toden, dort nicht verfügbar. Die Oberfläche gibt es auf Deutsch, Englisch, Französisch und Spanisch.

## Download und Installation

1. Installiere über die CurseForge-App oder lade [Level Time](https://www.curseforge.com/wow/addons/level-time) und für Ziele [Level Time Goals](https://www.curseforge.com/wow/addons/streamer-goals) herunter.
2. Für eine manuelle Installation entpackst du die Ordner in das Verzeichnis `Interface/AddOns` deiner Spielversion. Unter Windows liegt es im World-of-Warcraft-Ordner, zum Beispiel `_retail_\Interface\AddOns`; unter Wine oder Linux ist es derselbe Pfad im WoW-Prefix.
3. Melde dich an und tippe `/lt` für die Einstellungen oder `/lt help` für die Befehle.

Fehler und Ideen gern als [GitHub-Issues](https://github.com/Noobygames/wow-statistics/issues).

## So ist es gebaut

Level Time ist ein Lua-Addon mit Go-Werkzeugen drumherum. Die vierteilige Serie erklärt die Technik:

1. [Addon-Architektur](/de/blog/level-time-1-addon-architecture/)
2. [Lua mit Go testen](/de/blog/level-time-2-testing-lua-with-go/)
3. [Die Release-Pipeline](/de/blog/level-time-3-release-pipeline/)
4. [Goals und die öffentliche API](/de/blog/level-time-4-goals-public-api/)
