class_name RaytracedAcoustics
extends AcousticsBackend
## Geometric room acoustics by ray tracing — a stand-in until SATIE drives
## the room bus, but a physically grounded one.
##
## Each pass fires rays from every speaker against the exact room shell
## (physics layer Room.ACOUSTIC_LAYER). Rays lose energy per bounce by the
## wall material's absorption in three bands, plus air absorption, and
## scatter by the material's scattering coefficient. At every bounce the hit
## point is treated as a small secondary source that "rains" energy onto the
## listener (next-event estimation), giving an energy/time response per band.
##
## From the traced paths and that response:
##   early reflections           -> two delay taps (time, level, left/right pan)
##   mean free path + energy lost
##   per bounce (per band)        -> reverb length RT60 per band, damping, low cut
##   total reflected energy      -> reverb level relative to the direct sound
## (RT60 isn't read off the decay slope: a hard room barely decays within the
## traced bounces, so the slope is noise. Loss per bounce is measured exactly.)
## The direct sound itself is the speakers' AudioStreamPlayer3D.
##
## Room interiors here are convex, so a hit point always sees the listener
## and no shadow ray is cast. Add one if rooms ever get interior walls.

const C := 343.0  # speed of sound, m/s
const BANDS := ["low", "mid", "high"]  # ~250 Hz, ~1 kHz, ~4 kHz

## Energy absorption per band. Values from typical published tables.
const ABSORPTION := {
	"Plaster": [0.10, 0.05, 0.07],     # painted plaster/gypsum board on studs
	"Wood": [0.25, 0.10, 0.08],        # wood panelling (resonant lows)
	"Soundpanel": [0.25, 0.80, 0.90],  # 50 mm acoustic foam
	"Concrete": [0.01, 0.02, 0.03],    # sealed concrete
}
## Fraction of reflected energy scattered diffusely rather than specularly.
const SCATTERING := {"Plaster": 0.1, "Wood": 0.2, "Soundpanel": 0.6, "Concrete": 0.08}
## Air absorption, energy per metre, per band.
const AIR := [0.0, 0.001, 0.006]

const RAYS_PER_SOURCE := 96
const MAX_BOUNCES := 14
const RAYS_PER_FRAME := 40       # tracing budget; one pass spans several frames
const EARLY_MS := 80.0
const DEBUG_PATHS := 28
const MAX_RT60 := 8.0            # beyond this Freeverb is effectively infinite
const SMOOTHING := 0.5           # blend of each new pass while the room stays the same
const GLIDE := 0.5               # seconds for effect parameters to follow

## TUNE: reverb send level for a given reverberant-to-direct energy ratio.
const WET_SCALE := 0.1
const MAX_WET := 0.55

var listener: Node3D
var sources: Array[Vector3] = []
var material := "Plaster"
var geometry := {}

## Latest estimate (smoothed across passes).
var rt60 := [0.5, 0.5, 0.5]
var mean_free_path := 0.0
var reverb_ratio := 0.0
var taps: Array = []  # [{ms, db, dir}]

var _reverb := AudioEffectReverb.new()
var _delays: Array[AudioEffectDelay] = [AudioEffectDelay.new(), AudioEffectDelay.new()]
var _active_delay := 0
var _param_tween: Tween
var _tap_tween: Tween

var _pass: Dictionary = {}
var _queue: Array = []  # [source_index, direction]
var _restart_in := -1
var _room_is_new := true
var _last_listener_pos := Vector3.INF
var _rng := RandomNumberGenerator.new()

var _debug_visible := false
var _debug_mesh := MeshInstance3D.new()
var _debug_paths: Array = []  # polylines from the last pass: [[Vector3, energy], ...]


func setup(bus: StringName) -> void:
	super.setup(bus)
	var idx := AudioServer.get_bus_index(bus)
	for d in _delays:
		d.dry = 1.0
		d.feedback_active = false
		d.tap1_level_db = -60.0
		d.tap2_level_db = -60.0
		AudioServer.add_bus_effect(idx, d)
	_reverb.dry = 1.0
	_reverb.wet = 0.0
	_reverb.predelay_feedback = 0.0  # Godot's default 0.4 adds a flutter echo
	_reverb.spread = 1.0
	AudioServer.add_bus_effect(idx, _reverb)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_debug_mesh.mesh = ImmediateMesh.new()
	_debug_mesh.material_override = mat
	_debug_mesh.visible = false
	add_child(_debug_mesh)


