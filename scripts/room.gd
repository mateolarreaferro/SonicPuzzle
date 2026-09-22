class_name Room
extends Node3D
## Builds the playable room: swaps the S/M/L x Flat/Sloped/Vault shell,
## skins it with a surface material, keeps colliders and lights in sync.

## `geometry` = {bounds: AABB, volume: float (m³), area: float (m²)}
signal room_changed(state: Dictionary, geometry: Dictionary)

## Physics layer holding the exact room shell, used only by acoustic rays.
## The player collides with the simple box walls on layer 1 instead.
const ACOUSTIC_LAYER := 2

const MATERIAL_NODES := {
	"Wood": "Mat_Wood",
	"Soundpanel": "Mat_Soundpanel",
	"Concrete": "Mat_Concrete",
}
const TEXTURE_SCALE := 0.5  # triplanar tiles per metre

var state: Dictionary = {}
var bounds := AABB()
var volume := 0.0
var area := 0.0

var _materials := {}
var _shell: Node3D
var _walls: StaticBody3D
var _light: OmniLight3D
var _env: Environment


func _ready() -> void:
	_load_materials()
	_light = OmniLight3D.new()
	_light.shadow_enabled = true
	add_child(_light)
	_walls = StaticBody3D.new()
	add_child(_walls)


func set_environment(env: Environment) -> void:
	_env = env


func apply(new_state: Dictionary) -> void:
	var shape_changed: bool = state.is_empty() \
		or new_state["size"] != state["size"] or new_state["ceiling"] != state["ceiling"]
	state = new_state.duplicate()
	if shape_changed:
		_build_shell()
	_skin_shell()
	room_changed.emit(state, {"bounds": bounds, "volume": volume, "area": area})


## 0 = neutral white test room, 1 = fully "opened up" in the level color.
func set_mood(color: Color, amount: float, duration := 2.5) -> void:
	var target_color := Color.WHITE.lerp(color, amount)
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	t.tween_property(_light, "light_color", target_color, duration)
	t.tween_property(_light, "light_energy", lerpf(1.2, 3.0, amount), duration)
	if _env:
		t.tween_property(_env, "ambient_light_color", Color(0.85, 0.85, 0.85).lerp(color, amount), duration)
		t.tween_property(_env, "ambient_light_energy", lerpf(0.6, 0.35, amount), duration)
		t.tween_property(_env, "glow_intensity", lerpf(0.0, 1.2, amount), duration)


func _load_materials() -> void:
	var plaster := StandardMaterial3D.new()
	plaster.albedo_color = Color(0.92, 0.92, 0.9)
	plaster.roughness = 0.95
	plaster.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials["Plaster"] = plaster

	var lib: Node = (load("res://assets/materials/materials.glb") as PackedScene).instantiate()
	for key in MATERIAL_NODES:
		var mi := lib.find_child(MATERIAL_NODES[key], true, false) as MeshInstance3D
		if mi == null:
			push_warning("Room: material node %s missing, falling back to plaster" % MATERIAL_NODES[key])
			_materials[key] = plaster
			continue
		var mat := (mi.get_active_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
		# Room UVs are unscaled, so project the textures in world space instead.
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * TEXTURE_SCALE
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = mat
	lib.free()


func _build_shell() -> void:
	if _shell:
		remove_child(_shell)  # leave the physics space now, not at end of frame
		_shell.queue_free()
	_shell = (load(Levels.room_path(state["size"], state["ceiling"])) as PackedScene).instantiate()
	add_child(_shell)

	# The importer's -col trimesh follows the exact shell (sloped/vaulted ceilings
	# included), so keep it for acoustic rays but out of the player's way.
	for body: StaticBody3D in _shell.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = ACOUSTIC_LAYER
		body.collision_mask = 0

	bounds = AABB()
	volume = 0.0
	area = 0.0
	var first := true
	for mi: MeshInstance3D in _shell.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mi.transform * mi.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := mi.transform * faces[i]
			var b := mi.transform * faces[i + 1]
			var c := mi.transform * faces[i + 2]
			volume += a.dot(b.cross(c)) / 6.0
			area += (b - a).cross(c - a).length() / 2.0
	volume = absf(volume)

	_build_walls()
	_light.position = Vector3(bounds.get_center().x, bounds.position.y + bounds.size.y * 0.8, bounds.get_center().z)
	_light.omni_range = bounds.size.length()


func _skin_shell() -> void:
	var mat: Material = _materials[state["material"]]
	for mi in _shell.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat


func _build_walls() -> void:
	for child in _walls.get_children():
		child.free()
	var t := 0.5
	var c := bounds.get_center()
	var s := bounds.size
	var floor_y := bounds.position.y
	var h := s.y + 2.0
	_add_box(Vector3(c.x, floor_y - t / 2, c.z), Vector3(s.x + 2, t, s.z + 2))
	_add_box(Vector3(c.x, floor_y + h / 2, bounds.position.z - t / 2), Vector3(s.x + 2, h, t))
	_add_box(Vector3(c.x, floor_y + h / 2, bounds.end.z + t / 2), Vector3(s.x + 2, h, t))
	_add_box(Vector3(bounds.position.x - t / 2, floor_y + h / 2, c.z), Vector3(t, h, s.z + 2))
	_add_box(Vector3(bounds.end.x + t / 2, floor_y + h / 2, c.z), Vector3(t, h, s.z + 2))


func _add_box(pos: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	_walls.add_child(col)
