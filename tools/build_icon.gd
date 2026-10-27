extends SceneTree
## Renders the app icons from Kenney's vector astronaut: a space gradient, a glow, the alien
## mid-swing and a rope running to a hook in the top-right corner.
##   res://icon.png                                  1024 x 1024, project icon (iOS, Android legacy)
##   res://assets/art/icon/adaptive_background.png   432 x 432, Android adaptive background layer
##   res://assets/art/icon/adaptive_foreground.png   432 x 432, Android adaptive foreground layer,
##                                                   kept inside the safe circle launchers never mask
## Run: godot --headless --path . -s res://tools/build_icon.gd

const SIZE: int = 1024
const ADAPTIVE: int = 432
## The whole drawing is scaled to this size in the adaptive foreground, so the hook tip stays inside
## the 288 px safe circle in the middle of the 432 px layer.
const ADAPTIVE_CONTENT: int = 240
const ALIEN_SVG: String = "res://assets/art/icon/character_green_jump.svg"
const OUT: String = "res://icon.png"
const OUT_ADAPTIVE_BG: String = "res://assets/art/icon/adaptive_background.png"
const OUT_ADAPTIVE_FG: String = "res://assets/art/icon/adaptive_foreground.png"
const TOP: Color = Color("1b1236")
const BOTTOM: Color = Color("0a0b1a")
const GLOW: Color = Color("7be0a8")
const ROPE: Color = Color("c8ffe0")
## Positions as fractions of the icon size.
const GLOW_CENTER: Vector2 = Vector2(0.44, 0.56)
const HAND: Vector2 = Vector2(0.63, 0.7)
const TIP: Vector2 = Vector2(0.9, 0.1)


func _init() -> void:
	var foreground := _foreground(SIZE)
	var icon := _background(SIZE)
	icon.blend_rect(foreground, Rect2i(Vector2i.ZERO, foreground.get_size()), Vector2i.ZERO)
	icon.save_png(OUT)

	_background(ADAPTIVE).save_png(OUT_ADAPTIVE_BG)
	var small := foreground.duplicate() as Image
	small.resize(ADAPTIVE_CONTENT, ADAPTIVE_CONTENT, Image.INTERPOLATE_LANCZOS)
	var layer := Image.create(ADAPTIVE, ADAPTIVE, false, Image.FORMAT_RGBA8)
	var at := (ADAPTIVE - ADAPTIVE_CONTENT) / 2
	layer.blend_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(at, at))
	layer.save_png(OUT_ADAPTIVE_FG)
	print("wrote %s, %s, %s" % [OUT, OUT_ADAPTIVE_BG, OUT_ADAPTIVE_FG])
	quit()


func _background(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var k := float(size) / SIZE
	var center := GLOW_CENTER * size
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stars: Array[Vector3] = []
	for i in 70:
		stars.append(Vector3(rng.randf() * size, rng.randf() * size, rng.randf_range(1.5, 4.5) * maxf(k, 0.6)))
	for y in size:
		for x in size:
			var p := Vector2(x, y)
			var c := TOP.lerp(BOTTOM, float(y) / size)
			var glow := clampf(1.0 - p.distance_to(center) / (size * 0.42), 0.0, 1.0)
			c = c.lerp(GLOW, glow * glow * 0.35)
			for s in stars:
				var d := p.distance_to(Vector2(s.x, s.y))
				if d < s.z:
					c = c.lerp(Color.WHITE, (1.0 - d / s.z) * 0.8)
			img.set_pixel(x, y, c)
	return img


## Rope, hook and alien on a transparent layer.
func _foreground(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hand := HAND * size
	var tip := TIP * size
	_line(img, hand, tip, 16.0, ROPE)
	_hook(img, tip, (tip - hand).normalized(), ROPE)
	var alien := Image.new()
	alien.load_svg_from_string(FileAccess.get_file_as_string(ALIEN_SVG), 6.5 * size / SIZE)
	alien.convert(Image.FORMAT_RGBA8)
	var at := Vector2i(GLOW_CENTER * size) - alien.get_size() / 2
	img.blend_rect(alien, Rect2i(Vector2i.ZERO, alien.get_size()), at)
	return img


func _paint(img: Image, x: int, y: int, color: Color, cover: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(color, cover)))


func _line(img: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(width)
	for y in range(int(box.position.y), int(box.end.y)):
		for x in range(int(box.position.x), int(box.end.x)):
			var p := Vector2(x, y)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			var cover := clampf(width * 0.5 - d + 0.5, 0.0, 1.0)
			if cover > 0.0:
				_paint(img, x, y, color, cover)


func _hook(img: Image, tip: Vector2, dir: Vector2, color: Color) -> void:
	var side := dir.orthogonal()
	var head := PackedVector2Array([tip + dir * 30.0, tip - dir * 50.0 + side * 46.0, tip - dir * 22.0, tip - dir * 50.0 - side * 46.0])
	var box := Rect2(tip, Vector2.ZERO).grow(90.0)
	for y in range(int(box.position.y), int(box.end.y)):
		for x in range(int(box.position.x), int(box.end.x)):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), head):
				_paint(img, x, y, color, 1.0)
