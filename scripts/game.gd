extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BOT_AI_SCRIPT := preload("res://scripts/bot_ai.gd")

const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(  8, 1,  8),
	Vector3( -8, 1,  8),
	Vector3(  8, 1, -8),
	Vector3( -8, 1, -8),
	Vector3( 13, 1,  0),
	Vector3(-13, 1,  0),
	Vector3(  0, 1, 13),
	Vector3(  0, 1,-13),
]

const RESPAWN_DELAY := 4.0
const MATCH_DURATION := 600.0  # 10 minutes per match

const BOT_NAMES: Array[String] = [
	"Sir Slashalot", "Dame Bladeheart", "Lord Steelfang", "Lady Ironshield",
	"Baron Grimswing", "Countess Sharpwind", "Duke Hammerfist", "Duchess Thornblade",
	"Knight Shadowstrike", "Squire Quickparry", "Marshal Thundercut", "Captain Flameward"
]

@onready var players_node: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var hud: CanvasLayer = $HUD

var _spawn_idx: int = 0
var _match_time: float = MATCH_DURATION
var _match_active: bool = true

# Game mode: 0 = FFA, 1 = Team Deathmatch
var game_mode: int = 0
var team_scores: Dictionary = {1: 0, 2: 0}

# Bot management
var _bot_count: int = 0
var _bot_ais: Array = []
var _next_bot_id: int = -1000  # Negative IDs for bots to avoid conflicts
var _spawn_requested_peers: Dictionary = {}


func _ready() -> void:
	add_to_group("game_manager")

	# Check if this is a bot practice mode (offline)
	var is_offline := NetworkManager.is_bot_practice_mode

	if is_offline:
		# Spawn local player
		_spawn_local_player()
		# Spawn bots
		_spawn_bots(NetworkManager.bot_count, NetworkManager.bot_difficulty)
	else:
		if not NetworkManager.player_joined.is_connected(_on_player_joined):
			NetworkManager.player_joined.connect(_on_player_joined)
		if not NetworkManager.player_left.is_connected(_on_player_left):
			NetworkManager.player_left.connect(_on_player_left)

		if not multiplayer.is_server():
			if not NetworkManager.players.has(1):
				NetworkManager.players[1] = {name = "Host"}
			for pid in NetworkManager.players:
				_spawn_player(pid)
			_request_spawn_from_server.rpc_id(1)
			return

		_spawn_player(1)


func _process(delta: float) -> void:
	# Handle offline bot practice mode
	if NetworkManager.is_bot_practice_mode:
		if not _match_active:
			return
		_match_time -= delta
		if _match_time <= 0:
			_end_match()
		return

	if not multiplayer.is_server() or not _match_active:
		return

	_match_time -= delta
	if _match_time <= 0:
		_end_match()


func _spawn_local_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = "1"  # Local player ID
	player.player_peer_id = 1
	player.player_name = NetworkManager.local_player_name
	players_node.add_child(player, true)
	var pos := SPAWN_POSITIONS[_spawn_idx % SPAWN_POSITIONS.size()]
	_spawn_idx += 1
	player.global_position = pos

	# Setup camera for local player
	player.set_multiplayer_authority(1)


func _spawn_bots(count: int, difficulty: int = 1) -> void:
	_bot_count = count
	for i in range(count):
		_spawn_single_bot(difficulty)


func _spawn_single_bot(difficulty: int = 1) -> void:
	var bot_id := _next_bot_id
	_next_bot_id -= 1

	var player := PLAYER_SCENE.instantiate()
	player.name = str(bot_id)
	player.player_peer_id = bot_id

	# Give bot a random name
	var bot_name := BOT_NAMES[randi() % BOT_NAMES.size()]
	player.player_name = bot_name

	# Register bot in NetworkManager for scoreboard
	NetworkManager.players[bot_id] = {name = bot_name}

	players_node.add_child(player, true)
	var pos := SPAWN_POSITIONS[_spawn_idx % SPAWN_POSITIONS.size()]
	_spawn_idx += 1
	player.global_position = pos

	# Assign team in TDM mode
	if game_mode == 1:
		player.team = 1 if _spawn_idx % 2 == 0 else 2

	# Create and attach AI controller
	var ai := BOT_AI_SCRIPT.new()
	ai.name = "BotAI"
	player.add_child(ai)
	ai.initialize(player, difficulty)
	_bot_ais.append(ai)

	# Make bot visible to player (not controlled by network)
	player.body_mesh.visible = true
	player.name_label.visible = true


func _spawn_player(peer_id: int) -> void:
	if players_node.get_node_or_null(str(peer_id)) != null:
		return

	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.player_peer_id = peer_id
	player.player_name = NetworkManager.players.get(peer_id, {}).get("name", "Warrior")
	players_node.add_child(player, true)
	var pos := SPAWN_POSITIONS[_spawn_idx % SPAWN_POSITIONS.size()]
	_spawn_idx += 1
	player.global_position = pos

	# Assign team in TDM mode
	if game_mode == 1:
		player.team = 1 if _spawn_idx % 2 == 0 else 2

	if multiplayer.is_server() and not NetworkManager.is_bot_practice_mode:
		_spawn_player_remote.rpc(peer_id, player.player_name, player.team, player.global_position)


