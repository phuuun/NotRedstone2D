## SimulationEngine.gd
##
## Runs the simulation tick loop. A "tick" is a discrete simulation step,
## deliberately decoupled from render framerate - the grid should update
## at a fixed, readable pace regardless of how fast the game is rendering.
##
## This script owns ONLY the tick rules from the spec's "SIGNAL RULES"
## section. It reads/writes Cell data via GridManager, but never touches
## rendering directly - Main.gd is responsible for telling visuals to
## refresh() after a tick runs.
##
## PHASE SCOPE:
##   Phase 2: step 1 only - levers generate signal into their own cell.
##   Phase 3: step 2 added - wires propagate signal from neighboring
##     levers/wires, resolved instantly within a single tick via
##     iterative relaxation (see _step_wire_propagation).
##   Phase 4: step 3 added - lamps read the strongest signal from their
##     neighbors and turn on if it's greater than 0.
##   Phase 6 (current): repeaters joined the relaxation loop alongside
##     wires. Unlike a wire, a repeater only accepts input from the one
##     cell directly behind its facing direction, and outputs full
##     signal strength (no decay) - it "refreshes" a signal instead of
##     just relaying it. Directionality means every neighbor lookup now
##     has to ask "does that neighbor actually point at me?" instead of
##     assuming any adjacent lever/wire always transmits - see
##     _signal_from_neighbor, which is the single place that answers
##     that question for every caller (wire, repeater, and lamp alike).
## Each phase's logic gets its own private method below, called in order
## from run_tick(), so later phases are additions, not rewrites.

extends Node
class_name SimulationEngine

const TICK_INTERVAL_SECONDS: float = 0.2  # 5 ticks per second

var grid_manager: GridManager = null
var is_running: bool = false

# Internal accumulator for fixed-rate ticking independent of frame rate.
var _time_since_last_tick: float = 0.0

# Emitted after every completed tick so Main.gd knows to refresh visuals.
signal tick_completed

## Wires this engine to the grid it will simulate. Must be called once
## before starting the simulation.
func setup(manager: GridManager) -> void:
	grid_manager = manager

## Starts the simulation: ticks will begin advancing in _process().
func start() -> void:
	is_running = true
	_time_since_last_tick = 0.0

## Pauses the simulation: ticks stop advancing, grid state is preserved.
func pause() -> void:
	is_running = false

## Convenience toggle, used by both the keyboard shortcut and the UI button.
func toggle_running() -> void:
	if is_running:
		pause()
	else:
		start()

func _process(delta: float) -> void:
	if not is_running or grid_manager == null:
		return

	_time_since_last_tick += delta
	if _time_since_last_tick >= TICK_INTERVAL_SECONDS:
		_time_since_last_tick -= TICK_INTERVAL_SECONDS
		run_tick()

## Runs exactly one simulation step, in the order defined by the spec:
##   1. Levers generate signal
##   2. Wires and repeaters propagate/refresh signal
##   3. Lamps update based on incoming signal
func run_tick() -> void:
	_step_lever_generation()
	_step_wire_propagation()
	_step_lamp_update()
	tick_completed.emit()

## Step 1: every lever cell writes its own signal strength based on
## whether it's ON or OFF. This is the only thing Phase 2 does -
## the signal does not yet travel anywhere beyond the lever's own cell.
func _step_lever_generation() -> void:
	for x in range(GridManager.GRID_WIDTH):
		for y in range(GridManager.GRID_HEIGHT):
			var cell: GridManager.Cell = grid_manager.get_cell(x, y)
			if cell.component_type != Component.ComponentType.LEVER:
				continue
			cell.signal_strength = Component.MAX_SIGNAL if cell.lever_on else 0

# The 4 orthogonal neighbor directions (von Neumann neighborhood).
# Diagonals are intentionally excluded - wires only connect along
# straight grid edges, matching the spec's "Lever -> Wire -> Wire -> Lamp"
# chain example.
const _NEIGHBOR_OFFSETS: Array = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

## Step 2: every wire and repeater cell receives signal from its
## neighbors - wires take the strongest neighboring signal minus decay,
## repeaters take only the single cell behind their facing direction
## and output full strength (or 0) with no decay.
##
## Per design decision: signal propagation should feel INSTANT within
## a single tick (matching Minecraft redstone), not crawl one tile per
## tick. We get that by repeatedly relaxing the whole network until no
## cell's value changes anymore (convergence), all within this one call.
## Wires and repeaters are relaxed together in the same pass since a
## repeater can feed a wire and a wire can feed a repeater within the
## same tick.
##
## CRITICAL: every wire/repeater is reset to 0 before relaxing. If we
## instead relaxed starting from last tick's values, a cell whose
## source just turned off could keep getting "fed" by a
## stale-but-not-yet-decayed neighbor (since relaxation only compares
## against the previous PASS, not against an actual source), letting
## old signal persist or decay far slower than it should. Resetting to
## 0 first means signal can only re-enter the network from a true
## source (a lit lever) each tick, so turning a lever off correctly
## drops the whole downstream chain to 0 in the same tick it happens,
## not gradually.
##
## Each individual pass uses a snapshot-then-apply approach so a pass
## itself isn't order-dependent; we just run multiple passes back to
## back until the network stabilizes.
##
## Iteration count is capped at GRID_WIDTH + GRID_HEIGHT, which is more
## than enough passes for a signal to cross the longest possible path
## on the grid - this guards against hanging on a pathological layout
## (e.g. dense wire loops) while still always reaching the true stable
## result in practice.
func _step_wire_propagation() -> void:
	_reset_all_transmitter_signals()

	var max_passes: int = GridManager.GRID_WIDTH + GridManager.GRID_HEIGHT
	for _pass_index in range(max_passes):
		var previous_signals: Dictionary = _snapshot_wire_signals()
		var changed: bool = false

		for x in range(GridManager.GRID_WIDTH):
			for y in range(GridManager.GRID_HEIGHT):
				var cell: GridManager.Cell = grid_manager.get_cell(x, y)
				var new_signal: int
				if cell.component_type == Component.ComponentType.WIRE:
					new_signal = _wire_incoming_signal(x, y, previous_signals)
				elif cell.component_type == Component.ComponentType.REPEATER:
					new_signal = _repeater_incoming_signal(x, y, cell, previous_signals)
				else:
					continue
				if new_signal != cell.signal_strength:
					cell.signal_strength = new_signal
					changed = true

		# Network has reached a stable state - no point running more passes.
		if not changed:
			break

