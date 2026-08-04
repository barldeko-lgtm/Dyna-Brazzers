extends Node
class_name EnemyLightningSpell

# Target selection and execution for enemy lightning. Strategic cadence,
# spell priority and combat-reserve ownership remain in EnemySpellController.
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")

const PLAYER_TYRANNOSAURUS_ID := &"tyrannosaurus"
const PLAYER_EGG_EATER_ID := &"egg_eater"
const ENEMY_RAPTOR_ID := &"raptor"
const LIGHTNING_MODE_EGG_EATER := &"egg_eater"
const LIGHTNING_MODE_TYRANNOSAURUS := &"tyrannosaurus"

var controller = null
var lightning_sequence_active := false
var last_lightning_action_text := "ожидание подходящей цели"
var last_lightning_target_species := &""
var last_lightning_target_health := 0.0
var last_lightning_target_base_distance := -1.0
var last_lightning_nearby_raptor_count := 0


func setup(owner_controller: Node) -> void:
	controller = owner_controller


func is_sequence_active() -> bool:
	return lightning_sequence_active


func try_cast_at_egg_eater() -> bool:
	if controller == null or not is_instance_valid(controller):
		return false
	return _try_cast_priority_lightning(LIGHTNING_MODE_EGG_EATER)


func try_cast_at_tyrannosaurus() -> bool:
	if controller == null or not is_instance_valid(controller):
		return false
	return _try_cast_priority_lightning(LIGHTNING_MODE_TYRANNOSAURUS)


func get_debug_data() -> Dictionary:
	return {
		"lightning_action_text": last_lightning_action_text,
		"lightning_sequence_active": lightning_sequence_active,
		"lightning_target_species": String(last_lightning_target_species),
		"lightning_target_health": last_lightning_target_health,
		"lightning_target_base_distance": last_lightning_target_base_distance,
		"lightning_nearby_raptor_count": last_lightning_nearby_raptor_count,
		"lightning_energy_cost": _get_lightning_cost()
	}


func _try_cast_priority_lightning(target_mode: StringName) -> bool:
	controller.refresh_runtime_references()
	_reset_last_lightning_debug()

	if controller.world_grid == null or controller.nature_effects == null or controller.enemy_base == null:
		last_lightning_action_text = "отложена: база или мировая система эффектов не найдена"
		return false
	if (
		not controller.nature_effects.has_method("can_apply_lightning")
		or not controller.nature_effects.has_method("apply_lightning")
	):
		last_lightning_action_text = "отложена: общий эффект молнии недоступен"
		return false
	if controller.get_combat_reserve() + 0.001 < _get_lightning_cost():
		last_lightning_action_text = "ожидание: в резерве меньше 1000 энки"
		return false

	var scan := _collect_lightning_scan_data()
	var egg_eater_threats: Array = scan.get("egg_eater_threats", []) as Array
	var enemy_raptors: Array = scan.get("enemy_raptors", []) as Array

	if target_mode == LIGHTNING_MODE_EGG_EATER:
		if egg_eater_threats.is_empty():
			last_lightning_action_text = "яйцеед для молнии возле базы не найден"
			return false

		var egg_plan := _choose_egg_eater_lightning_plan(egg_eater_threats)

		if egg_plan.is_empty():
			var nearest_threat: Dictionary = egg_eater_threats[0]
			var needed_strikes := _get_required_egg_eater_lightning_strikes(
				float(nearest_threat.get("health", 0.0))
			)
			_set_last_lightning_target_debug(nearest_threat, 0)

			if needed_strikes <= 0:
				last_lightning_action_text = (
					"яйцеед слишком здоров для гарантированного убийства "
					+ "двумя ударами"
				)
			else:
				var needed_cost := _get_lightning_cost() * float(needed_strikes)
				last_lightning_action_text = (
					"ожидание резерва для яйцееда: нужно %d, есть %d"
					% [roundi(needed_cost), roundi(controller.get_combat_reserve())]
				)
			return false

		return _execute_lightning_plan(egg_plan)

	if target_mode != LIGHTNING_MODE_TYRANNOSAURUS:
		last_lightning_action_text = "ожидание подходящей цели"
		return false

	# Preserve the existing reserve hold against opportunistic tyrannosaurus
	# lightning while an unprotected egg eater is threatening the base.
	if not egg_eater_threats.is_empty():
		var nearest_threat: Dictionary = egg_eater_threats[0]
		_set_last_lightning_target_debug(nearest_threat, 0)
		last_lightning_action_text = "тирекс пропущен: приоритет у яйцееда возле базы"
		return false

	var tyrannosaurus_plan := _choose_tyrannosaurus_lightning_plan(
		scan.get("tyrannosaurus_candidates", []) as Array,
		enemy_raptors
	)

	if tyrannosaurus_plan.is_empty():
		last_lightning_action_text = "ожидание подходящего тирекса или яйцееда"
		return false

	return _execute_lightning_plan(tyrannosaurus_plan)


