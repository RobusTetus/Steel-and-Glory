extends CanvasLayer

const MAX_FEED_ENTRIES := 6
const FEED_DURATION    := 5.0
const HIT_INDICATOR_DURATION := 0.6
const PARRY_FLASH_DURATION := 0.3
const COMBO_DISPLAY_DURATION := 2.0

var _health_bar: ProgressBar
var _health_label: Label
var _stamina_bar: ProgressBar
var _stamina_label: Label
var _dead_panel: Panel
var _dead_label: Label
var _menu_btn: Button
var _crosshair: Label
var _kill_feed_vbox: VBoxContainer
var _kills_label: Label
var _esc_hint: Label
var _scoreboard_panel: Panel
var _scoreboard_vbox: VBoxContainer
var _hit_left: ColorRect
var _hit_right: ColorRect
var _hit_top: ColorRect
var _hit_bottom: ColorRect
var _hit_timer: float = 0.0
var _block_icon: Label

# New combat HUD elements
var _parry_indicator: Label
var _parry_timer: float = 0.0
var _combo_label: Label
var _combo_timer: float = 0.0
var _stagger_indicator: Label
var _dodge_indicator: Label
var _attack_type_label: Label
var _chat_panel: Panel
var _chat_input: LineEdit
var _chat_vbox: VBoxContainer
var _chat_visible: bool = false
var _match_timer_label: Label
var _match_end_panel: Panel
var _match_end_label: Label

var _local_player: CharacterBody3D = null


func _ready() -> void:
	_build_hud()
	set_process(true)


func _process(delta: float) -> void:
	if _local_player == null:
		_find_local_player()
	_update_hud(delta)


func _find_local_player() -> void:
	var players_node := get_parent().get_node_or_null("Players")
	if players_node == null:
		return
	for child in players_node.get_children():
		# In bot practice mode, local player has ID 1
		var is_local := false
		if NetworkManager.is_bot_practice_mode:
			is_local = child.player_peer_id == 1
		else:
			is_local = child.is_multiplayer_authority()
		
		if is_local:
			_local_player = child
			_local_player.hit_received.connect(_on_hit_received)
			_local_player.parry_success.connect(_on_parry_success)
			_local_player.combo_achieved.connect(_on_combo_achieved)
			_local_player.dodge_performed.connect(_on_dodge_performed)
			_local_player.attack_started.connect(_on_attack_started)
			break


