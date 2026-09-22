class_name AcousticsBackend
extends Node
## The seam between the game and whatever renders the room's acoustics.
##
## The game only ever talks to this interface. Each stem plays from its own
## speaker (an AudioStreamPlayer3D) on a per-speaker bus that feeds
## `music_bus`; a backend makes that bus sound like the current room.
## Swap the backend for SATIE on the Acoustics node in main.tscn.

var music_bus: StringName


## Called once, after the audio buses exist.
func setup(bus: StringName) -> void:
	music_bus = bus


## The node whose position/orientation is the listener (the player's camera).
func set_listener(_listener: Node3D) -> void:
	pass


## World positions of the speakers the stems play from.
func sources_changed(_positions: Array[Vector3]) -> void:
	pass


## A new level began. `level` is an entry from Levels.LEVELS.
func level_started(_level: Dictionary) -> void:
	pass


## The player changed the room. `state` = {size, ceiling, material};
## `geometry` = {bounds: AABB, volume: m³, area: m²}. The exact shell is also
## on physics layer Room.ACOUSTIC_LAYER for ray queries.
func room_changed(_state: Dictionary, _geometry: Dictionary) -> void:
	pass


## The player found the right room: the music should "open up".
func level_cleared(_level: Dictionary) -> void:
	pass


## Optional: draw/describe what the model is doing (for demos and tuning).
func set_debug_visible(_visible: bool) -> void:
	pass


## Optional: one-paragraph readout of the current acoustic estimate.
func describe() -> String:
	return ""
