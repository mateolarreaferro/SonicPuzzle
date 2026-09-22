class_name Player
extends CharacterBody3D
## First-person walker: WASD to walk, hold right mouse to look.

const SPEED := 3.0
const MOUSE_SENSITIVITY := 0.0025
const EYE_HEIGHT := 1.65

var input_enabled := true

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	camera.position.y = EYE_HEIGHT


func _unhandled_input(event: InputEvent) -> void:
	# Hold right mouse to look; the left button stays free for the UI.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		var looking: bool = event.pressed and input_enabled
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, -1.4, 1.4)


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if input_enabled:
		var i := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = (transform.basis * Vector3(i.x, 0, i.y)).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()


## Keep the player inside the room after it shrinks.
func confine_to(bounds: AABB, margin := 0.6) -> void:
	position.x = clampf(position.x, bounds.position.x + margin, bounds.end.x - margin)
	position.z = clampf(position.z, bounds.position.z + margin, bounds.end.z - margin)
	position.y = maxf(position.y, bounds.position.y)
