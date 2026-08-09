extends "res://scripts/flags/player_flag_visual.gd"

# Attack flags share the player base objective; the raptor guards the enemy base.
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
	visible = false


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