## Zeroes out every wire/repeater cell's signal before a fresh
## propagation pass. See _step_wire_propagation for why this reset is
## necessary.
func _reset_all_transmitter_signals() -> void:
	for x in range(GridManager.GRID_WIDTH):
		for y in range(GridManager.GRID_HEIGHT):
			var cell: GridManager.Cell = grid_manager.get_cell(x, y)
			if cell.component_type == Component.ComponentType.WIRE \
					or cell.component_type == Component.ComponentType.REPEATER:
				cell.signal_strength = 0

## Captures every cell's current signal_strength (levers, wires, and
## repeaters; lamps don't transmit so they're excluded from neighbor
## lookups by _signal_from_neighbor regardless). Keyed by Vector2i position.
func _snapshot_wire_signals() -> Dictionary:
	var snapshot: Dictionary = {}
	for x in range(GridManager.GRID_WIDTH):
		for y in range(GridManager.GRID_HEIGHT):
			var cell: GridManager.Cell = grid_manager.get_cell(x, y)
			snapshot[Vector2i(x, y)] = cell
	return snapshot

## Returns how much signal flows from the neighbor at (x, y) + offset
## into (x, y), given the snapshot. This is the single place that
## understands transmission direction, so wire propagation, repeater
## propagation, and lamp reads all agree on the same rules:
##   - LEVER / WIRE transmit their signal_strength in all 4 directions.
##   - REPEATER only transmits toward the cell its facing points at, so
##     it contributes nothing unless offset (the direction from the
##     neighbor to (x, y)) matches its facing.
##   - EMPTY / LAMP never transmit (lamps are a sink, not a relay).
func _signal_from_neighbor(x: int, y: int, offset: Vector2i, snapshot: Dictionary) -> int:
	var neighbor_pos: Vector2i = Vector2i(x, y) + offset
	if not snapshot.has(neighbor_pos):
		return 0
	var neighbor_cell: GridManager.Cell = snapshot[neighbor_pos]
	match neighbor_cell.component_type:
		Component.ComponentType.LEVER, Component.ComponentType.WIRE:
			return neighbor_cell.signal_strength
		Component.ComponentType.REPEATER:
			if neighbor_cell.facing == -offset:
				return neighbor_cell.signal_strength
			return 0
		_:
			return 0

## Strongest signal reaching (x, y) from any of its 4 orthogonal
## neighbors, respecting each neighbor's transmission rules (see
## _signal_from_neighbor). No decay is applied here - callers decide
## whether decay applies to their use case (wires decay by 1, repeaters
## and lamps do not).
func _strongest_neighbor_signal(x: int, y: int, snapshot: Dictionary) -> int:
	var strongest: int = 0
	for offset in _NEIGHBOR_OFFSETS:
		strongest = max(strongest, _signal_from_neighbor(x, y, offset, snapshot))
	return strongest

## Wire-specific rule: strongest neighboring signal, minus decay,
## clamped to [0, MAX_SIGNAL].
func _wire_incoming_signal(x: int, y: int, previous_signals: Dictionary) -> int:
	var strongest: int = _strongest_neighbor_signal(x, y, previous_signals)
	var result: int = strongest - Component.SIGNAL_DECAY
	return clamp(result, 0, Component.MAX_SIGNAL)

## Repeater-specific rule: unlike a wire, a repeater ignores every
## neighbor except the single cell directly behind its facing
## direction. If that cell is feeding it any signal at all, the
## repeater outputs full strength (no decay, no partial values) -
## it refreshes a signal rather than relaying it faithfully.
func _repeater_incoming_signal(x: int, y: int, cell: GridManager.Cell, previous_signals: Dictionary) -> int:
	var input_offset: Vector2i = -cell.facing
	var input_signal: int = _signal_from_neighbor(x, y, input_offset, previous_signals)
	return Component.MAX_SIGNAL if input_signal > 0 else 0

## Step 3: every lamp cell reads the strongest signal among its
## neighbors (no decay applied - the lamp is a sink, not a relay) and
## stores it in signal_strength. CellVisual already treats any lamp
## with signal_strength > 0 as ON, so no further state is needed here -
## this just keeps signal_strength accurate for that check (and for a
## possible future "how strong" display).
##
## Uses a fresh snapshot taken after wire propagation has fully
## resolved for this tick, so lamps see the final settled signal
## values, not an intermediate relaxation pass.
func _step_lamp_update() -> void:
	var current_signals: Dictionary = _snapshot_wire_signals()
	for x in range(GridManager.GRID_WIDTH):
		for y in range(GridManager.GRID_HEIGHT):
			var cell: GridManager.Cell = grid_manager.get_cell(x, y)
			if cell.component_type != Component.ComponentType.LAMP:
				continue
			cell.signal_strength = _strongest_neighbor_signal(x, y, current_signals)
