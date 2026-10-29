class_name Hud
extends CanvasLayer
## In-match controls (§4.4, §4.12). KNIFE (melee) and FIRE are aim sticks: a quick tap attacks at once with
## auto-aim; pressing and dragging out of the dead zone shows an aim arrow from the fighter, and
## letting go attacks that way; dragging back into the middle cancels. The HUD tracks those
## touches itself (multi-touch, so a rope finger and an attack finger work together). Pause is a
## TouchScreenButton. Button rects go to the TouchRouter so a touch that starts on a button never
## fires a rope. With the rope stick setting (D39) a third stick sits in the other bottom corner:
## drag it to aim the rope (an enemy or weapon near that direction is aimed at), let go to fire;
## a tap on it lets go of the rope. Each rope shows a short snap marker where aim assist sent it. Also shows own HP (top-left),
## with armor, chip damage and active pickups under it, a red screen edge when you are hit (and a
## heartbeat glow at low HP), the mode's scores and clock (top-center, §6.5), a mode line (bomb, zone, Gun Game level), a minimap and off-screen
## arrows in big arenas (D28), and short messages.

signal pause_pressed

const MELEE_DIAMETER: float = 170.0
const FIRE_DIAMETER: float = 150.0
const FIRE_GAP: float = 24.0
const PAUSE_SIZE: float = 90.0
const EDGE_MARGIN: float = 40.0
## Red screen edge when the local player is hit: fades over this long; a slow pulse below this share
## of max HP.
const HURT_EDGE_TIME: float = 0.45
const HURT_EDGE_WIDTH: float = 110.0
const HURT_EDGE_COLOR: Color = Color(1.0, 0.1, 0.05, 0.55)
const LOW_HP_SHARE: float = 0.25
const LOW_HP_GLOW: float = 0.45
const PAUSE_MARGIN: float = 24.0
const HP_BAR_SIZE: Vector2 = Vector2(360, 24)
const SCORE_FONT_SIZE: int = 44
const CHIP_WIDTH: float = 150.0
const MESSAGE_TIME: float = 2.5
## Drag less than this from the button's center (px) and the attack auto-aims.
const AIM_DEADZONE: float = 36.0
## A touch this much bigger than the button still counts as on it.
const BUTTON_TOUCH_SLACK: float = 1.15
## Aim preview from the fighter: weapon line length (px).
const AIM_LINE_LENGTH: float = 520.0
const AIM_COLOR: Color = Color(1.0, 0.92, 0.5, 0.85)
const ROPE_STICK_DIAMETER: float = 190.0
const ROPE_AIM_COLOR: Color = Color(0.6, 0.95, 1.0, 0.9)
## How long the snap marker shows (s).
const SNAP_TIME: float = 0.35

var router: TouchRouter
var player: Fighter
var others: Array[Fighter] = []
## Tutorial steps (§6.7), shown as the mode line.
var tracker: ChallengeTracker
## Bot difficulty shown under the score in offline Vs Bot.
var bot_label: String = ""
## The match's rules, for scores, clock and the mode line. Null shows no scores.
var mode: GameMode

var _fire_button: Node2D
var _fire_visual: Node2D
var _fire_down: bool = false
var _armed: bool = false
var _melee_button: Node2D
var _rope_stick: Node2D
var _rope_visual: Node2D
## Last rope target and where the finger was, for the snap marker; time left showing it.
var _snap_tap: Vector2 = Vector2.ZERO
var _snap_target: Vector2 = Vector2.ZERO
var _snap_time: float = 0.0
var _pause_button: TouchScreenButton
var _melee_visual: Node2D
var _pause_visual: Node2D
var _melee_down: bool = false
var _status: Node2D
var _minimap: Minimap
var _markers: OffscreenMarkers
var _message: String = ""
var _message_time: float = 0.0
## The local player's last HP, the lagging chip-damage HP and its hold, and the hurt edge (1 = just hit).
var _seen_hp: float = -1.0
var _chip_hp: float = 0.0
var _chip_hold: float = 0.0
var _hurt: float = 0.0
## touch index -> {button: &"melee" | &"fire", dir: Vector2, out: bool}
var _aims: Dictionary = {}


