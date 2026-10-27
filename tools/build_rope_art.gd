extends SceneTree
## Draws the rope tile and hook sprites (§3.8 specs) as white art that skins tint.
## Run: godot --headless --path . -s res://tools/build_rope_art.gd

const ROPE_PATH: String = "res://assets/art/fx/rope_tile.png"
const HOOK_PATH: String = "res://assets/art/fx/hook.png"
## Samples per pixel axis for anti-aliasing.
const AA: int = 4


func _init() -> void:
	_rope().save_png(ROPE_PATH)
	_hook().save_png(HOOK_PATH)
	print("wrote %s and %s" % [ROPE_PATH, HOOK_PATH])
	quit()


## 16 x 8, repeats horizontally: a braided cord with soft edges.
func _rope() -> Image:
	var img := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 16:
			var edge := absf(y - 3.5) / 3.5
			var alpha := clampf((1.0 - edge) * 3.0, 0.0, 1.0)
			var braid := 0.72 if posmod(x + y * 2, 8) < 3 else 1.0
			var shade := braid * (1.0 - edge * 0.35)
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return img


## 32 x 32, the rope attaches at the left-center edge: an eye, a shank and a chevron head.
func _hook() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var hits := 0
			for sy in AA:
				for sx in AA:
					var p := Vector2(x + (sx + 0.5) / AA, y + (sy + 0.5) / AA)
					if _hook_shape(p):
						hits += 1
			if hits > 0:
				var a := float(hits) / (AA * AA)
				var shade := 0.85 + 0.15 * (1.0 - absf(y - 16.0) / 16.0)
				img.set_pixel(x, y, Color(shade, shade, shade, a))
	return img


func _hook_shape(p: Vector2) -> bool:
	var eye := p.distance_to(Vector2(5, 16))
	if eye <= 4.5 and eye >= 2.2:
		return true
	if p.x >= 9.0 and p.x <= 17.0 and absf(p.y - 16.0) <= 2.0:
		return true
	var outer := Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(14, 5), Vector2(31, 16), Vector2(14, 27)]))
	var notch := Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(13, 9), Vector2(21, 16), Vector2(13, 23)]))
	return outer and not notch
