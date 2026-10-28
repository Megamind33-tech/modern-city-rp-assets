class_name Hud
extends CanvasLayer
## All 2D UI, built in code from one theme so it stays consistent. The HUD is a view:
## it emits intent signals and main.gd decides what they mean.

signal action_down
signal action_up
signal crew_order
signal tactical_toggled
signal dispatch_chosen(mode: String)
signal return_chosen(mode: String)
signal dialogue_next
signal project_bought(id: String)
signal end_shift_pressed
signal new_game_pressed
signal continue_pressed
signal pause_choice(choice: String)
signal quality_chosen(q: String)
signal volume_changed(v: float)

const NAVY := Color(0.11, 0.16, 0.23, 0.92)
const CREAM := Color(0.96, 0.92, 0.85)
const AMBER := Color(0.95, 0.66, 0.23)
const RED := Color(0.89, 0.29, 0.23)
const TEAL := Color(0.18, 0.61, 0.60)
const WEATHER := {"gusty_rain": "Gusty rain", "heavy_rain": "Heavy rain", "clearing": "Clearing skies"}

var root: Control
var stick: TouchStick
var action: HoldButton
var crew_button: Button
var prompt_label: Label
var bind_bar: ProgressBar
var day_label: Label
var money_label: Label
var timer_label: Label
var objectives: VBoxContainer
var toast: Label
var crew_status: Label
var dispatch_panel: PanelContainer
var result_panel: PanelContainer
var dialogue_panel: PanelContainer
var dashboard_panel: PanelContainer
var menu_panel: PanelContainer
var pause_panel: PanelContainer
var dispatch_banner: Button

var _meter_label: Label
var _dialogue_speaker: Label
var _dialogue_text: Label
var _toast_t := 0.0
var _theme: Theme


func _ready() -> void:
	layer = 10
	_theme = _make_theme()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	add_child(root)
	_build_hud()
	dispatch_panel = _modal(560)
	result_panel = _modal(560)
	dashboard_panel = _modal(720)
	menu_panel = _modal(520)
	pause_panel = _modal(420)
	_build_dialogue()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var panel := StyleBoxFlat.new()
	panel.bg_color = NAVY
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(20)
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(2)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b := StyleBoxFlat.new()
		b.set_corner_radius_all(12)
		b.content_margin_left = 18
		b.content_margin_right = 18
		b.content_margin_top = 10
		b.content_margin_bottom = 10
		match state:
			"normal":
				b.bg_color = RED
			"hover":
				b.bg_color = RED.lightened(0.12)
			"pressed":
				b.bg_color = RED.darkened(0.15)
			"disabled":
				b.bg_color = Color(0.32, 0.34, 0.38)
			"focus":
				b.bg_color = Color(0, 0, 0, 0)
				b.border_color = CREAM
				b.set_border_width_all(2)
		t.set_stylebox(state, "Button", b)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.75, 0.75, 0.75))
	t.set_color("font_color", "Label", CREAM)
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 12)
	return t


func _label(parent: Node, text: String, size: int = 22, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable, secondary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.focus_mode = Control.FOCUS_NONE
	if secondary:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.25, 0.33, 0.42)
		s.set_corner_radius_all(12)
		s.set_content_margin_all(12)
		b.add_theme_stylebox_override("normal", s)
		var h := s.duplicate()
		h.bg_color = Color(0.32, 0.41, 0.52)
		b.add_theme_stylebox_override("hover", h)
	b.pressed.connect(func() -> void:
		Audio.play("click", -12.0)
		cb.call())
	parent.add_child(b)
	return b


