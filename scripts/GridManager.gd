## GridManager.gd
##
## Owns the logical state of the grid: what component is in each cell,
## and what signal strength that cell currently holds.
##
## This script knows NOTHING about drawing or input - it is pure data
## + data-manipulation. Main.gd (input) and CellVisual.gd (rendering)
## both go through this script rather than touching grid data directly.
## Keeping this boundary clean is what lets Phase 5 (visuals) and
## Phase 3 (propagation) be written without editing this file again.

extends Node
class_name GridManager

const GRID_WIDTH: int = 50
const GRID_HEIGHT: int = 50

## A single grid cell's data.
## Plain inner class (not a Node) - cheap to create 2500 of these.
class Cell:
	var component_type: int = Component.ComponentType.EMPTY
	var signal_strength: int = 0
	var lever_on: bool = false  # Only meaningful when component_type == LEVER

# 2D array of Cell, indexed as _cells[x][y]
var _cells: Array = []

func _ready() -> void:
	_initialize_grid()

## Allocates the grid and fills it with empty cells.
func _initialize_grid() -> void:
	_cells.clear()
	for x in range(GRID_WIDTH):
		var column: Array = []
		for y in range(GRID_HEIGHT):
			column.append(Cell.new())
		_cells.append(column)

## Returns true if (x, y) is a valid grid coordinate.
func is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < GRID_WIDTH and y >= 0 and y < GRID_HEIGHT

## Returns the Cell at (x, y), or null if out of bounds.
func get_cell(x: int, y: int) -> Cell:
	if not is_in_bounds(x, y):
		return null
	return _cells[x][y]

## Places a component at (x, y), overwriting whatever was there.
## Resets signal strength and lever state since it's a fresh placement.
## Does nothing if out of bounds.
func place_component(x: int, y: int, type: int) -> void:
	var cell: Cell = get_cell(x, y)
	if cell == null:
		return
	cell.component_type = type
	cell.signal_strength = 0
	cell.lever_on = false

## Removes whatever is at (x, y), turning it back into EMPTY.
func remove_component(x: int, y: int) -> void:
	place_component(x, y, Component.ComponentType.EMPTY)

## Toggles a lever's ON/OFF state. No-op if the cell isn't a lever.
func toggle_lever(x: int, y: int) -> void:
	var cell: Cell = get_cell(x, y)
	if cell == null or cell.component_type != Component.ComponentType.LEVER:
		return
	cell.lever_on = not cell.lever_on
