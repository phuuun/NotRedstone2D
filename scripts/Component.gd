## Component.gd
##
## Central definition of all component types in the simulator.
## This is NOT a node - it's a static reference class that other scripts
## use to look up component metadata (max signal, default color, etc).
##
## When adding a new component in the future:
##   1. Add a new entry to ComponentType
##   2. Add its display name / default color below if needed
## That's it - GridManager, SimulationEngine, and CellVisual all read
## from here instead of hardcoding values, so adding components later
## should not require touching unrelated logic.

extends Node
class_name Component

# Every possible thing that can occupy a grid cell.
# Phase 1 only needs EMPTY/WIRE/LEVER/LAMP per the spec, but the enum
# is the natural extension point for future component types.
enum ComponentType {
	EMPTY,
	WIRE,
	LEVER,
	LAMP,
	REPEATER,
}

# Facing a repeater is placed with by default (pointing right/east).
# GridManager.rotate_component() cycles a cell's facing away from this.
const DEFAULT_FACING: Vector2i = Vector2i.RIGHT

# Maximum signal strength any component can hold or transmit.
const MAX_SIGNAL: int = 15

# Signal strength lost per tile of wire travel.
const SIGNAL_DECAY: int = 1

# Human-readable names, useful for debug labels / future UI tooltips.
static func get_name_for(type: int) -> String:
	match type:
		ComponentType.EMPTY:
			return "Empty"
		ComponentType.WIRE:
			return "Wire"
		ComponentType.LEVER:
			return "Lever"
		ComponentType.LAMP:
			return "Lamp"
		ComponentType.REPEATER:
			return "Repeater"
		_:
			return "Unknown"
