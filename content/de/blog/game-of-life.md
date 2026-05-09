---
title: "Conways Game of Life in Go: Eine Schritt-für-Schritt-Anleitung"
date: 2023-03-16
draft: false
description: "Ein umfassendes Tutorial zur Implementierung von Conways Game of Life in Go – mit Grid-Logik, Terminal-Rendering und Nebenläufigkeit."
images: ["img/game-of-live.gif"]
tags: ["go", "game of life"]
---

## Einführung

[Conways Game of Life](https://de.wikipedia.org/wiki/Conways_Spiel_des_Lebens) ist ein berühmter zellulärer Automat, erdacht vom britischen Mathematiker John Horton Conway. Es ist ein Nullspieler-Spiel, das sich auf Basis seines Ausgangszustands weiterentwickelt und keine weiteren Eingaben des Spielers erfordert. Das Spiel findet auf einem unendlichen zweidimensionalen Gitter quadratischer Zellen statt, wobei jede Zelle entweder lebendig oder tot ist.

In diesem Blog-Post erkunden wir, wie man Conways Game of Life in Go implementiert. Wir bieten Schritt-für-Schritt-Anleitungen mit funktionierenden Code-Beispielen und detaillierten Erklärungen.

Beispiel:

![Alt-Text](/img/game-of-live.gif)


## Regeln

Das Game of Life folgt vier einfachen Regeln:

1. Eine lebende Zelle mit weniger als zwei lebenden Nachbarn stirbt (Unterbevölkerung).
2. Eine lebende Zelle mit zwei oder drei lebenden Nachbarn überlebt in die nächste Generation.
3. Eine lebende Zelle mit mehr als drei lebenden Nachbarn stirbt (Überbevölkerung).
4. Eine tote Zelle mit genau drei lebenden Nachbarn wird lebendig (Reproduktion).

Diese Regeln werden für jede Iteration gleichzeitig auf alle Zellen des Gitters angewendet, wodurch interessante Muster und Verhaltensweisen entstehen.

## Implementierung

Fangen wir mit der Implementierung des Game of Life in Go an. Wir unterteilen die Implementierung in folgende Schritte:

1. Datenstrukturen definieren
2. Das Spielgitter initialisieren
3. Die Spiellogik implementieren
4. Das Gitter rendern
5. Die Haupt-Schleife aufsetzen

### 1. Datenstrukturen definieren

Zunächst definieren wir die Datenstrukturen, die wir zur Darstellung des Gitters und der Zellen verwenden. Wir erstellen einen `Grid`-Typ, der die Dimensionen des Gitters und ein zweidimensionales Slice von `Cell`-Werten enthält.

```go
type Cell bool

type Grid struct {
    Width  int
    Height int
    Cells  [][]Cell
}
```

### 2. Das Spielgitter initialisieren

Als Nächstes erstellen wir eine Funktion, um das Spielgitter mit einem Ausgangszustand zu initialisieren. Die Funktion nimmt die Dimensionen des Gitters und ein Slice mit den Anfangskoordinaten der lebenden Zellen entgegen und gibt eine befüllte `Grid`-Instanz zurück.

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

Jetzt implementieren wir die Spiellogik, indem wir eine Funktion erstellen, die den nächsten Zustand des Gitters basierend auf dem aktuellen Zustand und den Regeln des Game of Life berechnet.

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
```

### 4. Das Gitter rendern

Wir erstellen eine Funktion, um das Gitter im Terminal darzustellen, wobei lebende Zellen als „X" und tote Zellen als Leerzeichen angezeigt werden.

```go
func (g *Grid) Render() {
    for y := 0; y < g.Height; y++ {
        for x := 0; x < g.Width; x++ {
            if g.Cells[y][x] {
                fmt.Print("X")
            } else {
                fmt.Print(" ")
            }
        }
        fmt.Println()
    }
}

```

### 5. Die Haupt-Schleife aufsetzen

Abschließend richten wir die Haupt-Schleife ein, die das Spiel initialisiert, das Gitter wiederholt aktualisiert und im Terminal rendert.

```go
func main() {
 initialLiveCells := [][2]int{
  // Gleiter
  {1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2},

  // Leichtes Raumschiff (LWSS)
  {10, 2}, {11, 2}, {12, 2}, {13, 2},
  {9, 3}, {13, 3},
  {13, 4},
  {9, 5}, {12, 5},
 }

 grid := NewGrid(30, 15, initialLiveCells)
 for {
  grid.Render()
  grid.NextState()
  time.Sleep(500 * time.Millisecond)
 }
}

```

## Vollständiger Code

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
 for y := 0; y < g.Height; y++ {
  for x := 0; x < g.Width; x++ {
   if g.Cells[y][x] {
    fmt.Print("X")
   } else {
    fmt.Print(" ")
   }
  }
  fmt.Println()
 }
}

func main() {
 initialLiveCells := [][2]int{
  // Gleiter
  {1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2},

  // Leichtes Raumschiff (LWSS)
  {10, 2}, {11, 2}, {12, 2}, {13, 2},
  {9, 3}, {13, 3},
  {13, 4},
  {9, 5}, {12, 5},
 }

 grid := NewGrid(30, 15, initialLiveCells)
 for {
  grid.Render()
  grid.NextState()
  time.Sleep(500 * time.Millisecond)
 }
}


```

## YAML-Konfiguration (Optional)

Du kannst auch eine YAML-Konfigurationsdatei verwenden, um den Ausgangszustand des Gitters festzulegen. Hier ist ein Beispiel:

```yaml
width: 10
height: 10
initialLiveCells:
  - [1, 0]
  - [2, 1]
  - [0, 2]
  - [1, 2]
  - [2, 2]
```

Um die YAML-Konfigurationsdatei zu parsen, musst du ein Go-Paket für YAML-Parsing hinzufügen, wie [gopkg.in/yaml.v3](https://pkg.go.dev/gopkg.in/yaml.v3). Aktualisiere die Main-Funktion, um die Konfigurationsdatei zu lesen und das Gitter basierend auf ihrem Inhalt zu initialisieren.

## JSON-Konfiguration (Optional)

Alternativ kannst du eine JSON-Konfigurationsdatei verwenden, um den Ausgangszustand des Gitters festzulegen:

```json
{
  "width": 10,
  "height": 10,
  "initialLiveCells": [
    [1, 0],
    [2, 1],
    [0, 2],
    [1, 2],
    [2, 2]
  ]
}
```
