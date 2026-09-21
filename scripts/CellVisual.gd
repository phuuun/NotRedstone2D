## CellVisual.gd
##
## A single visual square representing one grid cell.
## One instance of this exists per (x, y) coordinate, positioned by Main.gd.
##
## This script ONLY draws - it has no knowledge of input or simulation
## rules. Main.gd tells it to refresh(), and it reads the current state
## from GridManager to decide what to draw.
##
## Phase 5: switched from a flat ColorRect to a custom _draw() based
## Control. Style is black minimal (Apple dark-mode palette): empty
## cells are a faint dot grid, wires are rounded traces that connect to
## neighbouring components, and components sit on rounded tiles.

extends Control
class_name CellVisual

var grid_x: int = 0
var grid_y: int = 0
var cell_size: float = 16.0

# Reference to the shared GridManager so this cell can read its own state.
var grid_manager: GridManager = null

# --- Palette (Apple dark-mode system colors) ---
const COLOR_DOT: Color = Color("2c2c2e")
const COLOR_TILE: Color = Color("1c1c1e")
const COLOR_IDLE: Color = Color("3a3a3c")           # anything unpowered
const COLOR_WIRE_WEAK: Color = Color("5c1f1a")      # signal = 1
const COLOR_WIRE_STRONG: Color = Color("ff453a")    # signal = 15
const COLOR_LEVER_ON: Color = Color("30d158")
const COLOR_KNOB: Color = Color("f5f5f7")
const COLOR_LAMP_ON: Color = Color("ffd60a")
const COLOR_REPEATER_OFF: Color = Color("636366")
const COLOR_REPEATER_ON: Color = Color("0a84ff")

const NEIGHBOR_DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

## Sets up this visual cell to track a specific grid coordinate.
func setup(x: int, y: int, manager: GridManager, size: float) -> void:
	grid_x = x
	grid_y = y
	grid_manager = manager
	cell_size = size
	# CellVisual must never absorb mouse input - that's Main.gd's job.
	# Without this, Controls default to STOP and silently eat every
	# click before it reaches Main's _unhandled_input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()

## Re-reads this cell's data from GridManager and requests a redraw.
## Call this whenever this cell's state might have changed.
func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if grid_manager == null:
		return
	var cell: GridManager.Cell = grid_manager.get_cell(grid_x, grid_y)
	if cell == null:
		return

	var center: Vector2 = Vector2(cell_size, cell_size) * 0.5

	match cell.component_type:
		Component.ComponentType.WIRE:
			_draw_wire(center, cell.signal_strength)
		Component.ComponentType.LEVER:
			_draw_lever(center, cell.lever_on)
		Component.ComponentType.LAMP:
			_draw_lamp(center, cell.signal_strength > 0)
		Component.ComponentType.REPEATER:
			_draw_repeater(center, cell.facing, cell.signal_strength > 0)
		_:
			draw_circle(center, cell_size * 0.06, COLOR_DOT, true, -1.0, true)

## Rounded rect helper, used for component tiles and the lever track.
func _draw_rounded(rect: Rect2, color: Color, radius: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius))
	draw_style_box(box, rect)

## Every non-wire component sits on the same rounded tile, inset 1px
## so neighbouring tiles read as separate pieces.
func _draw_tile() -> void:
	_draw_rounded(Rect2(Vector2.ONE, Vector2.ONE * (cell_size - 2.0)), COLOR_TILE, cell_size * 0.22)

## Draws a wire as a rounded trace from the cell center to the edge of
## every non-empty neighbour, so adjacent wires join into one continuous
## line. Unpowered is gray; powered runs dark red (1) to bright red (15)
## so signal strength along a line is readable at a glance.
func _draw_wire(center: Vector2, signal_strength: int) -> void:
	var color: Color = COLOR_IDLE
	if signal_strength > 0:
		var t: float = float(signal_strength) / float(Component.MAX_SIGNAL)
		color = COLOR_WIRE_WEAK.lerp(COLOR_WIRE_STRONG, t)
	var width: float = cell_size * 0.3

	for dir in NEIGHBOR_DIRS:
		var neighbor: GridManager.Cell = grid_manager.get_cell(grid_x + dir.x, grid_y + dir.y)
		if neighbor != null and neighbor.component_type != Component.ComponentType.EMPTY:
			draw_line(center, center + Vector2(dir) * cell_size * 0.5, color, width, true)
	# Round joint so corners and dead ends look smooth instead of square.
	draw_circle(center, width * 0.5, color, true, -1.0, true)

## Draws a lever as an iOS-style toggle switch: gray track with the knob
## on the left when OFF, green track with the knob on the right when ON.
func _draw_lever(center: Vector2, is_on: bool) -> void:
	_draw_tile()
	var track_size: Vector2 = Vector2(cell_size * 0.7, cell_size * 0.42)
	var track: Rect2 = Rect2(center - track_size * 0.5, track_size)
	_draw_rounded(track, COLOR_LEVER_ON if is_on else COLOR_IDLE, track_size.y * 0.5)

	var knob_radius: float = track_size.y * 0.5 - 1.0
	var knob_x: float = track.end.x - track_size.y * 0.5 if is_on else track.position.x + track_size.y * 0.5
	draw_circle(Vector2(knob_x, center.y), knob_radius, COLOR_KNOB, true, -1.0, true)

## Draws a lamp: a bulb dot that turns yellow with a soft halo when lit.
func _draw_lamp(center: Vector2, is_on: bool) -> void:
	_draw_tile()
	var radius: float = cell_size * 0.22
	if is_on:
		# Halo kept inside the tile so later-drawn neighbours don't clip it.
		draw_circle(center, cell_size * 0.46, Color(COLOR_LAMP_ON, 0.08), true, -1.0, true)
		draw_circle(center, cell_size * 0.34, Color(COLOR_LAMP_ON, 0.18), true, -1.0, true)
	draw_circle(center, radius, COLOR_LAMP_ON if is_on else COLOR_IDLE, true, -1.0, true)

## Draws a repeater as a double chevron pointing in its facing direction,
## so which way it reads input from / outputs to is visible at a glance.
## Blue when it currently has signal, gray when it doesn't.
func _draw_repeater(center: Vector2, facing: Vector2i, is_on: bool) -> void:
	_draw_tile()
	var color: Color = COLOR_REPEATER_ON if is_on else COLOR_REPEATER_OFF
	var dir: Vector2 = Vector2(facing)
	var side: Vector2 = dir.orthogonal() * cell_size * 0.2
	var depth: Vector2 = dir * cell_size * 0.1
	var width: float = max(1.5, cell_size * 0.1)

	for offset in [-0.1, 0.1]:
		var c: Vector2 = center + dir * cell_size * offset
		draw_polyline(PackedVector2Array([c - depth + side, c + depth, c - depth - side]), color, width, true)
