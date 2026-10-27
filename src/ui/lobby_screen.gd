class_name LobbyScreen
extends Control
## LAN party lobby (§6.2): host a game or join one on the same Wi-Fi or phone hotspot. No internet.
## Hosting shows the join code, the player slots and the same match picker as PLAY (mode, arena,
## bots). Joining lists games found by beacon and also takes a join code or an IP address. When the
## host starts, every device opens the match.

const MATCH_SCENE: String = "res://src/match/match.tscn"
const MAIN_MENU_SCENE: String = "res://src/ui/main_menu.tscn"
const BACKGROUND: Texture2D = preload("res://assets/art/arena/darkPurple.png")
const STEPS: Array[String] = [
	"1.  Put every phone on the same Wi-Fi, or turn on one phone's hotspot and connect the others to it.",
	"2.  One player taps HOST GAME.",
	"3.  Everyone else taps JOIN GAME and picks the game.",
]
const TIP: String = "No internet needed. Office and guest Wi-Fi often block this: use a hotspot."
## Give up on a host that doesn't answer after this long (s).
const JOIN_TIMEOUT: float = 8.0
## Space kept clear around the screen edge (phone notches and rounded corners).
const EDGE: Vector2 = Vector2(64, 40)

enum Page { CHOOSE, HOST, BROWSE, WAITING }

## Tests turn this off to stay on the page.
var change_scene: bool = true
var net: NetSession

var _page: Page = Page.CHOOSE
var _title: Label
var _back: Button
var _body: Control
var _status: Label
var _name_edit: LineEdit
## Parts of the current page that follow the lobby: the player slots, the game list, the start button.
var _slots_box: VBoxContainer
var _games_box: VBoxContainer
var _start: Button
var _hint: Label
var _info: Label
var _searching: Label
var _setup: MatchSetup
var _join_attempt: int = 0


func _ready() -> void:
	if net == null:
		net = Net
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(EDGE.x))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(EDGE.y))
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	column.add_child(header)
	_back = UiTheme.back_button(_go_back)
	header.add_child(_back)
	_title = UiTheme.label("LAN PARTY", 56, UiTheme.ACCENT)
	header.add_child(_title)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)
	_status = UiTheme.label("", 24, UiTheme.ACCENT_2)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	net.lobby_changed.connect(_on_lobby_changed)
	net.joined.connect(func() -> void:
		_status.text = ""
		_show(Page.WAITING))
	net.join_failed.connect(_on_join_failed)
	net.host_left.connect(func() -> void:
		_status.text = "The host closed the game."
		_show(Page.CHOOSE))
	net.match_starting.connect(_on_match_starting)
	net.discovery.games_changed.connect(_fill_games)
	_show(Page.CHOOSE)


func _process(_delta: float) -> void:
	if _searching != null and is_instance_valid(_searching):
		_searching.text = "LOOKING FOR GAMES" + ".".repeat(1 + int(Time.get_ticks_msec() / 400.0) % 3)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _show(page: Page) -> void:
	_page = page
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_slots_box = null
	_games_box = null
	_start = null
	_hint = null
	_info = null
	_searching = null
	_setup = null
	match _page:
		Page.CHOOSE:
			_title.text = "LAN PARTY"
			_back.text = "BACK"
			_build_choose()
		Page.HOST:
			_title.text = "YOUR GAME"
			_back.text = "CLOSE"
			_build_host()
		Page.BROWSE:
			_title.text = "JOIN GAME"
			_back.text = "BACK"
			_build_browse()
		Page.WAITING:
			_title.text = "LOBBY"
			_back.text = "LEAVE"
			_build_waiting()