func set_listener(node: Node3D) -> void:
	listener = node


func sources_changed(positions: Array[Vector3]) -> void:
	sources = positions.duplicate()
	_request_pass()


func room_changed(state: Dictionary, geo: Dictionary) -> void:
	material = state["material"]
	geometry = geo
	_room_is_new = true
	# Wait two physics frames so a freshly swapped shell is in the space.
	_request_pass(2)


func set_debug_visible(v: bool) -> void:
	_debug_visible = v
	_debug_mesh.visible = v
	_draw_debug()


func describe() -> String:
	var lines := PackedStringArray()
	lines.append("Reverb time (RT60)   low %.2f s   mid %.2f s   high %.2f s" % rt60)
	lines.append("Mean free path   %.1f m      Reverb / direct   %+.1f dB"
		% [mean_free_path, 10.0 * log(maxf(reverb_ratio, 1e-6)) / log(10.0)])
	var parts := PackedStringArray()
	for t in taps:
		parts.append("%.0f ms %+.0f dB %s" % [t["ms"], t["db"], _side(t["dir"])])
	lines.append("Early reflections   " + (", ".join(parts) if parts else "none audible"))
	return "\n".join(lines)


# --- tracing -----------------------------------------------------------------

func _request_pass(delay_frames := 1) -> void:
	_restart_in = maxi(_restart_in, delay_frames)


func _physics_process(_delta: float) -> void:
	if listener == null or sources.is_empty() or geometry.is_empty():
		return
	# Re-trace when the listener walks somewhere new.
	var lp := listener.global_position
	if _queue.is_empty() and lp.distance_to(_last_listener_pos) > 0.35:
		_request_pass()
	if _restart_in > 0:
		_restart_in -= 1
		if _restart_in == 0:
			_begin_pass()
		return
	if _queue.is_empty():
		return
	var space := listener.get_world_3d().direct_space_state
	for i in mini(RAYS_PER_FRAME, _queue.size()):
		var job: Array = _queue.pop_back()
		_trace(space, job[0], job[1])
	if _queue.is_empty():
		_finish_pass()


func _begin_pass() -> void:
	_restart_in = -1
	_last_listener_pos = listener.global_position
	_pass = {
		"listener": listener.global_position,
		"alpha": ABSORPTION[material],
		"scatter": SCATTERING[material],
		"direct": [0.0, 0.0, 0.0],   # energy reaching the listener straight from the speakers
		"early": {},                  # bin ms -> {e: mid energy, dir: Vector3}
		"reflected": 0.0,             # mid-band energy reaching the listener via walls
		"ln_loss": [0.0, 0.0, 0.0],   # per band: sum of ln(energy kept) per bounce
		"bounces": 0,
		"free_len": 0.0,
		"free_n": 0,
		"paths": [],
	}
	for s in sources.size():
		var d := sources[s].distance_to(_pass["listener"])
		for b in 3:
			# Fraction of an omni source's energy crossing a small sphere at the
			# listener: R²/(4d²). R² cancels against the reflections below.
			_pass["direct"][b] += 1.0 / (4.0 * d * d)
	_queue.clear()
	var twist := Basis(Vector3(_rng.randf(), _rng.randf(), _rng.randf()).normalized(), _rng.randf() * TAU)
	for s in sources.size():
		for i in RAYS_PER_SOURCE:
			_queue.append([s, twist * _fibonacci_dir(i, RAYS_PER_SOURCE)])


