extends CharacterBody3D

# ---- constants ----
const SPEED         := 5.0
const SPRINT_SPEED  := 8.5
const JUMP_VELOCITY := 4.8
const MOUSE_SENS    := 0.0022
const MAX_HEALTH    := 100
const MAX_STAMINA   := 100.0

# Attack damage by type
const ATTACK_DMG       := 30
const HEAVY_ATTACK_DMG := 55
const KICK_DMG         := 10
const STAB_DMG         := 35
const OVERHEAD_DMG     := 45

# Cooldowns
const ATTACK_CD       := 0.75
const HEAVY_ATTACK_CD := 1.4
const KICK_CD         := 1.0
const STAB_CD         := 0.6
const OVERHEAD_CD     := 1.0
const DODGE_CD        := 1.2
const FEINT_WINDOW    := 0.25  # Time window to cancel attack
const PARRY_WINDOW    := 0.3   # Perfect parry timing window
const BLOCK_MULT      := 0.15
const PARRY_MULT      := 0.0   # Perfect parry blocks all damage

# Stamina costs
const STAMINA_REGEN        := 18.0
const STAMINA_ATTACK_COST  := 20.0
const STAMINA_HEAVY_COST   := 35.0
const STAMINA_BLOCK_DRAIN  := 12.0
const STAMINA_SPRINT_DRAIN := 14.0
const STAMINA_KICK_COST    := 15.0
const STAMINA_JUMP_COST    := 10.0
const STAMINA_STAB_COST    := 18.0
const STAMINA_OVERHEAD_COST := 28.0
const STAMINA_DODGE_COST   := 25.0
const STAMINA_FEINT_COST   := 8.0

const SWING_SPEED := 8.0
const DODGE_SPEED := 12.0
const DODGE_DURATION := 0.35
const STAGGER_DURATION := 0.4
const COMBO_WINDOW := 0.5  # Time window to chain attacks

# Attack types enum
enum AttackType { NONE, SLASH_LEFT, SLASH_RIGHT, OVERHEAD, STAB, HEAVY, KICK }

# ---- exported / set by spawner ----
var player_peer_id: int = 1
var player_name: String = "Warrior"
var team: int = 0  # 0 = no team (FFA), 1 = team red, 2 = team blue

# ---- state ----
var health: int       = MAX_HEALTH
var stamina: float    = MAX_STAMINA
var is_dead: bool     = false
var atk_timer: float  = 0.0
var is_blocking: bool = false
var kills: int = 0
var deaths: int = 0
var assists: int = 0

# Combat state
var current_attack: int = AttackType.NONE
var _swing_progress: float = 0.0
var _swing_active: bool    = false
var _swing_is_heavy: bool  = false
var _can_feint: bool       = false
var _combo_count: int      = 0
var _combo_timer: float    = 0.0
var _last_attack_type: int = AttackType.NONE

# Parry system
var _parry_active: bool    = false
var _parry_timer: float    = 0.0
var _just_parried: bool    = false  # For visual/audio feedback

# Dodge system
var _is_dodging: bool      = false
var _dodge_timer: float    = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _dodge_cooldown: float = 0.0

# Stagger system
var _is_staggered: bool    = false
var _stagger_timer: float  = 0.0

# Audio cue variables
var _last_hit_was_parry: bool = false
var _last_damage_dealt: int = 0
var _footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL := 0.4
const SPRINT_FOOTSTEP_INTERVAL := 0.25

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ---- node refs ----
@onready var cam_pivot:    Node3D          = $CameraPivot
@onready var camera:       Camera3D        = $CameraPivot/Camera3D
@onready var sword_area:   Area3D          = $CameraPivot/SwordArea
@onready var sword_pivot:  Node3D          = $CameraPivot/SwordPivot
@onready var kick_area:    Area3D          = $CameraPivot/KickArea
@onready var kick_col:     CollisionShape3D = $CameraPivot/KickArea/CollisionShape3D
@onready var body_mesh:    MeshInstance3D  = $BodyMesh
@onready var name_label:   Label3D         = $NameLabel
@onready var sync_node:    MultiplayerSynchronizer = $Sync