func _ready() -> void:
	layer = 10
	_melee_button = Node2D.new()
	add_child(_melee_button)
	_melee_visual = _make_visual(_melee_button, _draw_melee)

	_fire_button = Node2D.new()
	add_child(_fire_button)
	_fire_visual = _make_visual(_fire_button, _draw_fire)
	_fire_button.visible = false

	_rope_stick = Node2D.new()
	add_child(_rope_stick)
	_rope_visual = _make_visual(_rope_stick, _draw_rope_stick)

	var pause_shape := RectangleShape2D.new()
	pause_shape.size = Vector2(PAUSE_SIZE, PAUSE_SIZE)
	_pause_button = _make_button(pause_shape)
	_pause_button.released.connect(func() -> void: pause_pressed.emit())
	_pause_visual = _make_visual(_pause_button, _draw_pause)

	_status = Node2D.new()
	_status.draw.connect(_draw_status)
	add_child(_status)

	get_viewport().size_changed.connect(_layout)
	Settings.changed.connect(_layout)
	_layout()


func setup(touch_router: TouchRouter, local_fighter: Fighter, other_fighters: Array[Fighter]) -> void:
	router = touch_router
	router.rope_aimed.connect(func(tap: Vector2, target: Vector2) -> void:
		_snap_tap = tap
		_snap_target = target
		_snap_time = SNAP_TIME)
	player = local_fighter
	others = other_fighters
	_layout()


## Minimap and off-screen arrows for arenas bigger than the screen (D28).
func attach_world(sim: MatchSim, arena: Arena, camera: CameraShake) -> void:
	_markers = OffscreenMarkers.new()
	_markers.sim = sim
	_markers.local_fighter_id = player.fighter_id
	add_child(_markers)
	_minimap = Minimap.new()
	_minimap.arena = arena
	_minimap.sim = sim
	_minimap.camera = camera
	_minimap.local_fighter_id = player.fighter_id
	add_child(_minimap)
	_layout()


## A centered banner for a few seconds ("Host left", mode announcements).
func show_message(text: String, seconds: float = MESSAGE_TIME) -> void:
	_message = text
	_message_time = seconds


func _process(delta: float) -> void:
	_message_time = maxf(0.0, _message_time - delta)
	_snap_time = maxf(0.0, _snap_time - delta)
	_watch_player_hp(delta)
	if not _aims.is_empty():
		_rope_visual.queue_redraw()
	_status.queue_redraw()
	var armed := _held_weapon() != null
	if armed != _armed:
		_armed = armed
		_fire_button.visible = armed
		_layout()
	if armed:
		_fire_visual.queue_redraw()


## Chip damage on the HP bar and the red edge, from the local player's HP going down.
func _watch_player_hp(delta: float) -> void:
	_hurt = maxf(0.0, _hurt - delta / HURT_EDGE_TIME)
	if player == null:
		return
	if _seen_hp < 0.0 or player.hp > _seen_hp:
		_chip_hp = player.hp
	elif player.hp < _seen_hp - 0.5:
		_hurt = 1.0
		_chip_hold = FighterView.CHIP_HOLD
	if _chip_hold > 0.0:
		_chip_hold -= delta
	else:
		_chip_hp = move_toward(_chip_hp, player.hp, TuningDB.t.max_hp * FighterView.CHIP_RATE * delta)
	_seen_hp = player.hp


## A red glow along the screen edges: strength 0..1.
func _draw_edge_glow(rect: Rect2, strength: float) -> void:
	if strength <= 0.01:
		return
	var w := HURT_EDGE_WIDTH
	var solid := Color(HURT_EDGE_COLOR, HURT_EDGE_COLOR.a * strength)
	var clear := Color(HURT_EDGE_COLOR, 0.0)
	var a := rect.position
	var b := rect.end
	var bands := [
		[Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x - w, a.y + w), Vector2(a.x + w, a.y + w)],
		[Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(b.x - w, b.y - w), Vector2(b.x - w, a.y + w)],
		[Vector2(b.x, b.y), Vector2(a.x, b.y), Vector2(a.x + w, b.y - w), Vector2(b.x - w, b.y - w)],
		[Vector2(a.x, b.y), Vector2(a.x, a.y), Vector2(a.x + w, a.y + w), Vector2(a.x + w, b.y - w)],
	]
	for band: Array in bands:
		_status.draw_polygon(PackedVector2Array(band), PackedColorArray([solid, solid, clear, clear]))