func _build_choose() -> void:
	var center := _centered()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	center.add_child(column)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 20)
	column.add_child(name_row)
	name_row.add_child(UiTheme.label("YOUR NAME", 24, UiTheme.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.text = ProfileStore.display_name()
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(520, 72)
	_name_edit.add_theme_font_size_override("font_size", 30)
	name_row.add_child(_name_edit)

	var tiles := HBoxContainer.new()
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles.add_theme_constant_override("separation", 32)
	column.add_child(tiles)
	tiles.add_child(_choice_tile("HOST GAME", "Make a game.\nFriends join you.", _host, true))
	tiles.add_child(_choice_tile("JOIN GAME", "Find a game on this\nWi-Fi or hotspot.", _browse, false))

	var help := PanelContainer.new()
	help.theme_type_variation = UiTheme.CARD
	help.custom_minimum_size.x = 1032
	column.add_child(help)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 10)
	help.add_child(lines)
	lines.add_child(UiTheme.caption("HOW TO PLAY TOGETHER"))
	for step in STEPS:
		lines.add_child(_thin(step, 22, UiTheme.TEXT))
	lines.add_child(_thin(TIP, 20, UiTheme.TEXT_DIM))


func _build_host() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(row)

	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	card.custom_minimum_size.x = 440
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	card.add_child(left)
	var ips := NetProtocol.local_ipv4()
	var ip := ips[0] if not ips.is_empty() else "127.0.0.1"
	left.add_child(UiTheme.caption("JOIN CODE"))
	left.add_child(UiTheme.label(NetProtocol.join_code(ip), 80, UiTheme.ACCENT))
	left.add_child(UiTheme.label("IP  %s" % ("  /  ".join(ips) if ips.size() > 1 else ip), 20, UiTheme.TEXT_DIM))
	left.add_child(_spacer(18))
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 8)
	left.add_child(_slots_box)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 24)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	_setup = MatchSetup.new(true, StringName(net.mode), StringName(net.arena), net.bot_difficulty, true)
	_setup.set_fill_bots(net.fill_with_bots)
	_setup.changed.connect(_on_host_setup_changed)
	right.add_child(_setup)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 28)
	right.add_child(footer)
	_hint = UiTheme.label("", 22, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_hint)
	_start = UiTheme.button("START", func() -> void: net.start_match(), UiTheme.PRIMARY, Vector2(400, 100))
	_start.add_theme_font_size_override("font_size", 42)
	footer.add_child(_start)
	_on_lobby_changed()


func _build_browse() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	left.custom_minimum_size.x = 900
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	left.add_child(UiTheme.caption("GAMES NEARBY"))
	_games_box = VBoxContainer.new()
	_games_box.add_theme_constant_override("separation", 14)
	left.add_child(_games_box)
	_fill_games()

	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	card.custom_minimum_size.x = 560
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	card.add_child(right)
	right.add_child(UiTheme.caption("JOIN WITH A CODE"))
	right.add_child(_thin("Not in the list? Type the code or IP shown on the host's screen.", 20, UiTheme.TEXT_DIM))
	var code := LineEdit.new()
	code.placeholder_text = "e.g. 0A-01"
	code.custom_minimum_size.y = 76
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.add_theme_font_size_override("font_size", 36)
	code.text_submitted.connect(_join_typed)
	right.add_child(code)
	right.add_child(UiTheme.button("JOIN", func() -> void: _join_typed(code.text), UiTheme.PRIMARY, Vector2(0, 84)))


func _build_waiting() -> void:
	var center := _centered()
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	card.custom_minimum_size.x = 760
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	_info = UiTheme.label("", 26, UiTheme.ACCENT)
	column.add_child(_info)
	column.add_child(_spacer(6))
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 8)
	column.add_child(_slots_box)
	column.add_child(_spacer(6))
	_hint = UiTheme.label("", 24, UiTheme.TEXT)
	column.add_child(_hint)
	_on_lobby_changed()


