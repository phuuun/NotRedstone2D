## Main.gd
##
## Top-level controller for the scene. Responsibilities:
##   - Build the visual grid (one CellVisual per cell)
##   - Track which component the player has selected (keyboard 0/1/2/3)
##   - Handle mouse input to place/remove/toggle components
##
## Phase 1 scope: grid creation + place/remove only.
## Lever toggle is included here since it's pure input handling, but
## lever signal generation itself belongs to SimulationEngine (Phase 2).
##
## Phase 6 added the repeater: clicking an existing repeater rotates its
## facing instead of placing over it, mirroring how clicking an existing
## lever toggles it rather than being replaced.
##
## This script deliberately does NOT contain grid data or drawing logic -
## those live in GridManager and CellVisual respectively. Main.gd only
## coordinates between them.

extends Node2D

const CELL_SIZE: int = 16  # pixels per grid cell on screen

@onready var grid_manager: GridManager = $GridManager

# Drives the tick loop (Phase 2+). Main.gd starts/stops it and refreshes
# visuals whenever it reports a completed tick - it never reaches into
# simulation rules itself.
@onready var simulation_engine: SimulationEngine = $SimulationEngine

@onready var run_pause_button: Button = $UILayer/RunPauseButton

# Hotbar buttons, one per selectable mode. Index order matches the
# order they're declared in the scene: Wire, Lever, Lamp, Repeater, Erase.
@onready var hotbar_wire_button: Button = $UILayer/Hotbar/WireButton
@onready var hotbar_lever_button: Button = $UILayer/Hotbar/LeverButton
@onready var hotbar_lamp_button: Button = $UILayer/Hotbar/LampButton
@onready var hotbar_repeater_button: Button = $UILayer/Hotbar/RepeaterButton
@onready var hotbar_erase_button: Button = $UILayer/Hotbar/EraseButton

# Container node that holds all CellVisual instances.
@onready var visual_container: Node2D = $VisualContainer

# 2D array mirroring grid_manager's layout, holding CellVisual refs
# so we can quickly refresh() the one(s) that changed instead of
# refreshing the entire grid every time.
var _visuals: Array = []

# Currently selected component type to place with left-click.
# Defaults to WIRE so the player can place immediately (key 1).
var _selected_type: int = Component.ComponentType.WIRE

func _ready() -> void:
	_build_visual_grid()
	simulation_engine.setup(grid_manager)
	simulation_engine.tick_completed.connect(_on_tick_completed)
	run_pause_button.pressed.connect(_on_run_pause_pressed)

	hotbar_wire_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.WIRE))
	hotbar_lever_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.LEVER))
	hotbar_lamp_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.LAMP))
	hotbar_repeater_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.REPEATER))
	hotbar_erase_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.EMPTY))
	_update_hotbar_highlight()

## Instantiates one CellVisual per grid cell and positions it.
func _build_visual_grid() -> void:
	_visuals.clear()
	for x in range(GridManager.GRID_WIDTH):
		var column: Array = []
		for y in range(GridManager.GRID_HEIGHT):
			var visual := CellVisual.new()
			# Full cell size, no gap - CellVisual now draws its own
			# 1px border in _draw(), so we don't need a literal gap
			# between nodes to fake grid lines anymore.
			visual.size = Vector2(CELL_SIZE, CELL_SIZE)
			visual.position = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			visual_container.add_child(visual)
			visual.setup(x, y, grid_manager, CELL_SIZE)
			column.append(visual)
		_visuals.append(column)

## Refreshes the visual at (x, y) to match current grid data.
func _refresh_cell_visual(x: int, y: int) -> void:
	if x < 0 or x >= GridManager.GRID_WIDTH or y < 0 or y >= GridManager.GRID_HEIGHT:
		return
	_visuals[x][y].refresh()

## Refreshes every cell's visual. Called after each simulation tick since
## a tick can change signal_strength anywhere on the grid at once.
func _refresh_all_visuals() -> void:
	for x in range(GridManager.GRID_WIDTH):
		for y in range(GridManager.GRID_HEIGHT):
			_visuals[x][y].refresh()

## Called whenever SimulationEngine finishes a tick.
func _on_tick_completed() -> void:
	_refresh_all_visuals()

