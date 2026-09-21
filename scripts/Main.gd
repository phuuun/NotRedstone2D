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

# Hotbar buttons, one per selectable mode. Index order matches the
# order they're declared in the scene: Wire, Lever, Lamp, Repeater, Erase.
@onready var hotbar_wire_button: Button = $UILayer/Hotbar/Items/WireButton
@onready var hotbar_lever_button: Button = $UILayer/Hotbar/Items/LeverButton
@onready var hotbar_lamp_button: Button = $UILayer/Hotbar/Items/LampButton
@onready var hotbar_repeater_button: Button = $UILayer/Hotbar/Items/RepeaterButton
@onready var hotbar_erase_button: Button = $UILayer/Hotbar/Items/EraseButton

@onready var hotbar: PanelContainer = $UILayer/Hotbar
@onready var camera: Camera2D = $Camera2D

# Container node that holds all CellVisual instances.
@onready var visual_container: Node2D = $VisualContainer

# 2D array mirroring grid_manager's layout, holding CellVisual refs
# so we can quickly refresh() the one(s) that changed instead of
# refreshing the entire grid every time.
var _visuals: Array = []

# Currently selected component type to place with left-click.
# Defaults to WIRE so the player can place immediately (key 1).
var _selected_type: int = Component.ComponentType.WIRE

# Mouse button currently held for a drag (-1 = none) and the last grid
# cell the drag painted, so the next motion event can fill the gap.
var _drag_button: int = -1
var _drag_last_cell: Vector2i = Vector2i.ZERO

func _ready() -> void:
	_build_visual_grid()
	simulation_engine.setup(grid_manager)
	simulation_engine.tick_completed.connect(_on_tick_completed)
	simulation_engine.start()  # sandbox always runs, no Run/Pause

	hotbar_wire_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.WIRE))
	hotbar_lever_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.LEVER))
	hotbar_lamp_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.LAMP))
	hotbar_repeater_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.REPEATER))
	hotbar_erase_button.pressed.connect(_on_hotbar_pressed.bind(Component.ComponentType.EMPTY))
	_update_hotbar_highlight()

	_apply_ui_theme()
	_fit_camera()
	get_viewport().size_changed.connect(_fit_camera)

## Board size in world pixels.
func _board_size() -> Vector2:
	return Vector2(GridManager.GRID_WIDTH, GridManager.GRID_HEIGHT) * CELL_SIZE

## Dark rounded backdrop behind the grid, so the board reads as a
## surface floating on the pure-black background.
func _draw() -> void:
	var board := StyleBoxFlat.new()
	board.bg_color = Color("0b0b0c")
	board.border_color = Color("1c1c1e")
	board.set_border_width_all(1)
	board.set_corner_radius_all(16)
	draw_style_box(board, Rect2(Vector2(-12, -12), _board_size() + Vector2(24, 24)))

## Zooms the camera so the whole board fits between the top button and
## the hotbar, and re-fits whenever the window is resized.
func _fit_camera() -> void:
	var board: Vector2 = _board_size()
	var view: Vector2 = get_viewport_rect().size
	var z: float = min(view.x / (board.x + 64.0), view.y / (board.y + 220.0))
	camera.zoom = Vector2(z, z)
	camera.position = board * 0.5

## Rounded style box used by every UI element.
func _ui_box(color: Color, radius: int = 10) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

## Black minimal UI: a frosted dark pill for the hotbar, ghost buttons
## that brighten on hover, and a white selected state (segmented-control
## style). Built in code so the whole look lives in one place.
func _apply_ui_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SF Pro Text", "Inter", "Helvetica Neue", "Segoe UI", "Cantarell"])
	font.font_weight = 500

	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	theme.set_stylebox("normal", "Button", _ui_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", "Button", _ui_box(Color("2c2c2e")))
	theme.set_stylebox("pressed", "Button", _ui_box(Color("f5f5f7")))
	theme.set_stylebox("hover_pressed", "Button", _ui_box(Color("f5f5f7")))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Color("8e8e93"))
	theme.set_color("font_hover_color", "Button", Color("f5f5f7"))
	theme.set_color("font_pressed_color", "Button", Color.BLACK)
	theme.set_color("font_hover_pressed_color", "Button", Color.BLACK)

	var glass := _ui_box(Color(0.09, 0.09, 0.1, 0.85), 14)
	glass.border_color = Color("2c2c2e")
	glass.set_border_width_all(1)
	glass.set_content_margin_all(6)
	theme.set_stylebox("panel", "PanelContainer", glass)

	hotbar.theme = theme

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

