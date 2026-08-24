extends Node

var worker_url = "https://matchup.chetanverma12ff.workers.dev"
var ice_servers = [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["turn:free.expressturn.com:3478"], "username": "000000002096009366", "credential": "QZgLiSLaRI1dpFC/G1GwXUF5qsI="}
]

var peer = WebRTCMultiplayerPeer.new()
var my_id = randi() % 10000
var peers_in_room = []

var poll_timer : Timer
func _ready():
	# WebRTC Mesh setup
	peer.create_mesh(my_id)
	multiplayer.multiplayer_peer = peer
	
	for server in ice_servers:
		peer.add_ice_server(server.urls[0], server.get("username", ""), server.get("credential", ""))

	# ... (purana code rehne dein) ...
	
	# Polling Timer: Har 1 second mein signals check karega
	poll_timer = Timer.new()
	add_child(poll_timer)
	poll_timer.wait_time = 1.5
	poll_timer.timeout.connect(_check_for_signals)
	poll_timer.start()

func _check_for_signals():
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_signals_received)
	http.request(worker_url + "/get_signals?id=" + str(my_id))

func _on_signals_received(_result, _code, _headers, body):
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data and data.size() > 0:
		for signal_data in data:
			var sender_id = int(signal_data.from)
			var payload = signal_data.data
			
			# WebRTC Handshake Processing
			if payload.has("type") and payload.type == "offer":
				_handle_offer(sender_id, payload)
			elif payload.has("type") and payload.type == "answer":
				peer.get_peer(sender_id).connection.set_remote_description("answer", payload.sdp)
			elif payload.has("candidate"):
				peer.get_peer(sender_id).connection.add_ice_candidate(payload.media, payload.index, payload.candidate)

func _handle_offer(sender_id, offer):
	# Agar koi offer bhej raha hai, toh use accept karo
	print("Offer received from: ", sender_id)
	# (Yahan Answer bhejne ka code aayega)
func join_lobby():
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_joined)
	http.request(worker_url + "/join?id=" + str(my_id))

func _on_joined(_result, _code, _headers, body):
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data:
		print("Joined Beast Room: ", data.roomId)
		# 49 second timer yahan se shuru hota hai
		for p in data.peers:
			if int(p.id) < my_id: # Signaling logic: Chota ID offer bhejega
				_create_offer(int(p.id))

# --- WEBSTRC HANDSHAKE (Asli Magic) ---
func _create_offer(target_id):
	var p_connection = peer.get_peer(target_id).connection
	p_connection.create_offer()
	# Offer ko Cloudflare ke raste dushre player ko bhejo
	# (Iske liye humein signaling code agle step mein chaiye)
