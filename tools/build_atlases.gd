extends SceneTree
## Packs sprite groups into texture atlases (§3.8) and writes one AtlasTexture resource per sprite, so
## each group draws from a single texture. Godot's own "Texture Atlas" import mode only runs inside
## the editor, so this does the same job from the command line.
## Run: godot --headless --path . -s res://tools/build_atlases.gd
## Then: godot --headless --path . --import, and tools/build_skins.gd (skins use the character atlas).
##
## Sprites are trimmed to their used pixels; AtlasTexture.margin restores the original size, so code
## sees the same texture sizes as before.

const OUT_DIR: String = "res://assets/art/atlas/"
## Empty pixels between packed sprites so linear filtering never bleeds a neighbour in.
const PADDING: int = 2
const MAX_SIZE: int = 2048

## group -> source PNGs
const GROUPS: Dictionary = {
	"characters": ["res://assets/art/characters/*.png", "res://assets/art/fx/hook.png"],
	"arena": ["res://assets/art/arena/spaceMeteors_*.png", "res://assets/art/arena/spaceBuilding_009.png"],
}


func _init() -> void:
	for group: String in GROUPS:
		_pack(group, _expand(GROUPS[group]))
	quit()


func _expand(patterns: Array) -> PackedStringArray:
	var files := PackedStringArray()
	for pattern: String in patterns:
		var dir := pattern.get_base_dir()
		var mask := pattern.get_file()
		for f in DirAccess.get_files_at(dir):
			if f.match(mask):
				files.append(dir + "/" + f)
	files.sort()
	return files


func _pack(group: String, files: PackedStringArray) -> void:
	var sprites: Array[Dictionary] = []
	for path in files:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		img.convert(Image.FORMAT_RGBA8)
		var used := img.get_used_rect()
		sprites.append({"name": path.get_file().get_basename(), "image": img.get_region(used), "used": used, "full": img.get_size()})
	# Shelf packing, tallest first.
	sprites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["used"].size.y > b["used"].size.y)
	# Try each power-of-two width and keep the most square result (smallest longest side).
	var width := 0
	var height := 0
	var placed: Array[Vector2i] = []
	var try_width := 128
	while try_width <= MAX_SIZE:
		var attempt := _place(sprites, try_width)
		if not attempt.is_empty():
			var h := 1
			for i in sprites.size():
				h = maxi(h, attempt[i].y + sprites[i]["used"].size.y + PADDING)
			h = int(pow(2, ceil(log(h) / log(2))))
			if width == 0 or maxi(try_width, h) < maxi(width, height):
				width = try_width
				height = h
				placed = attempt
		try_width *= 2
	if placed.is_empty():
		push_error("%s does not fit in %d px" % [group, MAX_SIZE])
		return

	var atlas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for i in sprites.size():
		var img: Image = sprites[i]["image"]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), placed[i])
	DirAccess.make_dir_recursive_absolute(OUT_DIR + group)
	var atlas_path := OUT_DIR + group + ".png"
	atlas.save_png(atlas_path)

	for i in sprites.size():
		var s: Dictionary = sprites[i]
		var used: Rect2i = s["used"]
		var full: Vector2i = s["full"]
		var region := Rect2(placed[i], used.size)
		var margin := Rect2(used.position, full - used.size)
		var tres := '[gd_resource type="AtlasTexture" format=3]\n\n[ext_resource type="Texture2D" path="%s" id="1_atlas"]\n\n[resource]\natlas = ExtResource("1_atlas")\nregion = Rect2(%d, %d, %d, %d)\nmargin = Rect2(%d, %d, %d, %d)\nfilter_clip = true\n' % [
			atlas_path, region.position.x, region.position.y, region.size.x, region.size.y,
			margin.position.x, margin.position.y, margin.size.x, margin.size.y]
		var f := FileAccess.open("%s%s/%s.tres" % [OUT_DIR, group, s["name"]], FileAccess.WRITE)
		f.store_string(tres)
	print("%s: %d sprites -> %s (%dx%d)" % [group, sprites.size(), atlas_path, width, height])


## Returns top-left positions for each sprite, or [] if they don't fit in this width.
func _place(sprites: Array[Dictionary], width: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x := PADDING
	var y := PADDING
	var shelf := 0
	for s in sprites:
		var size: Vector2i = s["used"].size
		if size.x + PADDING * 2 > width:
			return []
		if x + size.x + PADDING > width:
			x = PADDING
			y += shelf + PADDING
			shelf = 0
		out.append(Vector2i(x, y))
		x += size.x + PADDING
		shelf = maxi(shelf, size.y)
	if y + shelf + PADDING > MAX_SIZE:
		return []
	return out
