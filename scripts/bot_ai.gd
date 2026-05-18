extends Node

# Bot AI controller - attaches to a player node to control it autonomously
# This simulates player inputs for a non-networked bot character

# Bot difficulty settings
enum Difficulty { EASY, MEDIUM, HARD }

# References
var player: CharacterBody3D = null
var target: CharacterBody3D = null

# AI settings
var difficulty: int = Difficulty.MEDIUM
var reaction_time: float = 0.3  # Seconds before reacting
var attack_range: float = 2.5
var preferred_distance: float = 2.0
var attack_cooldown_min: float = 0.8
var attack_cooldown_max: float = 1.3

# Timing state
var _think_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _block_timer: float = 0.0
var _strafe_direction: int = 0  # -1 left, 0 none, 1 right
var _strafe_timer: float = 0.0
var _dodge_cooldown: float = 0.0

# Decision state
var _wants_attack: bool = false
var _wants_block: bool = false
var _wants_dodge: bool = false
var _attack_type: int = 0  # 0=slash, 1=heavy, 2=stab, 3=overhead, 4=kick

# Difficulty modifiers
var _accuracy: float = 0.7
var _aggression: float = 0.5
var _block_chance: float = 0.5


func _ready() -> void:
	_apply_difficulty_settings()


func initialize(player_node: CharacterBody3D, bot_difficulty: int = Difficulty.MEDIUM) -> void:
	player = player_node
	difficulty = bot_difficulty
	_apply_difficulty_settings()


func _apply_difficulty_settings() -> void:
	match difficulty:
		Difficulty.EASY:
			reaction_time = 0.6
			attack_range = 2.3
			preferred_distance = 2.2
			attack_cooldown_min = 1.1
			attack_cooldown_max = 1.7
			_accuracy = 0.4
			_aggression = 0.3
			_block_chance = 0.2
		Difficulty.MEDIUM:
			reaction_time = 0.35
			attack_range = 2.5
			preferred_distance = 1.9
			attack_cooldown_min = 0.75
			attack_cooldown_max = 1.2
			_accuracy = 0.65
			_aggression = 0.5
			_block_chance = 0.45
		Difficulty.HARD:
			reaction_time = 0.12
			attack_range = 2.8
			preferred_distance = 1.55
			attack_cooldown_min = 0.45
			attack_cooldown_max = 0.85
			_accuracy = 0.85
			_aggression = 0.9
			_block_chance = 0.65


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead:
		return

	# Update timers
	_think_timer -= delta
	_attack_cooldown -= delta
	_block_timer -= delta
	_strafe_timer -= delta
	_dodge_cooldown -= delta
	_update_controlled_player_timers(delta)

	if player._is_staggered:
		_execute_staggered_movement(delta)
		return

	if player._is_dodging:
		_execute_dodge_movement(delta)
		return

	# Find target periodically
	if _think_timer <= 0:
		_think_timer = reaction_time + randf() * 0.1
		_find_target()
		_make_decisions()

	# Execute movement
	_execute_movement(delta)

	# Execute combat actions
	_execute_combat(delta)


