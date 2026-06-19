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
##   Phase 2 (current): step 1 only - levers generate signal into their
##     own cell. Wires and lamps are intentionally left alone; they will
##     start participating in Phase 3 and Phase 4 respectively.
##   Phase 3 will add: wires receive strongest neighboring signal - 1.
##   Phase 4 will add: lamps update based on incoming signal.
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
##   2. Wires receive strongest neighboring signal minus 1   (Phase 3)
##   3. Lamps update based on incoming signal                (Phase 4)
func run_tick() -> void:
	_step_lever_generation()
	# _step_wire_propagation()  -- Phase 3
	# _step_lamp_update()       -- Phase 4
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