## Lobby news (a player joined or left, the host changed the mode): refresh what shows it.
func _on_lobby_changed() -> void:
	if _slots_box != null:
		for child in _slots_box.get_children():
			child.queue_free()
		_fill_slots(_slots_box)
	var mode := ModeDef.load_by_id(StringName(net.mode))
	var arena := String(ArenaRegistry.info(StringName(net.arena))["name"]).to_upper()
	if _info != null:
		_info.text = "%s  ·  %s" % [mode.display_name.to_upper() if mode != null else "", arena]
	if _page == Page.WAITING and _hint != null:
		var host := String(net.players[0]["name"]).to_upper() if not net.players.is_empty() else "THE HOST"
		_hint.text = "Waiting for %s to start..." % host
	if _start != null:
		var alone := net.players.size() < 2
		_start.disabled = alone and not net.fill_with_bots
		if _start.disabled:
			_hint.text = "Waiting for a friend to join, or turn on bots."
		elif alone:
			_hint.text = "You'll play with bots. Friends can still join."
		else:
			_hint.text = "%d players in. Start when everyone's here." % net.players.size()


func _fill_slots(box: VBoxContainer) -> void:
	var mode := ModeDef.load_by_id(StringName(net.mode))
	var total := mode.players if mode != null and mode.enemy_slots > 0 else NetProtocol.MAX_PLAYERS
	box.add_child(UiTheme.caption("PLAYERS  %d/%d" % [mini(net.players.size(), total), total]))
	for i in total:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var text := ""
		var color := UiTheme.TEXT_DIM
		if i < net.players.size():
			var p: Dictionary = net.players[i]
			text = "%d. %s" % [i + 1, String(p["name"]).to_upper()]
			if p["peer"] == net.my_peer_id():
				text += " (YOU)"
			color = UiTheme.player_color(NetSession.SKINS[i])
			dot.color = color
		elif net.fill_with_bots:
			text = "%d. BOT  ·  %s" % [i + 1, net.bot_difficulty.to_upper()]
			dot.color = Color(1, 1, 1, 0.25)
		else:
			text = "%d. OPEN" % (i + 1)
			dot.color = Color(1, 1, 1, 0.1)
		var l := UiTheme.label(text, 26 if i < net.players.size() else 22, color, HORIZONTAL_ALIGNMENT_LEFT)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if i == 0 and i < net.players.size():
			row.add_child(UiTheme.label("HOST", 16, UiTheme.TEXT_DIM))
		box.add_child(row)