signal player_killed(victim_id: int, killer_id: int)
signal hit_received(attacker_global_pos: Vector3)
signal attack_started(attack_type: int)
signal attack_landed(damage: int, is_parry: bool)
signal parry_success()
signal dodge_performed()
signal combo_achieved(combo_count: int)


func _ready() -> void:
	if name.is_valid_int():
		player_peer_id = int(name)

	if NetworkManager.players.has(player_peer_id):
		player_name = NetworkManager.players[player_peer_id].name
	name_label.text = player_name

	# In bot practice mode, only the local player (ID 1) has authority
	if NetworkManager.is_bot_practice_mode:
		if player_peer_id == 1:
			set_multiplayer_authority(1)
			sync_node.set_multiplayer_authority(1)
		# Bots don't need multiplayer authority since they're controlled by AI
	else:
		set_multiplayer_authority(player_peer_id)
		sync_node.set_multiplayer_authority(player_peer_id)

	add_to_group("players")

	# Setup camera and visibility for the local player
	var is_local_player := player_peer_id == 1 if NetworkManager.is_bot_practice_mode else is_multiplayer_authority()
	if is_local_player:
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		body_mesh.visible = false
		name_label.visible = false


# ---- input (authority only) ----

func _is_local_player() -> bool:
	if NetworkManager.is_bot_practice_mode:
		return player_peer_id == 1
	return is_multiplayer_authority()


