class_name Hud
extends CanvasLayer
## All on-screen UI, built in code so the whole layout reads in one place.
## Emits intents; game.gd decides what they mean.

signal option_chosen(key: String, value: String)
signal reference_pressed
signal overlay_confirmed
signal rays_toggled(on: bool)

const FONT := preload("res://assets/fonts/Manrope.ttf")
const ROWS := ["size", "ceiling", "material"]
const ROW_NAMES := {"size": "Size", "ceiling": "Ceiling", "material": "Material"}

const INK := Color(0.07, 0.08, 0.1)
const PAPER := Color(0.97, 0.96, 0.93)
const GLASS := Color(0.07, 0.08, 0.1, 0.8)
const LINE := Color(1, 1, 1, 0.1)
const MUTED := Color(1, 1, 1, 0.58)
const RIGHT := Color("6be3a4")

var _root := Control.new()
var _hud := Control.new()
var _eyebrow := Label.new()
var _title := Label.new()
var _premise := Label.new()
var _listen_button := Button.new()
var _listen_dots: Array[Panel] = []
var _listen_caption := Label.new()
var _reference_card: PanelContainer
var _rays_button := Button.new()
var _acoustics_label := Label.new()
var _rows := {}  # key -> {"buttons": {value: Button}, "status": Label, "dot": Panel}
var _toast := PanelContainer.new()
var _toast_label := Label.new()
var _toast_tween: Tween
var _overlay := Control.new()
var _overlay_dim := ColorRect.new()
var _overlay_title := Label.new()
var _overlay_body := Label.new()
var _overlay_button := Button.new()
var _accent := PAPER


func _ready() -> void:
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)
	_build_level_card()
	_build_reference_card()
	_build_room_controls()
	_build_acoustics_card()
	_build_toast()
	_build_overlay()


# --- public API --------------------------------------------------------------

func show_level(index: int, count: int, level: Dictionary) -> void:
	_accent = level["clear_color"]
	_eyebrow.text = "LEVEL %d OF %d" % [index + 1, count]
	_eyebrow.add_theme_color_override("font_color", _accent.lerp(Color.WHITE, 0.35))
	_title.text = level["title"]
	_premise.text = level["premise"]


## `correct[key]` is true/false, or absent while the player hasn't touched that row.
func show_room(state: Dictionary, correct: Dictionary) -> void:
	for key in ROWS:
		var row: Dictionary = _rows[key]
		var is_right: bool = correct.get(key, false)
		for value in row["buttons"]:
			var b: Button = row["buttons"][value]
			b.set_pressed_no_signal(value == state[key])
			if is_right and value == state[key]:
				b.add_theme_stylebox_override("pressed", _box(RIGHT, RIGHT))
				b.add_theme_stylebox_override("hover_pressed", _box(RIGHT, RIGHT))
			else:
				b.remove_theme_stylebox_override("pressed")
				b.remove_theme_stylebox_override("hover_pressed")
		var status: Label = row["status"]
		var dot: Panel = row["dot"]
		var was_right := status.text != ""
		status.text = "Sounds right" if is_right else ""
		dot.visible = is_right
		if is_right and not was_right:
			_pop(row["buttons"][state[key]])
			dot.modulate.a = 0.0
			create_tween().tween_property(dot, "modulate:a", 1.0, 0.25)


## Locks the room controls without greying them out, so the solved room stays visible.
func set_controls_enabled(enabled: bool) -> void:
	_reference_card.visible = enabled
	for key in ROWS:
		for b in _rows[key]["buttons"].values():
			(b as Button).mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func show_reference(playing: bool, listens_left: int) -> void:
	_listen_button.text = "Stop reference" if playing else "Hear the reference"
	_listen_button.disabled = listens_left <= 0 and not playing
	for i in _listen_dots.size():
		_listen_dots[i].modulate.a = 1.0 if i < listens_left else 0.18
	_listen_caption.text = "No listens left. Trust your ears." if listens_left <= 0 \
		else "%d of %d listens left" % [listens_left, Levels.REFERENCE_LISTENS]