func _fill_games() -> void:
	if _games_box == null:
		return
	for child in _games_box.get_children():
		child.queue_free()
	_searching = null
	if net.discovery.games.is_empty():
		var empty := PanelContainer.new()
		empty.theme_type_variation = UiTheme.CARD
		_games_box.add_child(empty)
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override("separation", 10)
		empty.add_child(lines)
		_searching = UiTheme.label("LOOKING FOR GAMES...", 30, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		lines.add_child(_searching)
		lines.add_child(_thin("Games hosted on this Wi-Fi or hotspot show up here. Make sure the host has tapped HOST GAME.", 20, UiTheme.TEXT_DIM))
		return
	for address: String in net.discovery.games:
		_games_box.add_child(_game_tile(address, net.discovery.games[address]["info"]))


func _game_tile(address: String, info: Dictionary) -> Button:
	var tile := UiTheme.button("", _join.bind(address), &"", Vector2(900, 112))
	var outdated := int(info.get("v", -1)) != NetProtocol.VERSION
	tile.disabled = outdated
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 32
	row.offset_right = -32
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(row)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(UiTheme.label("%s'S GAME" % String(info.get("n", "?")).to_upper(), 30, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	var mode := ModeDef.load_by_id(StringName(info.get("mode", "")))
	var detail := "%s  ·  %s" % [mode.display_name.to_upper() if mode != null else "?", String(ArenaRegistry.info(StringName(info.get("arena", "")))["name"]).to_upper()]
	text.add_child(UiTheme.label("UPDATE THE GAME TO JOIN" if outdated else detail, 18, UiTheme.ACCENT_2 if outdated else UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	var count := UiTheme.label("%d/%d" % [int(info.get("p", 0)), int(info.get("m", 4))], 34, UiTheme.ACCENT)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(count)
	return tile


func _on_host_setup_changed() -> void:
	net.mode = String(_setup.mode_id)
	net.arena = String(_setup.arena_id)
	net.bot_difficulty = _setup.difficulty
	net.fill_with_bots = _setup.fill_bots
	Settings.last_mode = net.mode
	Settings.last_arena = net.arena
	Settings.save_settings()
	net.update_settings()


func _host() -> void:
	_save_name()
	net.arena = Settings.last_arena
	net.mode = "ffa"
	for id in [Settings.last_mode, Settings.play_mode]:
		var def := ModeDef.load_by_id(StringName(id))
		if def != null and def.lan:
			net.mode = id
			break
	var err := net.host_game(_name_edit.text)
	if err != OK:
		_status.text = "Couldn't host (port %d busy?)" % NetProtocol.GAME_PORT
		return
	_status.text = ""
	_show(Page.HOST)


func _browse() -> void:
	_save_name()
	net.leave()
	var err := net.discovery.start_listening()
	_status.text = "" if err == OK else "Can't listen for games here; use the join code."
	_show(Page.BROWSE)


func _join(address: String) -> void:
	net.discovery.stop()
	_status.text = "Connecting to %s..." % address
	if net.join_game(address, ProfileStore.display_name()) != OK:
		_status.text = "Couldn't connect."
		return
	# ENet takes a long time to give up on a host that never answers: stop sooner and say why.
	_join_attempt += 1
	var attempt := _join_attempt
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(func() -> void:
		if attempt == _join_attempt and _page == Page.BROWSE and net.role == NetSession.Role.CLIENT:
			net.leave()
			_on_join_failed("Can't reach the host. Check you're on the same Wi-Fi, or try a phone hotspot."))


func _join_typed(text: String) -> void:
	var clean := text.strip_edges()
	var address := clean if clean.count(".") == 3 else ""
	if address.is_empty():
		var ips := NetProtocol.local_ipv4()
		address = NetProtocol.address_from_code(clean, ips[0] if not ips.is_empty() else "192.168.0.1")
	if address.is_empty():
		_status.text = "That code doesn't look right."
		return
	_join(address)


func _go_back() -> void:
	_join_attempt += 1
	if _page == Page.CHOOSE:
		net.leave()
		if change_scene:
			get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return
	net.leave()
	_status.text = ""
	_show(Page.CHOOSE)


func _on_join_failed(reason: String) -> void:
	_status.text = reason
	if _page != Page.BROWSE:
		_show(Page.BROWSE)
	if net.discovery.start_listening() != OK:
		_status.text += " Use the join code."


func _on_match_starting(_config: Dictionary) -> void:
	if change_scene:
		get_tree().change_scene_to_file(MATCH_SCENE)


func _save_name() -> void:
	if _name_edit == null or not is_instance_valid(_name_edit):
		return
	var clean := _name_edit.text.strip_edges().substr(0, 16)
	if clean.is_empty():
		clean = "Player"
	ProfileStore.data["display_name"] = clean
	ProfileStore.save_profile()


## A big tile on the first page: a title and two lines of what it does.
func _choice_tile(title: String, detail: String, action: Callable, primary: bool) -> Button:
	var tile := UiTheme.button("", action, &"", Vector2(500, 230))
	var text := VBoxContainer.new()
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 14)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(text)
	text.add_child(UiTheme.label(title, 44, UiTheme.ACCENT if primary else UiTheme.TEXT))
	text.add_child(_thin(detail, 22, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	return tile


func _thin(text: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiTheme.label(text, size, color, align)
	l.add_theme_font_override("font", UiTheme.FONT_THIN)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _centered() -> CenterContainer:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(center)
	return center


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c