func _find_target() -> void:
	if player == null:
		return

	var closest_dist: float = INF
	var closest_player: CharacterBody3D = null

	for other in get_tree().get_nodes_in_group("players"):
		if other == player or not is_instance_valid(other):
			continue
		if other.is_dead:
			continue
		# Don't target teammates
		if player.team > 0 and other.team == player.team:
			continue

		var dist := player.global_position.distance_to(other.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_player = other

	target = closest_player


func _make_decisions() -> void:
	if target == null:
		_wants_attack = false
		_wants_block = false
		_wants_dodge = false
		return

	var dist := player.global_position.distance_to(target.global_position)

	# Decide on blocking
	_wants_block = false
	if target._swing_active and dist < attack_range * 1.5 and player.stamina > 5.0:
		if randf() < _block_chance:
			_wants_block = true
			_block_timer = randf_range(0.25, 0.55)

	# Decide on dodging
	_wants_dodge = false
	if target._swing_active and dist < attack_range and _dodge_cooldown <= 0:
		if randf() < _block_chance * 0.5:  # Dodge less often than block
			_wants_dodge = true
			_dodge_cooldown = 2.0

	# Decide on attacking
	_wants_attack = false
	if dist < attack_range and _attack_cooldown <= 0 and not _wants_block and not player._swing_active:
		var pressure_bonus := 0.15 if dist < preferred_distance + 0.25 else 0.0
		var block_break_bonus := 0.12 if target.is_blocking else 0.0
		if _can_afford_any_attack() and randf() < min(0.98, _aggression + pressure_bonus + block_break_bonus):
			_wants_attack = true
			_attack_cooldown = randf_range(attack_cooldown_min, attack_cooldown_max)
			_attack_type = _choose_attack_type(dist)

	# Decide on strafing
	if _strafe_timer <= 0:
		_strafe_timer = 1.0 + randf() * 2.0
		var roll := randf()
		if roll < 0.3:
			_strafe_direction = -1
		elif roll < 0.6:
			_strafe_direction = 1
		else:
			_strafe_direction = 0


func _update_controlled_player_timers(delta: float) -> void:
	if player.atk_timer > 0:
		player.atk_timer = max(0.0, player.atk_timer - delta)

	if player._combo_timer > 0:
		player._combo_timer -= delta
		if player._combo_timer <= 0:
			player._combo_count = 0

	if player._parry_active:
		player._parry_timer -= delta
		if player._parry_timer <= 0:
			player._parry_active = false

	if player._dodge_cooldown > 0:
		player._dodge_cooldown = max(0.0, player._dodge_cooldown - delta)

	if player._is_staggered:
		player._stagger_timer -= delta
		if player._stagger_timer <= 0:
			player._is_staggered = false


func _execute_staggered_movement(delta: float) -> void:
	if not player.is_on_floor():
		player.velocity.y -= player.gravity * delta
	else:
		player.velocity.y = 0

	player.velocity.x = move_toward(player.velocity.x, 0, player.SPEED)
	player.velocity.z = move_toward(player.velocity.z, 0, player.SPEED)
	player.move_and_slide()


func _execute_dodge_movement(delta: float) -> void:
	player._dodge_timer -= delta
	player.velocity = player._dodge_direction * player.DODGE_SPEED
	player.velocity.y -= player.gravity * delta
	player.move_and_slide()
	if player._dodge_timer <= 0:
		player._is_dodging = false


func _execute_movement(delta: float) -> void:
	if player == null:
		return

	var move_dir := Vector3.ZERO

	if target != null and is_instance_valid(target):
		var to_target := target.global_position - player.global_position
		to_target.y = 0
		var dist := to_target.length()

		# Look at target
		if dist > 0.5:
			var look_dir := to_target.normalized()
			var target_rotation := atan2(-look_dir.x, -look_dir.z)
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, delta * (6.5 if difficulty == Difficulty.HARD else 5.0))

		# Move toward or away from target
		if player.stamina < 18.0 and dist < attack_range:
			move_dir = -to_target.normalized()
		elif dist > preferred_distance + 0.35:
			move_dir = to_target.normalized()
		elif dist < preferred_distance - 0.5:
			move_dir = -to_target.normalized()

		# Add strafe movement
		if _strafe_direction != 0:
			var right := player.global_transform.basis.x
			move_dir += right * _strafe_direction * 0.5
			move_dir = move_dir.normalized()
	else:
		# Wander when no target
		if randf() < 0.02:
			player.rotation.y += randf_range(-0.5, 0.5)
		move_dir = -player.global_transform.basis.z * 0.3

	# Apply gravity
	if not player.is_on_floor():
		player.velocity.y -= player.gravity * delta
	else:
		player.velocity.y = 0

	# Apply movement to player
	if move_dir.length() > 0.1:
		var speed : float = player.SPEED
		player.velocity.x = move_dir.x * speed
		player.velocity.z = move_dir.z * speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, player.SPEED * 0.5)
		player.velocity.z = move_toward(player.velocity.z, 0, player.SPEED * 0.5)

	player.move_and_slide()