## Shared by both the keyboard shortcut and the on-screen button so
## there's exactly one place that flips running state and updates the
## button label - neither input path duplicates the other's logic.
func _toggle_simulation() -> void:
	simulation_engine.toggle_running()
	run_pause_button.text = "Pause" if simulation_engine.is_running else "Run"

func _on_run_pause_pressed() -> void:
	_toggle_simulation()

## Converts a mouse position (in this node's local space) to grid coordinates.
func _mouse_to_grid(mouse_pos: Vector2) -> Vector2i:
	return Vector2i(int(mouse_pos.x / CELL_SIZE), int(mouse_pos.y / CELL_SIZE))

func _unhandled_input(event: InputEvent) -> void:
	_handle_keyboard_selection(event)
	_handle_simulation_toggle_key(event)
	_handle_mouse_click(event)

## Keys 1/2/3/4 select Wire/Lever/Lamp/Repeater; 0 selects Erase mode.
func _handle_keyboard_selection(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_1:
			_set_selected_type(Component.ComponentType.WIRE)
		KEY_2:
			_set_selected_type(Component.ComponentType.LEVER)
		KEY_3:
			_set_selected_type(Component.ComponentType.LAMP)
		KEY_4:
			_set_selected_type(Component.ComponentType.REPEATER)
		KEY_0:
			_set_selected_type(Component.ComponentType.EMPTY)  # Erase mode

## Single entry point for changing the selected component, used by both
## the keyboard shortcuts and the hotbar buttons, so the hotbar's
## highlighted state can never drift out of sync with what's actually
## selected regardless of which input path changed it.
func _set_selected_type(type: int) -> void:
	_selected_type = type
	_update_hotbar_highlight()

## Called when a hotbar button is pressed; bound with its component type.
func _on_hotbar_pressed(type: int) -> void:
	_set_selected_type(type)

## Visually marks whichever hotbar button matches the current selection
## as pressed/highlighted, and un-highlights the rest.
func _update_hotbar_highlight() -> void:
	hotbar_wire_button.button_pressed = (_selected_type == Component.ComponentType.WIRE)
	hotbar_lever_button.button_pressed = (_selected_type == Component.ComponentType.LEVER)
	hotbar_lamp_button.button_pressed = (_selected_type == Component.ComponentType.LAMP)
	hotbar_repeater_button.button_pressed = (_selected_type == Component.ComponentType.REPEATER)
	hotbar_erase_button.button_pressed = (_selected_type == Component.ComponentType.EMPTY)

## Space bar toggles Run/Pause, mirroring the on-screen button.
func _handle_simulation_toggle_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_SPACE:
		_toggle_simulation()

## Left click places the selected component (or toggles a lever if one is
## already there). Right click always erases, regardless of selection.
func _handle_mouse_click(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	var grid_pos: Vector2i = _mouse_to_grid(get_local_mouse_position())
	if not grid_manager.is_in_bounds(grid_pos.x, grid_pos.y):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(grid_pos.x, grid_pos.y)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		grid_manager.remove_component(grid_pos.x, grid_pos.y)
		_refresh_cell_visual(grid_pos.x, grid_pos.y)

func _handle_left_click(x: int, y: int) -> void:
	var cell: GridManager.Cell = grid_manager.get_cell(x, y)
	if cell == null:
		return

	# Clicking an existing lever ALWAYS toggles it, and clicking an
	# existing repeater ALWAYS rotates it, instead of replacing them -
	# regardless of what's currently selected. This takes priority over
	# placement so a stray click never silently overwrites either one
	# with whatever component happens to be selected.
	if cell.component_type == Component.ComponentType.LEVER:
		grid_manager.toggle_lever(x, y)
		_refresh_cell_visual(x, y)
		return
	if cell.component_type == Component.ComponentType.REPEATER:
		grid_manager.rotate_component(x, y)
		_refresh_cell_visual(x, y)
		return

	if _selected_type == Component.ComponentType.EMPTY:
		grid_manager.remove_component(x, y)
	else:
		grid_manager.place_component(x, y, _selected_type)
	_refresh_cell_visual(x, y)