func _input(event: InputEvent) -> void:
	if not _is_local_player():
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		cam_pivot.rotate_x(-event.relative.y * MOUSE_SENS)
		cam_pivot.rotation.x = clamp(cam_pivot.rotation.x, -PI / 2.1, PI / 2.1)
	if event.is_action_pressed("ui_cancel"):
		var m := Input.get_mouse_mode()
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if m == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	# Animate sword swing on all peers.
	_update_swing(delta)

	if not _is_local_player() or is_dead:
		return
	
	# Update timers
	_update_timers(delta)

	# Handle stagger state
	if _is_staggered:
		_stagger_timer -= delta
		if _stagger_timer <= 0:
			_is_staggered = false
		return  # Can't do anything while staggered

	# Handle dodge movement
	if _is_dodging:
		_dodge_timer -= delta
		velocity = _dodge_direction * DODGE_SPEED
		velocity.y -= gravity * delta
		move_and_slide()
		if _dodge_timer <= 0:
			_is_dodging = false
		return

	# Gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and stamina >= STAMINA_JUMP_COST:
		velocity.y = JUMP_VELOCITY
		stamina -= STAMINA_JUMP_COST

	# Sprint check.
	var is_sprinting := Input.is_action_pressed("sprint") and stamina > 0.0
	var spd := SPRINT_SPEED if is_sprinting else SPEED

	# Horizontal movement.
	var dir2 := Input.get_vector("strafe_left", "strafe_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(dir2.x, 0, dir2.y)).normalized()
	if dir:
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
	else:
		velocity.x = move_toward(velocity.x, 0, spd)
		velocity.z = move_toward(velocity.z, 0, spd)

	move_and_slide()
	
	# Footstep sounds
	if dir and is_on_floor():
		var interval := SPRINT_FOOTSTEP_INTERVAL if is_sprinting else FOOTSTEP_INTERVAL
		_footstep_timer -= delta
		if _footstep_timer <= 0:
			AudioManager.play_footstep(is_sprinting)
			_footstep_timer = interval

	# Stamina drain for sprinting (only while actually moving).
	if is_sprinting and dir:
		stamina = max(0.0, stamina - STAMINA_SPRINT_DRAIN * delta)

	# Blocking and parry system
	_handle_blocking(delta)

	# Stamina regen (only when not blocking and not sprinting-while-moving).
	if not is_blocking and not (is_sprinting and dir):
		stamina = min(MAX_STAMINA, stamina + STAMINA_REGEN * delta)

	# Attack cooldown.
	if atk_timer > 0:
		atk_timer -= delta

	# Handle combat inputs
	_handle_combat_input()

	# Dodge/roll (double tap direction or dedicated button)
	if Input.is_action_just_pressed("dodge") and _dodge_cooldown <= 0 and stamina >= STAMINA_DODGE_COST and is_on_floor():
		_perform_dodge(dir if dir else -transform.basis.z)


func _update_timers(delta: float) -> void:
	if _combo_timer > 0:
		_combo_timer -= delta
		if _combo_timer <= 0:
			_combo_count = 0
	
	if _dodge_cooldown > 0:
		_dodge_cooldown -= delta


func _handle_blocking(delta: float) -> void:
	var wants_block := Input.is_action_pressed("block") and stamina > 0.0
	
	# Parry window - activated when first pressing block
	if Input.is_action_just_pressed("block") and stamina > 0.0:
		_parry_active = true
		_parry_timer = PARRY_WINDOW
	
	if _parry_active:
		_parry_timer -= delta
		if _parry_timer <= 0:
			_parry_active = false
	
	is_blocking = wants_block
	if is_blocking:
		stamina = max(0.0, stamina - STAMINA_BLOCK_DRAIN * delta)


func _handle_combat_input() -> void:
	# Feint - cancel current attack
	if Input.is_action_just_pressed("feint") and _swing_active and _can_feint and stamina >= STAMINA_FEINT_COST:
		_cancel_attack()
		return

	if atk_timer > 0 or is_blocking:
		return

	# Directional attacks based on mouse movement + attack button
	# Or use dedicated buttons
	
	# Light attack (slash based on horizontal mouse movement, or default slash right)
	if Input.is_action_just_pressed("attack") and stamina >= STAMINA_ATTACK_COST:
		var attack_type := _get_directional_attack()
		_perform_attack(attack_type)
	
	# Heavy attack
	elif Input.is_action_just_pressed("heavy_attack") and stamina >= STAMINA_HEAVY_COST:
		_perform_attack(AttackType.HEAVY)
	
	# Stab attack (alternate attack)
	elif Input.is_action_just_pressed("stab") and stamina >= STAMINA_STAB_COST:
		_perform_attack(AttackType.STAB)
	
	# Overhead attack
	elif Input.is_action_just_pressed("overhead") and stamina >= STAMINA_OVERHEAD_COST:
		_perform_attack(AttackType.OVERHEAD)

	# Kick.
	elif Input.is_action_just_pressed("kick") and stamina >= STAMINA_KICK_COST:
		atk_timer = KICK_CD
		stamina -= STAMINA_KICK_COST
		if NetworkManager.is_bot_practice_mode:
			_do_kick()
		else:
			_do_kick.rpc()


func _get_directional_attack() -> int:
	# Alternate between slash left and slash right for combos
	if _combo_count > 0 and _last_attack_type == AttackType.SLASH_RIGHT:
		return AttackType.SLASH_LEFT
	elif _combo_count > 0 and _last_attack_type == AttackType.SLASH_LEFT:
		return AttackType.SLASH_RIGHT
	else:
		return AttackType.SLASH_RIGHT


func _perform_attack(attack_type: int) -> void:
	var cost: float
	var cooldown: float
	
	match attack_type:
		AttackType.SLASH_LEFT, AttackType.SLASH_RIGHT:
			cost = STAMINA_ATTACK_COST
			cooldown = ATTACK_CD
		AttackType.HEAVY:
			cost = STAMINA_HEAVY_COST
			cooldown = HEAVY_ATTACK_CD
		AttackType.STAB:
			cost = STAMINA_STAB_COST
			cooldown = STAB_CD
		AttackType.OVERHEAD:
			cost = STAMINA_OVERHEAD_COST
			cooldown = OVERHEAD_CD
		_:
			cost = STAMINA_ATTACK_COST
			cooldown = ATTACK_CD
	
	atk_timer = cooldown
	stamina -= cost
	_can_feint = true
	
	# Check for combo
	if _combo_timer > 0 and _last_attack_type != AttackType.NONE:
		_combo_count += 1
		combo_achieved.emit(_combo_count)
		# Visual combo effect
		if _combo_count >= 2:
			VFXManager.create_combo_effect(global_position, _combo_count)
	else:
		_combo_count = 1
	
	_combo_timer = COMBO_WINDOW
	_last_attack_type = attack_type
	current_attack = attack_type
	
	attack_started.emit(attack_type)
	if NetworkManager.is_bot_practice_mode:
		_do_directional_attack(attack_type)
	else:
		_do_directional_attack.rpc(attack_type)
	
	# Play swing sound locally
	if _is_local_player():
		AudioManager.play_swing(attack_type == AttackType.HEAVY)


func _cancel_attack() -> void:
	if not _can_feint:
		return
	
	stamina -= STAMINA_FEINT_COST
	_swing_active = false
	_swing_progress = 0.0
	_can_feint = false
	current_attack = AttackType.NONE
	sword_pivot.rotation = Vector3.ZERO
	atk_timer = 0.15  # Small cooldown after feint


func _perform_dodge(direction: Vector3) -> void:
	_is_dodging = true
	_dodge_timer = DODGE_DURATION
	_dodge_cooldown = DODGE_CD
	_dodge_direction = direction.normalized()
	stamina -= STAMINA_DODGE_COST
	dodge_performed.emit()
	if not NetworkManager.is_bot_practice_mode:
		_broadcast_dodge.rpc()
	
	# Play dodge sound locally
	if _is_local_player():
		AudioManager.play_dodge()


func apply_stagger() -> void:
	_is_staggered = true
	_stagger_timer = STAGGER_DURATION
	# Cancel any current attack
	if _swing_active:
		_swing_active = false
		_swing_progress = 0.0
		sword_pivot.rotation = Vector3.ZERO
	
	# Play stagger sound and effect
	if _is_local_player():
		AudioManager.play_stagger()
	VFXManager.create_stagger_effect(global_position)


# ---- sword swing animation ----

func _update_swing(delta: float) -> void:
	if _swing_active:
		_swing_progress += delta * SWING_SPEED
		
		# Disable feint after the feint window
		if _swing_progress > FEINT_WINDOW * SWING_SPEED:
			_can_feint = false
		
		if _swing_progress >= 1.0:
			_swing_active = false
			_swing_progress = 0.0
			sword_pivot.rotation = Vector3.ZERO
			current_attack = AttackType.NONE
		else:
			_animate_swing()


func _animate_swing() -> void:
	var angle: float
	var progress := _swing_progress
	
	match current_attack:
		AttackType.SLASH_RIGHT:
			angle = sin(progress * PI) * 1.2
			sword_pivot.rotation = Vector3(0, -angle, 0)
		AttackType.SLASH_LEFT:
			angle = sin(progress * PI) * 1.2
			sword_pivot.rotation = Vector3(0, angle, 0)
		AttackType.OVERHEAD:
			angle = sin(progress * PI) * 1.8
			sword_pivot.rotation = Vector3(angle, 0, 0)
		AttackType.STAB:
			# Thrust forward animation
			var thrust := sin(progress * PI) * 0.5
			sword_pivot.position.z = -0.5 - thrust
			sword_pivot.rotation = Vector3(-0.3, 0, 0)
		AttackType.HEAVY:
			angle = sin(progress * PI) * 2.0
			sword_pivot.rotation = Vector3(angle * 0.7, -angle * 0.5, angle * 0.3)
		_:
			angle = sin(progress * PI) * 1.2
			sword_pivot.rotation = Vector3(0, -angle, 0)


# ---- combat RPCs ----

@rpc("any_peer", "call_local", "reliable")
func _do_directional_attack(attack_type: int) -> void:
	if is_dead:
		return
	
	_swing_active = true
	_swing_progress = 0.0
	current_attack = attack_type
	
	# Reset sword pivot position for stab
	if attack_type != AttackType.STAB:
		sword_pivot.position = Vector3(0.35, -0.25, -0.5)
	
	var dmg := _get_damage_for_attack(attack_type)
	var hit_someone := false
	
	for body in sword_area.get_overlapping_bodies():
		if body == self or not body.has_method("receive_hit"):
			continue
		# Team check
		if team > 0 and body.has_method("get_team") and body.get_team() == team:
			continue
		var target: CharacterBody3D = body
		# In offline bot mode, call directly instead of RPC
		if NetworkManager.is_bot_practice_mode:
			target.receive_hit(dmg, player_peer_id, attack_type)
		else:
			target.receive_hit.rpc_id(target.player_peer_id, dmg, player_peer_id, attack_type)
		hit_someone = true
	
	if hit_someone:
		attack_landed.emit(dmg, false)


func _get_damage_for_attack(attack_type: int) -> int:
	match attack_type:
		AttackType.SLASH_LEFT, AttackType.SLASH_RIGHT:
			return ATTACK_DMG
		AttackType.HEAVY:
			return HEAVY_ATTACK_DMG
		AttackType.STAB:
			return STAB_DMG
		AttackType.OVERHEAD:
			return OVERHEAD_DMG
		_:
			return ATTACK_DMG


func get_team() -> int:
	return team


@rpc("any_peer", "call_local", "reliable")
func _do_attack(heavy: bool) -> void:
	if is_dead:
		return
	_swing_active = true
	_swing_progress = 0.0
	_swing_is_heavy = heavy
	current_attack = AttackType.HEAVY if heavy else AttackType.SLASH_RIGHT
	var dmg := HEAVY_ATTACK_DMG if heavy else ATTACK_DMG
	for body in sword_area.get_overlapping_bodies():
		if body == self or not body.has_method("receive_hit"):
			continue
		var target: CharacterBody3D = body
		# In offline bot mode, call directly instead of RPC
		if NetworkManager.is_bot_practice_mode:
			target.receive_hit(dmg, player_peer_id, current_attack)
		else:
			target.receive_hit.rpc_id(target.player_peer_id, dmg, player_peer_id, current_attack)


@rpc("any_peer", "call_local", "reliable")
func _do_kick() -> void:
	if is_dead:
		return
	kick_col.disabled = false
	await get_tree().create_timer(0.15).timeout
	for body in kick_area.get_overlapping_bodies():
		if body == self or not body.has_method("receive_kick"):
			continue
		# Team check
		if team > 0 and body.has_method("get_team") and body.get_team() == team:
			continue
		var target: CharacterBody3D = body
		# In offline bot mode, call directly instead of RPC
		if NetworkManager.is_bot_practice_mode:
			target.receive_kick(KICK_DMG, player_peer_id)
		else:
			target.receive_kick.rpc_id(target.player_peer_id, KICK_DMG, player_peer_id)
	kick_col.disabled = true


@rpc("any_peer", "call_local", "reliable")
func _broadcast_dodge() -> void:
	# Visual feedback for dodge on all clients
	pass  # Could add dodge animation/effects here


@rpc("any_peer", "reliable")
func receive_hit(amount: int, attacker_id: int, attack_type: int = AttackType.SLASH_RIGHT) -> void:
	if is_dead or _is_dodging:
		return
	
	var final_damage := amount
	var was_parried := false
	var is_local := _is_local_player()
	
	# Check for perfect parry
	if _parry_active and is_blocking:
		final_damage = int(amount * PARRY_MULT)
		was_parried = true
		_parry_active = false
		_just_parried = true
		parry_success.emit()
		
		# Play parry sound and effect
		if is_local:
			AudioManager.play_block(true)
		VFXManager.create_parry_effect(global_position + Vector3(0, 1.5, 0))
		
		# Stagger the attacker on parry
		var attacker := get_parent().get_node_or_null(str(attacker_id))
		if attacker and attacker.has_method("apply_stagger"):
			if NetworkManager.is_bot_practice_mode:
				attacker.apply_stagger()
			else:
				attacker.apply_stagger.rpc_id(attacker_id)
	elif is_blocking:
		final_damage = int(amount * BLOCK_MULT)
		# Play block sound and effect
		if is_local:
			AudioManager.play_block(false)
		VFXManager.create_block_effect(global_position + Vector3(0, 1.5, 0))
		# Heavy attacks and overheads can stagger through block
		if attack_type in [AttackType.HEAVY, AttackType.OVERHEAD] and stamina < 20:
			apply_stagger()
			final_damage = int(amount * 0.5)
	else:
		# Play hit sound and effect
		if is_local:
			AudioManager.play_hit(attack_type in [AttackType.HEAVY, AttackType.OVERHEAD])
		VFXManager.create_hit_effect(global_position + Vector3(0, 1.2, 0))
		# Apply stagger on heavy hits when not blocking
		if attack_type in [AttackType.HEAVY, AttackType.OVERHEAD]:
			apply_stagger()
	
	health = max(0, health - final_damage)
	_last_damage_dealt = final_damage
	_last_hit_was_parry = was_parried
	
	if NetworkManager.is_bot_practice_mode:
		_broadcast_health(health)
		_notify_hit(attacker_id)
		if health == 0:
			_broadcast_death(attacker_id)
	else:
		_broadcast_health.rpc(health)
		_notify_hit.rpc_id(player_peer_id, attacker_id)
		if health == 0:
			_broadcast_death.rpc(attacker_id)


@rpc("any_peer", "reliable")
func receive_kick(_amount: int, attacker_id: int) -> void:
	if is_dead or _is_dodging:
		return
	
	# Play kick impact sound
	if _is_local_player():
		AudioManager.play_kick()
	
	if is_blocking:
		# Kick breaks blocking and causes stagger
		is_blocking = false
		stamina = max(0.0, stamina - 30.0)
		apply_stagger()
	health = max(0, health - _amount)
	
	if NetworkManager.is_bot_practice_mode:
		_broadcast_health(health)
		_notify_hit(attacker_id)
		if health == 0:
			_broadcast_death(attacker_id)
	else:
		_broadcast_health.rpc(health)
		_notify_hit.rpc_id(player_peer_id, attacker_id)
		if health == 0:
			_broadcast_death.rpc(attacker_id)


@rpc("any_peer", "call_local", "reliable")
func apply_stagger_rpc() -> void:
	apply_stagger()


@rpc("any_peer", "reliable")
func _notify_hit(attacker_id: int) -> void:
	var attacker := get_parent().get_node_or_null(str(attacker_id))
	if attacker:
		hit_received.emit(attacker.global_position)


@rpc("authority", "call_local", "reliable")
func _broadcast_health(new_health: int) -> void:
	health = new_health


@rpc("authority", "call_local", "reliable")
func _broadcast_death(killer_id: int) -> void:
	if is_dead:
		return
	is_dead = true
	deaths += 1
	visible = false
	
	# Play death sound and effect
	AudioManager.play_death()
	VFXManager.create_death_effect(global_position + Vector3(0, 1.0, 0))
	
	if _is_local_player():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Notify game manager via group instead of fragile parent chain.
	for node in get_tree().get_nodes_in_group("game_manager"):
		if node.has_method("on_player_killed"):
			node.on_player_killed(player_peer_id, killer_id)


@rpc("authority", "call_local", "reliable")
func do_respawn(pos: Vector3) -> void:
	health = MAX_HEALTH
	stamina = MAX_STAMINA
	is_dead = false
	visible = true
	global_position = pos
	velocity = Vector3.ZERO
	if _is_local_player():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
