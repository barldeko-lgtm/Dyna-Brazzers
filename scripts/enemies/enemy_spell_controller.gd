extends Node2D
class_name EnemySpellController

# Enemy spell decisions stay separate from population production. On each
# four-second enemy-AI snapshot, the controller evaluates egg-eater lightning,
# emergency rain, profitable earthquake, then weakened-tyrannosaurus lightning.
# Every applied spell reuses the shared world nature-effects system.
#
# Rain targeting stays local to the visible map-clipped contour around the enemy
# base. It scores immediate unique grass spread plus DryGround recovery, but only
# when that DryGround is cardinally adjacent to existing grass. The ecological
# score is then adjusted by nearby adult enemy-herbivore demand. Isolated desert
# and young-grass growth remain intentionally ignored.
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const ENEMY_SPECIES_CATALOG := preload("res://scripts/catalogs/enemy_species_catalog.gd")
const PLAYER_SPECIES_CATALOG := preload("res://scripts/catalogs/player_species_catalog.gd")

const MATURE_GRASS_STAGE := 3
const INITIALIZATION_RETRY_FRAMES := 12
const COMBAT_RESERVE_SAVE_VERSION := 2
const PLAYER_TYRANNOSAURUS_ID := &"tyrannosaurus"
const PLAYER_EGG_EATER_ID := &"egg_eater"
const ENEMY_RAPTOR_ID := &"raptor"
const LIGHTNING_MODE_EGG_EATER := &"egg_eater"
const LIGHTNING_MODE_TYRANNOSAURUS := &"tyrannosaurus"
const EGG_STAGE_2 := 1
const RAIN_PAYMENT_NONE := &"none"
const RAIN_PAYMENT_ORDINARY := &"ordinary"
const RAIN_PAYMENT_RESERVE := &"reserve"
const INVALID_TILE := Vector2i(2147483647, 2147483647)
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.UP,
	Vector2i.DOWN
]

@export var rain_energy_cost := 50.0
@export var minimum_rain_target_score := 1
@export var new_grass_score := 10
@export var dry_ground_zero_hit_score := 5
@export var dry_ground_one_hit_score := 7
@export var dry_ground_two_hit_score := 9
@export var rain_expansion_phase_start_seconds := 600.0
@export var expansion_dry_ground_zero_hit_score := 8
@export var expansion_dry_ground_one_hit_score := 11
@export var expansion_dry_ground_two_hit_score := 15
@export var rain_initial_priority_phase_duration_seconds := 180.0
@export var rain_initial_priority_multiplier := 10.0
@export var empty_area_score_multiplier := 0.5
@export var herbivore_demand_multiplier_step := 0.3
@export var maximum_herbivore_score_multiplier := 2.5
@export var herbivore_near_distance_tiles := 3
@export var herbivore_medium_distance_tiles := 6
@export var herbivore_far_distance_tiles := 10
@export_range(0.0, 1.0, 0.05) var herbivore_medium_demand_weight := 0.5
@export_range(0.0, 1.0, 0.05) var herbivore_far_demand_weight := 0.25
@export var rain_search_radius_tiles := 20
@export var base_proximity_reference_distance_tiles := 20
@export var base_proximity_multiplier_step := 0.007
@export var expansion_base_proximity_multiplier_step := 0.014
@export var rain_area_frame_duration_seconds := 4.0
@export var search_area_frame_color := Color(1.0, 0.48, 0.12, 0.82)
@export var rain_area_frame_color := Color(0.20, 0.78, 1.0, 0.95)
@export var search_area_frame_line_width := 8.0
@export var rain_area_frame_line_width := 10.0

# Match time grows only the reserve capacity. Actual reserve energy is diverted
# from real enemy-creature income by EnemyEnergy and never appears from time alone.
@export var combat_reserve_unlock_minutes := 10
@export var combat_reserve_late_rate_after_minutes := 20
@export var combat_reserve_capacity_gain_per_minute := 100.0
@export var combat_reserve_capacity_late_gain_per_minute := 200.0
@export var combat_reserve_maximum := 3000.0
# Combat spells may empty stored reserve energy completely. This floor applies
# only to the capacity after a successful offensive cast.
@export var combat_reserve_minimum_after_cast := 500.0

@export_group("Enemy Lightning")
@export var lightning_energy_cost := 1000.0
@export var lightning_damage_threshold := 50.0
@export var lightning_double_strike_delay_seconds := 2.0
@export var tyrannosaurus_base_radius_tiles := 30.0
@export var tyrannosaurus_raptor_guard_radius_tiles := 20.0
@export var egg_eater_base_radius_tiles := 20.0

@export_group("Enemy Earthquake")
@export var earthquake_energy_cost := 1700.0
@export var minimum_earthquake_player_eggs := 2

var world_grid: Node = null
var nature_effects: Node = null
var enemy_ai: Node = null
var enemy_energy: Node = null
var enemy_base: Node2D = null

var combat_reserve := 0.0
var combat_reserve_capacity := 0.0
var next_combat_reserve_capacity_tick_minute := 0
var last_combat_reserve_income_deposit := 0.0
var lightning_sequence_active := false

var search_area_bounds := Rect2i()
var has_search_area_bounds := false
var visible_rain_frame_tile := INVALID_TILE
var rain_frame_remaining_seconds := 0.0

var last_action_text := "ожидание первого решения по спеллам"
var last_lightning_action_text := "ожидание подходящей цели"
var last_lightning_target_species := &""
var last_lightning_target_health := 0.0
var last_lightning_target_base_distance := -1.0
var last_lightning_nearby_raptor_count := 0
var last_earthquake_action_text := "ожидание выгодной кладки"
var last_earthquake_target_tile := INVALID_TILE
var last_earthquake_target_egg_count := 0
var last_earthquake_target_value := 0.0
var last_earthquake_target_stage_2_count := 0
var last_earthquake_candidate_center_count := 0
var last_rain_target_tile := INVALID_TILE
var last_grass_entries_scanned := 0
var last_mature_grass_count := 0
var last_spread_ready_grass_count := 0
var last_productive_grass_count := 0
var last_unique_spawn_target_count := 0
var last_adjacent_dry_ground_count := 0
var last_candidate_center_count := 0
var last_best_predicted_new_grass := 0
var last_best_dry_ground_zero_hit_count := 0
var last_best_dry_ground_one_hit_count := 0
var last_best_dry_ground_two_hit_count := 0
var last_best_dry_ground_score := 0
var last_rain_initial_priority_phase_active := false
var last_rain_expansion_phase_active := false
var last_eligible_herbivore_count := 0
var last_best_near_herbivore_count := 0
var last_best_medium_herbivore_count := 0
var last_best_far_herbivore_count := 0
var last_best_herbivore_demand := 0.0
var last_best_demand_multiplier := 0.5
var last_best_base_distance_tiles := 20
var last_best_base_proximity_multiplier := 1.0
var last_best_base_score := 0
var last_best_total_score := 0.0
var last_actual_new_grass := 0
var last_search_duration_usec := 0
var max_search_duration_usec := 0
var total_search_count := 0
var last_apply_duration_usec := 0
var max_apply_duration_usec := 0
var total_apply_count := 0


func _ready() -> void:
	add_to_group("enemy_spell_controller")
	_reset_combat_reserve_for_new_session()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 500
	call_deferred("_initialize_runtime")


func _process(delta: float) -> void:
	_update_combat_reserve_capacity_from_match_time()

	if not has_search_area_bounds:
		_refresh_runtime_references()
		if _refresh_search_area_bounds():
			queue_redraw()

	if rain_frame_remaining_seconds <= 0.0:
		return

	# The result outline uses real seconds while gameplay is running, but this
	# PAUSABLE node receives no process ticks while the in-game menu pauses the
	# SceneTree. Dividing by time_scale keeps 1x/2x/4x simulation speeds from
	# shortening the four-second inspection window.
	var safe_time_scale := maxf(Engine.time_scale, 0.0001)
	rain_frame_remaining_seconds = maxf(
		rain_frame_remaining_seconds - delta / safe_time_scale,
		0.0
	)

	if rain_frame_remaining_seconds > 0.0:
		return

	visible_rain_frame_tile = INVALID_TILE
	queue_redraw()


func _draw() -> void:
	if has_search_area_bounds:
		var search_rect := _tile_bounds_to_local_rect(search_area_bounds)

		if search_rect.size.x > 0.0 and search_rect.size.y > 0.0:
			draw_rect(
				search_rect,
				search_area_frame_color,
				false,
				maxf(search_area_frame_line_width, 1.0),
				true
			)

	if (
		visible_rain_frame_tile == INVALID_TILE
		or rain_frame_remaining_seconds <= 0.0
	):
		return

	var rain_radius := _get_rain_radius_tiles()
	if rain_radius <= 0:
		return

	var rain_size := rain_radius * 2 + 1
	var rain_bounds := Rect2i(
		visible_rain_frame_tile - Vector2i(rain_radius, rain_radius),
		Vector2i(rain_size, rain_size)
	)
	var rain_rect := _tile_bounds_to_local_rect(rain_bounds)

	if rain_rect.size.x > 0.0 and rain_rect.size.y > 0.0:
		draw_rect(
			rain_rect,
			rain_area_frame_color,
			false,
			maxf(rain_area_frame_line_width, 1.0),
			true
		)


func _exit_tree() -> void:
	_disconnect_enemy_ai()


func _initialize_runtime() -> void:
	for _attempt in range(INITIALIZATION_RETRY_FRAMES):
		_refresh_runtime_references()

		if _connect_enemy_ai():
			_update_combat_reserve_capacity_from_match_time()
			_refresh_search_area_bounds()
			queue_redraw()
			return

		await get_tree().process_frame

	push_warning("EnemySpellController: enemy AI turn signal was not found.")


func _connect_enemy_ai() -> bool:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		return false
	if not enemy_ai.has_signal("turn_completed"):
		return false

	var turn_callable := Callable(self, "_on_enemy_turn_completed")

	if not enemy_ai.is_connected("turn_completed", turn_callable):
		enemy_ai.connect("turn_completed", turn_callable)

	return true


func _disconnect_enemy_ai() -> void:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		return

	var turn_callable := Callable(self, "_on_enemy_turn_completed")

	if enemy_ai.has_signal("turn_completed") and enemy_ai.is_connected(
		"turn_completed", turn_callable
	):
		enemy_ai.disconnect("turn_completed", turn_callable)


