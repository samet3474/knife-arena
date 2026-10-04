extends Node
## Çok oyunculu ağ katmanı (WebSocket). Sunucu dünyayı yönetir; istemciler girdi gönderir,
## sunucudan gelen anlık görüntüleri (snapshot) çizer.
## Bu düğüm hem sunucuda hem istemcide /root/Main/Net yolunda bulunur (RPC'ler için şart).

signal connected
signal connection_failed
signal disconnected

const GAME_PORT := 9080

var main # main.gd örneği
var peer: WebSocketMultiplayerPeer


func _ready() -> void:
	name = "Net"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: connected.emit())
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: disconnected.emit())


func _new_peer() -> WebSocketMultiplayerPeer:
	var p := WebSocketMultiplayerPeer.new()
	# Anlık görüntüler büyük olabilir; yavaş telefonlarda kuyruk taşmasın
	p.inbound_buffer_size = 4 * 1024 * 1024
	p.outbound_buffer_size = 4 * 1024 * 1024
	p.max_queued_packets = 4096
	return p


## Sunucunun dinlediği port. Bulut sunucularında (Render vb.) PORT ortam değişkeniyle verilir.
func server_port() -> int:
	var env := OS.get_environment("PORT")
	return env.to_int() if env.is_valid_int() else GAME_PORT


func start_server() -> Error:
	peer = _new_peer()
	var err := peer.create_server(server_port())
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


## host: "192.168.1.78" gibi bir adres (yerel ağ, ws://...:9080) ya da tam adres
## ("wss://knife-arena.onrender.com" gibi, internetteki sunucu).
func connect_to(host: String) -> Error:
	peer = _new_peer()
	var url := host if host.begins_with("ws://") or host.begins_with("wss://") else "ws://%s:%d" % [host, GAME_PORT]
	var err := peer.create_client(url)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func close() -> void:
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	peer = null


func is_online() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("Oyuncu bağlandı: ", id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		print("Oyuncu ayrıldı: ", id)
		main.server_remove_peer(id)


# --- İstemci → sunucu ---------------------------------------------------------

@rpc("any_peer", "reliable")
func c_join(info: Dictionary) -> void:
	if multiplayer.is_server():
		main.server_join(multiplayer.get_remote_sender_id(), info)


@rpc("any_peer", "unreliable_ordered")
func c_input(move: Vector2, aim: Vector2, throw_held: bool, target: int) -> void:
	if multiplayer.is_server():
		main.server_input(multiplayer.get_remote_sender_id(), move, aim, throw_held, target)


@rpc("any_peer", "reliable")
func c_dash() -> void:
	if multiplayer.is_server():
		main.server_dash(multiplayer.get_remote_sender_id())


# --- Sunucu → istemci ---------------------------------------------------------

@rpc("authority", "reliable")
func s_welcome(data: Dictionary) -> void:
	main.client_welcome(data)


@rpc("authority", "reliable")
func s_snapshot(data: Dictionary) -> void:
	main.client_snapshot(data)


## Yönetim panelinden oyuncuya altın/seviye hediyesi (oyuncunun kendi kaydına yazılır).
@rpc("authority", "reliable")
func s_grant(coins: int, levels: int) -> void:
	main.client_grant(coins, levels)


func peer_ip(id: int) -> String:
	if peer == null or not multiplayer.get_peers().has(id):
		return "?"
	return peer.get_peer_address(id)


func kick(id: int) -> void:
	if peer != null and multiplayer.get_peers().has(id):
		peer.disconnect_peer(id)
