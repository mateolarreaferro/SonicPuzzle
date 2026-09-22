class_name Sfx
extends Node
## Interface sounds. They play on their own dry "UI" bus straight to Master,
## so they never pass through the room acoustics or the reference ducking,
## and never colour what the player is judging.

const BUS := &"UI"
const VOLUME_DB := -6.0
const SOUNDS := {
	"select": "res://assets/audio/sfx/select.wav",
	"correct": "res://assets/audio/sfx/correct.wav",
	"clear": "res://assets/audio/sfx/clear.wav",
}
## Each room property clicks at its own pitch so the three rows feel distinct.
const SELECT_PITCH := {"size": 0.85, "ceiling": 1.0, "material": 1.18}
const VOICES := 4

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
	for key in SOUNDS:
		_streams[key] = load(SOUNDS[key])
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = VOLUME_DB
		add_child(p)
		_players.append(p)


func play(sound: String, pitch := 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.play()


func select(property: String) -> void:
	play("select", SELECT_PITCH.get(property, 1.0) * randf_range(0.98, 1.02))