func _on_enemy_turn_completed(snapshot: Dictionary) -> void:
	if lightning_sequence_active:
		return

	# One strategic spell action per completed turn. A delayed second lightning
	# strike blocks the whole decision above; otherwise use the agreed priority.
	if _try_cast_priority_lightning(LIGHTNING_MODE_EGG_EATER):
		return

	var adult_herbivore_count := int(snapshot.get("adult_herbivore_count", 0))
	var average_satiety := float(
		snapshot.get("average_adult_herbivore_satiety_percent", -1.0)
	)
	var satiety_threshold := clampf(
		float(snapshot.get("minimum_average_herbivore_satiety_percent", 40.0)),
		0.0,
		100.0
	)
	var herd_needs_rain := (
		adult_herbivore_count > 0
		and average_satiety >= 0.0
		and average_satiety < satiety_threshold
	)

	if herd_needs_rain and _try_cast_rain_for_hungry_herd():
		return
	if _try_cast_earthquake():
		return

	_try_cast_priority_lightning(LIGHTNING_MODE_TYRANNOSAURUS)


func _try_cast_priority_lightning(target_mode: StringName) -> bool:
	_refresh_runtime_references()
	_reset_last_lightning_debug()

	if world_grid == null or nature_effects == null or enemy_base == null:
		last_lightning_action_text = "отложена: база или мировая система эффектов не найдена"
		return false
	if (
		not nature_effects.has_method("can_apply_lightning")
		or not nature_effects.has_method("apply_lightning")
	):
		last_lightning_action_text = "отложена: общий эффект молнии недоступен"
		return false
	if get_combat_reserve() + 0.001 < _get_lightning_cost():
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
					% [roundi(needed_cost), roundi(get_combat_reserve())]
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
	var base_anchor := _get_creature_or_base_anchor(enemy_base)

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
			and base_distance <= maxf(egg_eater_base_radius_tiles, 0.0)
		):
			egg_eater_threats.append(candidate)
		elif (
			species_id == PLAYER_TYRANNOSAURUS_ID
			and health <= maxf(lightning_damage_threshold, 0.0)
			and base_distance <= maxf(tyrannosaurus_base_radius_tiles, 0.0)
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

		if not can_spend_combat_reserve(total_cost):
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
	if not can_spend_combat_reserve(_get_lightning_cost()):
		return {}

	var valid_candidates: Array = []

	for candidate: Dictionary in candidates:
		var target_anchor: Vector2i = candidate.get("anchor", Vector2i.ZERO)
		var nearby_raptors := _count_raptors_within_radius(
			enemy_raptors,
			target_anchor,
			maxf(tyrannosaurus_raptor_guard_radius_tiles, 0.0)
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

	if not can_spend_combat_reserve(total_cost):
		last_lightning_action_text = "отложена: резерв изменился до удара"
		return false

	lightning_sequence_active = strike_count > 1

	if not bool(nature_effects.call("can_apply_lightning", target)):
		lightning_sequence_active = false
		last_lightning_action_text = "отложена: цель больше нельзя поразить"
		return false
	if not bool(nature_effects.call("apply_lightning", target)):
		lightning_sequence_active = false
		last_lightning_action_text = "не сработала: первый удар не применён"
		return false
	if not spend_combat_reserve_after_success(_get_lightning_cost()):
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
		lightning_double_strike_delay_seconds,
		0.0
	)
	var health_after_first_strike := maxf(float(target.get("health")), 0.0)
	_run_second_lightning_strike(target, health_after_first_strike)
	return true


func _run_second_lightning_strike(
	target: Node,
	health_after_first_strike: float
) -> void:
	var delay := maxf(lightning_double_strike_delay_seconds, 0.0)

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

	if not can_spend_combat_reserve(_get_lightning_cost()):
		lightning_sequence_active = false
		last_lightning_action_text = "второй удар отменён: резерв неожиданно изменился"
		return
	if not bool(nature_effects.call("can_apply_lightning", target)):
		lightning_sequence_active = false
		last_lightning_action_text = "второй удар отменён: цель недоступна"
		return
	if not bool(nature_effects.call("apply_lightning", target)):
		lightning_sequence_active = false
		last_lightning_action_text = "второй удар не применился; энка не списана"
		return
	if not spend_combat_reserve_after_success(_get_lightning_cost()):
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
	var one_strike_damage := maxf(lightning_damage_threshold, 0.0)

	if safe_health <= 0.0 or one_strike_damage <= 0.0:
		return 0
	if safe_health <= one_strike_damage + 0.001:
		return 1
	if safe_health <= one_strike_damage * 2.0 + 0.001:
		return 2
	return 0


func _get_lightning_cost() -> float:
	return maxf(lightning_energy_cost, 0.0)


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


func _try_cast_earthquake() -> bool:
	_refresh_runtime_references()
	_reset_last_earthquake_debug()

	if world_grid == null or nature_effects == null or enemy_base == null:
		last_earthquake_action_text = "отложено: база или мировая система эффектов не найдена"
		return false
	if (
		not nature_effects.has_method("can_apply_earthquake")
		or not nature_effects.has_method("apply_earthquake")
		or not nature_effects.has_method("get_earthquake_radius_tiles")
	):
		last_earthquake_action_text = "отложено: общий эффект землетрясения недоступен"
		return false

	var earthquake_cost := _get_earthquake_cost()

	if not can_spend_combat_reserve(earthquake_cost):
		last_earthquake_action_text = "ожидание: в резерве меньше %d энки" % roundi(
			earthquake_cost
		)
		return false

	var egg_data := _collect_earthquake_egg_data()
	var player_eggs: Array = []

	for data: Dictionary in egg_data:
		if StringName(data.get("faction_id", &"")) == CREATURE_FACTION.PLAYER:
			player_eggs.append(data)

	var minimum_eggs := maxi(minimum_earthquake_player_eggs, 2)

	if player_eggs.size() < minimum_eggs:
		last_earthquake_action_text = "ожидание: у игрока меньше %d яиц" % minimum_eggs
		return false

	var radius := maxi(int(nature_effects.call("get_earthquake_radius_tiles")), 0)
	var base_anchor := _get_creature_or_base_anchor(enemy_base)
	var candidate_centers := _build_earthquake_candidate_centers(
		egg_data,
		radius,
		base_anchor
	)
	var best_plan: Dictionary = {}
	var best_seen_plan: Dictionary = {}

	for center_variant: Variant in candidate_centers:
		if not (center_variant is Vector2i):
			continue

		var center: Vector2i = center_variant

		if nature_effects.has_method("can_apply_at_tile") and not bool(
			nature_effects.call("can_apply_at_tile", center)
		):
			continue

		last_earthquake_candidate_center_count += 1
		var plan := _evaluate_earthquake_center(center, egg_data, radius, base_anchor)

		if (
			int(plan.get("foreign_egg_count", 0)) == 0
			and int(plan.get("player_egg_count", 0)) >= minimum_eggs
			and _is_earthquake_plan_better(plan, best_seen_plan)
		):
			best_seen_plan = plan

		if not _is_earthquake_plan_profitable(plan):
			continue
		if _is_earthquake_plan_better(plan, best_plan):
			best_plan = plan

	PerformanceStats.add_counter(
		"enemy_earthquake_candidate_centers",
		last_earthquake_candidate_center_count
	)
	PerformanceStats.add_counter("enemy_earthquake_searches")

	if best_plan.is_empty():
		if best_seen_plan.is_empty():
			last_earthquake_action_text = (
				"ожидание: нет зоны минимум с %d яйцами игрока без своих"
				% minimum_eggs
			)
		else:
			_set_last_earthquake_target_debug(best_seen_plan)
			last_earthquake_action_text = (
				"невыгодно: лучшая зона %d яиц на %d, нужно больше %d"
				% [
					int(best_seen_plan.get("player_egg_count", 0)),
					roundi(float(best_seen_plan.get("total_value", 0.0))),
					roundi(earthquake_cost)
				]
			)
		return false

	var target_center: Vector2i = best_plan.get("center", INVALID_TILE)
	var current_plan := _evaluate_earthquake_center(
		target_center,
		_collect_earthquake_egg_data(),
		radius,
		base_anchor
	)

	if not _is_earthquake_plan_profitable(current_plan):
		last_earthquake_action_text = "отложено: выгодная кладка изменилась до удара"
		return false
	if not bool(nature_effects.call("can_apply_earthquake", target_center)):
		last_earthquake_action_text = "отложено: выбранную область больше нельзя поразить"
		return false
	if not bool(nature_effects.call("apply_earthquake", target_center)):
		last_earthquake_action_text = "не сработало: яйца не были уничтожены"
		return false
	if not spend_combat_reserve_after_success(earthquake_cost):
		last_earthquake_action_text = "ошибка: землетрясение прошло без списания резерва"
		return false

	_set_last_earthquake_target_debug(current_plan)
	last_earthquake_action_text = "удар: %d яиц на %d энки, стадия 2: %d, центр %s" % [
		last_earthquake_target_egg_count,
		roundi(last_earthquake_target_value),
		last_earthquake_target_stage_2_count,
		_format_tile(last_earthquake_target_tile)
	]
	PerformanceStats.add_counter("enemy_earthquake_casts")
	PerformanceStats.add_counter(
		"enemy_earthquake_target_eggs",
		last_earthquake_target_egg_count
	)
	PerformanceStats.add_counter(
		"enemy_earthquake_target_value",
		roundi(last_earthquake_target_value)
	)
	return true


func _collect_earthquake_egg_data() -> Array:
	var result: Array = []

	for egg_variant: Variant in get_tree().get_nodes_in_group("eggs"):
		var egg := egg_variant as Node

		if egg == null or not is_instance_valid(egg) or egg.is_queued_for_deletion():
			continue

		var raw_anchor: Variant = egg.get("anchor_tile")

		if not (raw_anchor is Vector2i):
			continue

		var footprint := Vector2i.ONE

		if egg.has_method("get_current_footprint"):
			var raw_footprint: Variant = egg.call("get_current_footprint")

			if raw_footprint is Vector2i:
				footprint = raw_footprint

		var faction_id := CREATURE_FACTION.get_id(egg)
		var species_id := _get_earthquake_egg_species_id(egg)
		var value := 0.0

		if faction_id == CREATURE_FACTION.PLAYER:
			value = _get_player_egg_value(species_id)

		result.append({
			"egg": egg,
			"faction_id": faction_id,
			"species_id": species_id,
			"value": value,
			"stage_2": int(egg.get("current_stage")) == EGG_STAGE_2,
			"anchor": raw_anchor,
			"footprint": footprint
		})

	return result


func _build_earthquake_candidate_centers(
	egg_data: Array,
	radius: int,
	base_anchor: Vector2i
) -> Array:
	if world_grid == null:
		return []

	var raw_map_min: Variant = world_grid.get("map_min")
	var raw_map_max: Variant = world_grid.get("map_max")

	if not (raw_map_min is Vector2i) or not (raw_map_max is Vector2i):
		return []

	var map_min: Vector2i = raw_map_min
	var map_max: Vector2i = raw_map_max
	var x_values := _build_earthquake_axis_candidates(
		egg_data,
		radius,
		0,
		base_anchor.x,
		map_min.x,
		map_max.x
	)
	var y_values := _build_earthquake_axis_candidates(
		egg_data,
		radius,
		1,
		base_anchor.y,
		map_min.y,
		map_max.y
	)
	var centers: Array = []

	for x: int in x_values:
		for y: int in y_values:
			centers.append(Vector2i(x, y))

	return centers


func _build_earthquake_axis_candidates(
	egg_data: Array,
	radius: int,
	axis: int,
	base_coordinate: int,
	map_minimum: int,
	map_maximum: int
) -> Array[int]:
	var breakpoints: Dictionary = {}
	breakpoints[map_minimum] = true
	breakpoints[map_maximum + 1] = true

	for data: Dictionary in egg_data:
		var anchor: Vector2i = data.get("anchor", Vector2i.ZERO)
		var footprint: Vector2i = data.get("footprint", Vector2i.ONE)
		var egg_max := anchor + footprint - Vector2i.ONE
		var egg_minimum := anchor.x if axis == 0 else anchor.y
		var egg_maximum := egg_max.x if axis == 0 else egg_max.y
		var interval_minimum := maxi(egg_minimum - radius, map_minimum)
		var interval_maximum := mini(egg_maximum + radius, map_maximum)

		if interval_minimum > interval_maximum:
			continue

		breakpoints[interval_minimum] = true
		breakpoints[interval_maximum + 1] = true

	var sorted_breakpoints: Array = breakpoints.keys()
	sorted_breakpoints.sort()
	var result: Array[int] = []

	for index in range(sorted_breakpoints.size() - 1):
		var segment_minimum := maxi(int(sorted_breakpoints[index]), map_minimum)
		var segment_maximum := mini(
			int(sorted_breakpoints[index + 1]) - 1,
			map_maximum
		)

		if segment_minimum > segment_maximum:
			continue

		# Every egg-overlap result is constant inside this segment. Use the point
		# nearest the enemy base so the final distance tie-break is exact, not an
		# approximation based only on egg interval edges.
		result.append(clampi(base_coordinate, segment_minimum, segment_maximum))

	return result


func _evaluate_earthquake_center(
	center: Vector2i,
	egg_data: Array,
	radius: int,
	base_anchor: Vector2i
) -> Dictionary:
	var player_egg_count := 0
	var foreign_egg_count := 0
	var stage_2_count := 0
	var total_value := 0.0

	for data: Dictionary in egg_data:
		if not _earthquake_area_overlaps_egg_data(center, radius, data):
			continue

		var faction_id := StringName(data.get("faction_id", &""))

		if faction_id != CREATURE_FACTION.PLAYER:
			foreign_egg_count += 1
			continue

		player_egg_count += 1
		total_value += maxf(float(data.get("value", 0.0)), 0.0)

		if bool(data.get("stage_2", false)):
			stage_2_count += 1

	return {
		"center": center,
		"player_egg_count": player_egg_count,
		"foreign_egg_count": foreign_egg_count,
		"stage_2_count": stage_2_count,
		"total_value": total_value,
		"base_distance": _tile_distance(base_anchor, center)
	}


func _earthquake_area_overlaps_egg_data(
	center: Vector2i,
	radius: int,
	data: Dictionary
) -> bool:
	var anchor: Vector2i = data.get("anchor", Vector2i.ZERO)
	var footprint: Vector2i = data.get("footprint", Vector2i.ONE)
	var egg_max := anchor + footprint - Vector2i.ONE
	var area_min := center - Vector2i.ONE * radius
	var area_max := center + Vector2i.ONE * radius
	return (
		anchor.x <= area_max.x
		and egg_max.x >= area_min.x
		and anchor.y <= area_max.y
		and egg_max.y >= area_min.y
	)


func _is_earthquake_plan_profitable(plan: Dictionary) -> bool:
	return (
		int(plan.get("foreign_egg_count", 0)) == 0
		and int(plan.get("player_egg_count", 0)) >= maxi(
			minimum_earthquake_player_eggs,
			2
		)
		and float(plan.get("total_value", 0.0)) > _get_earthquake_cost() + 0.001
	)


func _is_earthquake_plan_better(candidate: Dictionary, current_best: Dictionary) -> bool:
	if current_best.is_empty():
		return true

	var candidate_value := float(candidate.get("total_value", 0.0))
	var best_value := float(current_best.get("total_value", 0.0))

	if not is_equal_approx(candidate_value, best_value):
		return candidate_value > best_value

	var candidate_stage_2 := int(candidate.get("stage_2_count", 0))
	var best_stage_2 := int(current_best.get("stage_2_count", 0))

	if candidate_stage_2 != best_stage_2:
		return candidate_stage_2 > best_stage_2

	var candidate_count := int(candidate.get("player_egg_count", 0))
	var best_count := int(current_best.get("player_egg_count", 0))

	if candidate_count != best_count:
		return candidate_count > best_count

	var candidate_distance := float(candidate.get("base_distance", INF))
	var best_distance := float(current_best.get("base_distance", INF))

	if not is_equal_approx(candidate_distance, best_distance):
		return candidate_distance < best_distance

	var candidate_center: Vector2i = candidate.get("center", Vector2i.ZERO)
	var best_center: Vector2i = current_best.get("center", Vector2i.ZERO)

	if candidate_center.y != best_center.y:
		return candidate_center.y < best_center.y
	return candidate_center.x < best_center.x


func _get_earthquake_egg_species_id(egg: Node) -> StringName:
	var hatch_species := egg.get("hatch_species_data") as CreatureSpeciesData

	if hatch_species != null:
		return StringName(hatch_species.species_id)

	return StringName(str(egg.get("species_id")))


func _get_player_egg_value(species_id: StringName) -> float:
	var entry: Dictionary = PLAYER_SPECIES_CATALOG.get_entry(species_id)
	return maxf(float(entry.get("egg_purchase_cost", 0.0)), 0.0)


func _get_earthquake_cost() -> float:
	return maxf(earthquake_energy_cost, 0.0)


func _reset_last_earthquake_debug() -> void:
	last_earthquake_target_tile = INVALID_TILE
	last_earthquake_target_egg_count = 0
	last_earthquake_target_value = 0.0
	last_earthquake_target_stage_2_count = 0
	last_earthquake_candidate_center_count = 0


func _set_last_earthquake_target_debug(plan: Dictionary) -> void:
	last_earthquake_target_tile = plan.get("center", INVALID_TILE)
	last_earthquake_target_egg_count = int(plan.get("player_egg_count", 0))
	last_earthquake_target_value = float(plan.get("total_value", 0.0))
	last_earthquake_target_stage_2_count = int(plan.get("stage_2_count", 0))


func _try_cast_rain_for_hungry_herd() -> bool:
	_refresh_runtime_references()
	_reset_last_search_stats()

	if world_grid == null or nature_effects == null:
		last_action_text = "дождь отложен: мировая система эффектов не найдена"
		return false

	if not _refresh_search_area_bounds():
		last_action_text = "дождь отложен: область вокруг базы не найдена"
		return false

	if (
		enemy_energy == null
		or not enemy_energy.has_method("can_spend")
		or not enemy_energy.has_method("spend")
		or not enemy_energy.has_method("add_energy")
	):
		last_action_text = "дождь отложен: хранилище энки противника не найдено"
		return false

	var safe_cost := maxf(rain_energy_cost, 0.0)
	var rain_payment_source := _get_rain_payment_source(safe_cost)

	# Ordinary energy has priority. The reserve is a full-cost fallback only; the
	# two stores are never combined for one rain cast.
	if rain_payment_source == RAIN_PAYMENT_NONE:
		last_action_text = "дождь отложен: не хватает обычной энки и резерва"
		PerformanceStats.add_counter("enemy_rain_wait_energy")
		return false

	var target_data := _find_best_rain_target()

	if target_data.is_empty():
		last_action_text = "дождь отложен: рядом с травой нет полезной цели"
		PerformanceStats.add_counter("enemy_rain_no_target")
		return false

	var target_variant: Variant = target_data.get("tile", INVALID_TILE)

	if not (target_variant is Vector2i):
		last_action_text = "дождь отложен: рассчитана неверная цель"
		return false

	var target_tile: Vector2i = target_variant

	if (
		not nature_effects.has_method("can_apply_rain")
		or not nature_effects.has_method("apply_rain")
		or not bool(nature_effects.call("can_apply_rain", target_tile))
	):
		last_action_text = "дождь отложен: выбранная область больше не подходит"
		return false

	if not _spend_rain_energy(rain_payment_source, safe_cost):
		last_action_text = "дождь отложен: источник оплаты изменился"
		return false

	var grass_count_before := _get_registered_grass_count()
	var apply_start_usec := Time.get_ticks_usec()
	var rain_applied := bool(nature_effects.call("apply_rain", target_tile))
	_finish_apply_measurement(apply_start_usec)
	var grass_count_after := _get_registered_grass_count()
	last_actual_new_grass = maxi(grass_count_after - grass_count_before, 0)

	if not rain_applied:
		_refund_rain_energy(rain_payment_source, safe_cost)
		last_action_text = "дождь не сработал: энка возвращена в источник оплаты"
		PerformanceStats.add_counter("enemy_rain_failed_refunded")
		return false

	last_rain_target_tile = target_tile
	_show_rain_area_frame(target_tile)
	last_action_text = (
		"дождь (%s): %s, балл %.1f = база %d × спрос %.2f × близость %.3f; прогноз +%d / реально +%d"
		% [
			_format_rain_payment_source(rain_payment_source),
			_format_tile(target_tile),
			last_best_total_score,
			last_best_base_score,
			last_best_demand_multiplier,
			last_best_base_proximity_multiplier,
			last_best_predicted_new_grass,
			last_actual_new_grass
		]
	)
	PerformanceStats.add_counter("enemy_rain_casts")
	PerformanceStats.add_counter(
		"enemy_rain_predicted_new_grass",
		last_best_predicted_new_grass
	)
	PerformanceStats.add_counter(
		"enemy_rain_actual_new_grass",
		last_actual_new_grass
	)
	PerformanceStats.add_counter(
		"enemy_rain_prediction_gap",
		last_best_predicted_new_grass - last_actual_new_grass
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_dry_ground_zero_hit",
		last_best_dry_ground_zero_hit_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_dry_ground_one_hit",
		last_best_dry_ground_one_hit_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_dry_ground_two_hit",
		last_best_dry_ground_two_hit_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_dry_ground_score",
		last_best_dry_ground_score
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_total_score",
		roundi(last_best_total_score)
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_eligible_herbivores",
		last_eligible_herbivore_count
	)
	PerformanceStats.set_max_value(
		"enemy_rain_selected_demand_multiplier_max",
		last_best_demand_multiplier
	)
	return true


func _find_best_rain_target() -> Dictionary:
	var search_start_usec := Time.get_ticks_usec()
	var result: Dictionary = {}

	if not _can_scan_rain_target_data():
		_finish_search_measurement(search_start_usec)
		return result

	var rain_radius := _get_rain_radius_tiles()

	if rain_radius <= 0:
		_finish_search_measurement(search_start_usec)
		return result

	last_rain_initial_priority_phase_active = _is_rain_initial_priority_phase_active()
	last_rain_expansion_phase_active = _is_rain_expansion_phase_active()
	var active_dry_ground_scores := _get_active_dry_ground_scores(
		last_rain_expansion_phase_active
	)
	var active_base_proximity_step := _get_active_base_proximity_multiplier_step(
		last_rain_initial_priority_phase_active,
		last_rain_expansion_phase_active
	)
	var active_herbivore_demand_step := _get_active_herbivore_demand_multiplier_step(
		last_rain_initial_priority_phase_active
	)

	var grass_registry_variant: Variant = world_grid.get("grass_by_tile")
	var grass_registry: Dictionary = grass_registry_variant as Dictionary
	var source_tiles_by_spawn_target: Dictionary = {}

	# Map each unique cell that can receive new grass to all mature sources able
	# to create it. The future cell counts once even when several sources share it.
	for grass_tile_variant: Variant in grass_registry.keys():
		last_grass_entries_scanned += 1

		if not (grass_tile_variant is Vector2i):
			continue

		var grass_tile: Vector2i = grass_tile_variant

		if not _is_tile_inside_search_area(grass_tile):
			continue

		var grass := grass_registry.get(grass_tile, null) as Node

		if not _is_mature_grass(grass):
			continue

		last_mature_grass_count += 1

		if bool(grass.get("has_tried_to_spread")):
			continue

		last_spread_ready_grass_count += 1
		var immediate_spawn_tiles := _get_immediate_spawn_tiles(grass_tile)

		if immediate_spawn_tiles.is_empty():
			continue

		last_productive_grass_count += 1

		for spawn_tile: Vector2i in immediate_spawn_tiles:
			var source_set_variant: Variant = source_tiles_by_spawn_target.get(
				spawn_tile, null
			)
			var source_set: Dictionary = {}

			if source_set_variant is Dictionary:
				source_set = source_set_variant as Dictionary

			source_set[grass_tile] = true
			source_tiles_by_spawn_target[spawn_tile] = source_set

	last_unique_spawn_target_count = source_tiles_by_spawn_target.size()

	var candidate_new_grass: Dictionary = {}
	var candidate_dry_ground_score: Dictionary = {}
	var candidate_dry_ground_zero_hit: Dictionary = {}
	var candidate_dry_ground_one_hit: Dictionary = {}
	var candidate_dry_ground_two_hit: Dictionary = {}

	# Each unique future grass cell adds its weight once to every center that
	# covers at least one mature source capable of creating that cell.
	for source_set_variant: Variant in source_tiles_by_spawn_target.values():
		if not (source_set_variant is Dictionary):
			continue

		var source_set: Dictionary = source_set_variant as Dictionary
		var covered_centers: Dictionary = {}

		for source_tile_variant: Variant in source_set.keys():
			if source_tile_variant is Vector2i:
				_append_covering_centers(
					covered_centers,
					source_tile_variant,
					rain_radius
				)

		for center_variant: Variant in covered_centers.keys():
			if center_variant is Vector2i:
				candidate_new_grass[center_variant] = int(
					candidate_new_grass.get(center_variant, 0)
				) + 1

	# DryGround is useful only when grass can eventually occupy it. Therefore an
	# isolated desert cell is ignored, while a cardinal grass neighbour makes it
	# eligible even when no immediate spread is currently possible.
	var dry_ground_hit_lookup := _get_dry_ground_hit_lookup()
	var search_min := search_area_bounds.position
	var search_max := (
		search_area_bounds.position
		+ search_area_bounds.size
		- Vector2i.ONE
	)

	for tile_y in range(search_min.y, search_max.y + 1):
		for tile_x in range(search_min.x, search_max.x + 1):
			var dry_tile := Vector2i(tile_x, tile_y)

			if not bool(world_grid.call("has_dry_ground_at_tile", dry_tile)):
				continue
			if not _has_cardinal_grass_neighbor(dry_tile):
				continue

			last_adjacent_dry_ground_count += 1
			var rain_hits := clampi(int(dry_ground_hit_lookup.get(dry_tile, 0)), 0, 2)
			var dry_weight := _get_dry_ground_score_for_hits(
				rain_hits,
				active_dry_ground_scores
			)
			var dry_covered_centers: Dictionary = {}
			_append_covering_centers(dry_covered_centers, dry_tile, rain_radius)

			for center_variant: Variant in dry_covered_centers.keys():
				if not (center_variant is Vector2i):
					continue

				candidate_dry_ground_score[center_variant] = int(
					candidate_dry_ground_score.get(center_variant, 0)
				) + dry_weight

				match rain_hits:
					0:
						candidate_dry_ground_zero_hit[center_variant] = int(
							candidate_dry_ground_zero_hit.get(center_variant, 0)
						) + 1
					1:
						candidate_dry_ground_one_hit[center_variant] = int(
							candidate_dry_ground_one_hit.get(center_variant, 0)
						) + 1
					2:
						candidate_dry_ground_two_hit[center_variant] = int(
							candidate_dry_ground_two_hit.get(center_variant, 0)
						) + 1

	var candidate_centers: Dictionary = {}

	for center_variant: Variant in candidate_new_grass.keys():
		if center_variant is Vector2i:
			candidate_centers[center_variant] = true

	for center_variant: Variant in candidate_dry_ground_score.keys():
		if center_variant is Vector2i:
			candidate_centers[center_variant] = true

	last_candidate_center_count = candidate_centers.size()
	var herbivore_footprints := _collect_eligible_enemy_herbivore_footprints()
	last_eligible_herbivore_count = herbivore_footprints.size()
	var herbivore_demand_by_center := _build_herbivore_demand_map(
		herbivore_footprints,
		candidate_centers,
		rain_radius
	)
	var best_center := INVALID_TILE
	var best_total_score := -1.0
	var best_base_score := 0
	var best_predicted_new_grass := 0
	var best_dry_ground_zero_hit_count := 0
	var best_dry_ground_one_hit_count := 0
	var best_dry_ground_two_hit_count := 0
	var best_dry_ground_score := 0
	var best_herbivore_demand := 0.0
	var best_demand_multiplier := _get_herbivore_demand_multiplier(
		0.0,
		active_herbivore_demand_step
	)
	var best_base_distance_tiles := _get_base_proximity_reference_distance_tiles()
	var best_base_proximity_multiplier := 1.0
	var safe_new_grass_score := maxi(new_grass_score, 0)

	for center_variant: Variant in candidate_centers.keys():
		if not (center_variant is Vector2i):
			continue

		var center_tile: Vector2i = center_variant
		var predicted_new_grass := int(candidate_new_grass.get(center_tile, 0))
		var dry_score := int(candidate_dry_ground_score.get(center_tile, 0))
		var base_score := predicted_new_grass * safe_new_grass_score + dry_score
		var herbivore_demand := float(herbivore_demand_by_center.get(center_tile, 0.0))
		var demand_multiplier := _get_herbivore_demand_multiplier(
			herbivore_demand,
			active_herbivore_demand_step
		)
		var base_distance_tiles := _get_distance_from_rain_area_to_enemy_base(
			center_tile,
			rain_radius
		)
		var base_proximity_multiplier := _get_base_proximity_multiplier(
			base_distance_tiles,
			active_base_proximity_step
		)
		var total_score := (
			float(base_score)
			* demand_multiplier
			* base_proximity_multiplier
		)

		if _is_better_candidate(
			center_tile,
			total_score,
			best_center,
			best_total_score
		):
			best_center = center_tile
			best_total_score = total_score
			best_base_score = base_score
			best_predicted_new_grass = predicted_new_grass
			best_dry_ground_zero_hit_count = int(
				candidate_dry_ground_zero_hit.get(center_tile, 0)
			)
			best_dry_ground_one_hit_count = int(
				candidate_dry_ground_one_hit.get(center_tile, 0)
			)
			best_dry_ground_two_hit_count = int(
				candidate_dry_ground_two_hit.get(center_tile, 0)
			)
			best_dry_ground_score = dry_score
			best_herbivore_demand = herbivore_demand
			best_demand_multiplier = demand_multiplier
			best_base_distance_tiles = base_distance_tiles
			best_base_proximity_multiplier = base_proximity_multiplier

	var best_demand_breakdown := _get_herbivore_demand_breakdown(
		best_center,
		herbivore_footprints,
		rain_radius
	)
	last_best_predicted_new_grass = best_predicted_new_grass
	last_best_dry_ground_zero_hit_count = best_dry_ground_zero_hit_count
	last_best_dry_ground_one_hit_count = best_dry_ground_one_hit_count
	last_best_dry_ground_two_hit_count = best_dry_ground_two_hit_count
	last_best_dry_ground_score = best_dry_ground_score
	last_best_near_herbivore_count = int(best_demand_breakdown.get("near", 0))
	last_best_medium_herbivore_count = int(best_demand_breakdown.get("medium", 0))
	last_best_far_herbivore_count = int(best_demand_breakdown.get("far", 0))
	last_best_herbivore_demand = best_herbivore_demand
	last_best_demand_multiplier = best_demand_multiplier
	last_best_base_distance_tiles = best_base_distance_tiles
	last_best_base_proximity_multiplier = best_base_proximity_multiplier
	last_best_base_score = best_base_score
	last_best_total_score = maxf(best_total_score, 0.0)
	_finish_search_measurement(search_start_usec)

	if (
		best_center == INVALID_TILE
		or best_total_score < float(maxi(minimum_rain_target_score, 1))
	):
		return result

	return {
		"tile": best_center,
		"predicted_new_grass": best_predicted_new_grass,
		"dry_ground_zero_hit_count": best_dry_ground_zero_hit_count,
		"dry_ground_one_hit_count": best_dry_ground_one_hit_count,
		"dry_ground_two_hit_count": best_dry_ground_two_hit_count,
		"dry_ground_score": best_dry_ground_score,
		"near_herbivore_count": last_best_near_herbivore_count,
		"medium_herbivore_count": last_best_medium_herbivore_count,
		"far_herbivore_count": last_best_far_herbivore_count,
		"herbivore_demand": best_herbivore_demand,
		"demand_multiplier": best_demand_multiplier,
		"base_distance_tiles": best_base_distance_tiles,
		"base_proximity_multiplier": best_base_proximity_multiplier,
		"base_score": best_base_score,
		"total_score": best_total_score
	}


func _finish_search_measurement(search_start_usec: int) -> void:
	last_search_duration_usec = maxi(Time.get_ticks_usec() - search_start_usec, 0)
	max_search_duration_usec = maxi(max_search_duration_usec, last_search_duration_usec)
	total_search_count += 1

	PerformanceStats.add_counter("enemy_rain_searches")
	PerformanceStats.add_counter("enemy_rain_search_usec", last_search_duration_usec)
	PerformanceStats.add_counter("enemy_rain_grass_scanned", last_grass_entries_scanned)
	PerformanceStats.add_counter("enemy_rain_mature_grass", last_mature_grass_count)
	PerformanceStats.add_counter(
		"enemy_rain_spread_ready_grass",
		last_spread_ready_grass_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_productive_grass",
		last_productive_grass_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_unique_spawn_targets",
		last_unique_spawn_target_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_candidate_centers",
		last_candidate_center_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_adjacent_dry_ground",
		last_adjacent_dry_ground_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_best_dry_ground_score",
		last_best_dry_ground_score
	)
	PerformanceStats.add_counter(
		"enemy_rain_best_total_score",
		roundi(last_best_total_score)
	)
	PerformanceStats.add_counter(
		"enemy_rain_eligible_herbivores",
		last_eligible_herbivore_count
	)
	PerformanceStats.set_max_value(
		"enemy_rain_search_max_usec",
		last_search_duration_usec
	)
	PerformanceStats.set_max_value(
		"enemy_rain_best_spread_max",
		last_best_predicted_new_grass
	)
	PerformanceStats.set_max_value(
		"enemy_rain_best_total_score_max",
		last_best_total_score
	)
	PerformanceStats.set_max_value(
		"enemy_rain_demand_multiplier_max",
		last_best_demand_multiplier
	)


func _finish_apply_measurement(apply_start_usec: int) -> void:
	last_apply_duration_usec = maxi(Time.get_ticks_usec() - apply_start_usec, 0)
	max_apply_duration_usec = maxi(max_apply_duration_usec, last_apply_duration_usec)
	total_apply_count += 1

	PerformanceStats.add_counter("enemy_rain_apply_calls")
	PerformanceStats.add_counter("enemy_rain_apply_usec", last_apply_duration_usec)
	PerformanceStats.set_max_value(
		"enemy_rain_apply_max_usec",
		last_apply_duration_usec
	)


func _can_scan_rain_target_data() -> bool:
	if world_grid == null or not is_instance_valid(world_grid):
		return false
	if not world_grid.has_method("is_tile_inside_map"):
		return false
	if not world_grid.has_method("can_host_grass"):
		return false
	if not world_grid.has_method("has_grass_at_tile"):
		return false
	if not world_grid.has_method("has_dry_ground_at_tile"):
		return false
	if not world_grid.has_method("get_dry_ground_rain_hit_data"):
		return false

	var grass_registry_variant: Variant = world_grid.get("grass_by_tile")
	return grass_registry_variant is Dictionary


func _is_mature_grass(grass: Node) -> bool:
	return (
		grass != null
		and is_instance_valid(grass)
		and not grass.is_queued_for_deletion()
		and int(grass.get("current_stage")) == MATURE_GRASS_STAGE
	)


func _get_immediate_spawn_tiles(grass_tile: Vector2i) -> Array[Vector2i]:
	var spawn_tiles: Array[Vector2i] = []

	for offset: Vector2i in CARDINAL_OFFSETS:
		var target_tile := grass_tile + offset

		if not bool(world_grid.call("is_tile_inside_map", target_tile)):
			continue
		if not _is_tile_inside_search_area(target_tile):
			continue
		if bool(world_grid.call("has_grass_at_tile", target_tile)):
			continue
		if not bool(world_grid.call("can_host_grass", target_tile)):
			continue

		spawn_tiles.append(target_tile)

	return spawn_tiles


func _has_cardinal_grass_neighbor(tile: Vector2i) -> bool:
	for offset: Vector2i in CARDINAL_OFFSETS:
		var neighbor_tile := tile + offset

		if not bool(world_grid.call("is_tile_inside_map", neighbor_tile)):
			continue
		if bool(world_grid.call("has_grass_at_tile", neighbor_tile)):
			return true

	return false


func _get_dry_ground_hit_lookup() -> Dictionary:
	var hit_lookup: Dictionary = {}
	var hit_data_variant: Variant = world_grid.call("get_dry_ground_rain_hit_data")

	if not (hit_data_variant is Array):
		return hit_lookup

	var hit_data: Array = hit_data_variant as Array

	for record_variant: Variant in hit_data:
		if not (record_variant is Dictionary):
			continue

		var record: Dictionary = record_variant as Dictionary
		var tile := Vector2i(
			int(record.get("x", 0)),
			int(record.get("y", 0))
		)
		var hits := clampi(int(record.get("hits", 0)), 0, 2)

		if hits > 0 and bool(world_grid.call("has_dry_ground_at_tile", tile)):
			hit_lookup[tile] = hits

	return hit_lookup


func _get_dry_ground_score_for_hits(
	rain_hits: int,
	active_scores: Array[int]
) -> int:
	match clampi(rain_hits, 0, 2):
		1:
			return active_scores[1]
		2:
			return active_scores[2]
		_:
			return active_scores[0]


func _get_active_dry_ground_scores(expansion_phase_active: bool) -> Array[int]:
	if expansion_phase_active:
		return [
			maxi(expansion_dry_ground_zero_hit_score, 0),
			maxi(expansion_dry_ground_one_hit_score, 0),
			maxi(expansion_dry_ground_two_hit_score, 0)
		]

	return [
		maxi(dry_ground_zero_hit_score, 0),
		maxi(dry_ground_one_hit_score, 0),
		maxi(dry_ground_two_hit_score, 0)
	]


func _collect_eligible_enemy_herbivore_footprints() -> Array[Rect2i]:
	var footprints: Array[Rect2i] = []

	for creature_variant: Variant in get_tree().get_nodes_in_group("creatures"):
		var creature := creature_variant as Node

		if not _is_eligible_enemy_herbivore(creature):
			continue

		var anchor_variant: Variant = creature.get("anchor_tile")
		var footprint_variant: Variant = creature.get("footprint_size")

		if not (anchor_variant is Vector2i and footprint_variant is Vector2i):
			continue

		var anchor_tile: Vector2i = anchor_variant
		var footprint_size: Vector2i = footprint_variant
		footprints.append(Rect2i(
			anchor_tile,
			Vector2i(maxi(footprint_size.x, 1), maxi(footprint_size.y, 1))
		))

	return footprints


func _is_eligible_enemy_herbivore(creature: Node) -> bool:
	if (
		creature == null
		or not is_instance_valid(creature)
		or creature.is_queued_for_deletion()
		or CREATURE_FACTION.get_id(creature) != CREATURE_FACTION.ENEMY
	):
		return false

	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null or not species_data.is_herbivore():
		return false

	return ENEMY_SPECIES_CATALOG.get_species_data(species_data.species_id) == species_data


func _build_herbivore_demand_map(
	herbivore_footprints: Array[Rect2i],
	candidate_centers: Dictionary,
	rain_radius: int
) -> Dictionary:
	var demand_by_center: Dictionary = {}
	var far_distance := _get_far_herbivore_distance_tiles()
	var safe_rain_radius := maxi(rain_radius, 0)
	var expansion := safe_rain_radius + far_distance

	for footprint: Rect2i in herbivore_footprints:
		var footprint_max := footprint.position + footprint.size - Vector2i.ONE

		for center_y in range(
			footprint.position.y - expansion,
			footprint_max.y + expansion + 1
		):
			for center_x in range(
				footprint.position.x - expansion,
				footprint_max.x + expansion + 1
			):
				var center_tile := Vector2i(center_x, center_y)

				if not candidate_centers.has(center_tile):
					continue

				var distance := _get_distance_from_footprint_to_rain_area(
					footprint,
					center_tile,
					safe_rain_radius
				)
				var demand_weight := _get_herbivore_demand_weight(distance)

				if demand_weight <= 0.0:
					continue

				demand_by_center[center_tile] = float(
					demand_by_center.get(center_tile, 0.0)
				) + demand_weight

	return demand_by_center


func _get_herbivore_demand_breakdown(
	center_tile: Vector2i,
	herbivore_footprints: Array[Rect2i],
	rain_radius: int
) -> Dictionary:
	var breakdown := {
		"near": 0,
		"medium": 0,
		"far": 0
	}

	if center_tile == INVALID_TILE:
		return breakdown

	var near_distance := _get_near_herbivore_distance_tiles()
	var medium_distance := _get_medium_herbivore_distance_tiles()
	var far_distance := _get_far_herbivore_distance_tiles()

	for footprint: Rect2i in herbivore_footprints:
		var distance := _get_distance_from_footprint_to_rain_area(
			footprint,
			center_tile,
			rain_radius
		)

		if distance <= near_distance:
			breakdown["near"] = int(breakdown["near"]) + 1
		elif distance <= medium_distance:
			breakdown["medium"] = int(breakdown["medium"]) + 1
		elif distance <= far_distance:
			breakdown["far"] = int(breakdown["far"]) + 1

	return breakdown


func _get_distance_from_footprint_to_rain_area(
	footprint: Rect2i,
	center_tile: Vector2i,
	rain_radius: int
) -> int:
	var safe_radius := maxi(rain_radius, 0)
	var rain_min := center_tile - Vector2i(safe_radius, safe_radius)
	var rain_max := center_tile + Vector2i(safe_radius, safe_radius)
	var footprint_min := footprint.position
	var footprint_max := footprint.position + footprint.size - Vector2i.ONE
	var gap_x := maxi(
		maxi(footprint_min.x - rain_max.x, rain_min.x - footprint_max.x),
		0
	)
	var gap_y := maxi(
		maxi(footprint_min.y - rain_max.y, rain_min.y - footprint_max.y),
		0
	)
	return maxi(gap_x, gap_y)


func _get_herbivore_demand_weight(distance_tiles: int) -> float:
	if distance_tiles <= _get_near_herbivore_distance_tiles():
		return 1.0
	if distance_tiles <= _get_medium_herbivore_distance_tiles():
		return clampf(herbivore_medium_demand_weight, 0.0, 1.0)
	if distance_tiles <= _get_far_herbivore_distance_tiles():
		return clampf(herbivore_far_demand_weight, 0.0, 1.0)

	return 0.0


func _get_herbivore_demand_multiplier(
	weighted_demand: float,
	active_multiplier_step: float = -1.0
) -> float:
	var base_multiplier := maxf(empty_area_score_multiplier, 0.0)
	var maximum_multiplier := maxf(maximum_herbivore_score_multiplier, base_multiplier)
	var safe_step := active_multiplier_step

	if safe_step < 0.0:
		safe_step = _get_active_herbivore_demand_multiplier_step(
			_is_rain_initial_priority_phase_active()
		)

	return clampf(
		base_multiplier
		+ maxf(safe_step, 0.0) * maxf(weighted_demand, 0.0),
		base_multiplier,
		maximum_multiplier
	)


func _get_active_herbivore_demand_multiplier_step(
	initial_priority_phase_active: bool
) -> float:
	var safe_step := maxf(herbivore_demand_multiplier_step, 0.0)

	if initial_priority_phase_active:
		return safe_step * maxf(rain_initial_priority_multiplier, 0.0)

	return safe_step


func _get_near_herbivore_distance_tiles() -> int:
	return maxi(herbivore_near_distance_tiles, 0)


func _get_medium_herbivore_distance_tiles() -> int:
	return maxi(herbivore_medium_distance_tiles, _get_near_herbivore_distance_tiles())


func _get_far_herbivore_distance_tiles() -> int:
	return maxi(herbivore_far_distance_tiles, _get_medium_herbivore_distance_tiles())


func _get_distance_from_rain_area_to_enemy_base(
	center_tile: Vector2i,
	rain_radius: int
) -> int:
	if enemy_base == null or not is_instance_valid(enemy_base):
		return _get_base_proximity_reference_distance_tiles()

	var anchor_variant: Variant = enemy_base.get("anchor_tile")
	var footprint_variant: Variant = enemy_base.get("footprint_size")

	if not (anchor_variant is Vector2i and footprint_variant is Vector2i):
		return _get_base_proximity_reference_distance_tiles()

	var anchor_tile: Vector2i = anchor_variant
	var footprint_size: Vector2i = footprint_variant
	var base_footprint := Rect2i(
		anchor_tile,
		Vector2i(maxi(footprint_size.x, 1), maxi(footprint_size.y, 1))
	)
	return _get_distance_from_footprint_to_rain_area(
		base_footprint,
		center_tile,
		rain_radius
	)


func _get_base_proximity_multiplier(
	distance_tiles: int,
	active_multiplier_step: float
) -> float:
	var reference_distance := _get_base_proximity_reference_distance_tiles()
	var clamped_distance := clampi(distance_tiles, 0, reference_distance)
	return (
		1.0
		+ float(reference_distance - clamped_distance)
		* maxf(active_multiplier_step, 0.0)
	)


func _get_active_base_proximity_multiplier_step(
	initial_priority_phase_active: bool,
	expansion_phase_active: bool
) -> float:
	if initial_priority_phase_active:
		return (
			maxf(base_proximity_multiplier_step, 0.0)
			* maxf(rain_initial_priority_multiplier, 0.0)
		)
	if expansion_phase_active:
		return maxf(expansion_base_proximity_multiplier_step, 0.0)

	return maxf(base_proximity_multiplier_step, 0.0)


func _is_rain_initial_priority_phase_active() -> bool:
	return (
		_get_enemy_elapsed_simulation_seconds()
		< maxf(rain_initial_priority_phase_duration_seconds, 0.0)
	)


func _is_rain_expansion_phase_active() -> bool:
	return (
		_get_enemy_elapsed_simulation_seconds()
		>= maxf(rain_expansion_phase_start_seconds, 0.0)
	)


func _get_base_proximity_reference_distance_tiles() -> int:
	return maxi(base_proximity_reference_distance_tiles, 0)


func _append_covering_centers(
	covered_centers: Dictionary,
	covered_tile: Vector2i,
	rain_radius: int
) -> void:
	for center_y in range(covered_tile.y - rain_radius, covered_tile.y + rain_radius + 1):
		for center_x in range(covered_tile.x - rain_radius, covered_tile.x + rain_radius + 1):
			var center_tile := Vector2i(center_x, center_y)

			if (
				bool(world_grid.call("is_tile_inside_map", center_tile))
				and _is_rain_center_inside_search_area(center_tile, rain_radius)
			):
				covered_centers[center_tile] = true


func _is_better_candidate(
	candidate_tile: Vector2i,
	candidate_score: float,
	best_tile: Vector2i,
	best_score: float
) -> bool:
	if not is_equal_approx(candidate_score, best_score):
		return candidate_score > best_score
	if best_tile == INVALID_TILE:
		return true

	# Stable tie-break keeps identical worlds deterministic.
	if candidate_tile.y != best_tile.y:
		return candidate_tile.y < best_tile.y

	return candidate_tile.x < best_tile.x


func _refresh_search_area_bounds() -> bool:
	if world_grid == null or not is_instance_valid(world_grid):
		has_search_area_bounds = false
		return false

	if enemy_base == null or not is_instance_valid(enemy_base):
		enemy_base = world_grid.get_node_or_null("EnemyBase") as Node2D

	if enemy_base == null:
		has_search_area_bounds = false
		return false

	var anchor_variant: Variant = enemy_base.get("anchor_tile")
	var footprint_variant: Variant = enemy_base.get("footprint_size")
	var map_min_variant: Variant = world_grid.get("map_min")
	var map_max_variant: Variant = world_grid.get("map_max")

	if not (anchor_variant is Vector2i and footprint_variant is Vector2i):
		has_search_area_bounds = false
		return false
	if not (map_min_variant is Vector2i and map_max_variant is Vector2i):
		has_search_area_bounds = false
		return false

	var anchor_tile: Vector2i = anchor_variant
	var footprint_size: Vector2i = footprint_variant
	var map_min: Vector2i = map_min_variant
	var map_max: Vector2i = map_max_variant
	var radius := maxi(rain_search_radius_tiles, 0)
	var min_tile := anchor_tile - Vector2i(radius, radius)
	var max_tile := (
		anchor_tile
		+ Vector2i(maxi(footprint_size.x, 1), maxi(footprint_size.y, 1))
		- Vector2i.ONE
		+ Vector2i(radius, radius)
	)
	min_tile = Vector2i(maxi(min_tile.x, map_min.x), maxi(min_tile.y, map_min.y))
	max_tile = Vector2i(mini(max_tile.x, map_max.x), mini(max_tile.y, map_max.y))

	if min_tile.x > max_tile.x or min_tile.y > max_tile.y:
		has_search_area_bounds = false
		return false

	var next_bounds := Rect2i(min_tile, max_tile - min_tile + Vector2i.ONE)
	var bounds_changed := not has_search_area_bounds or next_bounds != search_area_bounds
	search_area_bounds = next_bounds
	has_search_area_bounds = true

	if bounds_changed:
		queue_redraw()

	return true


func _is_tile_inside_search_area(tile: Vector2i) -> bool:
	return has_search_area_bounds and search_area_bounds.has_point(tile)


func _is_rain_center_inside_search_area(center_tile: Vector2i, rain_radius: int) -> bool:
	if not has_search_area_bounds:
		return false

	var safe_radius := maxi(rain_radius, 0)
	var min_allowed := search_area_bounds.position
	var max_allowed := search_area_bounds.position + search_area_bounds.size - Vector2i.ONE
	return (
		center_tile.x - safe_radius >= min_allowed.x
		and center_tile.y - safe_radius >= min_allowed.y
		and center_tile.x + safe_radius <= max_allowed.x
		and center_tile.y + safe_radius <= max_allowed.y
	)


func _show_rain_area_frame(target_tile: Vector2i) -> void:
	visible_rain_frame_tile = target_tile
	rain_frame_remaining_seconds = maxf(rain_area_frame_duration_seconds, 0.0)
	queue_redraw()


func _tile_bounds_to_local_rect(tile_bounds: Rect2i) -> Rect2:
	if (
		world_grid == null
		or not is_instance_valid(world_grid)
		or tile_bounds.size.x <= 0
		or tile_bounds.size.y <= 0
		or not world_grid.has_method("map_to_world_center")
	):
		return Rect2()

	var min_tile := tile_bounds.position
	var max_tile := tile_bounds.position + tile_bounds.size - Vector2i.ONE
	var min_center_global: Vector2 = world_grid.call("map_to_world_center", min_tile)
	var max_center_global: Vector2 = world_grid.call("map_to_world_center", max_tile)
	var min_center := to_local(min_center_global)
	var max_center := to_local(max_center_global)
	var tile_size_variant: Variant = world_grid.get("tile_size")
	var tile_size_pixels := Vector2(128.0, 128.0)

	if tile_size_variant is Vector2i:
		var tile_size_grid: Vector2i = tile_size_variant
		tile_size_pixels = Vector2(tile_size_grid)

	var left := minf(min_center.x, max_center.x) - tile_size_pixels.x * 0.5
	var top := minf(min_center.y, max_center.y) - tile_size_pixels.y * 0.5
	var right := maxf(min_center.x, max_center.x) + tile_size_pixels.x * 0.5
	var bottom := maxf(min_center.y, max_center.y) + tile_size_pixels.y * 0.5
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


func _get_registered_grass_count() -> int:
	if world_grid == null or not is_instance_valid(world_grid):
		return 0

	var grass_registry_variant: Variant = world_grid.get("grass_by_tile")

	if not (grass_registry_variant is Dictionary):
		return 0

	var grass_registry: Dictionary = grass_registry_variant as Dictionary
	return grass_registry.size()


func _get_rain_radius_tiles() -> int:
	if nature_effects != null and nature_effects.has_method("get_rain_radius_tiles"):
		return maxi(int(nature_effects.call("get_rain_radius_tiles")), 0)

	return 0


func _refresh_runtime_references() -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		var parent_grid := get_parent() as Node

		if parent_grid != null and parent_grid.has_method("is_tile_inside_map"):
			world_grid = parent_grid
		else:
			world_grid = get_tree().get_first_node_in_group("world_grid")

	if nature_effects == null or not is_instance_valid(nature_effects):
		nature_effects = get_tree().get_first_node_in_group("nature_effects_system")

	if enemy_ai == null or not is_instance_valid(enemy_ai):
		enemy_ai = get_tree().get_first_node_in_group("enemy_ai")

	if enemy_energy == null or not is_instance_valid(enemy_energy):
		enemy_energy = get_tree().get_first_node_in_group("enemy_energy")

	if enemy_base == null or not is_instance_valid(enemy_base):
		if world_grid != null and is_instance_valid(world_grid):
			enemy_base = world_grid.get_node_or_null("EnemyBase") as Node2D


func _get_rain_payment_source(amount: float) -> StringName:
	var safe_cost := maxf(amount, 0.0)

	if (
		enemy_energy != null
		and is_instance_valid(enemy_energy)
		and enemy_energy.has_method("can_spend")
		and bool(enemy_energy.call("can_spend", safe_cost))
	):
		return RAIN_PAYMENT_ORDINARY

	if can_spend_combat_reserve(safe_cost):
		return RAIN_PAYMENT_RESERVE

	return RAIN_PAYMENT_NONE


func _spend_rain_energy(payment_source: StringName, amount: float) -> bool:
	var safe_cost := maxf(amount, 0.0)

	match payment_source:
		RAIN_PAYMENT_ORDINARY:
			return (
				enemy_energy != null
				and is_instance_valid(enemy_energy)
				and enemy_energy.has_method("spend")
				and bool(enemy_energy.call("spend", safe_cost))
			)
		RAIN_PAYMENT_RESERVE:
			if not can_spend_combat_reserve(safe_cost):
				return false
			combat_reserve = maxf(combat_reserve - safe_cost, 0.0)
			PerformanceStats.add_counter("enemy_rain_reserve_spent", roundi(safe_cost))
			return true

	return false


func _refund_rain_energy(payment_source: StringName, amount: float) -> void:
	var safe_amount := maxf(amount, 0.0)

	match payment_source:
		RAIN_PAYMENT_ORDINARY:
			if enemy_energy != null and enemy_energy.has_method("add_energy"):
				enemy_energy.call("add_energy", safe_amount)
		RAIN_PAYMENT_RESERVE:
			combat_reserve = minf(
				combat_reserve + safe_amount,
				_get_combat_reserve_capacity()
			)


func _format_rain_payment_source(payment_source: StringName) -> String:
	if payment_source == RAIN_PAYMENT_RESERVE:
		return "резерв"
	return "обычная энка"


func _reset_combat_reserve_for_new_session() -> void:
	combat_reserve = 0.0
	combat_reserve_capacity = 0.0
	next_combat_reserve_capacity_tick_minute = _get_first_combat_reserve_capacity_tick_minute()
	last_combat_reserve_income_deposit = 0.0


func _update_combat_reserve_capacity_from_match_time() -> void:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		_refresh_runtime_references()

	_advance_combat_reserve_capacity_to_elapsed(_get_enemy_elapsed_simulation_seconds())


func _advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds: float) -> void:
	var first_tick_minute := _get_first_combat_reserve_capacity_tick_minute()

	if next_combat_reserve_capacity_tick_minute < first_tick_minute:
		next_combat_reserve_capacity_tick_minute = first_tick_minute

	var elapsed_full_minutes := maxi(
		int(floor(maxf(elapsed_simulation_seconds, 0.0) / 60.0)),
		0
	)
	var safe_maximum := _get_combat_reserve_maximum()

	while next_combat_reserve_capacity_tick_minute <= elapsed_full_minutes:
		var gain := _get_combat_reserve_capacity_gain_for_tick(
			next_combat_reserve_capacity_tick_minute
		)
		combat_reserve_capacity = minf(
			combat_reserve_capacity + gain,
			safe_maximum
		)
		next_combat_reserve_capacity_tick_minute += 1

	combat_reserve = minf(combat_reserve, combat_reserve_capacity)


