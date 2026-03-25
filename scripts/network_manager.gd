extends Node

const PORT := 7777
const MAX_PLAYERS := 8

## peer_id → {name: String}
var players: Dictionary = {}
var local_player_name: String = "Warrior"

# Bot practice mode settings
var is_bot_practice_mode: bool = false
var bot_count: int = 3
var bot_difficulty: int = 1  # 0 = Easy, 1 = Medium, 2 = Hard

signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal connected_to_server()
signal connection_failed()
signal server_disconnected()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnect)


func host_game() -> Error:
	players[1] = {name = local_player_name}
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		players.clear()
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func join_game(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave_game() -> void:
	players.clear()
	is_bot_practice_mode = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func start_bot_practice(num_bots: int = 3, difficulty: int = 1) -> void:
	players.clear()
	players[1] = {name = local_player_name}
	is_bot_practice_mode = true
	bot_count = num_bots
	bot_difficulty = difficulty
	# No network peer needed for offline mode


# ---- internal signal handlers ----

func _on_peer_connected(id: int) -> void:
	# Server: send all known players to the newly arrived peer.
	if multiplayer.is_server():
		for pid in players:
			_register_player.rpc_id(id, pid, players[pid].name)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_left.emit(id)


func _on_connected_ok() -> void:
	# Client: introduce ourselves to the server.
	_send_my_info.rpc_id(1, local_player_name)
	connected_to_server.emit()


func _on_connection_fail() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnect() -> void:
	players.clear()
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()


# ---- RPCs ----

@rpc("any_peer", "reliable")
func _send_my_info(player_name: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = {name = player_name}
	# Broadcast to all peers so everyone's dictionary stays in sync.
	_register_player.rpc(sender, player_name)
	player_joined.emit(sender)


@rpc("authority", "call_local", "reliable")
func _register_player(peer_id: int, player_name: String) -> void:
	players[peer_id] = {name = player_name}
	player_joined.emit(peer_id)