func _trace(space: PhysicsDirectSpaceState3D, source: int, dir: Vector3) -> void:
	var origin: Vector3 = sources[source]
	var lp: Vector3 = _pass["listener"]
	var alpha: Array = _pass["alpha"]
	var scatter: float = _pass["scatter"]
	var direct_ms := origin.distance_to(lp) / C * 1000.0
	var energy := [1.0 / RAYS_PER_SOURCE, 1.0 / RAYS_PER_SOURCE, 1.0 / RAYS_PER_SOURCE]
	var travelled := 0.0
	var pos := origin
	var path := [[origin, 1.0]]
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = Room.ACOUSTIC_LAYER
	query.hit_back_faces = true

	for bounce in MAX_BOUNCES:
		query.from = pos
		query.to = pos + dir * 200.0
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break  # escaped through a seam
		var p: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		if n.dot(dir) > 0.0:
			n = -n
		var seg := pos.distance_to(p)
		travelled += seg
		if bounce > 0:
			_pass["free_len"] += seg
			_pass["free_n"] += 1
		_pass["bounces"] += 1
		for b in 3:
			var kept: float = (1.0 - alpha[b]) * exp(-AIR[b] * seg)
			_pass["ln_loss"][b] += log(kept)
			energy[b] *= kept
		path.append([p, energy[1] * RAYS_PER_SOURCE])

		# Next-event estimate: the hit patch radiates (Lambert) toward the listener.
		var to_l := lp - p
		var dl := to_l.length()
		var cos_t := maxf(n.dot(to_l / dl), 0.0)
		if cos_t > 0.0:
			var ms := (travelled + dl) / C * 1000.0 - direct_ms
			var e_mid: float = energy[1] * cos_t / (dl * dl) * exp(-AIR[1] * dl)
			_pass["reflected"] += e_mid
			if ms < EARLY_MS and bounce < 3:
				var ebin := roundf(ms)
				var slot: Dictionary = _pass["early"].get(ebin, {"e": 0.0, "dir": Vector3.ZERO})
				slot["e"] += e_mid
				slot["dir"] += (p - lp).normalized() * e_mid
				_pass["early"][ebin] = slot

		# Reflect: specular, or a diffuse (cosine-weighted) bounce.
		dir = dir.bounce(n) if _rng.randf() > scatter else _cosine_dir(n)
		pos = p + n * 0.002
		if energy[1] * RAYS_PER_SOURCE < 1e-4:
			break
	if _pass["paths"].size() < DEBUG_PATHS and source == 0:
		_pass["paths"].append(path)


func _finish_pass() -> void:
	var direct: Array = _pass["direct"]

	# Mean free path: measured between reflections; theory (4V/S) as fallback.
	var mfp: float = _pass["free_len"] / _pass["free_n"] if _pass["free_n"] > 0 \
		else 4.0 * geometry["volume"] / geometry["area"]

	# RT60 per band: energy falls by the mean per-bounce loss once every
	# mfp / C seconds, so 60 dB (ln 10^6 = 13.8) takes 13.8 * mfp / (C * loss).
	var new_rt := []
	var bounces: int = maxi(_pass["bounces"], 1)
	for b in 3:
		var loss: float = -_pass["ln_loss"][b] / bounces
		new_rt.append(clampf(13.8 * mfp / (C * maxf(loss, 1e-4)), 0.05, MAX_RT60))
	# Reflected energy at the listener, plus the untraced tail beyond
	# MAX_BOUNCES (a geometric series in the per-bounce loss).
	var kept := exp(_pass["ln_loss"][1] / bounces)
	var tail_scale := 1.0 / (1.0 - pow(kept, MAX_BOUNCES)) if kept < 0.9999 else float(MAX_BOUNCES)
	var total_ratio: float = _pass["reflected"] * tail_scale / maxf(direct[1], 1e-9)

	# Early reflections: two strongest arrivals at least 3 ms apart.
	var early := []
	for ms in _pass["early"]:
		var slot: Dictionary = _pass["early"][ms]
		early.append({"ms": float(ms), "e": slot["e"], "dir": (slot["dir"] as Vector3).normalized()})
	early.sort_custom(func(x, y): return x["e"] > y["e"])
	var new_taps := []
	for r in early:
		if new_taps.size() == 2:
			break
		if r["ms"] < 1.0 or new_taps.any(func(t): return absf(t["ms"] - r["ms"]) < 3.0):
			continue
		var db := 10.0 * log(r["e"] / maxf(direct[1], 1e-9)) / log(10.0)
		if db > -30.0:
			new_taps.append({"ms": r["ms"], "db": clampf(db, -30.0, -3.0), "dir": r["dir"]})
	new_taps.sort_custom(func(x, y): return x["ms"] < y["ms"])

	# Smooth passes within one room so walking around doesn't jitter;
	# a new room replaces the estimate outright (the effects glide anyway).
	var k := 1.0 if _room_is_new else SMOOTHING
	_room_is_new = false
	for b in 3:
		rt60[b] = lerpf(rt60[b], new_rt[b], k)
	mean_free_path = lerpf(mean_free_path, mfp, k)
	reverb_ratio = lerpf(reverb_ratio, total_ratio, k)
	taps = new_taps
	_debug_paths = _pass["paths"]
	_apply()
	_draw_debug()


# --- mapping onto Godot's effects --------------------------------------------

