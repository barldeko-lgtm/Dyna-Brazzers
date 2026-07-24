extends Node

# Static enemy attack objectives. Tyrannosauruses, pterodactyls and egg eaters
# use the same indirect-order plumbing as player flags, but the targets are not
# player-editable and are rebuilt at the player base whenever a session starts.
const ENEMY_FLAG_VISUAL_SCRIPT := preload("res://scripts/flags/enemy_flag_visual.gd")
const ENEMY_FLAG_ASSIGNMENT_SERVICE := preload("res://scripts/flags/enemy_flag_assignment_service.gd")

const TYRANNOSAURUS_ID: StringName = &"tyrannosaurus"
const PTERODACTYL_ID: StringName = &"pterodactyl"
const EGG_EATER_ID: StringName = &"egg_eater"
const TARGET_SPECIES_IDS: Array[StringName] = [
	TYRANNOSAURUS_ID,
	PTERODACTYL_ID,
	EGG_EATER_ID
]
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)
const BEHAVIOUR_UPDATE_INTERVAL := 0.5
const INITIALIZATION_RETRY_FRAMES := 12

var flags: Dictionary = {}
var flag_revisions: Dictionary = {}
var world_grid: Node = null
var flag_visual: Node2D = null
var assignment_service: RefCounted = null
var behaviour_update_timer := 0.0
var initialized := false


func _ready() -> void:
	add_to_group("enemy_flag_system")
	world_grid = get_parent()
	assignment_service = ENEMY_FLAG_ASSIGNMENT_SERVICE.new(self)
	call_deferred("_initialize_at_player_base")


func _physics_process(delta: float) -> void:
	if not initialized or assignment_service == null:
		return

	behaviour_update_timer -= delta

	if behaviour_update_timer > 0.0:
		return

	behaviour_update_timer = BEHAVIOUR_UPDATE_INTERVAL
	assignment_service.call("update")


func _exit_tree() -> void:
	if assignment_service != null:
		assignment_service.call("clear_runtime", true)


func _initialize_at_player_base() -> void:
	for _attempt in range(INITIALIZATION_RETRY_FRAMES):
		if world_grid == null or not is_instance_valid(world_grid):
			world_grid = get_tree().get_first_node_in_group("world_grid")

		var player_base := _find_player_base()

		if world_grid != null and player_base != null:
			var flag_tile := _get_player_base_flag_tile(player_base)

			if flag_tile != INVALID_ANCHOR:
				for species_id: StringName in TARGET_SPECIES_IDS:
					flags[species_id] = flag_tile
					flag_revisions[species_id] = 1

				_ensure_flag_visual()
				_sync_flag_visual()
				initialized = true
				behaviour_update_timer = 0.0
				return

		await get_tree().process_frame

	push_warning("EnemyAttackFlags: player base or world grid was not found.")


func _find_player_base() -> Node:
	if world_grid != null and is_instance_valid(world_grid):
		var local_player_base := world_grid.get_node_or_null("PlayerBase")

		if local_player_base != null:
			return local_player_base

	return get_tree().get_first_node_in_group("player_base")


func _get_player_base_flag_tile(player_base: Node) -> Vector2i:
	var anchor_variant: Variant = player_base.get("anchor_tile")
	var footprint_variant: Variant = player_base.get("footprint_size")

	if not (anchor_variant is Vector2i):
		return INVALID_ANCHOR

	var anchor: Vector2i = anchor_variant
	var footprint := Vector2i(2, 2)

	if footprint_variant is Vector2i:
		footprint = footprint_variant

	# A 2x2 base has no single center tile. Use its lower-right center cell; the
	# shared 11x11 objective area remains visually and mechanically centered on it.
	return anchor + Vector2i(
		maxi(floori(float(footprint.x) / 2.0), 0),
		maxi(floori(float(footprint.y) / 2.0), 0)
	)


func _ensure_flag_visual() -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		return

	if flag_visual != null and is_instance_valid(flag_visual):
		return

	var existing_visual := world_grid.get_node_or_null("EnemyFlagVisual") as Node2D

	if existing_visual != null:
		flag_visual = existing_visual
	else:
		flag_visual = ENEMY_FLAG_VISUAL_SCRIPT.new() as Node2D
		flag_visual.name = "EnemyFlagVisual"
		world_grid.add_child(flag_visual)

	if flag_visual != null and flag_visual.has_method("configure"):
		flag_visual.call("configure", world_grid)


func _sync_flag_visual() -> void:
	if flag_visual != null and is_instance_valid(flag_visual) and flag_visual.has_method("set_flags"):
		flag_visual.call("set_flags", flags)


func get_flag_count() -> int:
	return flags.size()


func has_flag(species_id: StringName) -> bool:
	return flags.has(species_id)


func get_flag_tile(species_id: StringName) -> Vector2i:
	var tile_variant: Variant = flags.get(species_id, INVALID_ANCHOR)
	return tile_variant if tile_variant is Vector2i else INVALID_ANCHOR


func get_flag_revision(species_id: StringName) -> int:
	return maxi(int(flag_revisions.get(species_id, 1)), 1)


func get_world_grid() -> Node:
	return world_grid


func get_creature_flag_debug_data(creature: Node) -> Dictionary:
	if assignment_service == null:
		return {"status": "вражеские флаги не готовы", "committed": false, "target_retry": 0}

	return assignment_service.call("get_debug_data", creature) as Dictionary