func _get_enemy_elapsed_simulation_seconds() -> float:
	if (
		enemy_ai != null
		and is_instance_valid(enemy_ai)
		and enemy_ai.has_method("get_elapsed_simulation_seconds")
	):
		return maxf(
			float(enemy_ai.call("get_elapsed_simulation_seconds")),
			0.0
		)

	return 0.0


func _get_first_combat_reserve_capacity_tick_minute() -> int:
	return maxi(combat_reserve_unlock_minutes, 0)


func _get_combat_reserve_capacity_gain_for_tick(tick_minute: int) -> float:
	var late_rate_after := maxi(
		combat_reserve_late_rate_after_minutes,
		maxi(combat_reserve_unlock_minutes, 0)
	)

	if tick_minute > late_rate_after:
		return maxf(combat_reserve_capacity_late_gain_per_minute, 0.0)

	return maxf(combat_reserve_capacity_gain_per_minute, 0.0)


func _get_combat_reserve_maximum() -> float:
	return maxf(combat_reserve_maximum, 0.0)


func _get_combat_reserve_capacity() -> float:
	return clampf(
		combat_reserve_capacity,
		0.0,
		_get_combat_reserve_maximum()
	)


func _get_combat_reserve_minimum_after_cast() -> float:
	return clampf(
		combat_reserve_minimum_after_cast,
		0.0,
		_get_combat_reserve_maximum()
	)


