extends Node3D
## Game loop: title -> levels (shape the room by ear) -> finished.
## A level clears on its own once all three room properties are right.

enum Phase { TITLE, PLAYING, CLEARED, FINISHED }

var phase := Phase.TITLE
var level_index := 0
var room_state: Dictionary
var listens_left: int
## Rows the player has changed this level. Feedback only shows for these,
## so a property that happens to start correct isn't given away.
var touched := {}

var _clear_timer := Timer.new()

@onready var room: Room = $Room
@onready var player: Player = $Player
@onready var music: Music = $Music
@onready var speakers: Speakers = $Speakers
@onready var sfx: Sfx = $Sfx
@onready var acoustics: AcousticsBackend = $Acoustics
@onready var hud: Hud = $Hud


func _ready() -> void:
	room.set_environment($WorldEnvironment.environment)
	speakers.setup(Music.STEMS_BUS)
	music.speakers = speakers
	acoustics.setup(Music.STEMS_BUS)
	acoustics.set_listener(player.camera)
	speakers.layout_changed.connect(acoustics.sources_changed)
	hud.rays_toggled.connect(acoustics.set_debug_visible)
	room.room_changed.connect(_on_room_changed)
	music.reference_finished.connect(_refresh_reference)
	hud.option_chosen.connect(_choose)
	hud.reference_pressed.connect(_toggle_reference)
	hud.overlay_confirmed.connect(_advance)
	_clear_timer.one_shot = true
	_clear_timer.timeout.connect(_on_clear_timer)
	add_child(_clear_timer)
	room_state = Levels.START_ROOM.duplicate()
	room.apply(room_state)
	_to_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("advance") and phase != Phase.PLAYING:
		_advance()
	elif phase == Phase.PLAYING:
		# Keyboard shortcuts mirror the on-screen controls.
		var step := -1 if Input.is_key_pressed(KEY_SHIFT) else 1
		for key in Levels.OPTIONS:
			if event.is_action_pressed("cycle_" + key):
				var options: Array = Levels.OPTIONS[key]
				_choose(key, options[posmod(options.find(room_state[key]) + step, options.size())])
		if event.is_action_pressed("play_reference"):
			_toggle_reference()


func _advance() -> void:
	match phase:
		Phase.TITLE:
			_start_level(0)
		Phase.CLEARED:
			if level_index + 1 < Levels.LEVELS.size():
				_start_level(level_index + 1)
			else:
				_finish()
		Phase.FINISHED:
			_to_title()


func _choose(key: String, value: String) -> void:
	if phase != Phase.PLAYING or room_state[key] == value:
		return
	room_state[key] = value
	touched[key] = true
	var right: bool = value == level_data()["target"][key]
	if right:
		sfx.play("correct")
	else:
		sfx.select(key)
	room.apply(room_state)
	if _all_right():
		_clear_timer.start(Levels.CLEAR_DELAY)
	else:
		_clear_timer.stop()


func _toggle_reference() -> void:
	if phase != Phase.PLAYING:
		return
	if music.is_reference_playing():
		music.stop_reference()
	elif listens_left > 0:
		listens_left -= 1
		music.play_reference(Levels.REFERENCE_SECONDS)
	_refresh_reference()


func _on_clear_timer() -> void:
	if phase == Phase.PLAYING and _all_right():
		_clear_level()


func _clear_level() -> void:
	phase = Phase.CLEARED
	var level := level_data()
	hud.set_controls_enabled(false)
	sfx.play("clear")
	music.open_up()
	acoustics.level_cleared(level)
	room.set_mood(level["clear_color"], 1.0, 3.0)
	var last := level_index + 1 >= Levels.LEVELS.size()
	hud.show_overlay("You found the room.",
		"Listen to it open up. Take a walk around.",
		"Finish" if last else "Next room", false)


func _start_level(index: int) -> void:
	phase = Phase.PLAYING
	level_index = index
	var level := level_data()
	listens_left = Levels.REFERENCE_LISTENS
	touched.clear()
	_clear_timer.stop()
	hud.hide_overlay()
	hud.show_level(index, Levels.LEVELS.size(), level)
	hud.set_controls_enabled(true)
	room_state = Levels.START_ROOM.duplicate()
	room.apply(room_state)
	room.set_mood(Color.WHITE, 0.0, 0.8)
	player.position = Vector3(room.bounds.get_center().x, room.bounds.position.y, room.bounds.get_center().z)
	player.input_enabled = true
	music.load_level(level)
	speakers.layout(room.bounds)
	acoustics.level_started(level)
	_refresh_reference()
	if index == 0:
		hud.toast("Hear the reference, then shape the room to match.", 3.5)


func _to_title() -> void:
	phase = Phase.TITLE
	player.input_enabled = false
	music.play_menu()
	room.set_mood(Color.WHITE, 0.0, 0.8)
	hud.show_overlay("Sonic Puzzle",
		"The music is dry. Shape the room around it (size, ceiling, material) until it "
		+ "sounds like the reference. You get %d listens per room, so use your ears."
		% Levels.REFERENCE_LISTENS,
		"Begin")


func _finish() -> void:
	phase = Phase.FINISHED
	player.input_enabled = false
	hud.show_overlay("Every room found.",
		"You tuned %d rooms by ear." % Levels.LEVELS.size(), "Play again")


func level_data() -> Dictionary:
	return Levels.LEVELS[level_index]


func _all_right() -> bool:
	var target: Dictionary = level_data()["target"]
	for key in Levels.OPTIONS:
		if room_state[key] != target[key]:
			return false
	return true


func _refresh_reference() -> void:
	hud.show_reference(music.is_reference_playing(), listens_left)


func _process(_delta: float) -> void:
	hud.show_acoustics(acoustics.describe())


func _on_room_changed(state: Dictionary, geometry: Dictionary) -> void:
	var bounds: AABB = geometry["bounds"]
	acoustics.room_changed(state, geometry)
	speakers.layout(bounds)
	player.confine_to(bounds)
	var correct := {}
	if phase == Phase.PLAYING:
		var target: Dictionary = level_data()["target"]
		for key in touched:
			correct[key] = state[key] == target[key]
	hud.show_room(state, correct)
