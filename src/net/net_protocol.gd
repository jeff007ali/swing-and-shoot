class_name NetProtocol
## Wire format and constants for LAN play (§6.2): protocol version, ports, join codes, beacons and the
## compact form of an InputCommand.

## Bump on any change to messages or sim state; peers with a different version can't join.
const VERSION: int = 6
const GAME_PORT: int = 7777
const BEACON_PORT: int = 7778
const MAX_CLIENTS: int = 3
const MAX_PLAYERS: int = 4
const BEACON_GAME_ID: String = "sns"

## ENet channels: reliable lobby/events, unreliable inputs, unreliable-ordered snapshots.
const CHANNEL_RELIABLE: int = 0
const CHANNEL_INPUTS: int = 1
const CHANNEL_SNAPSHOTS: int = 2

## Each input packet repeats this many recent commands to cover packet loss.
const INPUT_REDUNDANCY: int = 4
## Snapshots per second (every other tick at 60 Hz).
const SNAPSHOT_RATE: int = 30

const _FIRE: int = 1
const _RELEASE: int = 2
const _HELD: int = 4
const _MELEE: int = 8
const _FIRE_WEAPON: int = 16
const _KICK: int = 32


static func pack_command(cmd: InputCommand) -> Array:
	var flags := 0
	if cmd.rope_fire: flags |= _FIRE
	if cmd.rope_release: flags |= _RELEASE
	if cmd.rope_held: flags |= _HELD
	if cmd.melee: flags |= _MELEE
	if cmd.fire: flags |= _FIRE_WEAPON
	if cmd.kick: flags |= _KICK
	return [cmd.tick, flags, cmd.rope_target.x, cmd.rope_target.y, cmd.kick_dir.x, cmd.kick_dir.y, cmd.aim_dir.x, cmd.aim_dir.y, cmd.steer.x, cmd.steer.y]


static func unpack_command(a: Array) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.tick = a[0]
	var flags: int = a[1]
	cmd.rope_fire = flags & _FIRE != 0
	cmd.rope_release = flags & _RELEASE != 0
	cmd.rope_held = flags & _HELD != 0
	cmd.melee = flags & _MELEE != 0
	cmd.fire = flags & _FIRE_WEAPON != 0
	cmd.kick = flags & _KICK != 0
	cmd.rope_target = Vector2(a[2], a[3])
	cmd.kick_dir = Vector2(a[4], a[5])
	if a.size() >= 8:
		cmd.aim_dir = Vector2(a[6], a[7])
	if a.size() >= 10:
		cmd.steer = Vector2(a[8], a[9])
	return cmd


## A copy of cmd for a tick whose real command never arrived: the finger state carries over, but
## one-tick actions (fire, release, kick, melee) don't repeat.
static func held_only(cmd: InputCommand, tick: int) -> InputCommand:
	var out := InputCommand.new()
	out.tick = tick
	out.rope_held = cmd.rope_held
	out.steer = cmd.steer
	return out


## Join code (§6.2): the host's last two IPv4 octets as two base-36 pairs, e.g. 192.168.10.1 -> "0A-01".
static func join_code(ipv4: String) -> String:
	var parts := ipv4.split(".")
	if parts.size() != 4:
		return ""
	return "%s-%s" % [_base36_pair(int(parts[2])), _base36_pair(int(parts[3]))]


## The host address for a join code, using the first two octets of this device's own address.
static func address_from_code(code: String, own_ipv4: String) -> String:
	var clean := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	var own := own_ipv4.split(".")
	if clean.length() != 4 or own.size() != 4:
		return ""
	var c := _from_base36(clean.substr(0, 2))
	var d := _from_base36(clean.substr(2, 2))
	if c < 0 or c > 255 or d < 0 or d > 255:
		return ""
	return "%s.%s.%d.%d" % [own[0], own[1], c, d]


## This device's LAN IPv4 addresses (private ranges), best guess first: Wi-Fi and hotspot
## interfaces before mobile data, whose carrier 10.x address can't be reached by friends.
static func local_ipv4() -> PackedStringArray:
	var ranked: Array = []
	for iface: Dictionary in IP.get_local_interfaces():
		var rank := interface_rank(iface.get("name", ""))
		for a: String in iface.get("addresses", []):
			if is_lan_ipv4(a):
				ranked.append([rank, a])
	ranked.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out := PackedStringArray()
	for pair: Array in ranked:
		if not out.has(pair[1]):
			out.append(pair[1])
	return out


static func is_lan_ipv4(a: String) -> bool:
	if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
		return false
	return a.begins_with("192.168.") or a.begins_with("10.") or _is_172_private(a)


## 0 for Wi-Fi, hotspot and wired interfaces, 2 for mobile data and VPNs, 1 for anything else.
static func interface_rank(iface_name: String) -> int:
	var n := iface_name.to_lower()
	for prefix in ["wlan", "swlan", "ap", "softap", "wifi", "en", "eth"]:
		if n.begins_with(prefix):
			return 0
	for prefix in ["rmnet", "ccmni", "v4-", "pdp", "ppp", "tun", "utun", "ipsec", "dummy", "clat"]:
		if n.begins_with(prefix):
			return 2
	return 1


static func beacon(host_name: String, players: int, mode: String, arena: String) -> PackedByteArray:
	return JSON.stringify({
		"g": BEACON_GAME_ID, "v": VERSION, "n": host_name, "p": players, "m": MAX_PLAYERS,
		"port": GAME_PORT, "mode": mode, "arena": arena,
	}).to_utf8_buffer()


## The beacon as a Dictionary, or {} if it isn't one of ours.
static func parse_beacon(bytes: PackedByteArray) -> Dictionary:
	# A JSON instance stays quiet on bad input; stray packets on the beacon port are normal.
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or parsed.get("g", "") != BEACON_GAME_ID:
		return {}
	return parsed


static func _base36_pair(n: int) -> String:
	const DIGITS := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	return DIGITS[n / 36] + DIGITS[n % 36]


static func _from_base36(s: String) -> int:
	const DIGITS := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var hi := DIGITS.find(s[0])
	var lo := DIGITS.find(s[1])
	if hi < 0 or lo < 0:
		return -1
	return hi * 36 + lo


static func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var second := int(a.split(".")[1])
	return second >= 16 and second <= 31
