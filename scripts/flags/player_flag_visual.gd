extends Node2D

# Runtime world-space drawing for species flags and their influence areas.
# The visual never blocks tiles and has no gameplay authority of its own.

const FLAG_AREA_SIZE := Vector2i(11, 11)
const DEFAULT_TILE_SIZE := Vector2i(128, 128)

var world_grid: Node = null
var flags: Dictionary = {}
var preview_active := false
var preview_tile := Vector2i.ZERO
var preview_valid := false


func _ready() -> void:
	z_index = 3
	queue_redraw()


func configure(target_world_grid: Node) -> void:
	world_grid = target_world_grid
	queue_redraw()


func set_flags(new_flags: Dictionary) -> void:
	flags = new_flags.duplicate(true)
	queue_redraw()


func set_preview(tile: Vector2i, is_valid: bool) -> void:
	preview_active = true
	preview_tile = tile
	preview_valid = is_valid
	queue_redraw()


func hide_preview() -> void:
	preview_active = false
	queue_redraw()


func _draw() -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		return

	for species_id_variant: Variant in flags.keys():
		var species_id := StringName(species_id_variant)
		var tile_variant: Variant = flags.get(species_id_variant)

		if not (tile_variant is Vector2i):
			continue

		var flag_tile: Vector2i = tile_variant
		_draw_flag_area(flag_tile, species_id, _get_species_color(species_id), false)

	if preview_active:
		var preview_color := (
			Color(0.5, 1.0, 0.45, 1.0) if preview_valid else Color(1.0, 0.3, 0.25, 1.0)
		)
		_draw_flag_area(preview_tile, StringName(), preview_color, true)


func _draw_flag_area(
	flag_tile: Vector2i, species_id: StringName, base_color: Color, is_preview: bool
) -> void:
	var tile_size := _get_tile_size()
	var area_min := flag_tile - Vector2i(FLAG_AREA_SIZE.x / 2, FLAG_AREA_SIZE.y / 2)
	var area_min_world: Vector2 = world_grid.call("map_to_world_center", area_min)
	var top_left_world := area_min_world - Vector2(tile_size) * 0.5
	var area_pixel_size := Vector2(
		float(FLAG_AREA_SIZE.x * tile_size.x), float(FLAG_AREA_SIZE.y * tile_size.y)
	)
	var area_rect := Rect2(to_local(top_left_world), area_pixel_size)
	var fill_alpha := 0.035 if not is_preview else 0.055
	var border_alpha := 0.36 if not is_preview else 0.72

	draw_rect(area_rect, Color(base_color.r, base_color.g, base_color.b, fill_alpha), true)
	draw_rect(area_rect, Color(base_color.r, base_color.g, base_color.b, border_alpha), false, 3.0)

	var flag_center_world: Vector2 = world_grid.call("map_to_world_center", flag_tile)
	_draw_flag(to_local(flag_center_world), tile_size, species_id, base_color, is_preview)


func _draw_flag(
	center: Vector2, tile_size: Vector2i, species_id: StringName, base_color: Color, is_preview: bool
) -> void:
	var alpha := 0.55 if is_preview else 1.0
	var pole_bottom := center + Vector2(0.0, float(tile_size.y) * 0.36)
	var pole_top := center - Vector2(0.0, float(tile_size.y) * 0.48)
	var pole_color := Color(0.2, 0.12, 0.06, alpha)
	var cloth_color := Color(base_color.r, base_color.g, base_color.b, alpha)
	var outline_color := Color(0.06, 0.08, 0.06, alpha)

	draw_line(pole_bottom, pole_top, pole_color, 8.0, true)
	draw_circle(pole_bottom, 7.0, pole_color)

	var cloth_points := PackedVector2Array(
		[
			pole_top + Vector2(4.0, 2.0),
			pole_top + Vector2(float(tile_size.x) * 0.48, 12.0),
			pole_top + Vector2(float(tile_size.x) * 0.34, 38.0),
			pole_top + Vector2(4.0, 32.0)
		]
	)
	draw_colored_polygon(cloth_points, cloth_color)
	draw_polyline(
		PackedVector2Array(
			[cloth_points[0], cloth_points[1], cloth_points[2], cloth_points[3], cloth_points[0]]
		),
		outline_color,
		3.0,
		true
	)

	if species_id != &"stegosaurus":
		return

	# Three orange plates identify the stegosaurus flag without a font asset.
	var plate_color := Color(0.95, 0.48, 0.12, alpha)
	for plate_index in range(3):
		var plate_x := 22.0 + float(plate_index) * 20.0
		var plate_base := pole_top + Vector2(plate_x, 27.0)
		var plate_points := PackedVector2Array(
			[
				plate_base + Vector2(-7.0, 0.0),
				plate_base + Vector2(0.0, -12.0),
				plate_base + Vector2(7.0, 0.0)
			]
		)
		draw_colored_polygon(plate_points, plate_color)


func _get_tile_size() -> Vector2i:
	if world_grid != null:
		var tile_size_variant: Variant = world_grid.get("tile_size")

		if tile_size_variant is Vector2i:
			var configured_tile_size: Vector2i = tile_size_variant
			return configured_tile_size

	return DEFAULT_TILE_SIZE


func _get_species_color(species_id: StringName) -> Color:
	match species_id:
		&"stegosaurus":
			return Color(0.29, 0.78, 0.32, 1.0)
		&"triceratops":
			return Color(0.35, 0.75, 0.9, 1.0)
		&"tyrannosaurus":
			return Color(0.94, 0.32, 0.22, 1.0)
		&"raptor":
			return Color(0.96, 0.7, 0.18, 1.0)
		&"pterodactyl":
			return Color(0.64, 0.48, 0.9, 1.0)
		&"egg_eater":
			return Color(0.24, 0.78, 0.72, 1.0)
		_:
			return Color(0.72, 0.82, 0.76, 1.0)
