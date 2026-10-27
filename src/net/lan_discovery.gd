class_name LanDiscovery
extends Node
## LAN game discovery (§6.2): a host broadcasts a small UDP beacon once a second to 255.255.255.255
## and to each local /24 broadcast address; browsing devices listen and list the games they hear.
## iPhones need Apple's multicast entitlement to send or receive broadcasts; until then they join by
## code (§6.2), which works without it.

signal games_changed

const BEACON_INTERVAL: float = 1.0
## A game disappears from the list after this long without a beacon (s).
const GAME_TIMEOUT: float = 3.5

## Host side: returns the current beacon bytes.
var beacon_source: Callable
## Browse side: host address -> {info: Dictionary, seen: msec}
var games: Dictionary = {}

var _sender: PacketPeerUDP
var _listener: PacketPeerUDP
var _send_timer: float = 0.0


func start_broadcasting(source: Callable) -> void:
	stop()
	beacon_source = source
	_sender = PacketPeerUDP.new()
	_sender.set_broadcast_enabled(true)
	_send_timer = 0.0


func start_listening() -> Error:
	stop()
	_listener = PacketPeerUDP.new()
	# On Android this also takes the Wi-Fi multicast lock; without it the phone drops broadcast beacons.
	_listener.set_broadcast_enabled(true)
	var err := _listener.bind(NetProtocol.BEACON_PORT, "*")
	if err != OK:
		_listener = null
	return err


func stop() -> void:
	if _sender != null:
		_sender.close()
		_sender = null
	if _listener != null:
		_listener.close()
		_listener = null
	if not games.is_empty():
		games.clear()
		games_changed.emit()


func _process(delta: float) -> void:
	if _sender != null:
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = BEACON_INTERVAL
			_broadcast()
	if _listener != null:
		_receive()


func _broadcast() -> void:
	var bytes: PackedByteArray = beacon_source.call()
	var targets := PackedStringArray(["255.255.255.255"])
	for ip in NetProtocol.local_ipv4():
		var parts := ip.split(".")
		targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for target in targets:
		_sender.set_dest_address(target, NetProtocol.BEACON_PORT)
		_sender.put_packet(bytes)


func _receive() -> void:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var bytes := _listener.get_packet()
		var address := _listener.get_packet_ip()
		var info := NetProtocol.parse_beacon(bytes)
		if info.is_empty():
			continue
		changed = changed or not games.has(address) or games[address]["info"] != info
		games[address] = {"info": info, "seen": Time.get_ticks_msec()}
	var now := Time.get_ticks_msec()
	for address: String in games.keys():
		if now - int(games[address]["seen"]) > GAME_TIMEOUT * 1000.0:
			games.erase(address)
			changed = true
	if changed:
		games_changed.emit()
