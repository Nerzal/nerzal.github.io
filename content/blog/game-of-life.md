---
title: "Conway's Game of Life in Go: A Step-by-Step Guide"
date: 2023-03-16
draft: false
tags: ["go", "game of life"]
---

## Introduction

[Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life) is a famous cellular automaton devised by the British mathematician John Horton Conway. It is a zero-player game that evolves over time based on its initial state, requiring no further input from the player. The game takes place on an infinite two-dimensional grid of square cells, with each cell being either alive or dead.

In this blog post, we'll explore how to implement Conway's Game of Life in Go. We'll provide step-by-step instructions, complete with functioning example code and detailed explanations.

Example:

![Alt-Text](/img/game-of-live.gif)


## Rules

The Game of Life follows four simple rules:

1. A live cell with fewer than two live neighbors dies (underpopulation).
2. A live cell with two or three live neighbors lives on to the next generation.
3. A live cell with more than three live neighbors dies (overpopulation).
4. A dead cell with exactly three live neighbors becomes a live cell (reproduction).

These rules are applied simultaneously to all cells on the grid for each iteration, creating interesting patterns and behaviors.

## Implementation

Let's start implementing the Game of Life in Go. We'll divide the implementation into the following steps:

1. Define the data structures
2. Initialize the game grid
3. Implement the game logic
4. Render the grid
5. Set up the main loop

### 1. Define the Data Structures

First, let's define the data structures we'll use to represent the grid and the cells. We'll create a `Grid` type that will contain the grid's dimensions and a two-dimensional slice of `Cell` values.

```go
type Cell bool

type Grid struct {
    Width  int
    Height int
    Cells  [][]Cell
}
```

### 2. Initialize the Game Grid

Next, we'll create a function to initialize the game grid with an initial state. The function will take the grid's dimensions and a slice of initial live cell coordinates as input and return a populated `Grid` instance.

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

Now, let's implement the game logic by creating a function that computes the next state of the grid based on the current state and the rules of the Game of Life.

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

### 4. Render the Grid

We'll create a function to render the grid in the terminal, displaying live cells as "X" characters and dead cells as spaces.

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

### 5. Set Up the Main Loop

Finally, we'll set up the main loop that initializes the game, repeatedly updates the grid, and renders the grid to the terminal.

```go
func main() {
 initialLiveCells := [][2]int{
  // Glider
  {1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2},

  // Lightweight spaceship (LWSS)
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

## Complete Code

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
  // Glider
  {1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2},

  // Lightweight spaceship (LWSS)
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

## YAML Configuration (Optional)

You can also use a YAML configuration file to specify the initial state of the grid. Here's an example of a YAML configuration file:

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

To parse the YAML configuration file, you'll need to add a Go package for YAML parsing, such as [gopkg.in/yaml.v3](https://pkg.go.dev/gopkg.in/yaml.v3). Update the main function to read the configuration file and initialize the grid based on its contents.

## JSON Configuration (Optional)

Alternatively, you can use a JSON configuration file to specify the initial state of the grid. Here's an

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
