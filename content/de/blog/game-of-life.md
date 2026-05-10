---
title: "Conways Game of Life in Go: Eine Schritt-für-Schritt-Anleitung"
date: 2023-03-16
draft: false
toc: true
description: "Conways Game of Life in Go von Grund auf implementieren — Gitter-Logik, toroidales Wrapping, Terminal-Rendering und eine funktionierende Haupt-Schleife mit zwei klassischen Mustern."
images: ["img/game_of_life.png"]
featured_image: "img/game_of_life.png"
tags: ["go", "golang", "tutorial", "game-of-life", "beginner"]
show_reading_time: true
---

[Conways Game of Life](https://de.wikipedia.org/wiki/Conways_Spiel_des_Lebens) ist ein berühmter zellulärer Automat, den der britische Mathematiker John Horton Conway 1970 erdacht hat. Es ist ein Nullspieler-Spiel: Du legst einen Ausgangszustand fest und beobachtest, wie er sich nach festen Regeln weiterentwickelt — ohne weitere Eingaben. Trotz seiner einfachen Regeln erzeugt es überraschend komplexe, lebensähnliche Muster.

In diesem Post implementieren wir Game of Life in Go von Grund auf, Schritt für Schritt. Am Ende hast du eine funktionierende Terminal-Simulation, die einen **Gleiter** und ein **Leichtes Raumschiff (LWSS)** in Echtzeit rendert.

![Conways Game of Life Simulation im Go-Terminal](/img/game-of-live.gif)

## Voraussetzungen

Du brauchst [Go](https://go.dev/dl/) auf deinem Rechner. Die Standardbibliothek reicht vollständig aus — keine Drittanbieter-Pakete benötigt.

**Linux / macOS:**

```bash
# Installation prüfen
go version
```

**Windows (PowerShell):**

```powershell
# Installation prüfen
go version
```

Wenn `go version` etwas wie `go version go1.22 linux/amd64` ausgibt, bist du startklar. Falls nicht, folge der [offiziellen Installationsanleitung](https://go.dev/doc/install).

Erstelle eine neue Datei namens `main.go` in einem leeren Verzeichnis und folge der Anleitung.

## Regeln

Das Game of Life folgt vier Regeln, die für jeden Schritt gleichzeitig auf alle Zellen des Gitters angewendet werden:

1. Eine **lebende Zelle** mit weniger als zwei lebenden Nachbarn stirbt — _Unterbevölkerung_.
2. Eine **lebende Zelle** mit zwei oder drei lebenden Nachbarn überlebt.
3. Eine **lebende Zelle** mit mehr als drei lebenden Nachbarn stirbt — _Überbevölkerung_.
4. Eine **tote Zelle** mit genau drei lebenden Nachbarn wird lebendig — _Reproduktion_.

Mehr braucht es nicht. Der Rest ergibt sich aus dem Ausgangszustand.

## Implementierung

Wir unterteilen die Implementierung in fünf überschaubare Schritte.

### 1. Datenstrukturen definieren

`Cell` ist ein einfacher Boolean — lebendig oder tot. `Grid` hält die Dimensionen und ein zweidimensionales Slice von Zellen.

```go
type Cell bool

type Grid struct {
    Width  int
    Height int
    Cells  [][]Cell
}
```

### 2. Das Gitter initialisieren

`NewGrid` allokiert das zweidimensionale Slice und setzt die anfänglich lebenden Zellen an den angegebenen Koordinaten.

```go
func NewGrid(width, height int, initialLiveCells [][2]int) Grid {
    cells := make([][]Cell, height)
    for i := range cells {
        cells[i] = make([]Cell, width)
    }

    for _, coord := range initialLiveCells {
        x, y := coord[0], coord[1]
        cells[y][x] = true
    }

    return Grid{Width: width, Height: height, Cells: cells}
}
```

### 3. Die Spiellogik implementieren

`NextState` berechnet die nächste Generation. Wir allokieren ein neues Slice, damit wir nie denselben Zustand gleichzeitig lesen und schreiben — ein klassischer Fehler bei Game-of-Life-Implementierungen.

```go
func (g *Grid) NextState() {
    newCells := make([][]Cell, g.Height)
    for i := range newCells {
        newCells[i] = make([]Cell, g.Width)
    }

    for y := 0; y < g.Height; y++ {
        for x := 0; x < g.Width; x++ {
            liveNeighbors := g.countLiveNeighbors(x, y)

            if g.Cells[y][x] && (liveNeighbors == 2 || liveNeighbors == 3) {
                newCells[y][x] = true
            } else if !g.Cells[y][x] && liveNeighbors == 3 {
                newCells[y][x] = true
            }
        }
    }

    g.Cells = newCells
}
```

`countLiveNeighbors` prüft die acht umgebenden Zellen. Der `%`-Operator erzeugt ein **toroidales Gitter** — Zellen, die eine Kante verlassen, erscheinen auf der gegenüberliegenden Seite wieder, sodass die Simulation keine Randeffekte hat.

```go
func (g *Grid) countLiveNeighbors(x, y int) int {
    count := 0
    for i := -1; i <= 1; i++ {
        for j := -1; j <= 1; j++ {
            if i == 0 && j == 0 {
                continue
            }

            // Wrapping: (x + offset + Width) % Width hält den Wert in [0, Width)
            x2 := (x + i + g.Width) % g.Width
            y2 := (y + j + g.Height) % g.Height

            if g.Cells[y2][x2] {
                count++
            }
        }
    }
    return count
}
```

### 4. Das Gitter rendern

`Render` gibt das Gitter im Terminal aus. Lebende Zellen erscheinen als `█`, tote als Leerzeichen. Die ANSI-Escape-Sequenz `\033[H` bewegt den Cursor vor jedem Frame in die obere linke Ecke — das verhindert, dass die Ausgabe scrollt, und erzeugt einen flüssigen Animationseffekt.

```go
func (g *Grid) Render() {
    // Cursor an den Anfang bewegen, ohne zu löschen (verhindert Flackern)
    fmt.Print("\033[H")
    for y := 0; y < g.Height; y++ {
        for x := 0; x < g.Width; x++ {
            if g.Cells[y][x] {
                fmt.Print("█")
            } else {
                fmt.Print(" ")
            }
        }
        fmt.Println()
    }
}
```

### 5. Die Haupt-Schleife aufsetzen

Wir befüllen das Gitter mit zwei bekannten Mustern — einem **Gleiter** (bewegt sich diagonal) und einem **Leichten Raumschiff (LWSS)** (bewegt sich horizontal) — und lassen die Simulation endlos laufen.

```go
func main() {
    initialLiveCells := [][2]int{
        // Gleiter — bewegt sich diagonal
        {1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2},

        // Leichtes Raumschiff (LWSS) — bewegt sich horizontal
        {10, 2}, {11, 2}, {12, 2}, {13, 2},
        {9, 3}, {13, 3},
        {13, 4},
        {9, 5}, {12, 5},
    }

    // Terminal einmalig zu Beginn leeren
    fmt.Print("\033[2J")

    grid := NewGrid(40, 20, initialLiveCells)
    for {
        grid.Render()
        grid.NextState()
        time.Sleep(100 * time.Millisecond)
    }
}
```

## Vollständiger Code

Speichere dies als `main.go`:

```go
package main

import (
    "fmt"
    "time"
)

type Cell bool

type Grid struct {
    Width  int
    Height int
    Cells  [][]Cell
}

func NewGrid(width, height int, initialLiveCells [][2]int) Grid {
    cells := make([][]Cell, height)
    for i := range cells {
        cells[i] = make([]Cell, width)
    }
    for _, coord := range initialLiveCells {
        x, y := coord[0], coord[1]
        cells[y][x] = true
    }
    return Grid{Width: width, Height: height, Cells: cells}
}

func (g *Grid) NextState() {
    newCells := make([][]Cell, g.Height)
    for i := range newCells {
        newCells[i] = make([]Cell, g.Width)
    }
    for y := 0; y < g.Height; y++ {
        for x := 0; x < g.Width; x++ {
            liveNeighbors := g.countLiveNeighbors(x, y)
            if g.Cells[y][x] && (liveNeighbors == 2 || liveNeighbors == 3) {
                newCells[y][x] = true
            } else if !g.Cells[y][x] && liveNeighbors == 3 {
                newCells[y][x] = true
            }
        }
    }
    g.Cells = newCells
}

func (g *Grid) countLiveNeighbors(x, y int) int {
    count := 0
    for i := -1; i <= 1; i++ {
        for j := -1; j <= 1; j++ {
            if i == 0 && j == 0 {
                continue
            }
            x2 := (x + i + g.Width) % g.Width
            y2 := (y + j + g.Height) % g.Height
            if g.Cells[y2][x2] {
                count++
            }
        }
    }
    return count
}

func (g *Grid) Render() {
    fmt.Print("\033[H")
    for y := 0; y < g.Height; y++ {
        for x := 0; x < g.Width; x++ {
            if g.Cells[y][x] {
                fmt.Print("█")
            } else {
                fmt.Print(" ")
            }
        }
        fmt.Println()
    }
}

func main() {
    initialLiveCells := [][2]int{
        {1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2},
        {10, 2}, {11, 2}, {12, 2}, {13, 2},
        {9, 3}, {13, 3},
        {13, 4},
        {9, 5}, {12, 5},
    }
    fmt.Print("\033[2J")
    grid := NewGrid(40, 20, initialLiveCells)
    for {
        grid.Render()
        grid.NextState()
        time.Sleep(100 * time.Millisecond)
    }
}
```

## Das Programm starten

**Linux / macOS:**

```bash
go run main.go
```

**Windows (PowerShell):**

```powershell
go run main.go
```

Mit `Ctrl+C` beendest du die Simulation. Du solltest den Gleiter und das LWSS-Muster quer durch das Terminal wandern sehen.

## Wie es weitergeht

- Probiere andere Startmuster — die [LifeWiki](https://conwaylife.com/wiki/) katalogisiert tausende davon.
- Ersetze `fmt.Print` durch eine Terminal-Bibliothek wie [tcell](https://github.com/gdamore/tcell) oder [bubbletea](https://github.com/charmbracelet/bubbletea) für Farben und Tastatureingaben.
- Wenn dich das Containerisieren von Go-Anwendungen interessiert, schau in meinen Artikel über [Go und Docker](/de/blog/go-docker/).
