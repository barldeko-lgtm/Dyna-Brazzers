extends Node
class_name EnemyAIController

# Strategic enemy turn. Every four simulation seconds it takes one lightweight
# snapshot. It fills the herbivore cap only while adult herbivores are fed, skips
# the turn when they are hungry below the cap, and produces predators at the cap.
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const ENEMY_SPECIES_CATALOG := preload("res://scripts/catalogs/enemy_species_catalog.gd")

const STEGOSAURUS_ID: StringName = &"stegosaurus"
const TRICERATOPS_ID: StringName = &"triceratops"
const RAPTOR_ID: StringName = &"raptor"
const PTERODACTYL_ID: StringName = &"pterodactyl"
const TYRANNOSAURUS_ID: StringName = &"tyrannosaurus"
const STEGOSAURUS_PER_TRICERATOPS := 3
const PREDATOR_IDS: Array[StringName] = [
	RAPTOR_ID,
	PTERODACTYL_ID,
	TYRANNOSAURUS_ID
]
const BASE_DEFENSE_RAPTOR_TARGET := 2

@export var turn_interval := 4.0
@export var minimum_herbivore_cap := 10
@export var maximum_herbivore_cap := 60
@export_range(0.0, 100.0, 0.1) var minimum_average_herbivore_satiety_percent := 40.0

signal turn_completed(snapshot: Dictionary)

var turn_timer: Timer = null
var turn_index := 0
var elapsed_simulation_seconds := 0.0
var latest_snapshot: Dictionary = {}
var last_action_text := "ожидание первого хода"
var enemy_base: Node = null
var enemy_energy: Node = null
var next_late_predator_id: StringName = TYRANNOSAURUS_ID


func _ready() -> void:
	add_to_group("enemy_ai")
	latest_snapshot = _create_empty_snapshot()
	_refresh_runtime_references()
	_setup_turn_timer()


func _process(delta: float) -> void:
	elapsed_simulation_seconds += maxf(delta, 0.0)


func _setup_turn_timer() -> void:
	turn_timer = Timer.new()
	turn_timer.wait_time = get_turn_interval()
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
	var adult_herbivore_count := 0
	var adult_herbivore_satiety_total_percent := 0.0

	for creature_variant: Variant in get_tree().get_nodes_in_group("creatures"):
		var creature := creature_variant as Node

		if not _is_valid_enemy_creature(creature):
			continue

		var species_id := _get_creature_species_id(creature)

		if species_id == StringName():
			continue

		adult_by_species[species_id] = int(adult_by_species.get(species_id, 0)) + 1
		planned_population_by_species[species_id] = int(
			planned_population_by_species.get(species_id, 0)
		) + 1
		adult_count += 1

		if _is_herbivore_species_id(species_id):
			var satiety_percent := _get_creature_satiety_percent(creature)

			if satiety_percent >= 0.0:
				adult_herbivore_count += 1
				adult_herbivore_satiety_total_percent += satiety_percent

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

	var average_adult_herbivore_satiety_percent := -1.0

	if adult_herbivore_count > 0:
		average_adult_herbivore_satiety_percent = (
			adult_herbivore_satiety_total_percent / float(adult_herbivore_count)
		)

	var snapshot := {
		"turn_index": turn_index,
		"adult_by_species": adult_by_species,
		"egg_by_species": egg_by_species,
		"planned_population_by_species": planned_population_by_species,
		"adult_count": adult_count,
		"egg_count": egg_count,
		"planned_population_count": adult_count + egg_count,
		"adult_herbivore_count": adult_herbivore_count,
		"average_adult_herbivore_satiety_percent": average_adult_herbivore_satiety_percent,
		"minimum_average_herbivore_satiety_percent": get_minimum_average_herbivore_satiety_percent(),
		"herbivore_spawning_blocked_by_hunger": false,
		"enemy_energy_before_action": 0.0,
		"enemy_energy_after_action": 0.0,
		"selected_species_id": StringName(),
		"selected_egg_cost": 0.0,
		"production_phase": "waiting",
		"action": "observe_population"
	}
	_refresh_population_summary_fields(snapshot)
	return snapshot


