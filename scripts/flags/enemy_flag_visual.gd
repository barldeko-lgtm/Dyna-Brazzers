extends "res://scripts/flags/player_flag_visual.gd"

# Attack flags share the player base objective; the raptor guards the enemy base.
const ENEMY_FLAG_AREA_SIZE := Vector2i(11, 11)
const DISPLAY_ORDER: Array[StringName] = [
	&"tyrannosaurus",
	&"pterodactyl",
	&"egg_eater"
]
const RAPTOR_ID: StringName = &"raptor"
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)


func _ready() -> void:
	super._ready()
	z_index = 4


func _draw_flag(
	center: Vector2, tile_size: Vector2i, species_id: StringName, base_color: Color, is_preview: bool
) -> void:
	_draw_procedural_flag(center, tile_size, species_id, base_color, is_preview)


func _draw() -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		return

	var attack_flag_tile := _get_shared_flag_tile()

	if attack_flag_tile != INVALID_ANCHOR:
		_draw_attack_objective(attack_flag_tile)

	var raptor_flag_tile := get_raptor_flag_tile()

	if raptor_flag_tile != INVALID_ANCHOR:
		_draw_flag_area(
			raptor_flag_tile,
			RAPTOR_ID,
			_get_species_color(RAPTOR_ID),
			false
		)


func _draw_attack_objective(flag_tile: Vector2i) -> void:
	var tile_size := _get_tile_size()
	_draw_enemy_area(flag_tile, tile_size)
	var flag_center_world: Vector2 = world_grid.call("map_to_world_center", flag_tile)
	var flag_center := to_local(flag_center_world)
	var visible_species: Array[StringName] = []

	for species_id: StringName in DISPLAY_ORDER:
		if flags.has(species_id):
			visible_species.append(species_id)

	if visible_species.is_empty():
		return

	var spacing := float(tile_size.x) * 0.50
	var first_offset := -spacing * float(visible_species.size() - 1) * 0.5

	for index in range(visible_species.size()):
		var species_id := visible_species[index]
		var pole_center := flag_center + Vector2(
			first_offset + float(index) * spacing,
			float(index % 2) * 8.0
		)
		_draw_flag(
			pole_center,
			tile_size,
			species_id,
			_get_species_color(species_id),
			false
		)


func _get_shared_flag_tile() -> Vector2i:
	for species_id: StringName in DISPLAY_ORDER:
		var tile_variant: Variant = flags.get(species_id, INVALID_ANCHOR)

		if tile_variant is Vector2i:
			return tile_variant

	return INVALID_ANCHOR


func get_raptor_flag_tile() -> Vector2i:
	var tile_variant: Variant = flags.get(RAPTOR_ID, INVALID_ANCHOR)
	return tile_variant if tile_variant is Vector2i else INVALID_ANCHOR


func _draw_enemy_area(flag_tile: Vector2i, tile_size: Vector2i) -> void:
	var area_min := flag_tile - Vector2i(
		ENEMY_FLAG_AREA_SIZE.x / 2,
		ENEMY_FLAG_AREA_SIZE.y / 2
	)
	var area_min_world: Vector2 = world_grid.call("map_to_world_center", area_min)
	var top_left_world := area_min_world - Vector2(tile_size) * 0.5
	var area_pixel_size := Vector2(
		float(ENEMY_FLAG_AREA_SIZE.x * tile_size.x),
		float(ENEMY_FLAG_AREA_SIZE.y * tile_size.y)
	)
	var area_rect := Rect2(to_local(top_left_world), area_pixel_size)
	var enemy_area_color := Color(0.72, 0.12, 0.18, 1.0)

	draw_rect(
		area_rect,
		Color(enemy_area_color.r, enemy_area_color.g, enemy_area_color.b, 0.035),
		true
	)
	draw_rect(
		area_rect,
		Color(enemy_area_color.r, enemy_area_color.g, enemy_area_color.b, 0.48),
		false,
		3.0
	)
