extends Node

const DEFAULT_CREATURE_SCENE_PATH := "res://scenes/creatures/creature.tscn"
const DEFAULT_GRASS_SCENE_PATH := "res://scenes/resources/grass.tscn"
const DEFAULT_EGG_SCENE_PATH := "res://scenes/resources/egg.tscn"

var save_system: Node = null


func setup(owner_save_system: Node) -> void:
	save_system = owner_save_system


func collect_world_data() -> Dictionary:
	return {
		"camera": _collect_camera_data(),
		"player_energy": _collect_player_energy(),
		"creatures": _collect_creature_data(),
		"grass": _collect_grass_data(),
		"eggs": _collect_egg_data(),
		"cleared_dry_ground_tiles": _collect_cleared_dry_ground_tiles(),
		"dry_ground_rain_hits": _collect_dry_ground_rain_hits(),
	}


func _collect_camera_data() -> Dictionary:
	var camera := _get_game_camera()

	if camera == null:
		return {}

	return {
		"x": camera.global_position.x,
		"y": camera.global_position.y,
		"zoom_x": camera.zoom.x,
		"zoom_y": camera.zoom.y
	}

func _collect_player_energy() -> float:
	var player_energy: Node = get_tree().get_first_node_in_group("player_energy")

	if player_energy == null or not player_energy.has_method("get_energy"):
		return 0.0

	return float(player_energy.call("get_energy"))

func _collect_cleared_dry_ground_tiles() -> Array:
	var world_grid: Node = get_tree().get_first_node_in_group("world_grid")

	if world_grid == null or not world_grid.has_method("get_cleared_dry_ground_tiles"):
		return []

	return world_grid.call("get_cleared_dry_ground_tiles") as Array

func _collect_dry_ground_rain_hits() -> Array:
	var world_grid: Node = get_tree().get_first_node_in_group("world_grid")

	if world_grid == null or not world_grid.has_method("get_dry_ground_rain_hit_data"):
		return []

	return world_grid.call("get_dry_ground_rain_hit_data") as Array

func _collect_creature_data() -> Array[Dictionary]:
	var creatures_data: Array[Dictionary] = []

	for creature_node: Node in get_tree().get_nodes_in_group("creatures"):
		if not is_instance_valid(creature_node):
			continue

		if creature_node.is_queued_for_deletion():
			continue

		var creature_state: int = int(creature_node.get("state"))

		# Dead creatures are temporary corpse visuals and are not persisted.
		if creature_state == Creature.State.DEAD:
			continue

		var species_data: Resource = creature_node.get("species_data") as Resource

		if species_data == null or species_data.resource_path.is_empty():
			continue

		var anchor_tile: Vector2i = creature_node.get("anchor_tile")
		var scene_path: String = creature_node.scene_file_path

		if scene_path.is_empty():
			scene_path = DEFAULT_CREATURE_SCENE_PATH

		var creature_record: Dictionary = {
			"scene_path": scene_path,
			"species_path": species_data.resource_path,
			"anchor_x": anchor_tile.x,
			"anchor_y": anchor_tile.y,
			"health": float(creature_node.get("health")),
			"hunger": float(creature_node.get("hunger")),
			"age": float(creature_node.get("age")),
			"age_tick_elapsed": float(creature_node.get("age_tick_elapsed")),
			"reproduction_cooldown": float(
				creature_node.get("reproduction_cooldown_remaining")
			),
			"reproduction_progress": float(creature_node.get("reproduction_progress"))
		}
		save_system.call("_enrich_creature_save_record", creature_record, creature_node)
		creatures_data.append(creature_record)

	return creatures_data

func _collect_grass_data() -> Array[Dictionary]:
	var grass_data: Array[Dictionary] = []

	for grass_node: Node in get_tree().get_nodes_in_group("grass"):
		if not is_instance_valid(grass_node):
			continue

		if grass_node.is_queued_for_deletion():
			continue

		var tile: Vector2i = grass_node.get("tile_position")
		var growth_timer: Timer = grass_node.get_node_or_null("GrowthTimer") as Timer
		var spread_timer: Timer = grass_node.get_node_or_null("SpreadTimer") as Timer
		var scene_path: String = grass_node.scene_file_path

		if scene_path.is_empty():
			scene_path = DEFAULT_GRASS_SCENE_PATH

		grass_data.append({
			"scene_path": scene_path,
			"tile_x": tile.x,
			"tile_y": tile.y,
			"stage": int(grass_node.get("current_stage")),
			"has_tried_to_spread": bool(grass_node.get("has_tried_to_spread")),
			"growth_time_left": growth_timer.time_left if growth_timer != null else 0.0,
			"spread_time_left": spread_timer.time_left if spread_timer != null else 0.0
		})

	return grass_data