func _build_hud() -> void:
	# Top bar
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 14
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var chip := PanelContainer.new()
	top.add_child(chip)
	var chip_row := HBoxContainer.new()
	chip.add_child(chip_row)
	day_label = _label(chip_row, "Day 1", 24, AMBER)
	money_label = _label(chip_row, "£0", 24)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	timer_label = _label(top, "", 26, AMBER)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer2)
	_button(top, "View", func() -> void: tactical_toggled.emit(), true)
	_button(top, "II", func() -> void: pause_choice.emit("open"), true)
	# Objectives
	objectives = VBoxContainer.new()
	objectives.position = Vector2(22, 92)
	objectives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(objectives)
	dispatch_banner = _button(root, "Incoming call — tap to open", func() -> void: dispatch_panel.visible = true)
	dispatch_banner.position = Vector2(22, 92)
	dispatch_banner.visible = false
	# Toast
	toast = _label(root, "", 26, CREAM)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.offset_top = 150
	toast.offset_left = -330
	toast.offset_right = 330
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	toast.add_theme_constant_override("outline_size", 8)
	# Stick
	stick = TouchStick.new()
	stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stick.offset_left = 20
	stick.offset_top = -300
	stick.offset_right = 360
	stick.offset_bottom = -20
	root.add_child(stick)
	# Action button + prompt + bind meter
	action = HoldButton.new()
	action.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	action.offset_left = -230
	action.offset_top = -230
	action.offset_right = -40
	action.offset_bottom = -40
	action.down.connect(func() -> void: action_down.emit())
	action.up.connect(func() -> void: action_up.emit())
	root.add_child(action)
	prompt_label = _label(root, "", 22, CREAM)
	prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt_label.offset_left = -640
	prompt_label.offset_right = -40
	prompt_label.offset_top = -290
	prompt_label.offset_bottom = -245
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	prompt_label.add_theme_constant_override("outline_size", 6)
	bind_bar = ProgressBar.new()
	bind_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bind_bar.offset_left = -480
	bind_bar.offset_right = -250
	bind_bar.offset_top = -80
	bind_bar.offset_bottom = -52
	bind_bar.max_value = 1.0
	bind_bar.show_percentage = false
	bind_bar.visible = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	fill.set_corner_radius_all(8)
	bind_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(8)
	bind_bar.add_theme_stylebox_override("background", bg)
	root.add_child(bind_bar)
	_meter_label = _label(bind_bar, "", 16)
	_meter_label.position = Vector2(8, 2)
	# Crew order
	crew_button = _button(root, "Theo: cone off", func() -> void: crew_order.emit())
	crew_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	crew_button.offset_left = -470
	crew_button.offset_right = -250
	crew_button.offset_top = -200
	crew_button.offset_bottom = -140
	crew_button.add_theme_color_override("font_color", Color.WHITE)
	var teal := StyleBoxFlat.new()
	teal.bg_color = TEAL
	teal.set_corner_radius_all(12)
	teal.set_content_margin_all(10)
	crew_button.add_theme_stylebox_override("normal", teal)
	crew_button.visible = false
	crew_status = _label(root, "", 20, Color(0.7, 0.95, 0.92))
	crew_status.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	crew_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crew_status.offset_left = -700
	crew_status.offset_right = -250
	crew_status.offset_top = -130
	crew_status.offset_bottom = -100