func _execute_combat(delta: float) -> void:
	if player == null or player.is_dead:
		return

	# Stamina regen for bots (only when not blocking)
	if not player.is_blocking:
		player.stamina = min(player.MAX_STAMINA, player.stamina + player.STAMINA_REGEN * delta)

	# Handle blocking
	var was_blocking = player.is_blocking
	player.is_blocking = _wants_block and _block_timer > 0 and player.stamina > 0.0
	if player.is_blocking and not was_blocking:
		player._parry_active = true
		player._parry_timer = player.PARRY_WINDOW
	if player.is_blocking:
		player.stamina = max(0.0, player.stamina - player.STAMINA_BLOCK_DRAIN * delta)
	else:
		player._parry_active = false

	# Handle attacking
	if _wants_attack and player.atk_timer <= 0 and not player.is_blocking:
		_perform_attack()
		_wants_attack = false

	# Handle dodging
	if _wants_dodge and not player._is_dodging and player.stamina >= player.STAMINA_DODGE_COST:
		var dodge_dir := player.global_transform.basis.x * _strafe_direction if _strafe_direction != 0 else -player.global_transform.basis.z
		player._is_dodging = true
		player._dodge_timer = player.DODGE_DURATION
		player._dodge_cooldown = player.DODGE_CD
		player._dodge_direction = dodge_dir.normalized()
		player.stamina -= player.STAMINA_DODGE_COST
		_wants_dodge = false


func _can_afford_any_attack() -> bool:
	return player.stamina >= min(
		player.STAMINA_ATTACK_COST,
		min(player.STAMINA_STAB_COST, player.STAMINA_KICK_COST)
	)


func _choose_attack_type(dist: float) -> int:
	var roll := randf()
	if target != null and target.is_blocking:
		if dist < 1.7 and roll < 0.35:
			return _first_affordable_attack([4, 1, 3, 0, 2])  # Kick
		if roll < 0.65:
			return _first_affordable_attack([1, 3, 4, 0, 2])  # Heavy
		return _first_affordable_attack([3, 1, 4, 0, 2])  # Overhead

	if dist > preferred_distance + 0.6 and roll < _accuracy:
		return _first_affordable_attack([2, 0, 3, 1, 4])  # Stab from longer range
	if dist < 1.35 and roll < 0.25:
		return _first_affordable_attack([4, 0, 2, 3, 1])  # Kick up close
	if roll < 0.45:
		return _first_affordable_attack([0, 2, 4, 3, 1])  # Slash
	if roll < 0.68:
		return _first_affordable_attack([2, 0, 4, 3, 1])  # Stab
	if roll < 0.86:
		return _first_affordable_attack([3, 1, 0, 2, 4])  # Overhead
	return _first_affordable_attack([1, 3, 0, 2, 4])  # Heavy


func _first_affordable_attack(candidates: Array) -> int:
	for candidate in candidates:
		var attack_id := int(candidate)
		if player.stamina >= _attack_cost(attack_id):
			return attack_id
	return 0


func _attack_cost(attack_type: int) -> float:
	match attack_type:
		0:
			return player.STAMINA_ATTACK_COST
		1:
			return player.STAMINA_HEAVY_COST
		2:
			return player.STAMINA_STAB_COST
		3:
			return player.STAMINA_OVERHEAD_COST
		4:
			return player.STAMINA_KICK_COST
		_:
			return player.STAMINA_ATTACK_COST


func _perform_attack() -> void:
	if player == null:
		return

	match _attack_type:
		0:  # Slash
			if player.stamina >= player.STAMINA_ATTACK_COST:
				var slash_type: int = player.AttackType.SLASH_LEFT if player._last_attack_type == player.AttackType.SLASH_RIGHT else player.AttackType.SLASH_RIGHT
				player._perform_attack(slash_type)
		1:  # Heavy
			if player.stamina >= player.STAMINA_HEAVY_COST:
				player._perform_attack(player.AttackType.HEAVY)
		2:  # Stab
			if player.stamina >= player.STAMINA_STAB_COST:
				player._perform_attack(player.AttackType.STAB)
		3:  # Overhead
			if player.stamina >= player.STAMINA_OVERHEAD_COST:
				player._perform_attack(player.AttackType.OVERHEAD)
		4:  # Kick
			if player.stamina >= player.STAMINA_KICK_COST:
				player.atk_timer = player.KICK_CD
				player.stamina -= player.STAMINA_KICK_COST
				player._do_kick()