func _collect_lightning_scan_data() -> Dictionary:
	var enemy_raptors: Array = []
	var egg_eater_threats: Array = []
	var tyrannosaurus_candidates: Array = []
	var base_anchor := _get_creature_or_base_anchor(controller.enemy_base)

	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		if not _is_living_creature(creature):
			continue

		var species_data := creature.get("species_data") as CreatureSpeciesData

		if species_data == null:
			continue

		var species_id := StringName(species_data.species_id)
		var faction_id := CREATURE_FACTION.get_id(creature)
		var creature_anchor := _get_creature_or_base_anchor(creature)

		if faction_id == CREATURE_FACTION.ENEMY and species_id == ENEMY_RAPTOR_ID:
			enemy_raptors.append(creature)
			continue
		if faction_id != CREATURE_FACTION.PLAYER:
			continue

		var health := maxf(float(creature.get("health")), 0.0)
		var base_distance := _tile_distance(base_anchor, creature_anchor)
		var candidate := {
			"target": creature,
			"health": health,
			"base_distance": base_distance,
			"anchor": creature_anchor,
			"species_id": species_id
		}

		if (
			species_id == PLAYER_EGG_EATER_ID
			and base_distance <= maxf(controller.egg_eater_base_radius_tiles, 0.0)
		):
			egg_eater_threats.append(candidate)
		elif (
			species_id == PLAYER_TYRANNOSAURUS_ID
			and health <= maxf(controller.lightning_damage_threshold, 0.0)
			and base_distance <= maxf(controller.tyrannosaurus_base_radius_tiles, 0.0)
		):
			tyrannosaurus_candidates.append(candidate)

	egg_eater_threats.sort_custom(_sort_lightning_threat_by_distance)

	return {
		"enemy_raptors": enemy_raptors,
		"egg_eater_threats": egg_eater_threats if enemy_raptors.is_empty() else [],
		"tyrannosaurus_candidates": tyrannosaurus_candidates
	}


func _sort_lightning_threat_by_distance(a: Dictionary, b: Dictionary) -> bool:
	var distance_a := float(a.get("base_distance", INF))
	var distance_b := float(b.get("base_distance", INF))

	if not is_equal_approx(distance_a, distance_b):
		return distance_a < distance_b

	return float(a.get("health", INF)) < float(b.get("health", INF))


func _sort_tyrannosaurus_lightning_plan(a: Dictionary, b: Dictionary) -> bool:
	var health_a := float(a.get("health", INF))
	var health_b := float(b.get("health", INF))

	if not is_equal_approx(health_a, health_b):
		return health_a < health_b

	return float(a.get("base_distance", INF)) < float(b.get("base_distance", INF))


func _choose_egg_eater_lightning_plan(threats: Array) -> Dictionary:
	for threat: Dictionary in threats:
		var health := float(threat.get("health", 0.0))
		var strike_count := _get_required_egg_eater_lightning_strikes(health)

		if strike_count <= 0:
			continue

		var total_cost := _get_lightning_cost() * float(strike_count)

		if not controller.can_spend_combat_reserve(total_cost):
			continue

		var plan := threat.duplicate(true)
		plan["strike_count"] = strike_count
		plan["total_cost"] = total_cost
		plan["nearby_raptor_count"] = 0
		return plan

	return {}