func _collect_egg_data() -> Array[Dictionary]:
	var eggs_data: Array[Dictionary] = []

	for egg_node: Node in get_tree().get_nodes_in_group("eggs"):
		if not is_instance_valid(egg_node):
			continue

		if egg_node.is_queued_for_deletion():
			continue

		var anchor: Vector2i = egg_node.get("anchor_tile")
		var stage_1_timer: Timer = egg_node.get_node_or_null("Stage1Timer") as Timer
		var retry_timer: Timer = egg_node.get_node_or_null("ExpandRetryTimer") as Timer
		var hatch_timer: Timer = egg_node.get_node_or_null("HatchTimer") as Timer
		var hatch_species: Resource = egg_node.get("hatch_species_data") as Resource
		var hatch_species_path: String = ""

		if hatch_species != null:
			hatch_species_path = hatch_species.resource_path

		var hatch_creature_scene: PackedScene = egg_node.get("hatch_creature_scene") as PackedScene
		var hatch_creature_scene_path := DEFAULT_CREATURE_SCENE_PATH

		if hatch_creature_scene != null and not hatch_creature_scene.resource_path.is_empty():
			hatch_creature_scene_path = hatch_creature_scene.resource_path

		var scene_path: String = egg_node.scene_file_path

		if scene_path.is_empty():
			scene_path = DEFAULT_EGG_SCENE_PATH

		var egg_record: Dictionary = {
			"scene_path": scene_path,
			"species_id": String(egg_node.get("species_id")),
			"hatch_species_path": hatch_species_path,
			"hatch_creature_scene_path": hatch_creature_scene_path,
			"anchor_x": anchor.x,
			"anchor_y": anchor.y,
			"stage": int(egg_node.get("current_stage")),
			"stage_1_time_left": stage_1_timer.time_left if stage_1_timer != null else 0.0,
			"retry_time_left": retry_timer.time_left if retry_timer != null else 0.0,
			"hatch_time_left": hatch_timer.time_left if hatch_timer != null else 0.0
		}
		save_system.call("_enrich_egg_save_record", egg_record, egg_node)
		eggs_data.append(egg_record)

	return eggs_data

func apply_save_data(save_data: Dictionary) -> bool:
	var world_grid: Node = get_tree().get_first_node_in_group("world_grid")

	if world_grid == null:
		await get_tree().process_frame
		world_grid = get_tree().get_first_node_in_group("world_grid")

	if world_grid == null:
		return false

	var creatures_container: Node2D = world_grid.get_node_or_null("Creatures") as Node2D
	var grasses_container: Node2D = world_grid.get_node_or_null("Grasses") as Node2D
	var eggs_container: Node2D = world_grid.get_node_or_null("Eggs") as Node2D

	if creatures_container == null or grasses_container == null or eggs_container == null:
		return false

	Engine.time_scale = 0.0
	_clear_dynamic_simulation_nodes()
	await get_tree().process_frame
	await get_tree().process_frame

	_restore_cleared_dry_ground_tiles(
		save_data.get("cleared_dry_ground_tiles", []) as Array,
		world_grid
	)
	_restore_dry_ground_rain_hits(
		save_data.get("dry_ground_rain_hits", []) as Array,
		world_grid
	)
	_restore_grass(
		save_data.get("grass", []) as Array,
		world_grid,
		grasses_container
	)
	_restore_eggs(
		save_data.get("eggs", []) as Array,
		world_grid,
		eggs_container
	)
	_restore_creatures(
		save_data.get("creatures", []) as Array,
		world_grid,
		creatures_container
	)

	await get_tree().process_frame

	_restore_player_energy(float(save_data.get("player_energy", 0.0)))
	_restore_camera(save_data.get("camera", {}) as Dictionary)
	return true

func _clear_dynamic_simulation_nodes() -> void:
	var group_names: Array[String] = ["creatures", "eggs", "grass"]

	for group_name: String in group_names:
		for simulation_node: Node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(simulation_node):
				simulation_node.queue_free()

func _restore_cleared_dry_ground_tiles(saved_tiles: Array, world_grid: Node) -> void:
	if world_grid.has_method("restore_cleared_dry_ground_tiles"):
		world_grid.call("restore_cleared_dry_ground_tiles", saved_tiles)

func _restore_dry_ground_rain_hits(saved_hits: Array, world_grid: Node) -> void:
	if world_grid.has_method("restore_dry_ground_rain_hit_data"):
		world_grid.call("restore_dry_ground_rain_hit_data", saved_hits)