func _update_hud(delta: float) -> void:
	if _local_player == null:
		return

	var hp: int = _local_player.health
	_health_bar.value = hp
	_health_label.text = "%d / %d" % [hp, _local_player.MAX_HEALTH]

	var sp: float = _local_player.stamina
	_stamina_bar.value = sp
	_stamina_label.text = "%d / %d" % [int(sp), int(_local_player.MAX_STAMINA)]

	var dead: bool = _local_player.is_dead
	_dead_panel.visible = dead
	_crosshair.visible = not dead
	_esc_hint.visible = not dead

	_block_icon.visible = _local_player.is_blocking and not dead
	
	# Update parry indicator - show when parry window is active
	if _local_player._parry_active:
		_parry_indicator.visible = true
		_parry_indicator.text = "⚔ PARRY READY"
		_parry_indicator.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	elif _parry_timer > 0:
		_parry_timer -= delta
		_parry_indicator.visible = true
	else:
		_parry_indicator.visible = false
	
	# Update stagger indicator
	_stagger_indicator.visible = _local_player._is_staggered
	
	# Update combo display
	if _combo_timer > 0:
		_combo_timer -= delta
		_combo_label.modulate.a = min(1.0, _combo_timer / COMBO_DISPLAY_DURATION * 2)
	else:
		_combo_label.visible = false

	if dead:
		_dead_label.text = "☠  You were slain  ☠\nRespawning in a few seconds…"

	_kills_label.text = "Kills: %d   Deaths: %d" % [_local_player.kills, _local_player.deaths]

	# Hit direction indicator fade.
	if _hit_timer > 0:
		_hit_timer -= delta
		var alpha : float = clamp(_hit_timer / HIT_INDICATOR_DURATION, 0.0, 1.0) * 0.55
		_hit_left.color.a = _hit_left.color.a * alpha / max(_hit_left.color.a, 0.01) if _hit_left.color.a > 0 else 0
		_hit_right.color.a = _hit_right.color.a * alpha / max(_hit_right.color.a, 0.01) if _hit_right.color.a > 0 else 0
		_hit_top.color.a = _hit_top.color.a * alpha / max(_hit_top.color.a, 0.01) if _hit_top.color.a > 0 else 0
		_hit_bottom.color.a = _hit_bottom.color.a * alpha / max(_hit_bottom.color.a, 0.01) if _hit_bottom.color.a > 0 else 0
		if _hit_timer <= 0:
			_hit_left.visible = false
			_hit_right.visible = false
			_hit_top.visible = false
			_hit_bottom.visible = false

	# Scoreboard toggle.
	_scoreboard_panel.visible = Input.is_action_pressed("scoreboard")
	if _scoreboard_panel.visible:
		_refresh_scoreboard()
	
	# Update match timer
	var game_node = get_parent()
	if game_node and game_node.has_method("get_match_time"):
		var time_left: float = game_node.get_match_time()
		var minutes := int(time_left) / 60
		var seconds := int(time_left) % 60
		_match_timer_label.text = "%02d:%02d" % [minutes, seconds]
		if time_left < 60:
			_match_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		else:
			_match_timer_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	
	# Chat toggle
	if Input.is_action_just_pressed("chat") and not _chat_visible:
		_show_chat()
	elif Input.is_action_just_pressed("ui_cancel") and _chat_visible:
		_hide_chat()


func _on_hit_received(attacker_pos: Vector3) -> void:
	if _local_player == null:
		return
	var to_attacker := (attacker_pos - _local_player.global_position).normalized()
	var forward := -_local_player.global_transform.basis.z
	var right_dir := _local_player.global_transform.basis.x
	var dot_fwd := forward.dot(to_attacker)
	var dot_right := right_dir.dot(to_attacker)

	_hit_left.visible = false
	_hit_right.visible = false
	_hit_top.visible = false
	_hit_bottom.visible = false

	if abs(dot_right) > abs(dot_fwd):
		if dot_right > 0:
			_hit_right.visible = true
			_hit_right.color.a = 0.55
		else:
			_hit_left.visible = true
			_hit_left.color.a = 0.55
	else:
		if dot_fwd > 0:
			_hit_top.visible = true
			_hit_top.color.a = 0.55
		else:
			_hit_bottom.visible = true
			_hit_bottom.color.a = 0.55

	_hit_timer = HIT_INDICATOR_DURATION


func _on_parry_success() -> void:
	_parry_indicator.text = "✓ PARRIED!"
	_parry_indicator.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	_parry_indicator.visible = true
	_parry_timer = PARRY_FLASH_DURATION


func _on_combo_achieved(combo_count: int) -> void:
	_combo_label.visible = true
	_combo_label.modulate.a = 1.0
	if combo_count >= 5:
		_combo_label.text = "⚔ GODLIKE COMBO x%d! ⚔" % combo_count
		_combo_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	elif combo_count >= 3:
		_combo_label.text = "⚔ COMBO x%d! ⚔" % combo_count
		_combo_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	else:
		_combo_label.text = "COMBO x%d" % combo_count
		_combo_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_combo_timer = COMBO_DISPLAY_DURATION
	
	# Play combo sound
	AudioManager.play_combo(combo_count)


func _on_dodge_performed() -> void:
	# Brief dodge indicator flash
	_dodge_indicator.visible = true
	get_tree().create_timer(0.3).timeout.connect(
		func() -> void:
			if is_instance_valid(_dodge_indicator):
				_dodge_indicator.visible = false
	)


