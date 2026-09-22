class_name Speakers
extends Node3D
## One speaker per stem, standing in an arc in front of the player.
## Each plays its stem through an AudioStreamPlayer3D on its own bus
## ("Spk0", "Spk1", ...) that feeds the room bus, so the acoustics backend
## hears real source positions and every cone can move with its own stem.

signal layout_changed(positions: Array[Vector3])

const MAX_SPEAKERS := 6
const CABINET := Vector3(0.34, 0.52, 0.3)
const STAND_HEIGHT := 0.95
const ARC_DEGREES := 110.0
const MAX_RADIUS := 3.2

var room_bus: StringName
var _rigs: Array[Node3D] = []
var _players: Array[AudioStreamPlayer3D] = []
var _cones: Array[Node3D] = []
var _meters: Array[AudioEffectSpectrumAnalyzerInstance] = []
var _levels: Array[float] = []
var _cabinet_mat := StandardMaterial3D.new()
var _cone_mat := StandardMaterial3D.new()
var _trim_mat := StandardMaterial3D.new()


func _ready() -> void:
	_cabinet_mat.albedo_color = Color(0.09, 0.09, 0.1)
	_cabinet_mat.roughness = 0.55
	_cone_mat.albedo_color = Color(0.16, 0.16, 0.17)
	_cone_mat.roughness = 0.85
	_trim_mat.albedo_color = Color(0.55, 0.55, 0.57)
	_trim_mat.metallic = 0.8
	_trim_mat.roughness = 0.3


## Creates the speaker buses. Call once, after `bus` exists.
func setup(bus: StringName) -> void:
	room_bus = bus
	for i in MAX_SPEAKERS:
		var bus_name := _bus_name(i)
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, bus)
			var analyzer := AudioEffectSpectrumAnalyzer.new()
			analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
			AudioServer.add_bus_effect(idx, analyzer)


func load_stems(streams: Array) -> void:
	clear()
	for i in mini(streams.size(), MAX_SPEAKERS):
		var rig := _build_rig()
		add_child(rig)
		var p := AudioStreamPlayer3D.new()
		p.stream = streams[i]
		p.bus = _bus_name(i)
		# Distance loss only; the room model supplies everything else.
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 3.0
		p.attenuation_filter_db = 0.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.position = Vector3(0, STAND_HEIGHT + CABINET.y / 2, -CABINET.z / 2 - 0.02)
		rig.add_child(p)
		_rigs.append(rig)
		_players.append(p)
		_cones.append(rig.get_node("Cone"))
		_meters.append(AudioServer.get_bus_effect_instance(AudioServer.get_bus_index(_bus_name(i)), 0))
		_levels.append(0.0)


func clear() -> void:
	for rig in _rigs:
		rig.queue_free()
	_rigs.clear()
	_players.clear()
	_cones.clear()
	_meters.clear()
	_levels.clear()


func play() -> void:
	for p in _players:
		p.play()


## Spread the speakers on an arc around the room centre, facing the listener spot.
func layout(bounds: AABB) -> void:
	var centre := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var radius := minf(minf(bounds.size.x, bounds.size.z) / 2.0 - 0.8, MAX_RADIUS)
	var n := _rigs.size()
	var positions: Array[Vector3] = []
	for i in n:
		var t := 0.5 if n == 1 else float(i) / (n - 1)
		var angle := deg_to_rad(lerpf(-ARC_DEGREES / 2, ARC_DEGREES / 2, t))
		var rig := _rigs[i]
		rig.position = centre + Vector3(sin(angle), 0, -cos(angle)) * radius
		rig.look_at(centre)  # front face is -Z
		positions.append(rig.to_global(_players[i].position))
	layout_changed.emit(positions)


func _process(delta: float) -> void:
	# Cones follow each stem's low end, scaled by the room bus fader so they
	# rest while the reference plays.
	var fader := db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(room_bus))) \
		if room_bus else 1.0
	for i in _cones.size():
		var m := _meters[i].get_magnitude_for_frequency_range(30, 250)
		var target := clampf(linear_to_db(maxf(m.x, m.y)) / 40.0 + 1.3, 0.0, 1.0) * fader
		_levels[i] = lerpf(_levels[i], target, clampf(delta * 25.0, 0.0, 1.0))
		_cones[i].position.z = -CABINET.z / 2 - 0.01 - _levels[i] * 0.025


func _build_rig() -> Node3D:
	var rig := Node3D.new()
	var stand := _mesh(CylinderMesh.new(), _trim_mat)
	(stand.mesh as CylinderMesh).top_radius = 0.02
	(stand.mesh as CylinderMesh).bottom_radius = 0.02
	(stand.mesh as CylinderMesh).height = STAND_HEIGHT
	stand.position.y = STAND_HEIGHT / 2
	rig.add_child(stand)
	var foot := _mesh(CylinderMesh.new(), _trim_mat)
	(foot.mesh as CylinderMesh).top_radius = 0.18
	(foot.mesh as CylinderMesh).bottom_radius = 0.2
	(foot.mesh as CylinderMesh).height = 0.02
	foot.position.y = 0.01
	rig.add_child(foot)

	var cab := _mesh(BoxMesh.new(), _cabinet_mat)
	(cab.mesh as BoxMesh).size = CABINET
	cab.position.y = STAND_HEIGHT + CABINET.y / 2
	rig.add_child(cab)

	# Woofer (moves) and tweeter on the front face (-Z).
	var cone := Node3D.new()
	cone.name = "Cone"
	cone.position = Vector3(0, STAND_HEIGHT + CABINET.y * 0.38, -CABINET.z / 2 - 0.01)
	var woofer := _mesh(CylinderMesh.new(), _cone_mat)
	(woofer.mesh as CylinderMesh).top_radius = 0.11
	(woofer.mesh as CylinderMesh).bottom_radius = 0.13
	(woofer.mesh as CylinderMesh).height = 0.02
	woofer.rotation.x = PI / 2
	cone.add_child(woofer)
	var cap := _mesh(SphereMesh.new(), _trim_mat)
	(cap.mesh as SphereMesh).radius = 0.035
	(cap.mesh as SphereMesh).height = 0.035
	cap.position.z = -0.012
	cone.add_child(cap)
	rig.add_child(cone)

	var tweeter := _mesh(SphereMesh.new(), _trim_mat)
	(tweeter.mesh as SphereMesh).radius = 0.03
	(tweeter.mesh as SphereMesh).height = 0.03
	tweeter.position = Vector3(0, STAND_HEIGHT + CABINET.y * 0.8, -CABINET.z / 2 - 0.005)
	rig.add_child(tweeter)
	return rig


static func _mesh(mesh: PrimitiveMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _bus_name(i: int) -> StringName:
	return StringName("Spk%d" % i)
