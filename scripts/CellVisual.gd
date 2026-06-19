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
## Control. This lets each cell render a background fill PLUS a grid
## border PLUS a simple icon shape (lever switch, lamp bulb) in one
## pass, which a plain ColorRect can't do on its own.

extends Control
class_name CellVisual

var grid_x: int = 0
var grid_y: int = 0
var cell_size: float = 16.0

# Reference to the shared GridManager so this cell can read its own state.
var grid_manager: GridManager = null

# --- Palette ---
const COLOR_EMPTY: Color = Color(0.15, 0.15, 0.15)
const COLOR_WIRE_NO_SIGNAL: Color = Color(0.25, 0.04, 0.04)   # dark red, signal = 0
const COLOR_WIRE_MAX_SIGNAL: Color = Color(1.0, 0.15, 0.1)    # bright red, signal = 15
const COLOR_LEVER_BASE: Color = Color(0.35, 0.32, 0.3)        # mounting plate, same regardless of state
const COLOR_LEVER_OFF_HANDLE: Color = Color(0.55, 0.45, 0.35)
const COLOR_LEVER_ON_HANDLE: Color = Color(1.0, 0.8, 0.2)
const COLOR_LAMP_BASE: Color = Color(0.3, 0.3, 0.3)           # socket, same regardless of state
const COLOR_LAMP_OFF_BULB: Color = Color(0.5, 0.5, 0.5)
const COLOR_LAMP_ON_BULB: Color = Color(1.0, 0.95, 0.3)
const COLOR_GRID_LINE: Color = Color(0.0, 0.0, 0.0, 0.6)

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

	var full_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(cell_size, cell_size))

	match cell.component_type:
		Component.ComponentType.EMPTY:
			draw_rect(full_rect, COLOR_EMPTY)
		Component.ComponentType.WIRE:
			draw_rect(full_rect, _wire_color_for_signal(cell.signal_strength))
		Component.ComponentType.LEVER:
			_draw_lever(full_rect, cell.lever_on)
		Component.ComponentType.LAMP:
			_draw_lamp(full_rect, cell.signal_strength > 0)
		_:
			draw_rect(full_rect, COLOR_EMPTY)

	# Grid border on every cell, drawn last so it sits on top of the fill.
	draw_rect(full_rect, COLOR_GRID_LINE, false, 1.0)

## Maps a wire's signal strength (0-15) to a color along a gradient
## from dark red (no signal) to bright red (full signal, 15). This
## makes it possible to tell at a glance whether a wire is carrying a
## strong signal near its source or a weak one near the end of its
## range, instead of every non-zero signal looking identically "lit".
func _wire_color_for_signal(signal_strength: int) -> Color:
	var t: float = float(signal_strength) / float(Component.MAX_SIGNAL)
	return COLOR_WIRE_NO_SIGNAL.lerp(COLOR_WIRE_MAX_SIGNAL, t)

## Draws a lever: a mounting plate (background) with a switch handle
## drawn as a diagonal bar. The handle leans one way when OFF and the
## other way when ON, plus a color change - so the ON/OFF state reads
## clearly even without comparing colors side by side.
func _draw_lever(rect: Rect2, is_on: bool) -> void:
	draw_rect(rect, COLOR_LEVER_BASE)

	var center: Vector2 = rect.position + rect.size * 0.5
	var handle_color: Color = COLOR_LEVER_ON_HANDLE if is_on else COLOR_LEVER_OFF_HANDLE
	var half_len: float = rect.size.x * 0.3
	var thickness: float = max(2.0, rect.size.x * 0.12)

	# The handle pivots from the same anchor point but tips toward
	# opposite corners depending on state, so the flip is unmistakable
	# even at a glance.
	var tip_offset: Vector2
	if is_on:
		tip_offset = Vector2(half_len * 0.6, -half_len)   # leaning up
	else:
		tip_offset = Vector2(half_len * 0.6, half_len)    # leaning down

	var pivot: Vector2 = center + Vector2(-half_len * 0.3, half_len * 0.5)
	draw_line(pivot, pivot + tip_offset, handle_color, thickness)
	# Small base knob so the pivot point reads as an anchored switch.
	draw_circle(pivot, thickness * 0.8, handle_color)

## Draws a lamp: a socket (background) with a bulb circle that's lit
## yellow when ON, dim gray when OFF.
func _draw_lamp(rect: Rect2, is_on: bool) -> void:
	draw_rect(rect, COLOR_LAMP_BASE)

	var center: Vector2 = rect.position + rect.size * 0.5
	var radius: float = rect.size.x * 0.32
	var bulb_color: Color = COLOR_LAMP_ON_BULB if is_on else COLOR_LAMP_OFF_BULB
	draw_circle(center, radius, bulb_color)

	# Faint outer glow ring when lit, to read as "emitting light"
	# rather than just "a yellow circle".
	if is_on:
		draw_arc(center, radius * 1.35, 0, TAU, 24, Color(1.0, 0.95, 0.5, 0.4), 1.5)
