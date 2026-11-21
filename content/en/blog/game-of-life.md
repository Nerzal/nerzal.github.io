---
title: "Conway's Game of Life in Go: A Step-by-Step Guide"
seo_title: "Conway's Game of Life in Go"
date: 2023-03-16
draft: false
toc: true
description: "Implement Conway's Game of Life in Go from scratch — grid logic, toroidal wrapping, terminal rendering, and a working main loop with two classic patterns."
images: ["img/game_of_life.png"]
featured_image: "img/game_of_life.png"
tags: ["go", "golang", "tutorial", "game-of-life", "beginner"]
show_reading_time: true
---

{{< tldr >}}
- Conway's Game of Life is a zero-player cellular automaton from 1970 with four rules: underpopulation, survival with two or three neighbours, overpopulation, and reproduction with exactly three.
- This Go implementation uses only the standard library: a `Grid` struct with a two-dimensional `[]Cell` slice, where `Cell` is a `bool`.
- `NextState` writes each generation into a freshly allocated slice, because updating the grid in place feeds new cell states into the neighbour counts.
- The `%` operator in `countLiveNeighbors` wraps coordinates into a toroidal grid, so cells leaving one edge reappear on the opposite side.
- The terminal renderer uses the ANSI escape `\033[H` to redraw each frame in place and animates a Glider and a Lightweight Spaceship at 100 ms per step.
{{< /tldr >}}

[Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life) is a famous cellular automaton devised by British mathematician John Horton Conway in 1970. It is a zero-player game: you define an initial state and then watch it evolve according to a fixed set of rules, with no further input. The rules are simple, yet they produce surprisingly complex, lifelike patterns.

In this post we implement Game of Life in Go from scratch, step by step. By the end you will have a working terminal simulation that renders a **Glider** and a **Lightweight Spaceship (LWSS)** in real time.

![Conway's Game of Life simulation in a Go terminal](/img/game-of-live.gif)

## Prerequisites

You need [Go](https://go.dev/dl/) installed on your machine. The standard library is enough; this tutorial needs no third-party packages.

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
# Verify installation
go version
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
# Verify installation
go version
```

{{< /os-tab >}}
{{< /os-tabs >}}

If `go version` prints something like `go version go1.27.3 linux/amd64` you are good to go. If not, follow the [official installation guide](https://go.dev/doc/install).

Create a new file called `main.go` in an empty directory and follow along.

## Rules

The Game of Life follows four rules, applied simultaneously to every cell on the grid at each step:

1. A **live cell** with fewer than two live neighbours dies (_underpopulation_).
2. A **live cell** with two or three live neighbours survives.
3. A **live cell** with more than three live neighbours dies (_overpopulation_).
4. A **dead cell** with exactly three live neighbours becomes alive (_reproduction_).

Everything else emerges from the initial state.

## Implementation

We build it in five steps.

### 1. Define the Data Structures

`Cell` is just a boolean: alive or dead. `Grid` holds the dimensions and a two-dimensional slice of cells.

```go
type Cell bool

type Grid struct {
    Width  int
    Height int
    Cells  [][]Cell
}
```

### 2. Initialise the Grid

`NewGrid` allocates the two-dimensional slice and places the initial live cells at the given coordinates.

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

### 3. Implement the Game Logic

`NextState` computes the next generation. We allocate a fresh slice so we never read and write the same state simultaneously. Updating the grid in place is a classic Game of Life bug: cells you already changed feed their _new_ state into their neighbours' counts, so half the board is computed from the next generation instead of the current one.

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

`countLiveNeighbors` checks the eight surrounding cells. The `%` operator creates a **toroidal grid**: cells that leave one edge reappear on the opposite side, so the simulation never has boundary artifacts.

```go
func (g *Grid) countLiveNeighbors(x, y int) int {
    count := 0
    for i := -1; i <= 1; i++ {
        for j := -1; j <= 1; j++ {
            if i == 0 && j == 0 {
                continue
            }

            // Wrap around: (x + offset + Width) % Width keeps the value in [0, Width)
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

### 4. Render the Grid

`Render` prints the grid to the terminal. Live cells appear as `█`, dead cells as a space. The ANSI escape sequence `\033[H` moves the cursor to the top-left corner before each frame. The output does not scroll, so the frames replace each other and the animation looks smooth.

```go
func (g *Grid) Render() {
    // Move cursor to top-left without clearing (avoids flicker)
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

### 5. Set Up the Main Loop

We seed the grid with two well-known patterns, a **Glider** (moves diagonally across the grid) and a **Lightweight Spaceship (LWSS)** (moves horizontally), then run the simulation indefinitely.

```go
func main() {
    initialLiveCells := [][2]int{
        // Glider — travels diagonally
        {1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2},

        // Lightweight Spaceship (LWSS) — travels horizontally
        {10, 2}, {11, 2}, {12, 2}, {13, 2},
        {9, 3}, {13, 3},
        {13, 4},
        {9, 5}, {12, 5},
    }

    // Clear terminal once at the start
    fmt.Print("\033[2J")

    grid := NewGrid(40, 20, initialLiveCells)
    for {
        grid.Render()
        grid.NextState()
        time.Sleep(100 * time.Millisecond)
    }
}
```

## Complete Code

Save this as `main.go`:

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

## Running the Program

{{< os-tabs >}}
{{< os-tab "Linux / macOS" >}}

```bash
go run main.go
```

{{< /os-tab >}}
{{< os-tab "Windows (PowerShell)" >}}

```powershell
go run main.go
```

{{< /os-tab >}}
{{< /os-tabs >}}

Press `Ctrl+C` to stop. You should see the Glider and LWSS patterns moving across the terminal.

## What's Next

- Try different starting patterns. The [LifeWiki](https://conwaylife.com/wiki/) catalogues thousands of them.
- Replace `fmt.Print` with a proper terminal library like [tcell](https://github.com/gdamore/tcell) or [bubbletea](https://github.com/charmbracelet/bubbletea) for colour and keyboard input.
- If you are interested in containerising your Go applications, check out my post on [Go and Docker](/blog/go-docker/).