func get_save_data() -> Dictionary:
	_update_combat_reserve_capacity_from_match_time()
	return {
		"combat_reserve_save_version": COMBAT_RESERVE_SAVE_VERSION,
		"combat_reserve": get_combat_reserve(),
		"combat_reserve_capacity": get_combat_reserve_capacity(),
		"next_combat_reserve_capacity_tick_minute": next_combat_reserve_capacity_tick_minute
	}


func restore_save_data(saved_data: Dictionary) -> void:
	_refresh_runtime_references()
	var elapsed_simulation_seconds := _get_enemy_elapsed_simulation_seconds()
	var saved_version := int(saved_data.get("combat_reserve_save_version", 0))

	_reset_combat_reserve_for_new_session()

	if saved_version >= COMBAT_RESERVE_SAVE_VERSION:
		combat_reserve_capacity = clampf(
			float(saved_data.get("combat_reserve_capacity", 0.0)),
			0.0,
			_get_combat_reserve_maximum()
		)
		var default_next_tick := maxi(
			int(floor(elapsed_simulation_seconds / 60.0)) + 1,
			_get_first_combat_reserve_capacity_tick_minute()
		)
		next_combat_reserve_capacity_tick_minute = maxi(
			int(saved_data.get(
				"next_combat_reserve_capacity_tick_minute",
				default_next_tick
			)),
			_get_first_combat_reserve_capacity_tick_minute()
		)
		_advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds)
		combat_reserve = clampf(
			float(saved_data.get("combat_reserve", 0.0)),
			0.0,
			_get_combat_reserve_capacity()
		)
	else:
		# The previous reserve prototype created energy from elapsed time. Its saved
		# amount is intentionally discarded; only the capacity is rebuilt.
		_advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds)
		combat_reserve = 0.0