func _on_attack_started(attack_type: int) -> void:
	var attack_names := {
		0: "",
		1: "Slash ←",
		2: "Slash →",
		3: "Overhead",
		4: "Stab",
		5: "Heavy",
		6: "Kick"
	}
	_attack_type_label.text = attack_names.get(attack_type, "")
	_attack_type_label.visible = attack_type != 0
	
	get_tree().create_timer(0.5).timeout.connect(
		func() -> void:
			if is_instance_valid(_attack_type_label):
				_attack_type_label.visible = false
	)


func _show_chat() -> void:
	_chat_visible = true
	_chat_panel.visible = true
	_chat_input.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _hide_chat() -> void:
	_chat_visible = false
	_chat_panel.visible = false
	_chat_input.release_focus()
	_chat_input.text = ""
	if _local_player and not _local_player.is_dead:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_chat_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		_hide_chat()
		return
	
	var game_node = get_parent()
	if game_node and game_node.has_method("send_chat_message"):
		game_node.send_chat_message(text.strip_edges())
	
	_hide_chat()


func show_chat_message(sender: String, message: String) -> void:
	var entry := Label.new()
	entry.text = "[%s]: %s" % [sender, message]
	entry.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	entry.add_theme_font_size_override("font_size", 14)
	_chat_vbox.add_child(entry)
	
	# Limit chat history
	while _chat_vbox.get_child_count() > 20:
		_chat_vbox.get_child(0).queue_free()
	
	# Auto-fade old messages
	get_tree().create_timer(15.0).timeout.connect(
		func() -> void:
			if is_instance_valid(entry):
				entry.queue_free()
	)


func show_kill(killer: String, victim: String) -> void:
	var entry := Label.new()
	entry.text = "⚔  %s  slew  %s" % [killer, victim]
	entry.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	entry.add_theme_font_size_override("font_size", 16)
	_kill_feed_vbox.add_child(entry)
	while _kill_feed_vbox.get_child_count() > MAX_FEED_ENTRIES:
		_kill_feed_vbox.get_child(0).queue_free()
	get_tree().create_timer(FEED_DURATION).timeout.connect(
		func() -> void:
			if is_instance_valid(entry):
				entry.queue_free()
	)


func show_match_end(winner: String) -> void:
	_match_end_panel.visible = true
	_match_end_label.text = "⚔ MATCH OVER ⚔\n\n%s" % winner
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _refresh_scoreboard() -> void:
	for child in _scoreboard_vbox.get_children():
		child.queue_free()
	# Header
	var header := Label.new()
	header.text = "%-20s %6s %6s" % ["NAME", "KILLS", "DEATHS"]
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.95, 0.75, 0.15))
	_scoreboard_vbox.add_child(header)
	# Data
	var game_node = get_parent()
	if game_node and game_node.has_method("get_scoreboard_data"):
		var data: Array = game_node.get_scoreboard_data()
		for entry in data:
			var row := Label.new()
			row.text = "%-20s %6d %6d" % [entry.name, entry.kills, entry.deaths]
			row.add_theme_font_size_override("font_size", 15)
			row.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			_scoreboard_vbox.add_child(row)


func _on_menu_btn_pressed() -> void:
	var game_node = get_parent()
	if game_node and game_node.has_method("return_to_menu"):
		game_node.return_to_menu()


# ─── UI construction ───────────────────────────────────────────────