func _choose_tyrannosaurus_lightning_plan(
	candidates: Array,
	enemy_raptors: Array
) -> Dictionary:
	if not controller.can_spend_combat_reserve(_get_lightning_cost()):
		return {}

	var valid_candidates: Array = []

	for candidate: Dictionary in candidates:
		var target_anchor: Vector2i = candidate.get("anchor", Vector2i.ZERO)
		var nearby_raptors := _count_raptors_within_radius(
			enemy_raptors,
			target_anchor,
			maxf(controller.tyrannosaurus_raptor_guard_radius_tiles, 0.0)
		)

		if nearby_raptors > 0:
			continue

		var plan := candidate.duplicate(true)
		plan["strike_count"] = 1
		plan["total_cost"] = _get_lightning_cost()
		plan["nearby_raptor_count"] = nearby_raptors
		valid_candidates.append(plan)

	if valid_candidates.is_empty():
		return {}

	valid_candidates.sort_custom(_sort_tyrannosaurus_lightning_plan)
	return valid_candidates[0]


func _execute_lightning_plan(plan: Dictionary) -> bool:
	var target := plan.get("target", null) as Node
	var strike_count := maxi(int(plan.get("strike_count", 1)), 1)

	if not _is_valid_lightning_target(target):
		last_lightning_action_text = "отложена: выбранная цель исчезла"
		return false

	var total_cost := _get_lightning_cost() * float(strike_count)

	if not controller.can_spend_combat_reserve(total_cost):
		last_lightning_action_text = "отложена: резерв изменился до удара"
		return false

	lightning_sequence_active = strike_count > 1

	if not bool(controller.nature_effects.call("can_apply_lightning", target)):
		lightning_sequence_active = false
		last_lightning_action_text = "отложена: цель больше нельзя поразить"
		return false
	if not bool(controller.nature_effects.call("apply_lightning", target)):
		lightning_sequence_active = false
		last_lightning_action_text = "не сработала: первый удар не применён"
		return false
	if not controller.spend_combat_reserve_after_success(_get_lightning_cost()):
		lightning_sequence_active = false
		last_lightning_action_text = "ошибка: первый удар прошёл без списания резерва"
		return false

	_set_last_lightning_target_debug(
		plan,
		int(plan.get("nearby_raptor_count", 0))
	)
	PerformanceStats.add_counter("enemy_lightning_strikes")

	if strike_count <= 1:
		last_lightning_action_text = "удар по %s: %.0f HP, дистанция %.1f" % [
			_format_lightning_species(StringName(plan.get("species_id", &""))),
			float(plan.get("health", 0.0)),
			float(plan.get("base_distance", 0.0))
		]
		return true

	last_lightning_action_text = "яйцеед: первый удар, второй через %.1f сек" % maxf(
		controller.lightning_double_strike_delay_seconds,
		0.0
	)
	var health_after_first_strike := maxf(float(target.get("health")), 0.0)
	_run_second_lightning_strike(target, health_after_first_strike)
	return true