func _held_weapon() -> WeaponItem:
	if player == null or player.sim == null or player.weapon_id < 0:
		return null
	return player.sim.weapons.held_by(player)


func _make_button(shape: Shape2D) -> TouchScreenButton:
	var button := TouchScreenButton.new()
	button.shape = shape
	button.shape_centered = true
	button.shape_visible = false
	add_child(button)
	return button


func _make_visual(button: Node2D, draw_func: Callable) -> Node2D:
	var visual := Node2D.new()
	visual.draw.connect(draw_func.bind(visual))
	button.add_child(visual)
	return visual


func _layout() -> void:
	var safe := _safe_rect()
	var r := _melee_radius()
	var mirror := Settings.left_handed
	var melee_x := safe.position.x + EDGE_MARGIN + r if mirror else safe.end.x - EDGE_MARGIN - r
	_melee_button.position = Vector2(melee_x, safe.end.y - EDGE_MARGIN - r)
	var half := PAUSE_SIZE * 0.5
	_pause_button.position = safe.position + Vector2(PAUSE_MARGIN + half, PAUSE_MARGIN + half)
	var fr := _fire_radius()
	_fire_button.position = _melee_button.position + Vector2(r * 0.35 * (1.0 if mirror else -1.0), -(r + FIRE_GAP + fr))
	var sr := _rope_stick_radius()
	_rope_stick.visible = Settings.rope_stick
	var stick_x := safe.end.x - EDGE_MARGIN - sr if mirror else safe.position.x + EDGE_MARGIN + sr
	_rope_stick.position = Vector2(stick_x, safe.end.y - EDGE_MARGIN - sr)
	_melee_visual.queue_redraw()
	_fire_visual.queue_redraw()
	_rope_visual.queue_redraw()
	if _minimap != null:
		_minimap.position = Vector2(safe.end.x - PAUSE_MARGIN - Minimap.WIDTH, safe.position.y + PAUSE_MARGIN)
	if _markers != null:
		_markers.top_inset = PAUSE_MARGIN + PAUSE_SIZE
	if router != null:
		var rects: Array[Rect2] = [
			Rect2(_melee_button.position - Vector2(r, r), Vector2(r, r) * 2.0),
			Rect2(_pause_button.position - Vector2(half, half), Vector2(PAUSE_SIZE, PAUSE_SIZE)),
		]
		if _fire_button.visible:
			rects.append(Rect2(_fire_button.position - Vector2(fr, fr), Vector2(fr, fr) * 2.0))
		if _rope_stick.visible:
			rects.append(Rect2(_rope_stick.position - Vector2(sr, sr), Vector2(sr, sr) * 2.0))
		router.button_rects = rects


# --- Aim sticks ------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_aim_down(touch.index, touch.position)
		else:
			_aim_up(touch.index)
		return
	var drag := event as InputEventScreenDrag
	if drag != null and _aims.has(drag.index):
		_aim_move(drag.index, drag.position)


## Which attack button (if any) a touch at screen_pos starts on.
func _button_at(screen_pos: Vector2) -> StringName:
	if screen_pos.distance_to(_melee_button.position) <= _melee_radius() * BUTTON_TOUCH_SLACK:
		return &"melee"
	if _fire_button.visible and screen_pos.distance_to(_fire_button.position) <= _fire_radius() * BUTTON_TOUCH_SLACK:
		return &"fire"
	if _rope_stick.visible and screen_pos.distance_to(_rope_stick.position) <= _rope_stick_radius() * BUTTON_TOUCH_SLACK:
		return &"rope"
	return &""