## Refreshes (x, y) and its 4 neighbours - wires draw traces toward
## neighbouring components, so placing/removing one changes how the
## cells next to it look too.
func _refresh_around(x: int, y: int) -> void:
	_refresh_cell_visual(x, y)
	for dir in CellVisual.NEIGHBOR_DIRS:
		_refresh_cell_visual(x + dir.x, y + dir.y)

## Refreshes every cell's visual. Called after each simulation tick since
## a tick can change signal_strength anywhere on the grid at once.
func _refresh_all_visuals() -> void:
	for x in range(GridManager.GRID_WIDTH):
		for y in range(GridManager.GRID_HEIGHT):
			_visuals[x][y].refresh()

## Called whenever SimulationEngine finishes a tick.
func _on_tick_completed() -> void:
	_refresh_all_visuals()

## Converts a mouse position (in this node's local space) to grid coordinates.
func _mouse_to_grid(mouse_pos: Vector2) -> Vector2i:
	return Vector2i(floori(mouse_pos.x / CELL_SIZE), floori(mouse_pos.y / CELL_SIZE))

func _unhandled_input(event: InputEvent) -> void:
	_handle_keyboard_selection(event)
	_handle_mouse_click(event)
	_handle_mouse_drag(event)

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

## Left click places the selected component (or toggles a lever if one is
## already there). Right click always erases, regardless of selection.
## Either press also starts a drag, handled by _handle_mouse_drag().
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
		_refresh_around(grid_pos.x, grid_pos.y)
	else:
		return
	_drag_button = event.button_index
	_drag_last_cell = grid_pos

## Dragging with the button held paints a continuous cable: left drag
## lays wire (or erases, in Erase mode), right drag always erases.
## Fast mouse moves skip cells between motion events, so every cell on
## the path from the last painted cell to the current one is filled -
## the wire follows the cursor with no gaps.
func _handle_mouse_drag(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or _drag_button == -1:
		return
	# Checked via the button mask rather than a release event, since the
	# release can land on the hotbar and never reach _unhandled_input.
	if not event.button_mask & (1 << (_drag_button - 1)):
		_drag_button = -1
		return

	var target: Vector2i = _mouse_to_grid(get_local_mouse_position())
	var erase: bool = _drag_button == MOUSE_BUTTON_RIGHT or _selected_type == Component.ComponentType.EMPTY
	if not erase and _selected_type != Component.ComponentType.WIRE:
		return  # only wire is drag-placed; one lever/lamp/repeater per click

	# Walk one orthogonal step at a time (along whichever axis is further
	# off) so the trace stays 4-connected and actually carries signal,
	# instead of leaving diagonal gaps.
	var p: Vector2i = _drag_last_cell
	while p != target:
		var d: Vector2i = target - p
		if abs(d.x) >= abs(d.y):
			p.x += signi(d.x)
		else:
			p.y += signi(d.y)
		_paint_cell(p, erase)
	_drag_last_cell = target

## Applies one drag step to a cell. Wire only goes onto empty cells so
## dragging across a lever, lamp or repeater never overwrites it.
func _paint_cell(p: Vector2i, erase: bool) -> void:
	var cell: GridManager.Cell = grid_manager.get_cell(p.x, p.y)
	if cell == null:
		return
	if erase:
		grid_manager.remove_component(p.x, p.y)
	elif cell.component_type == Component.ComponentType.EMPTY:
		grid_manager.place_component(p.x, p.y, Component.ComponentType.WIRE)
	else:
		return
	_refresh_around(p.x, p.y)

func _handle_left_click(x: int, y: int) -> void:
	var cell: GridManager.Cell = grid_manager.get_cell(x, y)
	if cell == null:
		return

	# Erase mode removes anything, levers and repeaters included, so it
	# must be checked before the toggle/rotate interactions below.
	if _selected_type == Component.ComponentType.EMPTY:
		grid_manager.remove_component(x, y)
		_refresh_around(x, y)
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

	grid_manager.place_component(x, y, _selected_type)
	_refresh_around(x, y)
