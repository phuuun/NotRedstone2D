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
##   Phase 4 (current): step 3 added - lamps read the strongest signal
##     from their neighbors and turn on if it's greater than 0.
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
##   2. Wires receive strongest neighboring signal minus 1
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

## Step 2: every wire cell receives the strongest signal among its
## neighbors, minus the decay constant, clamped to [0, MAX_SIGNAL].
##
## Per design decision: signal propagation should feel INSTANT within
## a single tick (matching Minecraft redstone), not crawl one tile per
## tick. We get that by repeatedly relaxing the whole wire network
## until no cell's value changes anymore (convergence), all within this
## one call.
##
## CRITICAL: every wire is reset to 0 before relaxing. If we instead
## relaxed starting from last tick's values, a wire whose source just
## turned off could keep getting "fed" by a stale-but-not-yet-decayed
## neighbor (since relaxation only compares against the previous PASS,
## not against an actual source), letting old signal persist or decay
## far slower than it should. Resetting to 0 first means signal can
## only re-enter the network from a true source (a lit lever) each
## tick, so turning a lever off correctly drops the whole downstream
## chain to 0 in the same tick it happens, not gradually.
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
	_reset_all_wire_signals()

	var max_passes: int = GridManager.GRID_WIDTH + GridManager.GRID_HEIGHT
	for _pass_index in range(max_passes):
		var previous_signals: Dictionary = _snapshot_wire_signals()
		var changed: bool = false

		for x in range(GridManager.GRID_WIDTH):
			for y in range(GridManager.GRID_HEIGHT):
				var cell: GridManager.Cell = grid_manager.get_cell(x, y)
				if cell.component_type != Component.ComponentType.WIRE:
					continue
				var new_signal: int = _strongest_incoming_signal(x, y, previous_signals)
				if new_signal != cell.signal_strength:
					cell.signal_strength = new_signal
					changed = true

		# Network has reached a stable state - no point running more passes.
		if not changed:
			break

## Zeroes out every wire cell's signal before a fresh propagation pass.
## See _step_wire_propagation for why this reset is necessary.
func _reset_all_wire_signals() -> void:
	for x in range(GridManager.GRID_WIDTH):
		for y in range(GridManager.GRID_HEIGHT):
			var cell: GridManager.Cell = grid_manager.get_cell(x, y)
			if cell.component_type == Component.ComponentType.WIRE:
				cell.signal_strength = 0

## Captures every cell's current signal_strength (levers and wires;
## lamps don't transmit so they're excluded from neighbor lookups by
## _strongest_incoming_signal regardless). Keyed by Vector2i position.
func _snapshot_wire_signals() -> Dictionary:
	var snapshot: Dictionary = {}
	for x in range(GridManager.GRID_WIDTH):
		for y in range(GridManager.GRID_HEIGHT):
			var cell: GridManager.Cell = grid_manager.get_cell(x, y)
			snapshot[Vector2i(x, y)] = cell
	return snapshot

## Looks at the 4 orthogonal neighbors of (x, y) using the given
## snapshot, and returns the strongest signal among neighbors that can
## transmit (LEVER or WIRE). LAMP and EMPTY cells contribute nothing,
## since lamps only consume signal and empty cells carry none. No
## decay is applied here - callers decide whether decay applies to
## their use case (wires decay by 1, lamps do not since they're a
## sink rather than another link in the chain).
func _strongest_neighbor_signal(x: int, y: int, previous_signals: Dictionary) -> int:
	var strongest: int = 0
	for offset in _NEIGHBOR_OFFSETS:
		var neighbor_pos: Vector2i = Vector2i(x, y) + offset
		if not previous_signals.has(neighbor_pos):
			continue
		var neighbor_cell: GridManager.Cell = previous_signals[neighbor_pos]
		if neighbor_cell.component_type != Component.ComponentType.LEVER \
				and neighbor_cell.component_type != Component.ComponentType.WIRE:
			continue
		strongest = max(strongest, neighbor_cell.signal_strength)
	return strongest

## Wire-specific wrapper: strongest neighboring signal, minus decay,
## clamped to [0, MAX_SIGNAL]. Used by wire propagation.
func _strongest_incoming_signal(x: int, y: int, previous_signals: Dictionary) -> int:
	var strongest: int = _strongest_neighbor_signal(x, y, previous_signals)
	var result: int = strongest - Component.SIGNAL_DECAY
	return clamp(result, 0, Component.MAX_SIGNAL)

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
