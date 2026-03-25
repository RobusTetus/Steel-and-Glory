extends Control

# ---- UI refs (created in _build_ui) ----
var _name_edit: LineEdit
var _addr_edit: LineEdit
var _status: Label
var _host_btn: Button
var _join_btn: Button
var _practice_btn: Button
var _bot_count_slider: HSlider
var _bot_count_label: Label
var _difficulty_option: OptionButton


func _ready() -> void:
	_build_ui()
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_conn_failed)
	NetworkManager.server_disconnected.connect(_on_srv_disconnected)


func _build_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.04, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centered column
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(440, 0)
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "⚔  STEEL & GLORY  ⚔"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.15))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "First-Person Multiplayer Sword Fighting"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(sub)

	_spacer(vbox, 20)

	# Warrior name
	_label(vbox, "Your Warrior Name:")
	_name_edit = _line_edit(vbox, "Warrior", "Enter your name…")

	# Server address (for joining)
	_label(vbox, "Server Address  (for Join):")
	_addr_edit = _line_edit(vbox, "127.0.0.1", "e.g. 192.168.1.5")

	# Buttons
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)

	_host_btn = _button(hbox, "HOST GAME", _on_host_pressed)
	_join_btn = _button(hbox, "JOIN GAME", _on_join_pressed)

	_spacer(vbox, 10)
	
	# Bot Practice Section
	var practice_label := Label.new()
	practice_label.text = "─── PRACTICE WITH BOTS ───"
	practice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	practice_label.add_theme_font_size_override("font_size", 16)
	practice_label.add_theme_color_override("font_color", Color(0.75, 0.55, 0.15))
	vbox.add_child(practice_label)
	
	# Bot count slider
	var bot_hbox := HBoxContainer.new()
	bot_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(bot_hbox)
	
	var bot_label := Label.new()
	bot_label.text = "Number of Bots:"
	bot_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	bot_label.custom_minimum_size = Vector2(120, 0)
	bot_hbox.add_child(bot_label)
	
	_bot_count_slider = HSlider.new()
	_bot_count_slider.min_value = 1
	_bot_count_slider.max_value = 7
	_bot_count_slider.value = 3
	_bot_count_slider.step = 1
	_bot_count_slider.custom_minimum_size = Vector2(180, 0)
	_bot_count_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bot_count_slider.value_changed.connect(_on_bot_count_changed)
	bot_hbox.add_child(_bot_count_slider)
	
	_bot_count_label = Label.new()
	_bot_count_label.text = "3"
	_bot_count_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.15))
	_bot_count_label.custom_minimum_size = Vector2(30, 0)
	bot_hbox.add_child(_bot_count_label)
	
	# Difficulty selection
	var diff_hbox := HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(diff_hbox)
	
	var diff_label := Label.new()
	diff_label.text = "Bot Difficulty:"
	diff_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	diff_label.custom_minimum_size = Vector2(120, 0)
	diff_hbox.add_child(diff_label)
	
	_difficulty_option = OptionButton.new()
	_difficulty_option.add_item("Easy", 0)
	_difficulty_option.add_item("Medium", 1)
	_difficulty_option.add_item("Hard", 2)
	_difficulty_option.select(1)  # Default to Medium
	_difficulty_option.custom_minimum_size = Vector2(0, 36)
	_difficulty_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_hbox.add_child(_difficulty_option)
	
	# Practice button
	_practice_btn = Button.new()
	_practice_btn.text = "⚔  START PRACTICE  ⚔"
	_practice_btn.custom_minimum_size = Vector2(0, 52)
	_practice_btn.pressed.connect(_on_practice_pressed)
	vbox.add_child(_practice_btn)

	_spacer(vbox, 5)

	# Controls hint
	var hint := Label.new()
	hint.text = (
		"MOVEMENT: WASD – move  |  Mouse – look  |  Space – jump  |  Shift – sprint  |  Ctrl – dodge\n"
		+ "COMBAT: LMB – slash  |  MMB – heavy  |  R – stab  |  T – overhead  |  Q – feint  |  F – kick  |  RMB – block/parry\n"
		+ "OTHER: Tab – scoreboard  |  Y – chat  |  ESC – toggle cursor"
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(hint)

	_spacer(vbox, 8)

	# Status
	_status = Label.new()
	_status.text = "Welcome, brave warrior!"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	vbox.add_child(_status)


# ---- button handlers ----

func _on_host_pressed() -> void:
	_apply_name()
	_set_status("Starting server on port %d…" % NetworkManager.PORT, Color(0.9, 0.9, 0.4))
	var err := NetworkManager.host_game()
	if err == OK:
		_start_game()
	else:
		_set_status("Failed to host: " + str(err), Color.RED)


func _on_join_pressed() -> void:
	_apply_name()
	var addr := _addr_edit.text.strip_edges()
	if addr.is_empty():
		addr = "127.0.0.1"
	_set_buttons(false)
	_set_status("Connecting to " + addr + "…", Color(0.9, 0.9, 0.4))
	var err := NetworkManager.join_game(addr)
	if err != OK:
		_set_status("Could not initiate connection: " + str(err), Color.RED)
		_set_buttons(true)


func _on_practice_pressed() -> void:
	_apply_name()
	var bot_count := int(_bot_count_slider.value)
	var difficulty := _difficulty_option.get_selected_id()
	_set_status("Starting practice with %d bots…" % bot_count, Color(0.9, 0.9, 0.4))
	NetworkManager.start_bot_practice(bot_count, difficulty)
	_start_game()


func _on_bot_count_changed(value: float) -> void:
	_bot_count_label.text = str(int(value))


func _on_connected() -> void:
	_start_game()


func _on_conn_failed() -> void:
	_set_status("Connection failed — check address and try again.", Color.RED)
	_set_buttons(true)


func _on_srv_disconnected() -> void:
	_set_status("Server disconnected.", Color.RED)
	_set_buttons(true)


func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# ---- helpers ----

func _apply_name() -> void:
	var n := _name_edit.text.strip_edges()
	NetworkManager.local_player_name = n if not n.is_empty() else "Warrior"


func _set_status(msg: String, col: Color) -> void:
	_status.text = msg
	_status.add_theme_color_override("font_color", col)


func _set_buttons(enabled: bool) -> void:
	_host_btn.disabled = not enabled
	_join_btn.disabled = not enabled
	_practice_btn.disabled = not enabled


func _spacer(parent: Control, h: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)


func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	parent.add_child(l)


func _line_edit(parent: Control, default_text: String, placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.text = default_text
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(0, 42)
	parent.add_child(le)
	return le


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