func deposit_combat_reserve_income(amount: float) -> float:
	_update_combat_reserve_capacity_from_match_time()
	last_combat_reserve_income_deposit = 0.0
	var safe_amount := maxf(amount, 0.0)
	var available_space := maxf(
		_get_combat_reserve_capacity() - combat_reserve,
		0.0
	)

	if safe_amount <= 0.0 or available_space <= 0.0:
		return 0.0

	last_combat_reserve_income_deposit = minf(safe_amount, available_space)
	combat_reserve += last_combat_reserve_income_deposit
	PerformanceStats.add_counter(
		"enemy_combat_reserve_income",
		roundi(last_combat_reserve_income_deposit)
	)
	return last_combat_reserve_income_deposit


func get_combat_reserve() -> float:
	return clampf(combat_reserve, 0.0, _get_combat_reserve_capacity())


func get_combat_reserve_capacity() -> float:
	_update_combat_reserve_capacity_from_match_time()
	return _get_combat_reserve_capacity()


func get_combat_reserve_maximum() -> float:
	return _get_combat_reserve_maximum()


func get_combat_reserve_minimum_after_cast() -> float:
	return _get_combat_reserve_minimum_after_cast()


func get_next_combat_reserve_capacity_tick_minute() -> int:
	return maxi(
		next_combat_reserve_capacity_tick_minute,
		_get_first_combat_reserve_capacity_tick_minute()
	)


