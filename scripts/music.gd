class_name Music
extends Node
## Plays the level's dry stems from the speakers (through the room's
## acoustics), the reference preview (bypasses the room), and the
## "opened up" mix when a level clears.

signal reference_finished

const STEMS_BUS := &"Stems"
const REFERENCE_BUS := &"Reference"
const FADE := 0.6

var speakers: Speakers
var _reference := AudioStreamPlayer.new()
var _menu := AudioStreamPlayer.new()
var _reference_timer := Timer.new()
var _bus_tweens := {}


func _ready() -> void:
	_ensure_bus(STEMS_BUS)
	_ensure_bus(REFERENCE_BUS)
	_reference.bus = REFERENCE_BUS
	add_child(_reference)
	_menu.stream = _looping(load(Levels.MENU_MUSIC))
	add_child(_menu)
	_reference_timer.one_shot = true
	_reference_timer.timeout.connect(stop_reference)
	add_child(_reference_timer)


func play_menu() -> void:
	stop_level()
	_menu.volume_db = -40.0
	_menu.play()
	create_tween().tween_property(_menu, "volume_db", 0.0, 1.5)


func load_level(level: Dictionary) -> void:
	if _menu.playing:
		var t := create_tween()
		t.tween_property(_menu, "volume_db", -60.0, 1.0)
		t.tween_callback(_menu.stop)
	stop_level()
	var streams := []
	for path in level["stems"]:
		streams.append(_looping(load(path)))
	speakers.load_stems(streams)
	_reference.stream = load(level["reference"])
	_set_bus_db(STEMS_BUS, -60.0)
	_set_bus_db(REFERENCE_BUS, 0.0)
	speakers.play()
	_fade(STEMS_BUS, 0.0, 1.5)


func stop_level() -> void:
	_reference_timer.stop()
	_reference.stop()
	speakers.clear()


func is_reference_playing() -> bool:
	return _reference.playing and not _reference_timer.is_stopped()


## Mute the dry mix and play the start of the reference for `seconds`.
func play_reference(seconds: float) -> void:
	_fade(STEMS_BUS, -80.0)
	_set_bus_db(REFERENCE_BUS, 0.0)
	_reference.play(0.0)
	_reference_timer.start(minf(seconds, _reference.stream.get_length()))


func stop_reference() -> void:
	_reference_timer.stop()
	_fade(REFERENCE_BUS, -80.0).finished.connect(func():
		if _reference_timer.is_stopped():
			_reference.stop())
	_fade(STEMS_BUS, 0.0)
	reference_finished.emit()


## The reward: the dry stems give way to the full reference mix.
func open_up() -> void:
	_reference_timer.stop()
	_reference.stream = _looping(_reference.stream.duplicate())
	_set_bus_db(REFERENCE_BUS, -30.0)
	_reference.play(0.0)
	_fade(REFERENCE_BUS, 0.0, 3.0)
	_fade(STEMS_BUS, -80.0, 3.0)


func _fade(bus: StringName, db: float, time := FADE) -> Tween:
	var idx := AudioServer.get_bus_index(bus)
	if _bus_tweens.has(bus):
		(_bus_tweens[bus] as Tween).kill()
	var t := create_tween()
	_bus_tweens[bus] = t
	t.tween_method(func(v: float): AudioServer.set_bus_volume_db(idx, v),
		AudioServer.get_bus_volume_db(idx), db, time)
	return t


func _set_bus_db(bus: StringName, db: float) -> void:
	if _bus_tweens.has(bus):
		(_bus_tweens[bus] as Tween).kill()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), db)


func _ensure_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus)
	AudioServer.set_bus_send(idx, &"Master")


## Loop at runtime so dropping new stems in needs no import settings.
static func _looping(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	return stream
