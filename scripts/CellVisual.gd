## CellVisual.gd
##
## A single visual square representing one grid cell.
## One instance of this exists per (x, y) coordinate, positioned by Main.gd.
##
## This script ONLY draws - it has no knowledge of input or simulation
## rules. Main.gd tells it to refresh(), and it reads the current state
## from GridManager to decide what color to be.
##
## Phase 1 note: colors here are placeholders just so each component
## type is visually distinct. Phase 5 will replace draw logic with the
## final visual spec (dark/bright red wire, lever ON/OFF look, etc)
## without needing to touch GridManager or Main.gd.

extends ColorRect
class_name CellVisual

var grid_x: int = 0
var grid_y: int = 0

# Reference to the shared GridManager so this cell can read its own state.
var grid_manager: GridManager = null

# Placeholder palette - Phase 5 will replace these with the real visual spec.
const COLOR_EMPTY: Color = Color(0.15, 0.15, 0.15)
const COLOR_WIRE_OFF: Color = Color(0.4, 0.05, 0.05)   # dark red
const COLOR_WIRE_ON: Color = Color(1.0, 0.15, 0.15)    # bright red
const COLOR_LEVER_OFF: Color = Color(0.5, 0.4, 0.3)
const COLOR_LEVER_ON: Color = Color(1.0, 0.8, 0.2)
const COLOR_LAMP_OFF: Color = Color(0.5, 0.5, 0.5)     # gray
const COLOR_LAMP_ON: Color = Color(1.0, 0.95, 0.3)     # yellow

## Sets up this visual cell to track a specific grid coordinate.
func setup(x: int, y: int, manager: GridManager) -> void:
	grid_x = x
	grid_y = y
	grid_manager = manager
	# CellVisual is a ColorRect (a Control), and Controls default to
	# absorbing mouse input (mouse_filter = STOP). That would silently
	# eat every click before it ever reaches Main's _unhandled_input,
	# making the whole grid feel unresponsive. CellVisual never needs
	# to handle input itself - that's Main.gd's job - so we explicitly
	# tell it to ignore mouse events and let them pass through.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()

## Re-reads this cell's data from GridManager and updates appearance.
## Call this whenever this cell's state might have changed.
func refresh() -> void:
	if grid_manager == null:
		return
	var cell: GridManager.Cell = grid_manager.get_cell(grid_x, grid_y)
	if cell == null:
		return

	match cell.component_type:
		Component.ComponentType.EMPTY:
			color = COLOR_EMPTY
		Component.ComponentType.WIRE:
			color = COLOR_WIRE_ON if cell.signal_strength > 0 else COLOR_WIRE_OFF
		Component.ComponentType.LEVER:
			color = COLOR_LEVER_ON if cell.lever_on else COLOR_LEVER_OFF
		Component.ComponentType.LAMP:
			color = COLOR_LAMP_ON if cell.signal_strength > 0 else COLOR_LAMP_OFF
		_:
			color = COLOR_EMPTY