func perform_turn(snapshot: Dictionary) -> void:
	_refresh_runtime_references()
	_refresh_population_summary_fields(snapshot)

	var energy_before := _get_enemy_energy_value()
	snapshot["enemy_energy_before_action"] = energy_before
	snapshot["enemy_energy_after_action"] = energy_before

	var herbivore_count := int(snapshot.get("planned_herbivore_count", 0))
	var herbivore_cap := int(snapshot.get("herbivore_cap", get_current_herbivore_cap()))
	var herbivore_spawning_blocked := bool(
		snapshot.get("herbivore_spawning_blocked_by_hunger", false)
	)
	var selected_species_id := StringName()
	var production_phase := "waiting"

	if herbivore_count < herbivore_cap:
		if herbivore_spawning_blocked:
			var average_satiety := float(
				snapshot.get("average_adult_herbivore_satiety_percent", -1.0)
			)
			var satiety_threshold := float(
				snapshot.get(
					"minimum_average_herbivore_satiety_percent",
					get_minimum_average_herbivore_satiety_percent()
				)
			)
			snapshot["production_phase"] = "wait_food_pressure"
			snapshot["selected_species_id"] = StringName()
			snapshot["selected_egg_cost"] = 0.0
			snapshot["action"] = "skip_turn_food_pressure"
			last_action_text = "пропуск хода: сытость травоядных %.1f%% ниже %.0f%%" % [
				average_satiety,
				satiety_threshold
			]
			return

		production_phase = "herbivores"
		selected_species_id = choose_next_herbivore_species(snapshot)
	else:
		# At or above the cap predator production ignores herbivore satiety.
		production_phase = "predators"
		selected_species_id = choose_next_predator_species(snapshot)

	snapshot["production_phase"] = production_phase
	snapshot["selected_species_id"] = selected_species_id
	_try_create_selected_egg(snapshot, selected_species_id, production_phase)


func choose_next_herbivore_species(snapshot: Dictionary) -> StringName:
	var planned_counts := _read_population_counts(snapshot)
	var stegosaurus_count := int(planned_counts.get(STEGOSAURUS_ID, 0))
	var triceratops_count := int(planned_counts.get(TRICERATOPS_ID, 0))

	# Build three stegosauruses before each triceratops. Because projected counts
	# include eggs, the AI does not order duplicates while those eggs incubate.
	if stegosaurus_count >= (triceratops_count + 1) * STEGOSAURUS_PER_TRICERATOPS:
		return TRICERATOPS_ID

	return STEGOSAURUS_ID


func choose_next_predator_species(snapshot: Dictionary) -> StringName:
	var planned_counts := _read_population_counts(snapshot)
	var raptor_count := int(planned_counts.get(RAPTOR_ID, 0))
	var tyrannosaurus_count := int(planned_counts.get(TYRANNOSAURUS_ID, 0))
	var pterodactyl_count := int(planned_counts.get(PTERODACTYL_ID, 0))

	# First establish a cheap two-raptor defense around the enemy base. Eggs count
	# immediately, so the AI does not queue duplicate defenders while they hatch.
	if raptor_count < BASE_DEFENSE_RAPTOR_TARGET:
		return RAPTOR_ID

	# After the defense pair, establish one heavy ground predator and one flying
	# predator before entering the long-term alternating production cycle.
	if tyrannosaurus_count < 1:
		return TYRANNOSAURUS_ID

	if pterodactyl_count < 1:
		return PTERODACTYL_ID

	return next_late_predator_id


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


func get_elapsed_simulation_seconds() -> float:
	return maxf(elapsed_simulation_seconds, 0.0)


func get_current_herbivore_cap() -> int:
	var safe_minimum := maxi(minimum_herbivore_cap, 0)
	var safe_maximum := maxi(maximum_herbivore_cap, safe_minimum)
	var elapsed_full_minutes := int(floor(get_elapsed_simulation_seconds() / 60.0))
	return clampi(elapsed_full_minutes, safe_minimum, safe_maximum)


func get_minimum_average_herbivore_satiety_percent() -> float:
	return clampf(minimum_average_herbivore_satiety_percent, 0.0, 100.0)


func get_save_data() -> Dictionary:
	var time_left := get_turn_interval()

	if turn_timer != null and not turn_timer.is_stopped():
		time_left = turn_timer.time_left

	return {
		"elapsed_simulation_seconds": get_elapsed_simulation_seconds(),
		"turn_index": turn_index,
		"timer_time_left": time_left,
		"next_late_predator_id": String(next_late_predator_id)
	}


func restore_save_data(saved_data: Dictionary) -> void:
	elapsed_simulation_seconds = maxf(
		float(saved_data.get("elapsed_simulation_seconds", 0.0)),
		0.0
	)
	turn_index = maxi(int(saved_data.get("turn_index", 0)), 0)
	var restored_next_predator := StringName(
		String(saved_data.get("next_late_predator_id", String(TYRANNOSAURUS_ID)))
	)
	next_late_predator_id = (
		restored_next_predator
		if restored_next_predator == TYRANNOSAURUS_ID or restored_next_predator == PTERODACTYL_ID
		else TYRANNOSAURUS_ID
	)
	latest_snapshot = collect_population_snapshot()
	latest_snapshot["turn_index"] = turn_index
	latest_snapshot["action"] = "restored_waiting"
	last_action_text = "состояние восстановлено, ожидание следующего хода"

	if turn_timer == null:
		return

	var saved_time_left := float(
		saved_data.get("timer_time_left", get_turn_interval())
	)
	turn_timer.start(clampf(saved_time_left, 0.05, get_turn_interval()))