func _aim_down(index: int, screen_pos: Vector2) -> void:
	var button := _button_at(screen_pos)
	if button.is_empty() or get_tree().paused:
		return
	_aims[index] = {"button": button, "dir": Vector2.ZERO, "out": false, "offset": Vector2.ZERO}
	_set_down(button, true)


func _aim_move(index: int, screen_pos: Vector2) -> void:
	var aim: Dictionary = _aims[index]
	var center: Vector2 = _button_center(aim["button"])
	var offset := screen_pos - center
	aim["offset"] = offset
	if offset.length() > AIM_DEADZONE:
		aim["dir"] = offset.normalized()
		aim["out"] = true
	else:
		aim["dir"] = Vector2.ZERO


## Letting go attacks: aimed if dragged out, auto-aimed for a tap; dragged out and back cancels.
func _aim_up(index: int) -> void:
	if not _aims.has(index):
		return
	var aim: Dictionary = _aims[index]
	_aims.erase(index)
	_set_down(aim["button"], false)
	var dir: Vector2 = aim["dir"]
	if (aim["out"] and dir == Vector2.ZERO) or router == null:
		return
	match aim["button"]:
		&"melee":
			router.queue_melee(dir)
		&"fire":
			router.queue_fire(dir)
		&"rope":
			if dir == Vector2.ZERO:
				router.release_rope()
			else:
				router.fire_rope_toward(dir)


func _button_center(button: StringName) -> Vector2:
	match button:
		&"melee": return _melee_button.position
		&"fire": return _fire_button.position
	return _rope_stick.position


func _set_down(button: StringName, down: bool) -> void:
	match button:
		&"melee":
			_melee_down = down
			_melee_visual.queue_redraw()
		&"fire":
			_fire_down = down
			_fire_visual.queue_redraw()
		_:
			_rope_visual.queue_redraw()


## The aim arrow from the fighter while an attack button is dragged: the melee arc for KNIFE, a long
## line for FIRE.
func _draw_aim() -> void:
	if player == null or player.is_ko():
		return
	var t := TuningDB.t
	var at := get_viewport().get_canvas_transform() * (player.view.global_position if player.view != null else player.global_position)
	for aim: Dictionary in _aims.values():
		var dir: Vector2 = aim["dir"]
		if dir == Vector2.ZERO:
			continue
		if aim["button"] == &"rope":
			var target: Vector2 = router.direction_resolver.call(dir) if router != null and router.direction_resolver.is_valid() else player.global_position + dir * t.rope_range
			var to := get_viewport().get_canvas_transform() * target
			var dash := 0.0
			var length := at.distance_to(to)
			var along := (to - at).normalized()
			while dash < length:
				_status.draw_line(at + along * dash, at + along * minf(dash + 22.0, length), ROPE_AIM_COLOR, 4.0, true)
				dash += 36.0
			_status.draw_arc(to, 22.0, 0.0, TAU, 32, ROPE_AIM_COLOR, 4.0, true)
		elif aim["button"] == &"melee":
			var reach := Melee.reach(player, t)
			var half := deg_to_rad(t.melee_arc_deg) * 0.5
			var a := dir.angle()
			var pts := PackedVector2Array([at])
			for i in 17:
				pts.append(at + Vector2.from_angle(a - half + half * 2.0 * i / 16.0) * reach)
			_status.draw_colored_polygon(pts, Color(AIM_COLOR, 0.22))
			_status.draw_polyline(pts + PackedVector2Array([at]), AIM_COLOR, 3.0, true)
		else:
			var item := _held_weapon()
			var c := item.def.glow_color if item != null else AIM_COLOR
			var end := at + dir * AIM_LINE_LENGTH
			var dash := 0.0
			while dash < AIM_LINE_LENGTH - 20.0:
				_status.draw_line(at + dir * (dash + 40.0), at + dir * minf(dash + 64.0, AIM_LINE_LENGTH), Color(c, 0.85), 5.0, true)
				dash += 40.0
			_status.draw_colored_polygon(PackedVector2Array([end + dir * 22.0, end + dir.orthogonal() * 14.0, end - dir.orthogonal() * 14.0]), Color(c, 0.95))