func _modal(width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(width, 0)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	root.add_child(p)
	var v := VBoxContainer.new()
	v.name = "Body"
	p.add_child(v)
	return p


func _body(p: PanelContainer) -> VBoxContainer:
	var v: VBoxContainer = p.get_node("Body")
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	return v


func _wrap(parent: Node, text: String, size: int = 22, color: Color = CREAM) -> Label:
	var l := _label(parent, text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _build_dialogue() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_panel.offset_left = -380
	dialogue_panel.offset_right = 380
	dialogue_panel.offset_top = -250
	dialogue_panel.offset_bottom = -260
	dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialogue_panel.visible = false
	root.add_child(dialogue_panel)
	var v := VBoxContainer.new()
	dialogue_panel.add_child(v)
	_dialogue_speaker = _label(v, "", 22, AMBER)
	_dialogue_text = _wrap(v, "", 23)
	var hint := _label(v, "Tap to continue ▸", 16, Color(1, 1, 1, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var catcher := Button.new()
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["normal", "hover", "pressed"]:
		catcher.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	catcher.pressed.connect(func() -> void: dialogue_next.emit())
	dialogue_panel.add_child(catcher)


# --- Public API --------------------------------------------------------------

func set_status(day: int, money: int) -> void:
	day_label.text = "Day %d" % day
	money_label.text = "£%d" % money


func set_timer(seconds: float) -> void:
	if seconds < 0:
		timer_label.text = ""
		return
	var s := int(ceil(seconds))
	timer_label.text = "Storm worsens  %d:%02d" % [s / 60, s % 60]
	timer_label.add_theme_color_override("font_color", RED if seconds < 60 else AMBER)


func set_objectives(lines: Array) -> void:
	for c in objectives.get_children():
		c.queue_free()
	for l in lines:
		var lbl := _label(objectives, l["text"], 20, Color(0.6, 0.9, 0.6) if l["done"] else CREAM)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		lbl.add_theme_constant_override("outline_size", 6)


func set_action(text: String, enabled: bool, prompt: String = "") -> void:
	action.visible = text != ""
	action.text = text
	action.enabled = enabled
	prompt_label.text = prompt


## Context meter (chain bind, pull-start gauge, pumping). Default colour ramps amber→red.
func set_bind(level: float, caption: String = "", color: Variant = null) -> void:
	_meter_label.text = caption
	bind_bar.visible = level >= 0.0
	if level >= 0.0:
		bind_bar.value = level
		(bind_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color if color is Color else AMBER.lerp(RED, level)


func show_toast(text: String, seconds: float = 2.5) -> void:
	toast.text = text
	toast.modulate.a = 1.0
	_toast_t = seconds


func show_dialogue(speaker: String, line: String) -> void:
	dialogue_panel.visible = true
	_dialogue_speaker.text = speaker
	_dialogue_text.text = line


func hide_dialogue() -> void:
	dialogue_panel.visible = false


func any_modal() -> bool:
	return dispatch_panel.visible or result_panel.visible or dashboard_panel.visible or menu_panel.visible or pause_panel.visible


func set_controls_visible(on: bool) -> void:
	stick.visible = on
	if not on:
		stick.release()
		action.force_release()
		action.visible = false
		crew_button.visible = false
		bind_bar.visible = false
		prompt_label.text = ""


func open_dispatch(inst: Dictionary) -> void:
	var v := _body(dispatch_panel)
	_label(v, "INCOMING CALL", 18, RED)
	_wrap(v, inst["title"], 32)
	_wrap(v, inst["briefing"], 22)
	var sev := int(inst["severity"])
	_label(v, "Severity  %s%s     Weather  %s" % ["●".repeat(sev), "○".repeat(3 - sev), WEATHER.get(inst["weather"], inst["weather"])], 20, AMBER)
	if inst["complications"].has("live_wire"):
		_wrap(v, "Caller mentions sparks in the branches.", 20, Color(1.0, 0.8, 0.3))
	var row := HBoxContainer.new()
	v.add_child(row)
	var d := _button(row, "Drive there", func() -> void:
		dispatch_panel.visible = false
		dispatch_chosen.emit("drive"))
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var q := _button(row, "Quick dispatch", func() -> void:
		dispatch_panel.visible = false
		dispatch_chosen.emit("quick"), true)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(v, "Not yet — I'm busy", func() -> void: dispatch_panel.visible = false, true)
	dispatch_panel.visible = true


func open_result(result: Dictionary, consequence: String) -> void:
	var v := _body(result_panel)
	var ok: bool = result["outcome"] == "success"
	_label(v, "ROAD REOPENED" if ok else "THE STORM WON THIS ONE", 32, Color(0.6, 0.9, 0.6) if ok else RED)
	_label(v, result["title"], 20, Color(1, 1, 1, 0.7))
	var t := int(result["elapsed"])
	_label(v, "Time on scene  %d:%02d" % [t / 60, t % 60], 20)
	for l in result["payout"]["lines"]:
		var row := HBoxContainer.new()
		v.add_child(row)
		var name_l := _label(row, l["label"], 20)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var amt := int(l["amount"])
		_label(row, ("+£%d" % amt) if amt >= 0 else ("-£%d" % -amt), 20, Color(0.6, 0.9, 0.6) if amt >= 0 else RED)
	_label(v, "Total  £%d" % int(result["payout"]["total"]), 24, AMBER)
	if consequence != "":
		_wrap(v, consequence, 20, Color(0.85, 0.85, 0.95))
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	var d := _button(row2, "Drive back", func() -> void:
		result_panel.visible = false
		return_chosen.emit("drive"))
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var q := _button(row2, "Return to station", func() -> void:
		result_panel.visible = false
		return_chosen.emit("quick"), true)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_panel.visible = true


func open_dashboard(model: GameModel) -> void:
	var v := _body(dashboard_panel)
	_label(v, "STATION BOARD — Day %d" % model.day, 30, AMBER)
	_label(v, "Funds  £%d" % model.economy.money, 22)
	_label(v, "Crew", 22, RED)
	var ids := model.crew.members.keys()
	ids.sort()
	for id in ids:
		var m: Dictionary = model.crew.members[id]
		_label(v, "%s · %s   morale %d · trust %d · fatigue %d · xp %d" % [m["name"], m["role"], m["morale"], m["trust"], m["fatigue"], m["xp"]], 18)
	_label(v, "Projects", 22, RED)
	var projects := model.available_projects()
	if projects.is_empty():
		_label(v, "Nothing on the board right now.", 18, Color(1, 1, 1, 0.6))
	for p in projects:
		var row := HBoxContainer.new()
		v.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		_label(info, p["label"], 20)
		_wrap(info, p["description"], 16, Color(1, 1, 1, 0.65))
		var pid: String = p["id"]
		var b := _button(row, "£%d" % int(p["cost"]), func() -> void: project_bought.emit(pid))
		b.disabled = not model.economy.can_afford(int(p["cost"]))
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	var reason := model.can_end_shift()
	var end := _button(row2, "End shift" if reason == "" else reason, func() -> void:
		dashboard_panel.visible = false
		end_shift_pressed.emit())
	end.disabled = reason != ""
	end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row2, "Close", func() -> void: dashboard_panel.visible = false, true)
	dashboard_panel.visible = true


func open_menu(can_continue: bool, quality: String) -> void:
	var v := _body(menu_panel)
	var title := _label(v, "EMERGENCY CREW", 46, CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tag := _label(v, "Every rescue leaves a story.", 22, AMBER)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if can_continue:
		_button(v, "Continue", func() -> void:
			menu_panel.visible = false
			continue_pressed.emit())
	_button(v, "New game", func() -> void:
		menu_panel.visible = false
		new_game_pressed.emit(), can_continue)
	_settings_rows(v, quality)
	menu_panel.visible = true


func open_pause(has_call: bool, quality: String) -> void:
	var v := _body(pause_panel)
	_label(v, "PAUSED", 30, AMBER)
	_button(v, "Resume", func() -> void:
		pause_panel.visible = false
		pause_choice.emit("resume"))
	_button(v, "Save & main menu", func() -> void:
		pause_panel.visible = false
		pause_choice.emit("menu"), true)
	if has_call:
		_button(v, "Abandon this call", func() -> void:
			pause_panel.visible = false
			pause_choice.emit("abandon"), true)
	_settings_rows(v, quality)
	pause_panel.visible = true


func _settings_rows(v: VBoxContainer, quality: String) -> void:
	var q := HBoxContainer.new()
	v.add_child(q)
	_label(q, "Quality", 20)
	for name in ["low", "medium", "high"]:
		var qn: String = name
		var b := _button(q, qn.capitalize(), func() -> void: quality_chosen.emit(qn), qn != quality)
		b.custom_minimum_size = Vector2(110, 50)
	var vol := HBoxContainer.new()
	v.add_child(vol)
	_label(vol, "Volume", 20)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	s.custom_minimum_size = Vector2(260, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(x: float) -> void: volume_changed.emit(x))
	vol.add_child(s)


func _process(dt: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= dt
		toast.modulate.a = clampf(_toast_t / 0.5, 0.0, 1.0)