func _restore_grass(
	saved_grass: Array,
	world_grid: Node,
	container: Node2D
) -> void:
	for grass_variant: Variant in saved_grass:
		if not (grass_variant is Dictionary):
			continue

		var grass_record: Dictionary = grass_variant as Dictionary
		var scene_path: String = String(
			grass_record.get("scene_path", DEFAULT_GRASS_SCENE_PATH)
		)
		var grass_scene: PackedScene = load(scene_path) as PackedScene

		if grass_scene == null:
			continue

		var grass_node: Node2D = grass_scene.instantiate() as Node2D

		if grass_node == null:
			continue

		var stage: int = clampi(int(grass_record.get("stage", 0)), 0, 3)
		var tile: Vector2i = Vector2i(
			int(grass_record.get("tile_x", 0)),
			int(grass_record.get("tile_y", 0))
		)
		var world_position: Vector2 = world_grid.call(
			"grass_tile_to_world_position",
			tile
		)

		grass_node.set("start_stage", stage)
		grass_node.position = container.to_local(world_position)
		container.add_child(grass_node)

		grass_node.set(
			"has_tried_to_spread",
			bool(grass_record.get("has_tried_to_spread", false))
		)

		var growth_timer: Timer = grass_node.get_node_or_null("GrowthTimer") as Timer
		var spread_timer: Timer = grass_node.get_node_or_null("SpreadTimer") as Timer

		if growth_timer != null:
			growth_timer.stop()

		if spread_timer != null:
			spread_timer.stop()

		if stage < 3 and growth_timer != null:
			var growth_left: float = float(
				grass_record.get("growth_time_left", 0.0)
			)

			if growth_left <= 0.0:
				growth_left = float(grass_node.get("growth_time"))

			growth_timer.start(growth_left)
		elif stage == 3 and spread_timer != null:
			var has_spread: bool = bool(
				grass_record.get("has_tried_to_spread", false)
			)

			if not has_spread:
				var spread_left: float = float(
					grass_record.get("spread_time_left", 0.0)
				)

				if spread_left <= 0.0:
					spread_left = float(grass_node.get("spread_delay"))

				spread_timer.start(spread_left)

func _restore_eggs(
	saved_eggs: Array,
	world_grid: Node,
	container: Node2D
) -> void:
	for egg_variant: Variant in saved_eggs:
		if not (egg_variant is Dictionary):
			continue

		var egg_record: Dictionary = egg_variant as Dictionary
		var scene_path: String = String(
			egg_record.get("scene_path", DEFAULT_EGG_SCENE_PATH)
		)
		var egg_scene: PackedScene = load(scene_path) as PackedScene

		if egg_scene == null:
			continue

		var egg_node: Node2D = egg_scene.instantiate() as Node2D

		if egg_node == null:
			continue

		var anchor: Vector2i = Vector2i(
			int(egg_record.get("anchor_x", 0)),
			int(egg_record.get("anchor_y", 0))
		)
		var hatch_species_path: String = String(
			egg_record.get("hatch_species_path", "")
		)
		var hatch_creature_scene_path: String = String(
			egg_record.get("hatch_creature_scene_path", DEFAULT_CREATURE_SCENE_PATH)
		)
		var hatch_creature_scene: PackedScene = load(hatch_creature_scene_path) as PackedScene

		if hatch_creature_scene == null:
			hatch_creature_scene = load(DEFAULT_CREATURE_SCENE_PATH) as PackedScene

		if hatch_creature_scene == null:
			egg_node.queue_free()
			continue

		egg_node.set("species_id", String(egg_record.get("species_id", "stegosaurus")))
		egg_node.set("hatch_creature_scene", hatch_creature_scene)

		if not hatch_species_path.is_empty():
			var hatch_species: CreatureSpeciesData = load(hatch_species_path) as CreatureSpeciesData

			if hatch_species != null:
				egg_node.set("hatch_species_data", hatch_species)
				egg_node.set("species_id", hatch_species.species_id)

				if hatch_species.egg_stage_1_texture != null:
					egg_node.set("stage_1_texture", hatch_species.egg_stage_1_texture)

				if hatch_species.egg_stage_2_texture != null:
					egg_node.set("stage_2_texture", hatch_species.egg_stage_2_texture)

		var stage_1_world_position: Vector2 = world_grid.call(
			"anchor_to_world_position",
			anchor,
			Vector2i(1, 2)
		)
		egg_node.position = container.to_local(stage_1_world_position)
		container.add_child(egg_node)

		var stage_1_timer: Timer = egg_node.get_node_or_null("Stage1Timer") as Timer
		var retry_timer: Timer = egg_node.get_node_or_null("ExpandRetryTimer") as Timer
		var hatch_timer: Timer = egg_node.get_node_or_null("HatchTimer") as Timer

		if stage_1_timer != null:
			stage_1_timer.stop()

		if retry_timer != null:
			retry_timer.stop()

		if hatch_timer != null:
			hatch_timer.stop()

		var stage: int = clampi(int(egg_record.get("stage", 0)), 0, 1)
		egg_node.set("current_stage", stage)

		if egg_node.has_method("apply_current_stage_visual"):
			egg_node.call("apply_current_stage_visual")

		if stage == 0:
			var retry_left: float = float(egg_record.get("retry_time_left", 0.0))

			if retry_left > 0.0 and retry_timer != null:
				retry_timer.start(retry_left)
			elif stage_1_timer != null:
				var stage_1_left: float = float(
					egg_record.get("stage_1_time_left", 0.0)
				)

				if stage_1_left <= 0.0:
					stage_1_left = Egg.STAGE_1_DURATION

				stage_1_timer.start(stage_1_left)
		else:
			var blocker_registered: bool = bool(world_grid.call(
				"register_blocker",
				egg_node,
				anchor,
				Vector2i(2, 2)
			))
			if not blocker_registered:
				push_warning(
					"SaveSystem: skipped a stage-two egg at %s because its blocker could not be restored."
					% [anchor]
				)
				egg_node.queue_free()
				continue
			egg_node.set("is_registered_as_blocker", true)

			var stage_2_world_position: Vector2 = world_grid.call(
				"anchor_to_world_position",
				anchor,
				Vector2i(2, 2)
			)
			egg_node.global_position = stage_2_world_position

			if hatch_timer != null:
				var hatch_left: float = float(
					egg_record.get("hatch_time_left", 0.0)
				)

				if hatch_left <= 0.0:
					hatch_left = Egg.STAGE_2_DURATION

				hatch_timer.start(hatch_left)