func _apply() -> void:
	var rt_mid: float = rt60[1]
	# Godot's reverb is Freeverb: comb feedback g = 0.7 + 0.28 * room_size over
	# ~31 ms loops, so RT60 = -3 * 0.031 / log10(g). Solve for room_size.
	var g := pow(10.0, -3.0 * 0.031 / rt_mid)
	var room_size := clampf((g - 0.7) / 0.28, 0.0, 1.0)
	var damping := clampf(1.0 - rt60[2] / rt_mid, 0.0, 1.0)
	var hipass := clampf(1.0 - rt60[0] / rt_mid, 0.0, 1.0) * 0.5
	var wet := clampf(WET_SCALE * sqrt(reverb_ratio), 0.0, MAX_WET)
	# The tail starts roughly one mean free path after the direct sound.
	var predelay := clampf(mean_free_path / C * 1000.0, 2.0, 60.0)

	if _param_tween:
		_param_tween.kill()
	_param_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	_param_tween.tween_property(_reverb, "room_size", room_size, GLIDE)
	_param_tween.tween_property(_reverb, "damping", damping, GLIDE)
	_param_tween.tween_property(_reverb, "hipass", hipass, GLIDE)
	_param_tween.tween_property(_reverb, "wet", wet, GLIDE)
	_param_tween.tween_property(_reverb, "predelay_msec", predelay, GLIDE)
	_apply_taps()


## Delay times can't glide without pitch artefacts, so new times go on the
## idle delay and the two crossfade.
func _apply_taps() -> void:
	var cur := _delays[_active_delay]
	var levels := [-60.0, -60.0]
	var times := [cur.tap1_delay_ms, cur.tap2_delay_ms]
	for i in taps.size():
		levels[i] = taps[i]["db"]
		times[i] = taps[i]["ms"]
	var target := cur
	if absf(times[0] - cur.tap1_delay_ms) > 1.0 or absf(times[1] - cur.tap2_delay_ms) > 1.0:
		_active_delay = 1 - _active_delay
		target = _delays[_active_delay]
		target.tap1_delay_ms = times[0]
		target.tap2_delay_ms = times[1]
	if _tap_tween:
		_tap_tween.kill()
	_tap_tween = create_tween().set_parallel()
	for d in _delays:
		var on := d == target
		_tap_tween.tween_property(d, "tap1_level_db", levels[0] if on else -60.0, GLIDE * 0.6)
		_tap_tween.tween_property(d, "tap2_level_db", levels[1] if on else -60.0, GLIDE * 0.6)


func _process(_delta: float) -> void:
	# Pan the reflections as the listener turns.
	if listener == null or taps.is_empty():
		return
	var right := listener.global_transform.basis.x
	var d := _delays[_active_delay]
	d.tap1_pan = clampf((taps[0]["dir"] as Vector3).dot(right), -1.0, 1.0)
	if taps.size() > 1:
		d.tap2_pan = clampf((taps[1]["dir"] as Vector3).dot(right), -1.0, 1.0)


# --- helpers -----------------------------------------------------------------

func _draw_debug() -> void:
	var im := _debug_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	if not _debug_visible or _debug_paths.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	# First few bounces of some rays from one speaker; brightness = energy left.
	var segments := 4
	for path in _debug_paths:
		for i in mini(path.size() - 1, segments):
			for j in [i, i + 1]:
				var fade := 1.0 - float(j) / (segments + 1)
				im.surface_set_color(Color(0.45, 0.9, 1.0, clampf(path[j][1] * fade * 0.8, 0.03, 0.8)))
				im.surface_add_vertex(path[j][0])
	im.surface_end()


func _side(dir: Vector3) -> String:
	if listener == null:
		return ""
	var pan := dir.dot(listener.global_transform.basis.x)
	return "left" if pan < -0.33 else ("right" if pan > 0.33 else "center")


static func _fibonacci_dir(i: int, n: int) -> Vector3:
	var y := 1.0 - 2.0 * (i + 0.5) / n
	var r := sqrt(1.0 - y * y)
	var phi := i * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(phi) * r, y, sin(phi) * r)


func _cosine_dir(n: Vector3) -> Vector3:
	var u := _rng.randf()
	var v := _rng.randf() * TAU
	var local := Vector3(cos(v) * sqrt(u), sqrt(1.0 - u), sin(v) * sqrt(u))
	var t := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var bt := n.cross(t)
	return (t * local.x + n * local.y + bt * local.z).normalized()