func _build_hud() -> void:
	# Crosshair (centre)
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 28)
	_crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.position -= Vector2(8, 14)
	add_child(_crosshair)

	# Block indicator (centre, below crosshair)
	_block_icon = Label.new()
	_block_icon.text = "🛡 BLOCKING"
	_block_icon.add_theme_font_size_override("font_size", 18)
	_block_icon.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	_block_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_block_icon.position += Vector2(-42, 24)
	_block_icon.visible = false
	add_child(_block_icon)
	
	# Parry indicator (centre, above crosshair)
	_parry_indicator = Label.new()
	_parry_indicator.text = "⚔ PARRY READY"
	_parry_indicator.add_theme_font_size_override("font_size", 16)
	_parry_indicator.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	_parry_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_parry_indicator.position += Vector2(-50, -50)
	_parry_indicator.visible = false
	add_child(_parry_indicator)
	
	# Stagger indicator (centre)
	_stagger_indicator = Label.new()
	_stagger_indicator.text = "💫 STAGGERED"
	_stagger_indicator.add_theme_font_size_override("font_size", 22)
	_stagger_indicator.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_stagger_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_stagger_indicator.position += Vector2(-60, 50)
	_stagger_indicator.visible = false
	add_child(_stagger_indicator)
	
	# Dodge indicator
	_dodge_indicator = Label.new()
	_dodge_indicator.text = "⟳ DODGE"
	_dodge_indicator.add_theme_font_size_override("font_size", 16)
	_dodge_indicator.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	_dodge_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dodge_indicator.position += Vector2(-30, 70)
	_dodge_indicator.visible = false
	add_child(_dodge_indicator)
	
	# Combo label (centre-right)
	_combo_label = Label.new()
	_combo_label.text = "COMBO x2"
	_combo_label.add_theme_font_size_override("font_size", 28)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_combo_label.set_anchor(SIDE_LEFT, 0.7)
	_combo_label.set_anchor(SIDE_TOP, 0.4)
	_combo_label.visible = false
	add_child(_combo_label)
	
	# Attack type indicator (below crosshair)
	_attack_type_label = Label.new()
	_attack_type_label.text = ""
	_attack_type_label.add_theme_font_size_override("font_size", 14)
	_attack_type_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_attack_type_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_attack_type_label.position += Vector2(-30, 90)
	_attack_type_label.visible = false
	add_child(_attack_type_label)

	# Health bar (bottom-left)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.set_anchor(SIDE_LEFT,   0)
	hp_bg.set_anchor(SIDE_TOP,    1)
	hp_bg.set_anchor(SIDE_RIGHT,  0)
	hp_bg.set_anchor(SIDE_BOTTOM, 1)
	hp_bg.offset_left   = 16
	hp_bg.offset_top    = -76
	hp_bg.offset_right  = 256
	hp_bg.offset_bottom = -16
	add_child(hp_bg)

	var hp_vbox := VBoxContainer.new()
	hp_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_vbox.add_theme_constant_override("separation", 4)
	hp_bg.add_child(hp_vbox)

	var hp_title := Label.new()
	hp_title.text = "  ♥  HEALTH"
	hp_title.add_theme_font_size_override("font_size", 13)
	hp_title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	hp_vbox.add_child(hp_title)

	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0
	_health_bar.max_value = 100
	_health_bar.value = 100
	_health_bar.custom_minimum_size = Vector2(0, 22)
	_health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_vbox.add_child(_health_bar)

	_health_label = Label.new()
	_health_label.text = "100 / 100"
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 12)
	_health_label.add_theme_color_override("font_color", Color.WHITE)
	hp_vbox.add_child(_health_label)

	# Stamina bar (bottom-left, above health)
	var st_bg := ColorRect.new()
	st_bg.color = Color(0, 0, 0, 0.55)
	st_bg.set_anchor(SIDE_LEFT,   0)
	st_bg.set_anchor(SIDE_TOP,    1)
	st_bg.set_anchor(SIDE_RIGHT,  0)
	st_bg.set_anchor(SIDE_BOTTOM, 1)
	st_bg.offset_left   = 16
	st_bg.offset_top    = -136
	st_bg.offset_right  = 256
	st_bg.offset_bottom = -82
	add_child(st_bg)

	var st_vbox := VBoxContainer.new()
	st_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	st_vbox.add_theme_constant_override("separation", 4)
	st_bg.add_child(st_vbox)

	var st_title := Label.new()
	st_title.text = "  ⚡ STAMINA"
	st_title.add_theme_font_size_override("font_size", 13)
	st_title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2))
	st_vbox.add_child(st_title)

	_stamina_bar = ProgressBar.new()
	_stamina_bar.min_value = 0
	_stamina_bar.max_value = 100
	_stamina_bar.value = 100
	_stamina_bar.custom_minimum_size = Vector2(0, 18)
	_stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_vbox.add_child(_stamina_bar)

	_stamina_label = Label.new()
	_stamina_label.text = "100 / 100"
	_stamina_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamina_label.add_theme_font_size_override("font_size", 12)
	_stamina_label.add_theme_color_override("font_color", Color.WHITE)
	st_vbox.add_child(_stamina_label)

	# Kill/death counter (top-left)
	var kd_bg := ColorRect.new()
	kd_bg.color = Color(0, 0, 0, 0.45)
	kd_bg.set_anchor(SIDE_LEFT,   0)
	kd_bg.set_anchor(SIDE_TOP,    0)
	kd_bg.set_anchor(SIDE_RIGHT,  0)
	kd_bg.set_anchor(SIDE_BOTTOM, 0)
	kd_bg.offset_left   = 8
	kd_bg.offset_top    = 8
	kd_bg.offset_right  = 240
	kd_bg.offset_bottom = 38
	add_child(kd_bg)

	_kills_label = Label.new()
	_kills_label.text = "Kills: 0   Deaths: 0"
	_kills_label.add_theme_font_size_override("font_size", 14)
	_kills_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_kills_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kills_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kd_bg.add_child(_kills_label)
	
	# Match timer (top-center)
	var timer_bg := ColorRect.new()
	timer_bg.color = Color(0, 0, 0, 0.55)
	timer_bg.set_anchor(SIDE_LEFT, 0.5)
	timer_bg.set_anchor(SIDE_TOP, 0)
	timer_bg.set_anchor(SIDE_RIGHT, 0.5)
	timer_bg.set_anchor(SIDE_BOTTOM, 0)
	timer_bg.offset_left = -50
	timer_bg.offset_top = 8
	timer_bg.offset_right = 50
	timer_bg.offset_bottom = 42
	add_child(timer_bg)
	
	_match_timer_label = Label.new()
	_match_timer_label.text = "10:00"
	_match_timer_label.add_theme_font_size_override("font_size", 22)
	_match_timer_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_match_timer_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_match_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_bg.add_child(_match_timer_label)

	# Kill feed (top-right)
	var feed_bg := ColorRect.new()
	feed_bg.color = Color(0, 0, 0, 0.40)
	feed_bg.set_anchor(SIDE_LEFT,   1)
	feed_bg.set_anchor(SIDE_TOP,    0)
	feed_bg.set_anchor(SIDE_RIGHT,  1)
	feed_bg.set_anchor(SIDE_BOTTOM, 0)
	feed_bg.offset_left   = -380
	feed_bg.offset_top    = 8
	feed_bg.offset_right  = -8
	feed_bg.offset_bottom = 180
	add_child(feed_bg)

	_kill_feed_vbox = VBoxContainer.new()
	_kill_feed_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kill_feed_vbox.add_theme_constant_override("separation", 4)
	feed_bg.add_child(_kill_feed_vbox)

	# Dead overlay (centre)
	_dead_panel = Panel.new()
	_dead_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dead_panel.visible = false
	var dead_style := StyleBoxFlat.new()
	dead_style.bg_color = Color(0.1, 0, 0, 0.72)
	_dead_panel.add_theme_stylebox_override("panel", dead_style)
	add_child(_dead_panel)

	_dead_label = Label.new()
	_dead_label.text = "☠  You were slain  ☠"
	_dead_label.add_theme_font_size_override("font_size", 36)
	_dead_label.add_theme_color_override("font_color", Color(0.95, 0.2, 0.2))
	_dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dead_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dead_panel.add_child(_dead_label)

	_menu_btn = Button.new()
	_menu_btn.text = "LEAVE MATCH"
	_menu_btn.custom_minimum_size = Vector2(200, 48)
	_menu_btn.set_anchor(SIDE_LEFT, 0.5)
	_menu_btn.set_anchor(SIDE_TOP, 0.65)
	_menu_btn.offset_left = -100
	_menu_btn.pressed.connect(_on_menu_btn_pressed)
	_dead_panel.add_child(_menu_btn)

	# Hit direction indicators (screen edges)
	_hit_left = _make_hit_indicator(SIDE_LEFT)
	_hit_right = _make_hit_indicator(SIDE_RIGHT)
	_hit_top = _make_hit_indicator(SIDE_TOP)
	_hit_bottom = _make_hit_indicator(SIDE_BOTTOM)

	# Scoreboard overlay (centre, shown on Tab)
	_scoreboard_panel = Panel.new()
	_scoreboard_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_scoreboard_panel.custom_minimum_size = Vector2(500, 350)
	_scoreboard_panel.offset_left = -250
	_scoreboard_panel.offset_top = -175
	_scoreboard_panel.offset_right = 250
	_scoreboard_panel.offset_bottom = 175
	_scoreboard_panel.visible = false
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = Color(0.05, 0.03, 0.03, 0.88)
	sb_style.border_color = Color(0.95, 0.75, 0.15, 0.6)
	sb_style.set_border_width_all(2)
	_scoreboard_panel.add_theme_stylebox_override("panel", sb_style)
	add_child(_scoreboard_panel)

	var sb_title := Label.new()
	sb_title.text = "⚔  SCOREBOARD  ⚔"
	sb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sb_title.add_theme_font_size_override("font_size", 22)
	sb_title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.15))
	sb_title.set_anchor(SIDE_RIGHT, 1)
	sb_title.offset_top = 10
	sb_title.offset_bottom = 40
	_scoreboard_panel.add_child(sb_title)

	_scoreboard_vbox = VBoxContainer.new()
	_scoreboard_vbox.set_anchor(SIDE_RIGHT, 1)
	_scoreboard_vbox.set_anchor(SIDE_BOTTOM, 1)
	_scoreboard_vbox.offset_left = 20
	_scoreboard_vbox.offset_top = 50
	_scoreboard_vbox.offset_right = -20
	_scoreboard_vbox.offset_bottom = -10
	_scoreboard_vbox.add_theme_constant_override("separation", 6)
	_scoreboard_panel.add_child(_scoreboard_vbox)

	# ESC hint (bottom-centre)
	_esc_hint = Label.new()
	_esc_hint.text = "LMB–attack  RMB–block/parry  F–kick  R–stab  T–overhead  Q–feint  Ctrl–dodge  Y–chat  Tab–score"
	_esc_hint.add_theme_font_size_override("font_size", 11)
	_esc_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_esc_hint.set_anchor(SIDE_LEFT,   0)
	_esc_hint.set_anchor(SIDE_TOP,    1)
	_esc_hint.set_anchor(SIDE_RIGHT,  1)
	_esc_hint.set_anchor(SIDE_BOTTOM, 1)
	_esc_hint.offset_top    = -28
	_esc_hint.offset_bottom = -4
	_esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_esc_hint)
	
	# Chat panel (bottom-left, above health bar)
	_chat_panel = Panel.new()
	_chat_panel.set_anchor(SIDE_LEFT, 0)
	_chat_panel.set_anchor(SIDE_TOP, 1)
	_chat_panel.set_anchor(SIDE_RIGHT, 0)
	_chat_panel.set_anchor(SIDE_BOTTOM, 1)
	_chat_panel.offset_left = 16
	_chat_panel.offset_top = -280
	_chat_panel.offset_right = 400
	_chat_panel.offset_bottom = -150
	var chat_style := StyleBoxFlat.new()
	chat_style.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	chat_style.border_color = Color(0.3, 0.3, 0.3, 0.6)
	chat_style.set_border_width_all(1)
	_chat_panel.add_theme_stylebox_override("panel", chat_style)
	_chat_panel.visible = false
	add_child(_chat_panel)
	
	_chat_vbox = VBoxContainer.new()
	_chat_vbox.set_anchor(SIDE_RIGHT, 1)
	_chat_vbox.set_anchor(SIDE_BOTTOM, 1)
	_chat_vbox.offset_left = 8
	_chat_vbox.offset_top = 8
	_chat_vbox.offset_right = -8
	_chat_vbox.offset_bottom = -40
	_chat_vbox.add_theme_constant_override("separation", 2)
	_chat_panel.add_child(_chat_vbox)
	
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Type message and press Enter..."
	_chat_input.set_anchor(SIDE_LEFT, 0)
	_chat_input.set_anchor(SIDE_TOP, 1)
	_chat_input.set_anchor(SIDE_RIGHT, 1)
	_chat_input.set_anchor(SIDE_BOTTOM, 1)
	_chat_input.offset_left = 8
	_chat_input.offset_top = -32
	_chat_input.offset_right = -8
	_chat_input.offset_bottom = -4
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_panel.add_child(_chat_input)
	
	# Match end overlay
	_match_end_panel = Panel.new()
	_match_end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_match_end_panel.visible = false
	var match_end_style := StyleBoxFlat.new()
	match_end_style.bg_color = Color(0.05, 0.02, 0.02, 0.9)
	_match_end_panel.add_theme_stylebox_override("panel", match_end_style)
	add_child(_match_end_panel)
	
	_match_end_label = Label.new()
	_match_end_label.text = "⚔ MATCH OVER ⚔"
	_match_end_label.add_theme_font_size_override("font_size", 48)
	_match_end_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.15))
	_match_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_match_end_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_match_end_panel.add_child(_match_end_label)
	
	var back_btn := Button.new()
	back_btn.text = "RETURN TO MENU"
	back_btn.custom_minimum_size = Vector2(200, 52)
	back_btn.set_anchor(SIDE_LEFT, 0.5)
	back_btn.set_anchor(SIDE_TOP, 0.7)
	back_btn.offset_left = -100
	back_btn.pressed.connect(_on_menu_btn_pressed)
	_match_end_panel.add_child(back_btn)