func _restore_creatures(
	saved_creatures: Array,
	world_grid: Node,
	container: Node2D
) -> void:
	for creature_variant: Variant in saved_creatures:
		if not (creature_variant is Dictionary):
			continue

		var creature_record: Dictionary = creature_variant as Dictionary
		var scene_path: String = String(
			creature_record.get("scene_path", DEFAULT_CREATURE_SCENE_PATH)
		)
		var species_path: String = String(
			creature_record.get("species_path", "")
		)
		var creature_scene: PackedScene = load(scene_path) as PackedScene
		var species_data: Resource = load(species_path) as Resource

		if creature_scene == null or species_data == null:
			continue

		var creature_node: Node2D = creature_scene.instantiate() as Node2D

		if creature_node == null:
			continue

		var anchor: Vector2i = Vector2i(
			int(creature_record.get("anchor_x", 0)),
			int(creature_record.get("anchor_y", 0))
		)
		var footprint: Vector2i = creature_node.get("footprint_size")
		var world_position: Vector2 = world_grid.call(
			"anchor_to_world_position",
			anchor,
			footprint
		)

		creature_node.set("species_data", species_data)
		creature_node.set("health", float(creature_record.get("health", 1.0)))
		creature_node.set("hunger", float(creature_record.get("hunger", 1.0)))
		creature_node.position = container.to_local(world_position)
		container.add_child(creature_node)

		creature_node.set("age", float(creature_record.get("age", 0.0)))
		creature_node.set(
			"age_tick_elapsed",
			float(creature_record.get("age_tick_elapsed", 0.0))
		)
		creature_node.set(
			"reproduction_cooldown_remaining",
			float(creature_record.get("reproduction_cooldown", 0.0))
		)
		creature_node.set(
			"reproduction_progress",
			clampf(
				float(creature_record.get("reproduction_progress", 0.0)),
				0.0,
				float(species_data.get("reproduction_progress_max"))
			)
		)

func _restore_player_energy(saved_energy: float) -> void:
	var player_energy: Node = get_tree().get_first_node_in_group("player_energy")

	if player_energy == null or not player_energy.has_method("restore_energy"):
		return

	player_energy.call("restore_energy", saved_energy)

func _restore_camera(camera_data: Dictionary) -> void:
	if camera_data.is_empty():
		return

	var camera := _get_game_camera()

	if camera == null:
		return

	camera.global_position = Vector2(
		float(camera_data.get("x", 0.0)),
		float(camera_data.get("y", 0.0))
	)
	camera.zoom = Vector2(
		float(camera_data.get("zoom_x", 1.0)),
		float(camera_data.get("zoom_y", 1.0))
	)

func _get_game_camera() -> Camera2D:
	var camera := get_tree().get_first_node_in_group("game_camera") as Camera2D

	if camera != null:
		return camera

	return get_viewport().get_camera_2d()
