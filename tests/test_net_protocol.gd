extends GutTest
## §6.2 wire format: join codes, beacons and the compact InputCommand.


func test_join_code_round_trip() -> void:
	assert_eq(NetProtocol.join_code("192.168.10.1"), "0A-01")
	assert_eq(NetProtocol.join_code("10.0.255.254"), "73-72")
	assert_eq(NetProtocol.address_from_code("0A-01", "192.168.10.57"), "192.168.10.1")
	assert_eq(NetProtocol.address_from_code(" 73 72 ", "10.0.4.4"), "10.0.255.254", "spaces and case don't matter")


func test_bad_join_codes_are_rejected() -> void:
	assert_eq(NetProtocol.address_from_code("ZZ-ZZ", "192.168.1.2"), "", "out of range")
	assert_eq(NetProtocol.address_from_code("123", "192.168.1.2"), "", "too short")
	assert_eq(NetProtocol.join_code("not an ip"), "")


func test_beacon_round_trip() -> void:
	var info := NetProtocol.parse_beacon(NetProtocol.beacon("Jafar", 2, "vs_bot", "station"))
	assert_eq(info["n"], "Jafar")
	assert_eq(int(info["p"]), 2)
	assert_eq(int(info["v"]), NetProtocol.VERSION)
	assert_eq(info["arena"], "station")
	assert_eq(NetProtocol.parse_beacon("{\"g\":\"other\"}".to_utf8_buffer()), {}, "other games are ignored")
	assert_eq(NetProtocol.parse_beacon("garbage".to_utf8_buffer()), {})


func test_command_pack_round_trip() -> void:
	var cmd := InputCommand.new()
	cmd.tick = 1234
	cmd.rope_fire = true
	cmd.rope_target = Vector2(512.5, -40.25)
	cmd.rope_held = true
	cmd.melee = true
	cmd.kick = true
	cmd.kick_dir = Vector2(0.6, -0.8)
	var back := NetProtocol.unpack_command(NetProtocol.pack_command(cmd))
	assert_eq(back.to_dict(), cmd.to_dict())


func test_missing_input_keeps_only_the_held_finger() -> void:
	var cmd := InputCommand.new()
	cmd.rope_fire = true
	cmd.rope_held = true
	cmd.melee = true
	var filler := NetProtocol.held_only(cmd, 77)
	assert_eq(filler.tick, 77)
	assert_true(filler.rope_held)
	assert_false(filler.rope_fire, "one-tick actions don't repeat")
	assert_false(filler.melee)