func _run_second_lightning_strike(
	target: Node,
	health_after_first_strike: float
) -> void:
	var delay := maxf(controller.lightning_double_strike_delay_seconds, 0.0)

	if delay > 0.0:
		await get_tree().create_timer(delay, false, false, false).timeout

	if not _is_valid_lightning_target(target):
		lightning_sequence_active = false
		last_lightning_action_text = "яйцеед уничтожен до второго удара; лишняя энка не списана"
		return

	# The two-strike plan was approved only because it could kill the target. Keep
	# passive regeneration during the deliberate delay from invalidating that
	# promise, while preserving any extra damage received from other sources.
	var current_health := maxf(float(target.get("health")), 0.0)
	var preserved_health := minf(
		current_health,
		maxf(health_after_first_strike, 0.0)
	)
	if preserved_health + 0.001 < current_health:
		target.set("health", preserved_health)

	if not controller.can_spend_combat_reserve(_get_lightning_cost()):
		lightning_sequence_active = false
		last_lightning_action_text = "второй удар отменён: резерв неожиданно изменился"
		return
	if not bool(controller.nature_effects.call("can_apply_lightning", target)):
		lightning_sequence_active = false
		last_lightning_action_text = "второй удар отменён: цель недоступна"
		return
	if not bool(controller.nature_effects.call("apply_lightning", target)):
		lightning_sequence_active = false
		last_lightning_action_text = "второй удар не применился; энка не списана"
		return
	if not controller.spend_combat_reserve_after_success(_get_lightning_cost()):
		lightning_sequence_active = false
		last_lightning_action_text = "ошибка списания после второго удара"
		return

	PerformanceStats.add_counter("enemy_lightning_strikes")
	PerformanceStats.add_counter("enemy_double_lightning_sequences")
	lightning_sequence_active = false
	last_lightning_action_text = "двойная молния по яйцееду завершена"


func _count_raptors_within_radius(
	raptors: Array,
	target_anchor: Vector2i,
	radius_tiles: float
) -> int:
	var count := 0

	for raptor: Node in raptors:
		if not _is_living_creature(raptor):
			continue
		if (
			_tile_distance(_get_creature_or_base_anchor(raptor), target_anchor)
			<= radius_tiles
		):
			count += 1

	return count


func _is_living_creature(creature: Node) -> bool:
	return (
		creature != null
		and is_instance_valid(creature)
		and not creature.is_queued_for_deletion()
		and int(creature.get("state")) != Creature.State.DEAD
		and float(creature.get("health")) > 0.0
	)


func _is_valid_lightning_target(target: Node) -> bool:
	return (
		_is_living_creature(target)
		and CREATURE_FACTION.get_id(target) == CREATURE_FACTION.PLAYER
	)


func _get_creature_or_base_anchor(node: Node) -> Vector2i:
	if node == null or not is_instance_valid(node):
		return Vector2i.ZERO
	if node.has_method("get_navigation_anchor"):
		var navigation_anchor: Variant = node.call("get_navigation_anchor")
		if navigation_anchor is Vector2i:
			return navigation_anchor

	var raw_anchor: Variant = node.get("anchor_tile")
	return raw_anchor if raw_anchor is Vector2i else Vector2i.ZERO


func _tile_distance(from_tile: Vector2i, to_tile: Vector2i) -> float:
	return Vector2(from_tile).distance_to(Vector2(to_tile))


func _get_required_egg_eater_lightning_strikes(health: float) -> int:
	var safe_health := maxf(health, 0.0)
	var one_strike_damage := maxf(controller.lightning_damage_threshold, 0.0)

	if safe_health <= 0.0 or one_strike_damage <= 0.0:
		return 0
	if safe_health <= one_strike_damage + 0.001:
		return 1
	if safe_health <= one_strike_damage * 2.0 + 0.001:
		return 2
	return 0


func _get_lightning_cost() -> float:
	return maxf(controller.lightning_energy_cost, 0.0)


func _reset_last_lightning_debug() -> void:
	last_lightning_target_species = &""
	last_lightning_target_health = 0.0
	last_lightning_target_base_distance = -1.0
	last_lightning_nearby_raptor_count = 0


func _set_last_lightning_target_debug(plan: Dictionary, nearby_raptors: int) -> void:
	last_lightning_target_species = StringName(plan.get("species_id", &""))
	last_lightning_target_health = float(plan.get("health", 0.0))
	last_lightning_target_base_distance = float(plan.get("base_distance", -1.0))
	last_lightning_nearby_raptor_count = maxi(nearby_raptors, 0)


func _format_lightning_species(species_id: StringName) -> String:
	if species_id == PLAYER_EGG_EATER_ID:
		return "яйцееду"
	if species_id == PLAYER_TYRANNOSAURUS_ID:
		return "тирексу"
	return "цели"