func show_acoustics(text: String) -> void:
	_acoustics_label.text = text


func toast(text: String, hold := 2.2) -> void:
	_toast_label.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(hold)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func show_overlay(title: String, body: String, button_text: String, dim := true) -> void:
	_overlay_title.text = title
	_overlay_body.text = body
	_overlay_button.text = button_text
	_overlay_dim.visible = dim
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.4)
	_hud.visible = not dim


func hide_overlay() -> void:
	_overlay.visible = false
	_hud.visible = true


# --- layout ------------------------------------------------------------------

func _build_level_card() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_style_label(_eyebrow, 13, 800, MUTED, 3)
	_style_label(_title, 40, 800)
	_style_label(_premise, 17, 500, Color(1, 1, 1, 0.78))
	_premise.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_premise.custom_minimum_size.x = 420
	for l in [_eyebrow, _title, _premise]:
		box.add_child(l)
	var card := _card(box)
	_hud.add_child(card)
	_anchor(card, Vector2(0, 0), Vector2(28, 28))


func _build_reference_card() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_style_primary(_listen_button)
	_listen_button.custom_minimum_size = Vector2(250, 50)
	_listen_button.pressed.connect(reference_pressed.emit)
	box.add_child(_listen_button)

	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 8)
	for i in Levels.REFERENCE_LISTENS:
		var d := _dot(PAPER, 8)
		dots.add_child(d)
		_listen_dots.append(d)
	box.add_child(dots)
	_style_label(_listen_caption, 13, 600, MUTED)
	_listen_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_listen_caption)

	_reference_card = _card(box)
	_hud.add_child(_reference_card)
	_anchor(_reference_card, Vector2(1, 0), Vector2(-28, 28))


func _build_room_controls() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	for key in ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var label_col := VBoxContainer.new()
		label_col.custom_minimum_size.x = 118
		label_col.alignment = BoxContainer.ALIGNMENT_CENTER
		label_col.add_theme_constant_override("separation", 2)
		var heading := Label.new()
		_style_label(heading, 13, 800, MUTED, 3)
		heading.text = ROW_NAMES[key].to_upper()
		label_col.add_child(heading)
		var status_row := HBoxContainer.new()
		status_row.add_theme_constant_override("separation", 6)
		var dot := _dot(RIGHT, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.visible = false
		status_row.add_child(dot)
		var status := Label.new()
		_style_label(status, 13, 700, RIGHT)
		status_row.add_child(status)
		label_col.add_child(status_row)
		row.add_child(label_col)

		var group := ButtonGroup.new()
		var buttons := {}
		for value in Levels.OPTIONS[key]:
			var b := Button.new()
			b.text = Levels.option_label(key, value)
			b.toggle_mode = true
			b.button_group = group
			b.focus_mode = Control.FOCUS_NONE
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.custom_minimum_size = Vector2(124, 44)
			b.pressed.connect(option_chosen.emit.bind(key, value))
			row.add_child(b)
			buttons[value] = b
		_rows[key] = {"buttons": buttons, "status": status, "dot": dot}
		box.add_child(row)

	var hint := Label.new()
	_style_label(hint, 13, 600, Color(1, 1, 1, 0.42))
	hint.text = "Hold right mouse to look around  ·  WASD to walk"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var card := _card(box)
	_hud.add_child(card)
	_anchor(card, Vector2(0.5, 1), Vector2(0, -28))


## Bottom-left: toggle for the ray view, plus the numbers behind the sound.
func _build_acoustics_card() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_rays_button.text = "Show sound rays"
	_rays_button.toggle_mode = true
	_rays_button.focus_mode = Control.FOCUS_NONE
	_rays_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_rays_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_rays_button.toggled.connect(func(on: bool):
		_rays_button.text = "Hide sound rays" if on else "Show sound rays"
		_acoustics_label.visible = on
		rays_toggled.emit(on))
	box.add_child(_rays_button)
	_style_label(_acoustics_label, 13, 600, Color(1, 1, 1, 0.75))
	_acoustics_label.add_theme_constant_override("line_spacing", 4)
	_acoustics_label.visible = false
	box.add_child(_acoustics_label)
	var card := _card(box, 14, 14)
	_hud.add_child(card)
	_anchor(card, Vector2(0, 1), Vector2(28, -28))


func _build_toast() -> void:
	_style_label(_toast_label, 20, 700)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	_toast.add_theme_stylebox_override("panel", _box(GLASS, LINE, 999, 26, 12))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_hud.add_child(_toast)
	_anchor(_toast, Vector2(0.5, 0.36), Vector2.ZERO)


func _build_overlay() -> void:
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)
	_overlay_dim.color = Color(0.02, 0.02, 0.03, 0.72)
	_overlay_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_overlay_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	_style_label(_overlay_title, 56, 800)
	_style_label(_overlay_body, 18, 500, Color(1, 1, 1, 0.8))
	for l in [_overlay_title, _overlay_body]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_body.custom_minimum_size.x = 560
	_style_primary(_overlay_button)
	_overlay_button.custom_minimum_size = Vector2(240, 54)
	_overlay_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_overlay_button.pressed.connect(overlay_confirmed.emit)
	box.add_child(_overlay_button)
	var card := _card(box, 48, 24)
	center.add_child(card)