func get_next_combat_reserve_capacity_gain() -> float:
	return _get_combat_reserve_capacity_gain_for_tick(
		get_next_combat_reserve_capacity_tick_minute()
	)


func get_seconds_until_next_combat_reserve_capacity_tick() -> float:
	var next_tick_seconds := float(
		get_next_combat_reserve_capacity_tick_minute()
	) * 60.0
	return maxf(next_tick_seconds - _get_enemy_elapsed_simulation_seconds(), 0.0)


func is_combat_reserve_unlocked() -> bool:
	return _get_enemy_elapsed_simulation_seconds() >= (
		float(maxi(combat_reserve_unlock_minutes, 0)) * 60.0
	)


func can_spend_combat_reserve(amount: float) -> bool:
	_update_combat_reserve_capacity_from_match_time()
	var safe_cost := maxf(amount, 0.0)
	return combat_reserve + 0.001 >= safe_cost


# Call this only after a combat spell has applied successfully. Stored reserve
# energy pays the exact cost and may reach zero. The capacity loses the same
# amount but keeps its configured floor, then resumes normal minute growth.
func spend_combat_reserve_after_success(amount: float) -> bool:
	var safe_cost := maxf(amount, 0.0)

	if safe_cost <= 0.0 or not can_spend_combat_reserve(safe_cost):
		return false

	combat_reserve = maxf(combat_reserve - safe_cost, 0.0)
	combat_reserve_capacity = clampf(
		maxf(
			combat_reserve_capacity - safe_cost,
			_get_combat_reserve_minimum_after_cast()
		),
		0.0,
		_get_combat_reserve_maximum()
	)
	combat_reserve = minf(combat_reserve, combat_reserve_capacity)
	PerformanceStats.add_counter("enemy_combat_reserve_spent", roundi(safe_cost))
	PerformanceStats.add_counter("enemy_combat_reserve_capacity_spent", roundi(safe_cost))
	PerformanceStats.add_counter("enemy_combat_spell_casts")
	return true


