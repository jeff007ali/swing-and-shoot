class_name RopeView
extends Node2D
## Draws one fighter's rope and hook (§4.11), interpolated between sim ticks: a tiled rope texture and
## a hook sprite from the skin, both tinted with its colors. The rope brightens with tension. For the
## local player it also plays the looping tension hum, pitched by pull strength.

const WIDTH: float = 8.0
## Hook sprite: the tip is this far ahead of the rope end at its left-center edge (§3.8).
const HOOK_TIP: float = 31.0
const HOOK_EYE: float = 5.0
const HUM_VOLUME_DB: float = -16.0
const HUM_MIN_TENSION: float = 0.05

var fighter: Fighter

var _line: Line2D
var _hook: Sprite2D
var _hum: AudioStreamPlayer
var _rope_color: Color = Color.WHITE
var _hook_color: Color = Color.WHITE


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var skin := SkinDef.load_by_id(fighter.skin_id)
	_line = Line2D.new()
	_line.width = WIDTH
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	_line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(_line)
	_hook = Sprite2D.new()
	_hook.centered = false
	add_child(_hook)
	_rope_color = UiTheme.player_color(fighter.skin_id)
	Settings.changed.connect(func() -> void: _rope_color = UiTheme.player_color(fighter.skin_id))
	if skin != null:
		_hook_color = skin.hook_color
		_line.texture = skin.rope_texture
		_hook.texture = skin.hook_texture
		if skin.hook_texture != null:
			_hook.offset = Vector2(-HOOK_TIP, -skin.hook_texture.get_height() * 0.5)
	_line.default_color = _rope_color
	_hook.modulate = _hook_color
	if fighter.is_local_player:
		var loop := Sfx.stream(&"rope_hum").duplicate() as AudioStreamOggVorbis
		if loop != null:
			loop.loop = true
			_hum = AudioStreamPlayer.new()
			_hum.stream = loop
			_hum.bus = &"SFX"
			_hum.volume_db = HUM_VOLUME_DB
			add_child(_hum)
	visible = false


func _process(_delta: float) -> void:
	var rope := fighter.rope
	if rope.state == SimIds.RopeState.IDLE or fighter.state == SimIds.FighterState.KO:
		visible = false
		_update_hum(0.0)
		return
	visible = true
	var f := Engine.get_physics_interpolation_fraction()
	var from := fighter.prev_position.lerp(fighter.global_position, f)
	var to := rope.prev_hook_pos.lerp(rope.hook_pos, f)
	var dir := (to - from).normalized()
	# The hook's tip sits on the hook point; the rope ties on at its eye.
	_line.points = PackedVector2Array([from, to - dir * (HOOK_TIP - HOOK_EYE)])
	_line.default_color = _rope_color.lerp(Color.WHITE, rope.tension * 0.6)
	_line.width = WIDTH * (1.0 - rope.tension * 0.3)
	modulate.a = 0.6 if rope.state == SimIds.RopeState.RETRACTING else 1.0
	_hook.position = to
	_hook.rotation = dir.angle()
	_update_hum(rope.tension)


func _update_hum(tension: float) -> void:
	if _hum == null:
		return
	if tension > HUM_MIN_TENSION:
		_hum.pitch_scale = 0.8 + tension * 0.7
		if not _hum.playing:
			_hum.play()
	elif _hum.playing:
		_hum.stop()

