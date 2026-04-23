extends Node

const PORT        := 7777
const MAX_PLAYERS := 4

signal player_joined(id: int)
signal player_left(id: int)
signal connection_error()

var _peer: ENetMultiplayerPeer = null

# ── Verbindung ───────────────────────────────────────────────

func host_game() -> void:
	if _peer:
		disconnect_game()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Server-Start fehlgeschlagen (Port %d)" % PORT)
		_peer = null
		return
	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func join_game(ip: String) -> void:
	if _peer:
		disconnect_game()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, PORT)
	if err != OK:
		push_error("NetworkManager: Verbindung zu %s:%d fehlgeschlagen" % [ip, PORT])
		_peer = null
		connection_error.emit()
		return
	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	_peer = null

func is_active() -> bool:
	return _peer != null

func get_player_count() -> int:
	if not is_active():
		return 1
	return multiplayer.get_peers().size() + 1

# ── Gebäude-Sync ─────────────────────────────────────────────

func request_place_building(x: int, z: int, type: int) -> void:
	if not is_active() or multiplayer.is_server():
		BuildingManager.place_building(x, z, type as BuildingManager.Type)
		if is_active():
			_rpc_place.rpc(x, z, type)
	else:
		_rpc_place_request.rpc_id(1, x, z, type)

func request_remove_building(x: int, z: int) -> void:
	if not is_active() or multiplayer.is_server():
		BuildingManager.remove_building(x, z)
		if is_active():
			_rpc_remove.rpc(x, z)
	else:
		_rpc_remove_request.rpc_id(1, x, z)

@rpc("any_peer", "reliable")
func _rpc_place_request(x: int, z: int, type: int) -> void:
	BuildingManager.place_building(x, z, type as BuildingManager.Type)
	_rpc_place.rpc(x, z, type)

@rpc("authority", "reliable")
func _rpc_place(x: int, z: int, type: int) -> void:
	BuildingManager.place_building(x, z, type as BuildingManager.Type)

@rpc("any_peer", "reliable")
func _rpc_remove_request(x: int, z: int) -> void:
	BuildingManager.remove_building(x, z)
	_rpc_remove.rpc(x, z)

@rpc("authority", "reliable")
func _rpc_remove(x: int, z: int) -> void:
	BuildingManager.remove_building(x, z)

# ── Initial-Sync ─────────────────────────────────────────────

@rpc("authority", "reliable")
func _rpc_sync_state(buildings: Array, season: String, day: int,
		timer: float, terrain_cells: Array) -> void:
	BuildingManager.restore_buildings(buildings)
	SeasonManager.restore_from_data({"season": season, "day": day, "timer": timer})
	var terrain: Terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	if terrain:
		for cell: Dictionary in terrain_cells:
			terrain.set_cell_height(int(cell["x"]), int(cell["z"]), int(cell["h"]))

func _send_initial_state(to_id: int) -> void:
	var season_data := SeasonManager.get_save_data()
	var terrain_cells: Array = []
	var terrain: Terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	if terrain:
		for x in range(20):
			for z in range(20):
				terrain_cells.append({"x": x, "z": z, "h": terrain.get_height_at(x, z)})
	_rpc_sync_state.rpc_id(to_id,
		BuildingManager.get_all_buildings(),
		season_data.get("season", "TEMPERATE"),
		int(season_data.get("day", 1)),
		float(season_data.get("timer", 0.0)),
		terrain_cells)

# ── Peer-Events ───────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	player_joined.emit(id)
	if multiplayer.is_server():
		_send_initial_state(id)

func _on_peer_disconnected(id: int) -> void:
	player_left.emit(id)

func _on_connected_to_server() -> void:
	SceneManager.goto("res://scenes/main.tscn")

func _on_connection_failed() -> void:
	disconnect_game()
	connection_error.emit()
