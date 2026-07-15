extends Node2D

# Fixed player-owned nature base. It is a static 2x2 world-grid blocker and
# serves as the creation point for eggs bought by the player.
@onready var body_sprite: Sprite2D = $BodySprite
@onready var shadow_sprite: Sprite2D = $ShadowSprite

@export var footprint_size := Vector2i(2, 2)
@export var visual_target_size := Vector2(256.0, 256.0)
@export var shadow_offset := Vector2(0.0, 18.0)
@export var shadow_alpha := 0.22

const EGG_STAGE_1_FOOTPRINT := Vector2i(1, 2)
const EGG_SEARCH_RADIUS := 6
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)
const CREATURE_SCENE := preload("res://scenes/creatures/creature.tscn")

var world_grid: Node = null
var anchor_tile := Vector2i.ZERO
var is_registered_as_blocker := false


func _ready() -> void:
	configure_visual()
	world_grid = find_world_grid()

	if world_grid == null:
		push_error("PlayerBase: world grid was not found.")
		return

	var requested_anchor: Vector2i = world_grid.world_to_anchor_tile(
		global_position,
		footprint_size
	)
	anchor_tile = requested_anchor

	if not world_grid.can_place_footprint(anchor_tile, footprint_size, self):
		anchor_tile = world_grid.find_nearest_valid_anchor(
			requested_anchor,
			footprint_size,
			self,
			8
		)

	if not world_grid.register_blocker(self, anchor_tile, footprint_size):
		push_error(
			"PlayerBase: cannot occupy a valid 2x2 footprint near (%d, %d)." % [
				requested_anchor.x,
				requested_anchor.y
			]
		)
		queue_free()
		return

	if anchor_tile != requested_anchor:
		push_warning(
			"PlayerBase: spawn footprint was blocked; base moved from (%d, %d) to (%d, %d)." % [
				requested_anchor.x,
				requested_anchor.y,
				anchor_tile.x,
				anchor_tile.y
			]
		)

	is_registered_as_blocker = true
	global_position = world_grid.anchor_to_world_position(anchor_tile, footprint_size)


func _exit_tree() -> void:
	if world_grid != null and is_registered_as_blocker:
		world_grid.unregister_blocker(self, footprint_size)
		is_registered_as_blocker = false


func create_player_egg(species_data: CreatureSpeciesData) -> Node2D:
	if species_data == null or species_data.egg_scene == null:
		return null

	if world_grid == null:
		world_grid = find_world_grid()

	if world_grid == null:
		return null

	var egg_anchor := find_player_egg_spawn_anchor()

	if egg_anchor == INVALID_ANCHOR:
		return null

	var eggs_container := world_grid.get_node_or_null("Eggs") as Node2D

	if eggs_container == null:
		push_error("PlayerBase: Eggs container was not found.")
		return null

	var new_egg := species_data.egg_scene.instantiate() as Node2D

	if new_egg == null:
		return null

	new_egg.set("species_id", species_data.species_id)
	new_egg.set("hatch_species_data", species_data)

	if species_data.egg_stage_1_texture != null:
		new_egg.set("stage_1_texture", species_data.egg_stage_1_texture)

	if species_data.egg_stage_2_texture != null:
		new_egg.set("stage_2_texture", species_data.egg_stage_2_texture)

	new_egg.set("stage_1_duration", species_data.egg_stage_1_duration)
	new_egg.set("expand_retry_interval", species_data.egg_expand_retry_interval)
	new_egg.set("stage_2_duration", species_data.egg_stage_2_duration)
	new_egg.set("hatch_health", species_data.hatchling_health)
	new_egg.set("hatch_hunger", species_data.hatchling_hunger)
	new_egg.set("hatch_creature_scene", CREATURE_SCENE)

	var egg_world_position: Vector2 = world_grid.anchor_to_world_position(
		egg_anchor,
		EGG_STAGE_1_FOOTPRINT
	)
	new_egg.position = eggs_container.to_local(egg_world_position)
	eggs_container.add_child(new_egg)
	return new_egg


func find_player_egg_spawn_anchor() -> Vector2i:
	if world_grid == null:
		return INVALID_ANCHOR

	var preferred_anchors: Array[Vector2i] = [
		anchor_tile + Vector2i(-1, 0),
		anchor_tile + Vector2i(footprint_size.x, 0),
		anchor_tile + Vector2i(0, -EGG_STAGE_1_FOOTPRINT.y),
		anchor_tile + Vector2i(1, -EGG_STAGE_1_FOOTPRINT.y),
		anchor_tile + Vector2i(0, footprint_size.y),
		anchor_tile + Vector2i(1, footprint_size.y)
	]

	for candidate_anchor in preferred_anchors:
		if can_place_player_egg_anchor(candidate_anchor):
			return candidate_anchor

	for radius in range(1, EGG_SEARCH_RADIUS + 1):
		var min_x := anchor_tile.x - radius
		var max_x := anchor_tile.x + footprint_size.x - 1 + radius
		var min_y := anchor_tile.y - radius - EGG_STAGE_1_FOOTPRINT.y + 1
		var max_y := anchor_tile.y + footprint_size.y - 1 + radius

		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				var candidate_anchor := Vector2i(x, y)

				if can_place_player_egg_anchor(candidate_anchor):
					return candidate_anchor

	return INVALID_ANCHOR


func can_place_player_egg_anchor(candidate_anchor: Vector2i) -> bool:
	if world_grid == null:
		return false

	if not world_grid.can_place_footprint(candidate_anchor, EGG_STAGE_1_FOOTPRINT):
		return false

	var candidate_tiles: Array = world_grid.get_footprint_tiles(
		candidate_anchor,
		EGG_STAGE_1_FOOTPRINT
	)

	for egg in get_tree().get_nodes_in_group("eggs"):
		if not is_instance_valid(egg) or egg.is_queued_for_deletion():
			continue

		var existing_anchor: Vector2i = egg.get("anchor_tile")
		var existing_footprint: Vector2i = EGG_STAGE_1_FOOTPRINT

		if egg.has_method("get_current_footprint"):
			var footprint_value: Variant = egg.call("get_current_footprint")

			if footprint_value is Vector2i:
				existing_footprint = footprint_value

		var existing_tiles: Array = world_grid.get_footprint_tiles(
			existing_anchor,
			existing_footprint
		)

		for tile in candidate_tiles:
			if existing_tiles.has(tile):
				return false

	return true


func configure_visual() -> void:
	_configure_sprite_scale()
	_configure_shadow()


func _configure_sprite_scale() -> void:
	if body_sprite == null:
		return

	# The source art is intentionally larger than its 256x256 world footprint.
	# Linear filtering with mipmaps keeps the downscaled sprite clean and leaves
	# detail available when the observer camera zooms in.
	body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	if body_sprite.texture == null:
		return

	var texture_size := body_sprite.texture.get_size()

	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var sprite_scale := Vector2(
		visual_target_size.x / texture_size.x,
		visual_target_size.y / texture_size.y
	)
	body_sprite.scale = sprite_scale

	if shadow_sprite != null:
		shadow_sprite.scale = sprite_scale


func _configure_shadow() -> void:
	if shadow_sprite == null:
		return

	if body_sprite != null:
		shadow_sprite.texture = body_sprite.texture

	shadow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	shadow_sprite.position = shadow_offset
	shadow_sprite.modulate = Color(0.0, 0.0, 0.0, shadow_alpha)


func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_blocker") and current.has_method("world_to_anchor_tile"):
			return current

		current = current.get_parent()

	return null