func _reset_last_search_stats() -> void:
	last_rain_target_tile = INVALID_TILE
	last_grass_entries_scanned = 0
	last_mature_grass_count = 0
	last_spread_ready_grass_count = 0
	last_productive_grass_count = 0
	last_unique_spawn_target_count = 0
	last_adjacent_dry_ground_count = 0
	last_candidate_center_count = 0
	last_best_predicted_new_grass = 0
	last_best_dry_ground_zero_hit_count = 0
	last_best_dry_ground_one_hit_count = 0
	last_best_dry_ground_two_hit_count = 0
	last_best_dry_ground_score = 0
	last_rain_initial_priority_phase_active = _is_rain_initial_priority_phase_active()
	last_rain_expansion_phase_active = _is_rain_expansion_phase_active()
	last_eligible_herbivore_count = 0
	last_best_near_herbivore_count = 0
	last_best_medium_herbivore_count = 0
	last_best_far_herbivore_count = 0
	last_best_herbivore_demand = 0.0
	last_best_demand_multiplier = _get_herbivore_demand_multiplier(0.0)
	last_best_base_distance_tiles = _get_base_proximity_reference_distance_tiles()
	last_best_base_proximity_multiplier = 1.0
	last_best_base_score = 0
	last_best_total_score = 0.0
	last_actual_new_grass = 0
	last_search_duration_usec = 0
	last_apply_duration_usec = 0


