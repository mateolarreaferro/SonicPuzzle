class_name Levels
## Game data: room options, rules, and the level list.
## Tune the puzzle here — nothing else needs to change.

const SIZES := ["S", "M", "L"]
const CEILINGS := ["Flat", "Sloped", "Vault"]
## "Plaster" is the empty white default room; it is never a solution.
const MATERIALS := ["Plaster", "Wood", "Soundpanel", "Concrete"]

const SIZE_NAMES := {"S": "Small", "M": "Medium", "L": "Large"}
const OPTIONS := {"size": SIZES, "ceiling": CEILINGS, "material": MATERIALS}

## Every level starts in this room.
const START_ROOM := {"size": "M", "ceiling": "Flat", "material": "Plaster"}

## Rules / restrictions.
const REFERENCE_LISTENS := 3      # reference plays per level
const REFERENCE_SECONDS := 8.0    # length of each reference preview
const CLEAR_DELAY := 0.8         # seconds the right room must hold before the level clears

const LEVELS := [
	{
		"title": "Trap",
		"premise": "A trap beat, tight and punchy. It wants a room that doesn't talk back.",
		"stems": [
			"res://assets/audio/trap/beat.wav",
			"res://assets/audio/trap/808_bass.wav",
			"res://assets/audio/trap/brass_stab.wav",
			"res://assets/audio/trap/lead_1.wav",
			"res://assets/audio/trap/lead_2.wav",
		],
		"reference": "res://assets/audio/trap/reference.wav",
		"target": {"size": "S", "ceiling": "Flat", "material": "Soundpanel"},
		"clear_color": Color(0.62, 0.32, 1.0),
	},
	{
		"title": "Elevator Jazz",
		"premise": "A small combo. Warm, a little bloom, nothing muddy.",
		"stems": [
			"res://assets/audio/jazz/drums.wav",
			"res://assets/audio/jazz/upright_bass.wav",
			"res://assets/audio/jazz/guitar.wav",
			"res://assets/audio/jazz/flute.wav",
		],
		"reference": "res://assets/audio/jazz/reference.wav",
		"target": {"size": "M", "ceiling": "Sloped", "material": "Wood"},
		"clear_color": Color(1.0, 0.62, 0.28),
	},
	{
		"title": "Slap House",
		"premise": "Big room energy. Let it ring.",
		"stems": [
			"res://assets/audio/house/drums.mp3",
			"res://assets/audio/house/bass.mp3",
			"res://assets/audio/house/dreamy_chords.mp3",
			"res://assets/audio/house/vocal.mp3",
			"res://assets/audio/house/fx.mp3",
		],
		"reference": "res://assets/audio/house/reference.mp3",
		"target": {"size": "L", "ceiling": "Vault", "material": "Concrete"},
		"clear_color": Color(0.2, 0.85, 1.0),
	},
]

const MENU_MUSIC := "res://assets/audio/menu/background.wav"


static func room_path(size: String, ceiling: String) -> String:
	return "res://assets/rooms/Room_%s_%s.glb" % [size, ceiling]


static func option_label(key: String, value: String) -> String:
	return SIZE_NAMES[value] if key == "size" else value