## The rope's snap marker: a ring where the rope went, and a line from the finger if aim assist
## moved it (D39).
func _draw_snap() -> void:
	if _snap_time <= 0.0:
		return
	var k := _snap_time / SNAP_TIME
	var xform := get_viewport().get_canvas_transform()
	var target := xform * _snap_target
	var tap := xform * _snap_tap
	if tap.distance_to(target) > 12.0:
		_status.draw_line(tap, target, Color(ROPE_AIM_COLOR, 0.5 * k), 2.0, true)
		_status.draw_circle(tap, 5.0, Color(ROPE_AIM_COLOR, 0.5 * k))
	_status.draw_arc(target, 18.0 + 14.0 * (1.0 - k), 0.0, TAU, 32, Color(ROPE_AIM_COLOR, k), 4.0, true)


func _draw_rope_stick(v: Node2D) -> void:
	var r := _rope_stick_radius()
	var knob := Vector2.ZERO
	for aim: Dictionary in _aims.values():
		if aim["button"] == &"rope":
			knob = (aim["offset"] as Vector2).limit_length(r * 0.6)
	v.draw_circle(Vector2.ZERO, r, Color(ROPE_AIM_COLOR, 0.12))
	v.draw_arc(Vector2.ZERO, r - 2.0, 0.0, TAU, 64, Color(ROPE_AIM_COLOR, 0.6), 4.0, true)
	v.draw_circle(knob, r * 0.32, Color(ROPE_AIM_COLOR, 0.35 if knob != Vector2.ZERO else 0.2))
	v.draw_string(UiTheme.FONT, Vector2(-r, r * 0.62), "ROPE", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 22, Color(1, 1, 1, 0.7))


func _rope_stick_radius() -> float:
	return ROPE_STICK_DIAMETER * 0.5 * clampf(Settings.button_scale, 0.5, 2.0)


## Button sizes with the player's size setting (§6.7).
func _melee_radius() -> float:
	return MELEE_DIAMETER * 0.5 * clampf(Settings.button_scale, 0.5, 2.0)


func _fire_radius() -> float:
	return FIRE_DIAMETER * 0.5 * clampf(Settings.button_scale, 0.5, 2.0)


## Visible canvas rect minus the device's notch/rounded-corner insets.
func _safe_rect() -> Rect2:
	var visible_size := get_viewport().get_visible_rect().size
	if not OS.has_feature("mobile"):
		return Rect2(Vector2.ZERO, visible_size)
	var safe := DisplayServer.get_display_safe_area()
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return Rect2(Vector2.ZERO, visible_size)
	var k := visible_size / window
	return Rect2(Vector2(safe.position) * k, Vector2(safe.size) * k)


func _color(f: Fighter) -> Color:
	return UiTheme.player_color(f.skin_id)