func _make_hit_indicator(side: int) -> ColorRect:
	var indicator := ColorRect.new()
	indicator.color = Color(0.9, 0.1, 0.1, 0.0)
	indicator.visible = false
	match side:
		SIDE_LEFT:
			indicator.set_anchor(SIDE_TOP, 0.2)
			indicator.set_anchor(SIDE_BOTTOM, 0.8)
			indicator.offset_left = 0
			indicator.offset_right = 8
		SIDE_RIGHT:
			indicator.set_anchor(SIDE_LEFT, 1)
			indicator.set_anchor(SIDE_RIGHT, 1)
			indicator.set_anchor(SIDE_TOP, 0.2)
			indicator.set_anchor(SIDE_BOTTOM, 0.8)
			indicator.offset_left = -8
			indicator.offset_right = 0
		SIDE_TOP:
			indicator.set_anchor(SIDE_LEFT, 0.2)
			indicator.set_anchor(SIDE_RIGHT, 0.8)
			indicator.offset_top = 0
			indicator.offset_bottom = 8
		SIDE_BOTTOM:
			indicator.set_anchor(SIDE_LEFT, 0.2)
			indicator.set_anchor(SIDE_RIGHT, 0.8)
			indicator.set_anchor(SIDE_TOP, 1)
			indicator.set_anchor(SIDE_BOTTOM, 1)
			indicator.offset_top = -8
			indicator.offset_bottom = 0
	add_child(indicator)
	return indicator