func _on_player_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		_spawn_player(peer_id)
		return

	if (
		_spawn_requested_peers.has(peer_id)
		and players_node.get_node_or_null(str(peer_id)) == null
	):
		_spawn_player(peer_id)


func _on_player_left(peer_id: int) -> void:
	_spawn_requested_peers.erase(peer_id)
	var node := players_node.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


@rpc("any_peer", "reliable")
func _request_spawn_from_server() -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 1:
		return

	_spawn_requested_peers[peer_id] = true
	if NetworkManager.players.has(peer_id):
		_spawn_player(peer_id)
	_send_existing_players(peer_id)


func _send_existing_players(peer_id: int) -> void:
	for child in players_node.get_children():
		_spawn_player_remote.rpc_id(
			peer_id,
			child.player_peer_id,
			child.player_name,
			child.team,
			child.global_position
		)


@rpc("authority", "reliable")
func _spawn_player_remote(peer_id: int, player_name: String, team: int, pos: Vector3) -> void:
	if multiplayer.is_server() or NetworkManager.is_bot_practice_mode:
		return

	NetworkManager.players[peer_id] = {name = player_name}

	var player = players_node.get_node_or_null(str(peer_id))
	if player == null:
		player = PLAYER_SCENE.instantiate()
		player.name = str(peer_id)
		players_node.add_child(player, true)

	player.player_peer_id = peer_id
	player.player_name = player_name
	player.team = team
	player.global_position = pos
	if player.has_method("_setup_network_identity"):
		player._setup_network_identity()


func on_player_killed(victim_id: int, killer_id: int) -> void:
	var victim_name: String = NetworkManager.players.get(victim_id, {}).get("name", "Unknown")
	var killer_name: String = NetworkManager.players.get(killer_id, {}).get("name", "Unknown")
	var killer_node := players_node.get_node_or_null(str(killer_id))

	# Handle offline bot practice mode
	if NetworkManager.is_bot_practice_mode:
		# Handle local player name
		if victim_id == 1:
			victim_name = NetworkManager.local_player_name
		if killer_id == 1:
			killer_name = NetworkManager.local_player_name
		_show_kill_feed_local(killer_name, victim_name)
		if killer_node:
			killer_node.kills += 1
			if game_mode == 1 and killer_node.team > 0:
				team_scores[killer_node.team] += 1
		_do_respawn_offline(victim_id)
		return

	if not multiplayer.is_server():
		return
	_show_kill_feed.rpc(killer_name, victim_name)
	if killer_node:
		killer_node.kills += 1
		# Update team score in TDM
		if game_mode == 1 and killer_node.team > 0:
			team_scores[killer_node.team] += 1
	_do_respawn(victim_id)


func _do_respawn(victim_id: int) -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	var player := players_node.get_node_or_null(str(victim_id))
	if player == null:
		return
	var pos := SPAWN_POSITIONS[randi() % SPAWN_POSITIONS.size()]
	player.do_respawn(pos)
	player.do_respawn.rpc(pos)


func _do_respawn_offline(victim_id: int) -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	var player := players_node.get_node_or_null(str(victim_id))
	if player == null:
		return
	var pos := SPAWN_POSITIONS[randi() % SPAWN_POSITIONS.size()]
	player.do_respawn(pos)


func _show_kill_feed_local(killer: String, victim: String) -> void:
	if hud and hud.has_method("show_kill"):
		hud.show_kill(killer, victim)


func _end_match() -> void:
	_match_active = false
	var winner := _determine_winner()
	if NetworkManager.is_bot_practice_mode:
		_show_match_end(winner)
	else:
		_show_match_end.rpc(winner)


func _determine_winner() -> String:
	if game_mode == 1:
		if team_scores[1] > team_scores[2]:
			return "Team Red Wins!"
		elif team_scores[2] > team_scores[1]:
			return "Team Blue Wins!"
		else:
			return "It's a Draw!"
	else:
		var data := get_scoreboard_data()
		if data.size() > 0:
			return "%s Wins with %d kills!" % [data[0].name, data[0].kills]
		return "Match Over!"


@rpc("authority", "call_local", "reliable")
func _show_match_end(winner: String) -> void:
	if hud and hud.has_method("show_match_end"):
		hud.show_match_end(winner)


@rpc("authority", "call_local", "reliable")
func _show_kill_feed(killer: String, victim: String) -> void:
	if hud and hud.has_method("show_kill"):
		hud.show_kill(killer, victim)


# Chat system
func send_chat_message(message: String) -> void:
	var sender_name := NetworkManager.local_player_name
	_broadcast_chat.rpc(sender_name, message)


@rpc("any_peer", "call_local", "reliable")
func _broadcast_chat(sender: String, message: String) -> void:
	if hud and hud.has_method("show_chat_message"):
		hud.show_chat_message(sender, message)


func get_match_time() -> float:
	return _match_time


func get_scoreboard_data() -> Array:
	var data: Array = []
	for child in players_node.get_children():
		data.append({
			"name": child.player_name,
			"kills": child.kills,
			"deaths": child.deaths,
			"health": child.health,
			"team": child.team if "team" in child else 0,
		})
	data.sort_custom(func(a, b): return a.kills > b.kills)
	return data


func return_to_menu() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://main.tscn")
