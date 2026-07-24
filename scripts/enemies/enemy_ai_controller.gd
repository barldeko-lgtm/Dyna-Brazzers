extends Node
class_name EnemyAIController

# First strategic-AI foundation. Every turn it takes one lightweight snapshot of
# the enemy population. Eggs already count as their future adult species so
# later production decisions do not order duplicates while eggs are incubating.
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const ENEMY_SPECIES_CATALOG := preload("res://scripts/catalogs/enemy_species_catalog.gd")

@export var turn_interval := 4.0

signal turn_completed(snapshot: Dictionary)

var turn_timer: Timer = null
var turn_index := 0
var latest_snapshot: Dictionary = {}
var last_action_text := "ожидание первого хода"


func _ready() -> void:
	add_to_group("enemy_ai")
	latest_snapshot = _create_empty_snapshot()
	_setup_turn_timer()


func _setup_turn_timer() -> void:
	turn_timer = Timer.new()
	turn_timer.wait_time = maxf(turn_interval, 0.05)
	turn_timer.one_shot = false
	turn_timer.timeout.connect(_on_turn_timer_timeout)
	add_child(turn_timer)
	turn_timer.start()


func _on_turn_timer_timeout() -> void:
	turn_index += 1
	latest_snapshot = collect_population_snapshot()
	latest_snapshot["turn_index"] = turn_index
	perform_turn(latest_snapshot)
	turn_completed.emit(latest_snapshot.duplicate(true))


func collect_population_snapshot() -> Dictionary:
	var adult_by_species := _create_empty_population_counts()
	var egg_by_species := _create_empty_population_counts()
	var planned_population_by_species := _create_empty_population_counts()
	var adult_count := 0
	var egg_count := 0

	for creature_variant: Variant in get_tree().get_nodes_in_group("creatures"):
		var creature := creature_variant as Node

		if not _is_valid_enemy_entity(creature):
			continue

		var species_id := _get_creature_species_id(creature)

		if species_id == StringName():
			continue

		adult_by_species[species_id] = int(adult_by_species.get(species_id, 0)) + 1
		planned_population_by_species[species_id] = int(
			planned_population_by_species.get(species_id, 0)
		) + 1
		adult_count += 1

	for egg_variant: Variant in get_tree().get_nodes_in_group("eggs"):
		var egg := egg_variant as Node

		if not _is_valid_enemy_entity(egg):
			continue

		var species_id := _get_egg_species_id(egg)

		if species_id == StringName():
			continue

		egg_by_species[species_id] = int(egg_by_species.get(species_id, 0)) + 1
		# An incubating egg already occupies one future population slot.
		planned_population_by_species[species_id] = int(
			planned_population_by_species.get(species_id, 0)
		) + 1
		egg_count += 1

	return {
		"turn_index": turn_index,
		"adult_by_species": adult_by_species,
		"egg_by_species": egg_by_species,
		"planned_population_by_species": planned_population_by_species,
		"adult_count": adult_count,
		"egg_count": egg_count,
		"planned_population_count": adult_count + egg_count,
		"action": "observe_population"
	}


func perform_turn(snapshot: Dictionary) -> void:
	# This first vertical slice deliberately does not change gameplay yet. Future
	# steps will compare egg, flag, spell, and wait actions using this snapshot.
	last_action_text = "снимок собран, действие пока не подключено"
	snapshot["action"] = "observe_population"


func get_population_snapshot() -> Dictionary:
	return latest_snapshot.duplicate(true)


func get_last_action_text() -> String:
	return last_action_text


func get_turn_interval() -> float:
	return maxf(turn_interval, 0.05)


func get_time_until_next_turn() -> float:
	if turn_timer == null or turn_timer.is_stopped():
		return get_turn_interval()

	return turn_timer.time_left


func _create_empty_snapshot() -> Dictionary:
	return {
		"turn_index": 0,
		"adult_by_species": _create_empty_population_counts(),
		"egg_by_species": _create_empty_population_counts(),
		"planned_population_by_species": _create_empty_population_counts(),
		"adult_count": 0,
		"egg_count": 0,
		"planned_population_count": 0,
		"action": "waiting"
	}


func _create_empty_population_counts() -> Dictionary:
	var counts: Dictionary = {}

	for species_id: StringName in ENEMY_SPECIES_CATALOG.get_supported_ids():
		counts[species_id] = 0

	return counts


func _is_valid_enemy_entity(entity: Node) -> bool:
	return (
		entity != null
		and is_instance_valid(entity)
		and not entity.is_queued_for_deletion()
		and CREATURE_FACTION.get_id(entity) == CREATURE_FACTION.ENEMY
	)


func _get_creature_species_id(creature: Node) -> StringName:
	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null:
		return StringName()

	return _normalize_supported_species_id(species_data.species_id)


func _get_egg_species_id(egg: Node) -> StringName:
	var hatch_species_data := egg.get("hatch_species_data") as CreatureSpeciesData

	if hatch_species_data != null:
		return _normalize_supported_species_id(hatch_species_data.species_id)

	var raw_species_id: Variant = egg.get("species_id")

	if raw_species_id == null:
		return StringName()

	return _normalize_supported_species_id(raw_species_id)


func _normalize_supported_species_id(species_variant: Variant) -> StringName:
	var species_text := String(species_variant).strip_edges()

	if species_text.is_empty():
		return StringName()

	var species_id := StringName(species_text)
	return species_id if ENEMY_SPECIES_CATALOG.has_species(species_id) else StringName()
