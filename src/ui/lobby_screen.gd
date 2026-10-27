class_name LobbyScreen
extends Control
## LAN party lobby (§6.2): host a game or join one on the same Wi-Fi or phone hotspot. No internet.
## Hosting shows the join code and the players; joining lists games found by beacon and also takes a
## join code or an IP address. When the host starts, every device opens the match.

const MATCH_SCENE: String = "res://src/match/match.tscn"
const MAIN_MENU_SCENE: String = "res://src/ui/main_menu.tscn"
const BACKGROUND: Texture2D = preload("res://assets/art/arena/darkPurple.png")
const HELP: String = "All phones on the same Wi-Fi, or on one phone's hotspot. No internet needed."
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]

enum Page { CHOOSE, HOST, BROWSE, WAITING }

## Tests turn this off to stay on the page.
var change_scene: bool = true
var net: NetSession

var _page: Page = Page.CHOOSE
var _body: VBoxContainer
var _status: Label
var _name_edit: LineEdit


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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.custom_minimum_size.x = 900
	panel.add_child(column)
	var title := Label.new()
	title.text = "LAN PARTY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	column.add_child(title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 16)
	column.add_child(_body)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", UiTheme.ACCENT_2)
	column.add_child(_status)

	net.lobby_changed.connect(_refresh)
	net.joined.connect(func() -> void: _show(Page.WAITING))
	net.join_failed.connect(_on_join_failed)
	net.host_left.connect(func() -> void:
		_status.text = "The host closed the game."
		_show(Page.CHOOSE))
	net.match_starting.connect(_on_match_starting)
	net.discovery.games_changed.connect(_refresh)
	_show(Page.CHOOSE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _show(page: Page) -> void:
	_page = page
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	for child in _body.get_children():
		child.queue_free()
	match _page:
		Page.CHOOSE:
			_build_choose()
		Page.HOST:
			_build_host()
		Page.BROWSE:
			_build_browse()
		Page.WAITING:
			_build_waiting()


func _build_choose() -> void:
	_body.add_child(_label("YOUR NAME", 22, UiTheme.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.text = ProfileStore.display_name()
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size.y = 64
	_body.add_child(_name_edit)
	_body.add_child(_button("HOST GAME", _host))
	_body.add_child(_button("JOIN GAME", _browse))
	_body.add_child(_button("BACK", _back))
	_body.add_child(_label(HELP, 20, UiTheme.TEXT_DIM))


func _build_host() -> void:
	var ips := NetProtocol.local_ipv4()
	var ip := ips[0] if not ips.is_empty() else "127.0.0.1"
	_body.add_child(_label("JOIN CODE", 22, UiTheme.TEXT_DIM))
	_body.add_child(_label(NetProtocol.join_code(ip), 72, UiTheme.ACCENT))
	_body.add_child(_label("or IP %s" % ip, 20, UiTheme.TEXT_DIM))
	_body.add_child(_players_list())
	var modes := OptionButton.new()
	modes.add_theme_font_size_override("font_size", 26)
	modes.custom_minimum_size = Vector2(520, 64)
	modes.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var lan_modes := ModeDef.all().filter(func(d: ModeDef) -> bool: return d.lan)
	for i in lan_modes.size():
		var d: ModeDef = lan_modes[i]
		modes.add_item(d.display_name.to_upper(), i)
		if String(d.id) == net.mode:
			modes.select(i)
	modes.item_selected.connect(func(index: int) -> void:
		var d: ModeDef = lan_modes[index]
		net.mode = String(d.id)
		Settings.last_mode = net.mode
		Settings.save_settings()
		net.update_settings())
	_body.add_child(modes)
	var fill := CheckButton.new()
	fill.text = "Fill empty slots with bots"
	fill.button_pressed = net.fill_with_bots
	fill.toggled.connect(func(on: bool) -> void:
		net.fill_with_bots = on
		net.update_settings())
	_body.add_child(fill)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for level in DIFFICULTIES:
		var b := Button.new()
		b.text = level.to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = net.bot_difficulty == level
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func() -> void:
			net.bot_difficulty = level
			net.update_settings())
		row.add_child(b)
	_body.add_child(row)
	var start := _button("START", func() -> void: net.start_match())
	start.disabled = net.players.size() < 2 and not net.fill_with_bots
	_body.add_child(start)
	_body.add_child(_button("BACK", _back))


func _build_browse() -> void:
	_body.add_child(_label("GAMES NEARBY", 22, UiTheme.TEXT_DIM))
	if net.discovery.games.is_empty():
		_body.add_child(_label("Looking for games...", 22, UiTheme.TEXT_DIM))
	for address: String in net.discovery.games:
		var info: Dictionary = net.discovery.games[address]["info"]
		var text := "%s   %d/%d   %s" % [String(info.get("n", "?")).to_upper(), int(info.get("p", 0)), int(info.get("m", 4)), String(info.get("arena", "")).to_upper()]
		var b := _button(text, _join.bind(address))
		b.disabled = int(info.get("v", -1)) != NetProtocol.VERSION
		_body.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var code := LineEdit.new()
	code.placeholder_text = "CODE (e.g. 0A-01) or IP"
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.custom_minimum_size.y = 64
	row.add_child(code)
	var go := Button.new()
	go.text = "JOIN"
	go.pressed.connect(func() -> void: _join_typed(code.text))
	row.add_child(go)
	_body.add_child(row)
	_body.add_child(_button("BACK", _back))


func _build_waiting() -> void:
	_body.add_child(_label("CONNECTED", 22, UiTheme.TEXT_DIM))
	_body.add_child(_players_list())
	_body.add_child(_label("Waiting for the host to start...", 24, UiTheme.TEXT))
	_body.add_child(_button("LEAVE", _back))


func _players_list() -> Control:
	var box := VBoxContainer.new()
	var mode := ModeDef.load_by_id(StringName(net.mode))
	if mode != null:
		box.add_child(_label("%s  ·  %s" % [mode.display_name.to_upper(), ArenaRegistry.info(StringName(net.arena))["name"].to_upper()], 22, UiTheme.ACCENT))
	for i in net.players.size():
		var p: Dictionary = net.players[i]
		var skin := SkinDef.load_by_id(NetSession.SKINS[i])
		var you := " (YOU)" if p["peer"] == net.my_peer_id() else ""
		box.add_child(_label("%d. %s%s" % [i + 1, String(p["name"]).to_upper(), you], 30, UiTheme.player_color(NetSession.SKINS[i]) if skin != null else UiTheme.TEXT))
	if net.fill_with_bots and net.players.size() < NetProtocol.MAX_PLAYERS:
		box.add_child(_label("+ %d bots (%s)" % [NetProtocol.MAX_PLAYERS - net.players.size(), net.bot_difficulty.to_upper()], 22, UiTheme.TEXT_DIM))
	return box


func _host() -> void:
	_save_name()
	net.arena = Settings.last_arena
	var last := ModeDef.load_by_id(StringName(Settings.last_mode))
	net.mode = Settings.last_mode if last != null and last.lan else "ffa"
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


func _back() -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
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


func _on_match_starting(_config: Dictionary) -> void:
	if change_scene:
		get_tree().change_scene_to_file(MATCH_SCENE)


func _save_name() -> void:
	if _name_edit == null:
		return
	var clean := _name_edit.text.strip_edges().substr(0, 16)
	if clean.is_empty():
		clean = "Player"
	ProfileStore.data["display_name"] = clean
	ProfileStore.save_profile()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(600, 80)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		Sfx.play(&"ui_click", Vector2.ZERO)
		action.call())
	return b
