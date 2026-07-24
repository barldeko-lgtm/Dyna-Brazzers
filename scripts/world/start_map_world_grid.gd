extends "res://scripts/world/world_grid.gd"

# Camera bounds for the authored map. Grass may occupy and spread onto any
# normal walkable terrain except either faction base footprint.
const PLAYER_BASE_SCENE := preload("res://scenes/world/player_base.tscn")
const ENEMY_BASE_SCENE := preload("res://scenes/world/enemy_base.tscn")
const ENEMY_ENERGY_SCRIPT := preload("res://scripts/enemies/enemy_energy.gd")
const ENEMY_PRODUCTION_SCRIPT := preload("res://scripts/enemies/enemy_egg_production_controller.gd")
const ENEMY_AI_SCRIPT := preload("res://scripts/enemies/enemy_ai_controller.gd")
const ENEMY_SPELL_CONTROLLER_SCRIPT := preload("res://scripts/enemies/enemy_spell_controller.gd")
const ENEMY_FLAG_SYSTEM_SCRIPT := preload("res://scripts/flags/enemy_flag_system.gd")
const PLAYER_BASE_NODE_NAME := "PlayerBase"
const ENEMY_BASE_NODE_NAME := "EnemyBase"
const ENEMY_ENERGY_NODE_NAME := "EnemyEnergy"
const ENEMY_PRODUCTION_NODE_NAME := "EnemyEggProduction"
const ENEMY_AI_NODE_NAME := "EnemyAI"
const ENEMY_SPELL_CONTROLLER_NODE_NAME := "EnemySpellController"
const ENEMY_FLAG_SYSTEM_NODE_NAME := "EnemyAttackFlags"
const BASE_FOOTPRINT := Vector2i(2, 2)
const ENEMY_BASE_FALLBACK_MARGIN := Vector2i(4, 4)


func _ready() -> void:
	super._ready()
	spawn_player_base_if_needed()
	spawn_enemy_base_if_needed()
	spawn_enemy_runtime_if_needed()


func can_host_grass(tile: Vector2i) -> bool:
	if not is_tile_walkable(tile):
		return false

	var occupant: Node = occupied_by_tile.get(tile, null)

	if occupant != null and is_instance_valid(occupant) and occupant.is_in_group("faction_base"):
		return false

	return true


func get_world_bounds_rect() -> Rect2:
	ensure_initialized()

	if ground == null:
		return Rect2()

	var half_tile: Vector2 = Vector2(tile_size) * 0.5
	var min_center: Vector2 = map_to_world_center(map_min)
	var max_center: Vector2 = map_to_world_center(map_max)
	var min_edge: Vector2 = min_center - half_tile
	var max_edge: Vector2 = max_center + half_tile

	return Rect2(min_edge, max_edge - min_edge)


func spawn_player_base_if_needed() -> void:
	if get_node_or_null(PLAYER_BASE_NODE_NAME) != null:
		return

	var spawn_marker := get_node_or_null("CameraStart") as Node2D

	if spawn_marker == null:
		push_error("StartMapWorldGrid: CameraStart marker was not found for the player base.")
		return

	_spawn_base(
		PLAYER_BASE_SCENE,
		PLAYER_BASE_NODE_NAME,
		spawn_marker.position
	)


func spawn_enemy_base_if_needed() -> void:
	if get_node_or_null(ENEMY_BASE_NODE_NAME) != null:
		return

	var spawn_marker := get_node_or_null("EnemyBaseStart") as Node2D
	var spawn_position := Vector2.ZERO

	if spawn_marker != null:
		spawn_position = spawn_marker.position
	else:
		# Keep the authored TileMap untouched. Until an EnemyBaseStart marker is
		# placed in Godot, use a deterministic anchor near the opposite map edge.
		ensure_initialized()
		var fallback_anchor := _find_enemy_fallback_anchor()
		spawn_position = anchor_to_world_position(fallback_anchor, BASE_FOOTPRINT)

	_spawn_base(
		ENEMY_BASE_SCENE,
		ENEMY_BASE_NODE_NAME,
		spawn_position
	)


func spawn_enemy_runtime_if_needed() -> void:
	if get_node_or_null(ENEMY_ENERGY_NODE_NAME) == null:
		var enemy_energy := ENEMY_ENERGY_SCRIPT.new() as Node

		if enemy_energy == null:
			push_error("StartMapWorldGrid: enemy energy could not be created.")
		else:
			enemy_energy.name = ENEMY_ENERGY_NODE_NAME
			add_child(enemy_energy)

	if get_node_or_null(ENEMY_PRODUCTION_NODE_NAME) == null:
		var enemy_production := ENEMY_PRODUCTION_SCRIPT.new() as Node

		if enemy_production == null:
			push_error("StartMapWorldGrid: enemy egg production could not be created.")
		else:
			enemy_production.name = ENEMY_PRODUCTION_NODE_NAME
			add_child(enemy_production)

	if get_node_or_null(ENEMY_AI_NODE_NAME) == null:
		var enemy_ai := ENEMY_AI_SCRIPT.new() as Node

		if enemy_ai == null:
			push_error("StartMapWorldGrid: enemy AI could not be created.")
		else:
			enemy_ai.name = ENEMY_AI_NODE_NAME
			add_child(enemy_ai)

	if get_node_or_null(ENEMY_SPELL_CONTROLLER_NODE_NAME) == null:
		var enemy_spells := ENEMY_SPELL_CONTROLLER_SCRIPT.new() as Node

		if enemy_spells == null:
			push_error("StartMapWorldGrid: enemy spell controller could not be created.")
		else:
			enemy_spells.name = ENEMY_SPELL_CONTROLLER_NODE_NAME
			add_child(enemy_spells)

	if get_node_or_null(ENEMY_FLAG_SYSTEM_NODE_NAME) == null:
		var enemy_flags := ENEMY_FLAG_SYSTEM_SCRIPT.new() as Node

		if enemy_flags == null:
			push_error("StartMapWorldGrid: enemy attack flags could not be created.")
		else:
			enemy_flags.name = ENEMY_FLAG_SYSTEM_NODE_NAME
			add_child(enemy_flags)


func _find_enemy_fallback_anchor() -> Vector2i:
	var preferred_anchor := Vector2i(
		maxi(map_min.x, map_max.x - ENEMY_BASE_FALLBACK_MARGIN.x),
		maxi(map_min.y, map_max.y - ENEMY_BASE_FALLBACK_MARGIN.y)
	)

	for y in range(preferred_anchor.y, map_min.y - 1, -1):
		for x in range(preferred_anchor.x, map_min.x - 1, -1):
			var candidate_anchor := Vector2i(x, y)

			if can_place_footprint(candidate_anchor, BASE_FOOTPRINT):
				return candidate_anchor

	return preferred_anchor


func _spawn_base(
	base_scene: PackedScene,
	base_name: String,
	spawn_position: Vector2
) -> void:
	var faction_base := base_scene.instantiate() as Node2D

	if faction_base == null:
		push_error("StartMapWorldGrid: %s scene could not be instantiated." % base_name)
		return

	faction_base.name = base_name
	faction_base.position = spawn_position
	add_child(faction_base)