# --- styling helpers ---------------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font(600)
	t.default_font_size = 16
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_stylebox("panel", "PanelContainer", _box(GLASS, LINE, 18, 22, 20))
	t.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.3)))
	t.set_stylebox("pressed", "Button", _box(PAPER, PAPER))
	t.set_stylebox("hover_pressed", "Button", _box(PAPER, PAPER))
	t.set_stylebox("disabled", "Button", _box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.05)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	return t


func _style_primary(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _font(800))
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal", _box(PAPER, PAPER, 999))
	b.add_theme_stylebox_override("hover", _box(Color.WHITE, Color.WHITE, 999))
	b.add_theme_stylebox_override("pressed", _box(Color(0.85, 0.84, 0.8), Color(0.85, 0.84, 0.8), 999))
	b.add_theme_stylebox_override("disabled", _box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.08), 999))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, INK)


func _style_label(l: Label, size: int, weight: int, color := Color.WHITE, tracking := 0) -> void:
	l.add_theme_font_override("font", _font(weight, tracking))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _card(content: Control, margin := 22, radius := 18) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(GLASS, LINE, radius, margin, margin - 2))
	card.add_child(content)
	return card


func _dot(color: Color, diameter: int) -> Panel:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(diameter, diameter)
	var box := _box(color, color, diameter / 2, 0, 0)
	box.set_border_width_all(0)
	box.corner_detail = 12
	d.add_theme_stylebox_override("panel", box)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## Pin `c` to a fractional point of the screen; it grows away from that edge.
static func _anchor(c: Control, point: Vector2, offset: Vector2) -> void:
	c.anchor_left = point.x
	c.anchor_right = point.x
	c.anchor_top = point.y
	c.anchor_bottom = point.y
	c.offset_left = offset.x
	c.offset_right = offset.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y
	c.grow_horizontal = [Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN][int(point.x * 2)]
	c.grow_vertical = [Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN][clampi(roundi(point.y * 2), 0, 2)]


func _pop(c: Control) -> void:
	c.pivot_offset = c.size / 2
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2(1.08, 1.08), 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.25)


static func _box(bg: Color, border: Color, radius := 10, margin_h := 16, margin_v := 8) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(1)
	b.set_corner_radius_all(radius)
	b.content_margin_left = margin_h
	b.content_margin_right = margin_h
	b.content_margin_top = margin_v
	b.content_margin_bottom = margin_v
	return b


static func _font(weight: int, tracking := 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = FONT
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	if tracking:
		f.set_spacing(TextServer.SPACING_GLYPH, tracking)
	return f