func _try_create_selected_egg(
	snapshot: Dictionary,
	selected_species_id: StringName,
	production_phase: String
) -> void:
	var catalog_entry := ENEMY_SPECIES_CATALOG.get_entry(selected_species_id)
	var species_data := catalog_entry.get("species_data") as CreatureSpeciesData
	var egg_cost := maxf(float(catalog_entry.get("egg_purchase_cost", 0.0)), 0.0)
	snapshot["selected_egg_cost"] = egg_cost

	if species_data == null:
		last_action_text = "ожидание: данные выбранного вида не найдены"
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

	var energy_before := float(snapshot.get("enemy_energy_before_action", 0.0))

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
	if production_phase == "predators":
		_advance_predator_rotation_after_success(selected_species_id)
	snapshot["enemy_energy_after_action"] = _get_enemy_energy_value()
	snapshot["action"] = (
		"create_herbivore_egg"
		if production_phase == "herbivores"
		else "create_predator_egg"
	)
	last_action_text = "создано яйцо: %s (-%d энки)" % [
		species_data.species_name,
		roundi(egg_cost)
	]


func _advance_predator_rotation_after_success(created_species_id: StringName) -> void:
	if created_species_id == TYRANNOSAURUS_ID:
		next_late_predator_id = PTERODACTYL_ID
	elif created_species_id == PTERODACTYL_ID:
		next_late_predator_id = TYRANNOSAURUS_ID


func _create_empty_snapshot() -> Dictionary:
	var snapshot := {
		"turn_index": 0,
		"adult_by_species": _create_empty_population_counts(),
		"egg_by_species": _create_empty_population_counts(),
		"planned_population_by_species": _create_empty_population_counts(),
		"adult_count": 0,
		"egg_count": 0,
		"planned_population_count": 0,
		"adult_herbivore_count": 0,
		"average_adult_herbivore_satiety_percent": -1.0,
		"minimum_average_herbivore_satiety_percent": get_minimum_average_herbivore_satiety_percent(),
		"herbivore_spawning_blocked_by_hunger": false,
		"enemy_energy_before_action": 0.0,
		"enemy_energy_after_action": 0.0,
		"selected_species_id": StringName(),
		"selected_egg_cost": 0.0,
		"production_phase": "waiting",
		"action": "waiting"
	}
	_refresh_population_summary_fields(snapshot)
	return snapshot


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
	_refresh_population_summary_fields(snapshot)


func _refresh_population_summary_fields(snapshot: Dictionary) -> void:
	var planned_counts := _read_population_counts(snapshot)
	var herbivore_count := (
		int(planned_counts.get(STEGOSAURUS_ID, 0))
		+ int(planned_counts.get(TRICERATOPS_ID, 0))
	)
	var predator_count := 0

	for species_id: StringName in PREDATOR_IDS:
		predator_count += int(planned_counts.get(species_id, 0))

	var adult_herbivore_count := int(snapshot.get("adult_herbivore_count", 0))
	var average_satiety := float(
		snapshot.get("average_adult_herbivore_satiety_percent", -1.0)
	)
	var satiety_threshold := get_minimum_average_herbivore_satiety_percent()
	var spawning_blocked_by_hunger := (
		adult_herbivore_count > 0
		and average_satiety >= 0.0
		and average_satiety < satiety_threshold
	)

	snapshot["elapsed_simulation_seconds"] = get_elapsed_simulation_seconds()
	snapshot["elapsed_full_minutes"] = int(floor(get_elapsed_simulation_seconds() / 60.0))
	snapshot["herbivore_cap"] = get_current_herbivore_cap()
	snapshot["planned_herbivore_count"] = herbivore_count
	snapshot["planned_predator_count"] = predator_count
	snapshot["minimum_average_herbivore_satiety_percent"] = satiety_threshold
	snapshot["herbivore_spawning_blocked_by_hunger"] = spawning_blocked_by_hunger


func _read_population_counts(snapshot: Dictionary) -> Dictionary:
	var planned_counts_variant: Variant = snapshot.get("planned_population_by_species", {})
	return planned_counts_variant if planned_counts_variant is Dictionary else {}


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


func _is_valid_enemy_creature(creature: Node) -> bool:
	if not _is_valid_enemy_entity(creature):
		return false

	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null:
		return false

	var species_id := _normalize_supported_species_id(species_data.species_id)

	if species_id == StringName():
		return false

	# The faction tag is the ownership source of truth. Matching the enemy catalog
	# as a second guard prevents a wrongly tagged player resource from entering the
	# enemy population or adult-herbivore satiety average.
	return ENEMY_SPECIES_CATALOG.get_species_data(species_id) == species_data


func _is_herbivore_species_id(species_id: StringName) -> bool:
	return species_id == STEGOSAURUS_ID or species_id == TRICERATOPS_ID


func _get_creature_satiety_percent(creature: Node) -> float:
	if creature == null or not is_instance_valid(creature):
		return -1.0

	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null or not species_data.is_herbivore():
		return -1.0

	var raw_hunger: Variant = creature.get("hunger")

	if raw_hunger == null:
		return -1.0

	var maximum_hunger := maxf(float(species_data.max_hunger), 0.001)
	return clampf(float(raw_hunger) / maximum_hunger * 100.0, 0.0, 100.0)


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
