extends Node
class_name EnemyAIController

# Strategic enemy turn. Every four simulation seconds it takes one lightweight
# snapshot, then uses the projected population (adults + incubating eggs) to
# choose and buy the next herbivore egg.
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const ENEMY_SPECIES_CATALOG := preload("res://scripts/catalogs/enemy_species_catalog.gd")

const STEGOSAURUS_ID: StringName = &"stegosaurus"
const TRICERATOPS_ID: StringName = &"triceratops"
const STEGOSAURUS_PER_TRICERATOPS := 3

@export var turn_interval := 4.0

signal turn_completed(snapshot: Dictionary)

var turn_timer: Timer = null
var turn_index := 0
var latest_snapshot: Dictionary = {}
var last_action_text := "ожидание первого хода"
var enemy_base: Node = null
var enemy_energy: Node = null


func _ready() -> void:
	add_to_group("enemy_ai")
	latest_snapshot = _create_empty_snapshot()
	_refresh_runtime_references()
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
		"enemy_energy_before_action": 0.0,
		"enemy_energy_after_action": 0.0,
		"selected_species_id": StringName(),
		"selected_egg_cost": 0.0,
		"action": "observe_population"
	}


func perform_turn(snapshot: Dictionary) -> void:
	_refresh_runtime_references()

	var energy_before := _get_enemy_energy_value()
	snapshot["enemy_energy_before_action"] = energy_before
	snapshot["enemy_energy_after_action"] = energy_before

	var selected_species_id := choose_next_herbivore_species(snapshot)
	snapshot["selected_species_id"] = selected_species_id

	var catalog_entry := ENEMY_SPECIES_CATALOG.get_entry(selected_species_id)
	var species_data := catalog_entry.get("species_data") as CreatureSpeciesData
	var egg_cost := maxf(float(catalog_entry.get("egg_purchase_cost", 0.0)), 0.0)
	snapshot["selected_egg_cost"] = egg_cost

	if species_data == null:
		last_action_text = "ожидание: данные выбранного травоядного не найдены"
		snapshot["action"] = "wait_missing_species"
		return

	if enemy_base == null or not enemy_base.has_method("create_enemy_egg"):
		last_action_text = "ожидание: база противника не найдена"
		snapshot["action"] = "wait_missing_base"
		return

	if (
		enemy_energy == null
		or not enemy_energy.has_method("can_spend")
		or not enemy_energy.has_method("spend")
	):
		last_action_text = "ожидание: хранилище энки противника не найдено"
		snapshot["action"] = "wait_missing_energy"
		return

	if not bool(enemy_energy.call("can_spend", egg_cost)):
		last_action_text = "копит на яйцо: %s (%d/%d энки)" % [
			species_data.species_name,
			roundi(energy_before),
			roundi(egg_cost)
		]
		snapshot["action"] = "wait_energy"
		return

	var created_egg := enemy_base.call("create_enemy_egg", species_data) as Node2D

	if created_egg == null:
		last_action_text = "ожидание: возле базы нет места для яйца %s" % species_data.species_name
		snapshot["action"] = "wait_egg_space"
		return

	if not bool(enemy_energy.call("spend", egg_cost)):
		created_egg.queue_free()
		last_action_text = "ожидание: энку не удалось списать"
		snapshot["action"] = "wait_spend_failed"
		return

	_record_created_egg_in_snapshot(snapshot, selected_species_id)
	snapshot["enemy_energy_after_action"] = _get_enemy_energy_value()
	snapshot["action"] = "create_herbivore_egg"
	last_action_text = "создано яйцо: %s (-%d энки)" % [
		species_data.species_name,
		roundi(egg_cost)
	]


func choose_next_herbivore_species(snapshot: Dictionary) -> StringName:
	var planned_counts_variant: Variant = snapshot.get("planned_population_by_species", {})
	var planned_counts: Dictionary = (
		planned_counts_variant if planned_counts_variant is Dictionary else {}
	)
	var stegosaurus_count := int(planned_counts.get(STEGOSAURUS_ID, 0))
	var triceratops_count := int(planned_counts.get(TRICERATOPS_ID, 0))

	# Build three stegosauruses before each triceratops. Because projected counts
	# include eggs, the AI does not order duplicates while those eggs incubate.
	if stegosaurus_count >= (triceratops_count + 1) * STEGOSAURUS_PER_TRICERATOPS:
		return TRICERATOPS_ID

	return STEGOSAURUS_ID


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


func get_enemy_energy_value() -> float:
	_refresh_runtime_references()
	return _get_enemy_energy_value()


func _create_empty_snapshot() -> Dictionary:
	return {
		"turn_index": 0,
		"adult_by_species": _create_empty_population_counts(),
		"egg_by_species": _create_empty_population_counts(),
		"planned_population_by_species": _create_empty_population_counts(),
		"adult_count": 0,
		"egg_count": 0,
		"planned_population_count": 0,
		"enemy_energy_before_action": 0.0,
		"enemy_energy_after_action": 0.0,
		"selected_species_id": StringName(),
		"selected_egg_cost": 0.0,
		"action": "waiting"
	}


func _create_empty_population_counts() -> Dictionary:
	var counts: Dictionary = {}

	for species_id: StringName in ENEMY_SPECIES_CATALOG.get_supported_ids():
		counts[species_id] = 0

	return counts


func _record_created_egg_in_snapshot(snapshot: Dictionary, species_id: StringName) -> void:
	var egg_counts_variant: Variant = snapshot.get("egg_by_species", {})
	var planned_counts_variant: Variant = snapshot.get("planned_population_by_species", {})
	var egg_counts: Dictionary = egg_counts_variant if egg_counts_variant is Dictionary else {}
	var planned_counts: Dictionary = (
		planned_counts_variant if planned_counts_variant is Dictionary else {}
	)

	egg_counts[species_id] = int(egg_counts.get(species_id, 0)) + 1
	planned_counts[species_id] = int(planned_counts.get(species_id, 0)) + 1
	snapshot["egg_by_species"] = egg_counts
	snapshot["planned_population_by_species"] = planned_counts
	snapshot["egg_count"] = int(snapshot.get("egg_count", 0)) + 1
	snapshot["planned_population_count"] = int(
		snapshot.get("planned_population_count", 0)
	) + 1


func _refresh_runtime_references() -> void:
	if enemy_base == null or not is_instance_valid(enemy_base):
		enemy_base = get_tree().get_first_node_in_group("enemy_base")

	if enemy_energy == null or not is_instance_valid(enemy_energy):
		enemy_energy = get_tree().get_first_node_in_group("enemy_energy")


func _get_enemy_energy_value() -> float:
	if enemy_energy != null and enemy_energy.has_method("get_energy"):
		return maxf(float(enemy_energy.call("get_energy")), 0.0)

	return 0.0


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