func _draw_status() -> void:
	if player == null:
		return
	var safe := _safe_rect()
	var font := UiTheme.FONT
	var origin := safe.position + Vector2(PAUSE_MARGIN * 2.0 + PAUSE_SIZE, PAUSE_MARGIN + (PAUSE_SIZE - HP_BAR_SIZE.y) * 0.5)
	var frac := clampf(player.hp / TuningDB.t.max_hp, 0.0, 1.0)
	var chip := clampf(_chip_hp / TuningDB.t.max_hp, 0.0, 1.0)
	if not player.is_ko():
		var low := 0.0
		if player.hp < TuningDB.t.max_hp * LOW_HP_SHARE:
			low = LOW_HP_GLOW * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.2))
		_draw_edge_glow(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size), maxf(_hurt, low))
	_status.draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0, 0, 0, 0.45))
	if chip > frac:
		_status.draw_rect(Rect2(origin + Vector2(HP_BAR_SIZE.x * frac, 0), Vector2(HP_BAR_SIZE.x * (chip - frac), HP_BAR_SIZE.y)), Color(1, 1, 1, 0.8))
	_status.draw_rect(Rect2(origin, Vector2(HP_BAR_SIZE.x * frac, HP_BAR_SIZE.y)), _color(player).lerp(Color(1, 0.35, 0.3), 1.0 - frac))
	if player.armor > 0.0:
		var armor_frac := clampf(player.armor / TuningDB.t.max_armor, 0.0, 1.0)
		_status.draw_rect(Rect2(origin + Vector2(0, HP_BAR_SIZE.y - 7), Vector2(HP_BAR_SIZE.x * armor_frac, 7)), FighterView.ARMOR_COLOR)
	_status.draw_rect(Rect2(origin, HP_BAR_SIZE), Color(1, 1, 1, 0.6), false, 2.0)
	_status.draw_string(font, origin + Vector2(10, HP_BAR_SIZE.y - 5), "%d" % ceili(player.hp) + ("  +%d" % ceili(player.armor) if player.armor > 0.0 else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	_draw_buffs(origin + Vector2(0, HP_BAR_SIZE.y + 24))


	var center_x := safe.get_center().x
	var y := safe.position.y + PAUSE_MARGIN + 44.0
	var below := y + 30.0
	if mode is SurvivalMode:
		var surv := mode as SurvivalMode
		_status.draw_string(font, Vector2(center_x - 300, y), "WAVE %d/%d" % [surv.wave, surv.def.score_target], HORIZONTAL_ALIGNMENT_CENTER, 600, SCORE_FONT_SIZE - 6, Color.WHITE)
		var hearts := "LIVES %d" % maxi(0, surv.lives)
		if surv.boss_active:
			hearts += "   BOSS %d" % ceili(surv.boss_hp)
		_status.draw_string(font, Vector2(center_x - 300, y + 28), hearts, HORIZONTAL_ALIGNMENT_CENTER, 600, 22, Color(1, 0.6, 0.6))
		below += 26.0
	elif mode != null and mode.is_team_mode():
		var half := 160.0
		var mine := mode.key_of(player)
		for team in 2:
			var c := UiTheme.team_color(team)
			var name := GameMode.TEAM_NAMES[team] + (" (YOU)" if team == mine else "")
			if team == 0:
				_status.draw_string(font, Vector2(center_x - half - 260, y), name, HORIZONTAL_ALIGNMENT_RIGHT, 250, 26, c)
				_status.draw_string(font, Vector2(center_x - half, y), mode.score_text(team), HORIZONTAL_ALIGNMENT_RIGHT, half - 30, SCORE_FONT_SIZE, Color.WHITE)
			else:
				_status.draw_string(font, Vector2(center_x + 30, y), mode.score_text(team), HORIZONTAL_ALIGNMENT_LEFT, half - 30, SCORE_FONT_SIZE, Color.WHITE)
				_status.draw_string(font, Vector2(center_x + half + 10, y), name, HORIZONTAL_ALIGNMENT_LEFT, 250, 26, c)
		_status.draw_string(font, Vector2(center_x - 20, y), ":", HORIZONTAL_ALIGNMENT_CENTER, 40, SCORE_FONT_SIZE, Color(1, 1, 1, 0.7))
	elif mode != null and others.size() == 1:
		var other := others[0]
		var half := 160.0
		_status.draw_string(font, Vector2(center_x - half - 120, y), "YOU", HORIZONTAL_ALIGNMENT_RIGHT, 110, 28, _color(player))
		_status.draw_string(font, Vector2(center_x - half, y), mode.score_text(player.fighter_id), HORIZONTAL_ALIGNMENT_RIGHT, half - 30, SCORE_FONT_SIZE, Color.WHITE)
		_status.draw_string(font, Vector2(center_x - 20, y), ":", HORIZONTAL_ALIGNMENT_CENTER, 40, SCORE_FONT_SIZE, Color(1, 1, 1, 0.7))
		_status.draw_string(font, Vector2(center_x + 30, y), mode.score_text(other.fighter_id), HORIZONTAL_ALIGNMENT_LEFT, half - 30, SCORE_FONT_SIZE, Color.WHITE)
		_status.draw_string(font, Vector2(center_x + half + 10, y), other.display_name.to_upper().substr(0, 10), HORIZONTAL_ALIGNMENT_LEFT, 200, 28, _color(other))
		if not bot_label.is_empty():
			_status.draw_string(font, Vector2(center_x - 100, below), bot_label, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color(1, 1, 1, 0.5))
			below += 22.0
	elif mode != null and others.size() > 1:
		var all: Array[Fighter] = [player]
		all.append_array(others)
		var x := center_x - CHIP_WIDTH * all.size() * 0.5
		for f in all:
			var c := _color(f)
			_status.draw_circle(Vector2(x + 14, y - 12), 9.0, c)
			if f == player:
				_status.draw_arc(Vector2(x + 14, y - 12), 12.0, 0.0, TAU, 24, Color.WHITE, 2.0)
			_status.draw_string(font, Vector2(x + 30, y - 2), mode.score_text(f.fighter_id), HORIZONTAL_ALIGNMENT_LEFT, CHIP_WIDTH - 34, 30, Color.WHITE)
			_status.draw_string(font, Vector2(x + 2, y + 22), f.display_name.to_upper().substr(0, 9), HORIZONTAL_ALIGNMENT_LEFT, CHIP_WIDTH - 8, 16, Color(c, 0.85))
			x += CHIP_WIDTH
		below += 18.0
	if mode != null:
		var tick := player.sim.tick if player.sim != null else 0
		var left := mode.time_left(tick)
		if left >= 0.0:
			var secs := ceili(left)
			var urgent := left < 10.0
			_status.draw_string(font, Vector2(center_x - 100, below), "%d:%02d" % [secs / 60, secs % 60], HORIZONTAL_ALIGNMENT_CENTER, 200, 24, Color(1, 0.4, 0.3) if urgent else Color(1, 1, 1, 0.75))
			below += 30.0
		var line := _mode_line(tick)
		if not line.is_empty():
			var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 120.0)
			_status.draw_string(font, Vector2(center_x - 400, below + 8), line, HORIZONTAL_ALIGNMENT_CENTER, 800, 24, Color(1, 0.85, 0.4, pulse))

	_draw_aim()
	_draw_snap()

	if _message_time > 0.0:
		var alpha := clampf(_message_time / 0.4, 0.0, 1.0)
		var mid := safe.get_center()
		_status.draw_rect(Rect2(mid.x - 420, mid.y - 210, 840, 90), Color(0, 0, 0, 0.55 * alpha))
		_status.draw_string(font, Vector2(mid.x - 420, mid.y - 150), _message, HORIZONTAL_ALIGNMENT_CENTER, 840, 40, Color(1, 1, 1, alpha))


## Seconds left on haste and power, under the HP bar.
func _draw_buffs(at: Vector2) -> void:
	var tick := player.sim.tick if player.sim != null else 0
	var x := at.x
	for buff: Array in [["HASTE", player.haste_until, FighterView.HASTE_COLOR], ["POWER", player.power_until, FighterView.POWER_COLOR]]:
		var left := float(int(buff[1]) - tick) / SimIds.TICK_RATE
		if left <= 0.0 or player.is_ko():
			continue
		var text := "%s %d" % [buff[0], ceili(left)]
		_status.draw_string(UiTheme.FONT, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, buff[2])
		x += UiTheme.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0


## One line about the mode that matters to the local player right now.
func _mode_line(tick: int) -> String:
	if tracker != null:
		var step := tracker.current_def()
		if step == null:
			return "TUTORIAL COMPLETE!"
		var count := "  (%d/%d)" % [tracker.progress[tracker.current], step.count] if step.count > 1 else ""
		return "STEP %d/%d: %s%s" % [tracker.current + 1, tracker.challenges.size(), step.text.to_upper(), count]
	if mode is HotPotato:
		var potato := mode as HotPotato
		if potato.holder_id == player.fighter_id:
			return "YOU HAVE THE BOMB! HOOK OR KNIFE SOMEONE  %.0f" % ceilf(potato.fuse_fraction(tick) * potato.fuse_length / SimIds.TICK_RATE)
	elif mode is KingOfTheSwing:
		var koth := mode as KingOfTheSwing
		if koth.holder == koth.key_of(player):
			return "HOLDING THE ZONE"
		if koth.contested and player.global_position.distance_to(koth.zone_center(tick)) <= koth.def.zone_radius:
			return "ZONE CONTESTED"
	elif mode is GunGame:
		var gun := mode as GunGame
		var weapon := gun.weapon_for(player)
		if weapon.is_empty():
			return "FINAL LEVEL: PUNCH A KO TO WIN"
		var def := WeaponDef.load_by_id(weapon)
		return "LEVEL %d/%d  %s" % [int(gun.levels.get(player.fighter_id, 0)) + 1, gun.target_points(), def.display_name.to_upper() if def != null else ""]
	return ""


func _draw_fire(v: Node2D) -> void:
	var item := _held_weapon()
	if item == null:
		return
	var r := _fire_radius()
	var c := item.def.glow_color
	v.draw_circle(Vector2.ZERO, r, Color(c, 0.4 if _fire_down else 0.2))
	v.draw_arc(Vector2.ZERO, r - 2.0, 0.0, TAU, 64, Color(c, 0.85), 4.0, true)
	var font := UiTheme.FONT
	var label := "FIRE"
	var sub := ""
	if item.def.kind == WeaponDef.Kind.BLADE:
		label = "SWING"
	elif item.def.kind == WeaponDef.Kind.GUN:
		label = "THROW" if item.ammo <= 0 else "FIRE"
		sub = "" if item.ammo <= 0 else "%d" % item.ammo
	elif item.def.kind == WeaponDef.Kind.SPECIAL:
		label = SpecialWeapons.use_label(item)
		sub = "%d" % item.ammo if item.def.ammo > 1 and item.ammo > 0 else ""
		if item.def.projectile_kind == &"thruster" and player.sim.special_weapons.is_thrusting(player, player.sim.tick):
			label = "HOLD TO STEER"
	elif item.def.ammo > 0:
		sub = "%d" % item.ammo
	v.draw_string(font, Vector2(-r, 4), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 30, Color.WHITE)
	v.draw_string(font, Vector2(-r, 34), item.def.display_name.to_upper() + ("  " + sub if not sub.is_empty() else ""), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 16, Color(1, 1, 1, 0.8))


func _draw_melee(v: Node2D) -> void:
	var r := _melee_radius()
	v.draw_circle(Vector2.ZERO, r, Color(1, 1, 1, 0.32 if _melee_down else 0.14))
	v.draw_arc(Vector2.ZERO, r - 2.0, 0.0, TAU, 64, Color(1, 1, 1, 0.55), 4.0, true)
	var font := UiTheme.FONT
	var item := _held_weapon()
	var blade := item != null and item.def.kind == WeaponDef.Kind.BLADE
	_draw_knife_icon(v, Vector2(0, -r * 0.3), r * 0.5)
	v.draw_string(font, Vector2(-r, r * 0.42), item.def.display_name.to_upper() if blade else "KNIFE", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 30, Color(1, 1, 1, 0.85))


## A knife pointing up and to the right, about size across.
func _draw_knife_icon(v: Node2D, at: Vector2, size: float) -> void:
	var dir := Vector2(1, -1).normalized()
	var side := dir.orthogonal()
	var hand := at - dir * size * 0.55
	var guard := hand + dir * size * 0.35
	var tip := at + dir * size * 0.75
	var c := Color(1, 1, 1, 0.85)
	v.draw_line(hand, guard, c, size * 0.16, true)
	v.draw_line(guard - side * size * 0.17, guard + side * size * 0.17, c, size * 0.08, true)
	v.draw_colored_polygon(PackedVector2Array([guard - side * size * 0.12, tip, guard + side * size * 0.07]), c)


func _draw_pause(v: Node2D) -> void:
	var half := PAUSE_SIZE * 0.5
	var rect := Rect2(-half, -half, PAUSE_SIZE, PAUSE_SIZE)
	v.draw_rect(rect, Color(1, 1, 1, 0.12))
	v.draw_rect(rect, Color(1, 1, 1, 0.45), false, 3.0)
	v.draw_rect(Rect2(-16, -20, 10, 40), Color(1, 1, 1, 0.8))
	v.draw_rect(Rect2(6, -20, 10, 40), Color(1, 1, 1, 0.8))