func get_last_action_text() -> String:
	return last_action_text


func get_last_rain_target_tile() -> Vector2i:
	return last_rain_target_tile


func get_last_grass_entries_scanned() -> int:
	return last_grass_entries_scanned


func get_last_mature_grass_count() -> int:
	return last_mature_grass_count


func get_last_spread_ready_grass_count() -> int:
	return last_spread_ready_grass_count


func get_last_productive_grass_count() -> int:
	return last_productive_grass_count


func get_last_unique_spawn_target_count() -> int:
	return last_unique_spawn_target_count


func get_last_candidate_center_count() -> int:
	return last_candidate_center_count


func get_last_best_predicted_new_grass() -> int:
	return last_best_predicted_new_grass


func get_last_search_duration_msec() -> float:
	return float(last_search_duration_usec) / 1000.0


func get_max_search_duration_msec() -> float:
	return float(max_search_duration_usec) / 1000.0


func get_total_search_count() -> int:
	return total_search_count


func _get_enemy_energy_debug_value(method_name: StringName) -> float:
	if (
		enemy_energy != null
		and is_instance_valid(enemy_energy)
		and enemy_energy.has_method(method_name)
	):
		return maxf(float(enemy_energy.call(method_name)), 0.0)
	return 0.0


func get_rain_debug_data() -> Dictionary:
	_update_combat_reserve_capacity_from_match_time()
	var active_dry_ground_scores := _get_active_dry_ground_scores(
		last_rain_expansion_phase_active
	)
	var active_base_proximity_step := _get_active_base_proximity_multiplier_step(
		last_rain_initial_priority_phase_active,
		last_rain_expansion_phase_active
	)
	var active_herbivore_demand_step := _get_active_herbivore_demand_multiplier_step(
		last_rain_initial_priority_phase_active
	)
	return {
		"action_text": last_action_text,
		"lightning_action_text": last_lightning_action_text,
		"lightning_sequence_active": lightning_sequence_active,
		"lightning_target_species": String(last_lightning_target_species),
		"lightning_target_health": last_lightning_target_health,
		"lightning_target_base_distance": last_lightning_target_base_distance,
		"lightning_nearby_raptor_count": last_lightning_nearby_raptor_count,
		"lightning_energy_cost": _get_lightning_cost(),
		"earthquake_action_text": last_earthquake_action_text,
		"earthquake_energy_cost": _get_earthquake_cost(),
		"earthquake_target_tile": last_earthquake_target_tile,
		"earthquake_target_egg_count": last_earthquake_target_egg_count,
		"earthquake_target_value": last_earthquake_target_value,
		"earthquake_target_stage_2_count": last_earthquake_target_stage_2_count,
		"earthquake_candidate_center_count": last_earthquake_candidate_center_count,
		"combat_reserve": get_combat_reserve(),
		"combat_reserve_capacity": get_combat_reserve_capacity(),
		"combat_reserve_maximum": get_combat_reserve_maximum(),
		"combat_reserve_minimum_after_cast": get_combat_reserve_minimum_after_cast(),
		"combat_reserve_unlocked": is_combat_reserve_unlocked(),
		"combat_reserve_next_capacity_tick_minute": get_next_combat_reserve_capacity_tick_minute(),
		"combat_reserve_next_capacity_gain": get_next_combat_reserve_capacity_gain(),
		"combat_reserve_seconds_until_next_capacity_tick": get_seconds_until_next_combat_reserve_capacity_tick(),
		"combat_reserve_last_income_deposit": last_combat_reserve_income_deposit,
		"enemy_income_per_second": _get_enemy_energy_debug_value("get_income_per_second"),
		"combat_reserve_income_threshold_per_second": _get_enemy_energy_debug_value("get_combat_reserve_income_threshold_per_second"),
		"combat_reserve_income_share": _get_enemy_energy_debug_value("get_combat_reserve_income_share"),
		"enemy_last_income_to_ordinary_energy": _get_enemy_energy_debug_value("get_last_income_to_ordinary_energy"),
		"grass_entries_scanned": last_grass_entries_scanned,
		"mature_grass_count": last_mature_grass_count,
		"spread_ready_grass_count": last_spread_ready_grass_count,
		"productive_grass_count": last_productive_grass_count,
		"unique_spawn_target_count": last_unique_spawn_target_count,
		"adjacent_dry_ground_count": last_adjacent_dry_ground_count,
		"candidate_center_count": last_candidate_center_count,
		"best_predicted_new_grass": last_best_predicted_new_grass,
		"best_dry_ground_zero_hit_count": last_best_dry_ground_zero_hit_count,
		"best_dry_ground_one_hit_count": last_best_dry_ground_one_hit_count,
		"best_dry_ground_two_hit_count": last_best_dry_ground_two_hit_count,
		"best_dry_ground_score": last_best_dry_ground_score,
		"eligible_herbivore_count": last_eligible_herbivore_count,
		"best_near_herbivore_count": last_best_near_herbivore_count,
		"best_medium_herbivore_count": last_best_medium_herbivore_count,
		"best_far_herbivore_count": last_best_far_herbivore_count,
		"best_herbivore_demand": last_best_herbivore_demand,
		"best_demand_multiplier": last_best_demand_multiplier,
		"best_base_distance_tiles": last_best_base_distance_tiles,
		"best_base_proximity_multiplier": last_best_base_proximity_multiplier,
		"best_base_score": last_best_base_score,
		"best_total_score": last_best_total_score,
		"new_grass_score": maxi(new_grass_score, 0),
		"dry_ground_zero_hit_score": active_dry_ground_scores[0],
		"dry_ground_one_hit_score": active_dry_ground_scores[1],
		"dry_ground_two_hit_score": active_dry_ground_scores[2],
		"rain_expansion_phase_active": last_rain_expansion_phase_active,
		"rain_expansion_phase_start_seconds": maxf(
			rain_expansion_phase_start_seconds,
			0.0
		),
		"rain_initial_priority_phase_active": last_rain_initial_priority_phase_active,
		"rain_initial_priority_phase_duration_seconds": maxf(
			rain_initial_priority_phase_duration_seconds,
			0.0
		),
		"empty_area_score_multiplier": maxf(empty_area_score_multiplier, 0.0),
		"herbivore_demand_multiplier_step": active_herbivore_demand_step,
		"maximum_herbivore_score_multiplier": maxf(
			maximum_herbivore_score_multiplier,
			maxf(empty_area_score_multiplier, 0.0)
		),
		"herbivore_near_distance_tiles": _get_near_herbivore_distance_tiles(),
		"herbivore_medium_distance_tiles": _get_medium_herbivore_distance_tiles(),
		"herbivore_far_distance_tiles": _get_far_herbivore_distance_tiles(),
		"base_proximity_reference_distance_tiles": _get_base_proximity_reference_distance_tiles(),
		"base_proximity_multiplier_step": active_base_proximity_step,
		"actual_new_grass": last_actual_new_grass,
		"prediction_gap": last_best_predicted_new_grass - last_actual_new_grass,
		"search_duration_msec": get_last_search_duration_msec(),
		"max_search_duration_msec": get_max_search_duration_msec(),
		"total_search_count": total_search_count,
		"apply_duration_msec": float(last_apply_duration_usec) / 1000.0,
		"max_apply_duration_msec": float(max_apply_duration_usec) / 1000.0,
		"total_apply_count": total_apply_count,
		"search_radius_tiles": maxi(rain_search_radius_tiles, 0),
		"rain_frame_duration_seconds": maxf(rain_area_frame_duration_seconds, 0.0)
	}


func get_rain_energy_cost() -> float:
	return maxf(rain_energy_cost, 0.0)


func _format_tile(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]
