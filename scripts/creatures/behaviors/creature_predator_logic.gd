extends RefCounted

const Duel = preload("res://scripts/combat/duel.gd")
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const TARGET_RECHECK_INTERVAL := 2.0
const TARGET_RECHECK_JITTER := 0.2
const TIMER_JITTER_BUCKET_COUNT := 401
const TIMER_JITTER_MULTIPLIER := 97
const INTERVENTION_RECHECK_INTERVAL := 0.5
const FAILED_TARGET_RECHECK_INTERVAL := 3.0
const TARGET_SWITCH_ADVANTAGE_STEPS := 2
const TARGET_CANDIDATE_LIMIT := 3
const APPROACH_RECHECK_DISTANCE := 4
const PLAYER_FLAG_COMMITMENT_META := &"player_flag_committed_revision"
const ENEMY_FLAG_COMMITMENT_META := &"enemy_flag_committed_revision"

enum HuntMode {
	NONE,
	STRATEGIC,
	DEFENSE,
	HUNGER
}

var creature: Node
var target_prey: Node = null
var target_recheck_remaining := 0.0
var failed_prey_recheck_remaining: Dictionary = {}
var approach_recheck_done := false
var locked_approach_anchor := Vector2i.ZERO
var has_locked_approach := false
var has_hunt_route := false
var hunt_mode: HuntMode = HuntMode.NONE
var intervention_duel: Duel = null
var intervention_protected_creature: Node = null
var intervention_attacker: Node = null
var intervention_reserved := false
var intervention_recheck_remaining := 0.0


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func _get_staggered_target_recheck_interval() -> float:
	var owner_bucket := posmod(
		int(creature.get_instance_id()),
		TIMER_JITTER_BUCKET_COUNT
	)
	var jitter_bucket := posmod(
		owner_bucket * TIMER_JITTER_MULTIPLIER,
		TIMER_JITTER_BUCKET_COUNT
	)
	var jitter_phase := float(jitter_bucket) / float(TIMER_JITTER_BUCKET_COUNT - 1)
	return TARGET_RECHECK_INTERVAL + lerpf(
		-TARGET_RECHECK_JITTER,
		TARGET_RECHECK_JITTER,
		jitter_phase
	)


func is_hunting() -> bool:
	return (
		is_instance_valid(target_prey)
		and creature.state != creature.State.COMBAT
		and creature.state != creature.State.DEAD
	)


func get_hunt_target() -> Node:
	return target_prey if is_instance_valid(target_prey) else null


func cancel_hunt_target() -> void:
	_clear_intervention()
	_clear_hunt_target()
	hunt_mode = HuntMode.NONE


func should_hold_at_locked_approach() -> bool:
	return (
		is_instance_valid(target_prey)
		and has_locked_approach
		and creature.anchor_tile == locked_approach_anchor
		and _remaining_route_steps() == 0
	)


func should_engage_target() -> bool:
	return (
		is_instance_valid(target_prey)
		and has_locked_approach
		and creature.is_moving
		and creature.pending_anchor_tile == locked_approach_anchor
		and _remaining_route_steps() == 1
		and _is_locked_approach_adjacent_to_target()
	)


func _is_locked_approach_adjacent_to_target() -> bool:
	if (
		creature.world_grid == null
		or not is_instance_valid(target_prey)
		or not creature.world_grid.creature_anchors.has(target_prey)
	):
		return false

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[target_prey]
	return are_footprints_side_adjacent(
		locked_approach_anchor,
		creature.footprint_size,
		prey_anchor,
		target_prey.footprint_size
	)


func update_predator_behavior(delta: float) -> void:
	if creature.species_data.is_predator():
		PerformanceStats.add_counter("predator_behavior_ticks")

	if not creature.species_data.is_predator() or creature.world_grid == null:
		_clear_hunt_target()
		hunt_mode = HuntMode.NONE
		return

	if (
		creature.state == creature.State.DEAD
		or creature.state == creature.State.EATING
		or creature.state == creature.State.LAYING_EGG
		or creature.state == creature.State.COMBAT
	):
		return

	_update_failed_prey_cooldowns(delta)

	var desired_mode := _get_desired_hunt_mode()

	if desired_mode == HuntMode.NONE:
		_clear_intervention()
		_clear_hunt_target()
		hunt_mode = HuntMode.NONE
		return

	if desired_mode == HuntMode.STRATEGIC and _strategic_hunt_is_preempted():
		_cancel_strategic_hunt(_has_active_flag_commitment())
		return

	if intervention_duel != null and _update_intervention_behavior():
		return

	if (
		creature.species_data.is_attacking_predator()
		and is_instance_valid(target_prey)
		and target_prey.get("current_duel") != null
	):
		if _try_acquire_intervention():
			return

	if hunt_mode != desired_mode:
		_clear_intervention()
		_clear_hunt_target()
		hunt_mode = desired_mode

	if desired_mode == HuntMode.DEFENSE:
		intervention_recheck_remaining -= delta

		if intervention_recheck_remaining <= 0.0:
			intervention_recheck_remaining = INTERVENTION_RECHECK_INTERVAL

			if _try_acquire_intervention():
				return

	var pending_prey: Node = creature.get_pending_duel_opponent()

	if pending_prey != null:
		_resolve_pending_duel(pending_prey)
		return

	# A dead/removed prey or a prey already engaged by another hunter is released
	# immediately. The same update may then select a different target.
	if target_prey != null and not _has_valid_hunt_target():
		_clear_hunt_target()

	if target_prey == null:
		target_recheck_remaining -= delta

		if target_recheck_remaining <= 0.0:
			_acquire_hunt_target()

		if target_prey == null:
			return
	elif not _is_target_engaged_by_creature():
		target_recheck_remaining -= delta

		if target_recheck_remaining <= 0.0:
			_recheck_hunt_target()
			target_recheck_remaining = _get_staggered_target_recheck_interval()

	if not is_instance_valid(target_prey):
		_clear_hunt_target()
		return

	if is_prey_in_duel_range(target_prey):
		if creature.is_moving or bool(target_prey.get("is_moving")):
			_begin_duel_settlement(target_prey)
			return

		start_duel_with(target_prey)
		return

	if should_engage_target() and not _begin_target_engagement():
		# Another hunter won the engagement race. Drop this route and immediately
		# look for another available prey instead of waiting for the next interval.
		_clear_hunt_target()
		_acquire_hunt_target()
		return

	if _is_target_engaged_by_creature():
		if should_abort_target_engagement():
			_cancel_target_engagement()
			return

		if should_hold_at_locked_approach():
			_clear_hunt_target()
			return

		if creature.is_moving:
			return

		if _remaining_route_steps() > 0:
			creature.start_next_path_step_if_needed()
		return

	if _should_recheck_approach_side():
		_refresh_approach_path()

	if creature.is_moving:
		return

	if _remaining_route_steps() == 0:
		if creature.predator_path_retry_cooldown_remaining <= 0.0:
			_refresh_approach_path()

			if _remaining_route_steps() == 0:
				# The locked target currently has no reachable approach side.
				creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval
		return

	creature.start_next_path_step_if_needed()


func _get_desired_hunt_mode() -> HuntMode:
	if creature.hunger <= creature.species_data.hunger_search_threshold:
		return HuntMode.HUNGER

	if creature.species_data.is_defensive_predator():
		return HuntMode.DEFENSE

	if (
		creature.species_data.is_attacking_predator()
		and creature.hunger <= creature.species_data.strategic_hunt_threshold
	):
		return HuntMode.STRATEGIC

	return HuntMode.NONE


func _strategic_hunt_is_preempted() -> bool:
	if (
		_has_active_flag_commitment()
		and not creature.species_data.strategic_hunt_overrides_flag
	):
		return true

	return (
		creature.reproduction_logic != null
		and creature.reproduction_logic.has_method("has_reproduction_priority_over_strategic_hunt")
		and bool(creature.reproduction_logic.call("has_reproduction_priority_over_strategic_hunt"))
	)


func _has_active_flag_commitment() -> bool:
	return (
		creature.has_meta(PLAYER_FLAG_COMMITMENT_META)
		or creature.has_meta(ENEMY_FLAG_COMMITMENT_META)
	)


func _cancel_strategic_hunt(preserve_current_route: bool) -> void:
	var pending_prey: Node = creature.get_pending_duel_opponent()

	if pending_prey != null:
		_cancel_duel_settlement(pending_prey)

	_clear_intervention()
	_clear_hunt_target(preserve_current_route)
	hunt_mode = HuntMode.NONE


func _has_valid_hunt_target() -> bool:
	if not is_instance_valid(target_prey):
		return false

	if not target_prey.has_method("can_be_hunted") or not target_prey.can_be_hunted():
		return false

	if _is_prey_claimed_by_other_hunter(target_prey):
		return false

	if target_prey.has_method("get_pending_duel_opponent"):
		var pending_opponent: Node = target_prey.get_pending_duel_opponent()

		if pending_opponent != null and pending_opponent != creature:
			return false

	return _is_allowed_prey_for_current_mode(target_prey)


func _is_allowed_prey_for_current_mode(candidate: Node) -> bool:
	var candidate_species := candidate.get("species_data") as CreatureSpeciesData

	if candidate_species == null:
		return false

	if hunt_mode == HuntMode.STRATEGIC:
		return _is_opposing_player_enemy_faction(candidate)

	if hunt_mode == HuntMode.DEFENSE:
		return _is_opposing_player_enemy_faction(candidate)

	if hunt_mode == HuntMode.HUNGER and creature.species_data.is_attacking_predator():
		return not _is_same_species_and_faction(candidate, candidate_species)

	if hunt_mode == HuntMode.HUNGER and creature.species_data.is_defensive_predator():
		if candidate_species.is_herbivore():
			return true

		if candidate_species.is_predator() or candidate_species.is_egg_eater():
			return not _is_same_faction(candidate)

		return false

	if hunt_mode != HuntMode.HUNGER:
		return false

	if candidate_species.is_predator() or candidate_species.is_egg_eater():
		return _is_opposing_player_enemy_faction(candidate)

	return true


func can_intervene_in_duel(duel: Duel, protected_creature: Node) -> bool:
	if (
		duel == null
		or not is_instance_valid(duel)
		or not duel.can_accept_intervention()
		or protected_creature == null
		or not is_instance_valid(protected_creature)
		or protected_creature == duel.initiator
		or (protected_creature != duel.fighter_a and protected_creature != duel.fighter_b)
	):
		return false

	var protected_species := protected_creature.get("species_data") as CreatureSpeciesData

	if (
		protected_species == null
		or (not protected_species.is_herbivore() and not protected_species.is_egg_eater())
		or not _is_same_faction(protected_creature)
	):
		return false

	var attacker: Node = duel.fighter_b if duel.fighter_a == protected_creature else duel.fighter_a
	var attacker_species := attacker.get("species_data") as CreatureSpeciesData
	var role_can_intervene: bool = (
		(
			creature.species_data.is_defensive_predator()
			and creature.hunger > creature.species_data.hunger_search_threshold
		)
		or (
			creature.species_data.is_attacking_predator()
			and target_prey == attacker
		)
	)

	return (
		role_can_intervene
		and attacker == duel.initiator
		and attacker_species != null
		and attacker_species.is_predator()
		and _is_opposing_player_enemy_faction(attacker)
	)


func _try_acquire_intervention() -> bool:
	if creature.world_grid == null:
		return false

	var origin_anchor: Vector2i = creature.get_navigation_anchor()
	var best_plan: Dictionary = {}
	var best_route_steps := 2147483647

	for candidate_variant: Variant in creature.world_grid.creature_anchors.keys():
		if not (candidate_variant is Node):
			continue

		var protected_creature := candidate_variant as Node
		var candidate_duel := protected_creature.get("current_duel") as Duel

		if not can_intervene_in_duel(candidate_duel, protected_creature):
			continue

		var attacker: Node = (
			candidate_duel.fighter_b
			if candidate_duel.fighter_a == protected_creature
			else candidate_duel.fighter_a
		)
		var attacker_anchor: Vector2i = creature.world_grid.creature_anchors.get(
			attacker,
			origin_anchor
		)

		if creature.species_data.is_defensive_predator():
			var active_radius := maxi(int(creature.species_data.defensive_hunt_radius), 0)

			if creature.world_grid.estimate_path_steps(origin_anchor, attacker_anchor) > active_radius:
				continue

		var plan := _find_best_approach_plan(attacker, origin_anchor)

		if plan.is_empty():
			continue

		var path: Array = plan.get("path", []) as Array

		if path.size() >= best_route_steps:
			continue

		best_route_steps = path.size()
		best_plan = plan
		best_plan["duel"] = candidate_duel
		best_plan["protected_creature"] = protected_creature
		best_plan["attacker"] = attacker

	if best_plan.is_empty():
		return false

	_commit_intervention_plan(best_plan)
	return true


func _commit_intervention_plan(plan: Dictionary) -> void:
	_clear_hunt_target()
	intervention_duel = plan.get("duel", null) as Duel
	intervention_protected_creature = plan.get("protected_creature", null) as Node
	intervention_attacker = plan.get("attacker", null) as Node
	intervention_reserved = false
	target_prey = intervention_attacker
	locked_approach_anchor = plan.get("approach_anchor", Vector2i.ZERO)
	has_locked_approach = bool(plan.get("has_approach", false))
	has_hunt_route = true
	_replace_predator_route(plan.get("path", []) as Array)


func _update_intervention_behavior() -> bool:
	if not _is_intervention_target_valid():
		_clear_intervention()
		_clear_hunt_target()
		return false

	var reserver: Node = intervention_duel.get_intervention_reserver()

	if reserver != null and reserver != creature:
		_clear_intervention()
		_clear_hunt_target()
		return false

	if intervention_reserved:
		return reserver == creature

	if creature.is_moving:
		return true

	if _is_prey_in_duel_range_from_anchor(intervention_attacker, creature.anchor_tile):
		if intervention_duel.reserve_intervention(creature, intervention_protected_creature):
			intervention_reserved = true
			has_hunt_route = false
			_clear_predator_route()
			creature.face_target(intervention_attacker)
			return true

		_clear_intervention()
		_clear_hunt_target()
		return false

	if _remaining_route_steps() == 0:
		if creature.predator_path_retry_cooldown_remaining <= 0.0:
			var plan := _find_best_approach_plan(
				intervention_attacker,
				creature.get_navigation_anchor()
			)

			if plan.is_empty():
				creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval
				return true

			locked_approach_anchor = plan.get("approach_anchor", Vector2i.ZERO)
			has_locked_approach = bool(plan.get("has_approach", false))
			has_hunt_route = true
			_replace_predator_route(plan.get("path", []) as Array)

	if _remaining_route_steps() > 0:
		creature.start_next_path_step_if_needed()

	return true


func _is_intervention_target_valid() -> bool:
	if (
		intervention_duel == null
		or not is_instance_valid(intervention_duel)
		or not intervention_duel.is_active
		or not is_instance_valid(intervention_protected_creature)
		or not is_instance_valid(intervention_attacker)
		or intervention_protected_creature.get("current_duel") != intervention_duel
		or intervention_attacker.get("current_duel") != intervention_duel
	):
		return false

	var protected_species := intervention_protected_creature.get("species_data") as CreatureSpeciesData
	var attacker_species := intervention_attacker.get("species_data") as CreatureSpeciesData
	var role_can_intervene: bool = (
		(
			creature.species_data.is_defensive_predator()
			and creature.hunger > creature.species_data.hunger_search_threshold
		)
		or (
			creature.species_data.is_attacking_predator()
			and target_prey == intervention_attacker
		)
	)

	return (
		role_can_intervene
		and protected_species != null
		and (protected_species.is_herbivore() or protected_species.is_egg_eater())
		and attacker_species != null
		and attacker_species.is_predator()
		and intervention_duel.initiator == intervention_attacker
		and _is_same_faction(intervention_protected_creature)
		and _is_opposing_player_enemy_faction(intervention_attacker)
	)


func _clear_intervention() -> void:
	if (
		is_instance_valid(intervention_duel)
		and intervention_duel.get_intervention_reserver() == creature
	):
		intervention_duel.cancel_intervention(creature)

	intervention_duel = null
	intervention_protected_creature = null
	intervention_attacker = null
	intervention_reserved = false


func complete_duel_intervention(attacker: Node, completed_duel: Duel) -> void:
	if completed_duel != intervention_duel or attacker != intervention_attacker:
		return

	intervention_duel = null
	intervention_protected_creature = null
	intervention_attacker = null
	intervention_reserved = false
	start_duel_with(attacker, false)


func _is_opposing_player_enemy_faction(candidate: Node) -> bool:
	var hunter_faction := CREATURE_FACTION.get_id(creature)
	var candidate_faction := CREATURE_FACTION.get_id(candidate)
	return (
		(hunter_faction == CREATURE_FACTION.PLAYER and candidate_faction == CREATURE_FACTION.ENEMY)
		or (hunter_faction == CREATURE_FACTION.ENEMY and candidate_faction == CREATURE_FACTION.PLAYER)
	)


func _is_same_faction(candidate: Node) -> bool:
	return CREATURE_FACTION.get_id(creature) == CREATURE_FACTION.get_id(candidate)


func _is_same_species_and_faction(
	candidate: Node,
	candidate_species: CreatureSpeciesData
) -> bool:
	return (
		StringName(creature.species_data.species_id) == StringName(candidate_species.species_id)
		and CREATURE_FACTION.get_id(creature) == CREATURE_FACTION.get_id(candidate)
	)


func _is_prey_claimed_by_other_hunter(prey: Node) -> bool:
	if not is_instance_valid(prey) or not prey.has_method("get_combat_engagement_hunter"):
		return false

	var engagement_hunter: Node = prey.get_combat_engagement_hunter()
	return engagement_hunter != null and engagement_hunter != creature


func _is_target_engaged_by_creature() -> bool:
	return (
		is_instance_valid(target_prey)
		and target_prey.has_method("get_combat_engagement_hunter")
		and target_prey.get_combat_engagement_hunter() == creature
	)


func should_abort_target_engagement() -> bool:
	return (
		_is_target_engaged_by_creature()
		and not creature.is_moving
		and _remaining_route_steps() == 0
		and creature.anchor_tile != locked_approach_anchor
	)


func _cancel_target_engagement() -> void:
	if is_instance_valid(target_prey) and target_prey.has_method("cancel_combat_engagement"):
		target_prey.cancel_combat_engagement(creature)


func _begin_target_engagement() -> bool:
	if (
		not is_instance_valid(target_prey)
		or _is_prey_claimed_by_other_hunter(target_prey)
		or not target_prey.has_method("begin_combat_engagement")
	):
		return false

	target_prey.begin_combat_engagement(creature)
	return _is_target_engaged_by_creature()


func _clear_hunt_target(preserve_current_route: bool = false) -> void:
	if is_instance_valid(target_prey) and target_prey.has_method("cancel_combat_engagement"):
		target_prey.cancel_combat_engagement(creature)

	target_prey = null
	target_recheck_remaining = 0.0
	approach_recheck_done = false
	locked_approach_anchor = Vector2i.ZERO
	has_locked_approach = false

	if has_hunt_route and not preserve_current_route:
		_clear_predator_route()

	has_hunt_route = false


func _clear_predator_route() -> void:
	if creature.movement_controller != null and creature.movement_controller.has_method("clear_behavior_route"):
		creature.movement_controller.clear_behavior_route()


func _replace_predator_route(path: Array) -> void:
	if creature.movement_controller != null and creature.movement_controller.has_method("replace_behavior_route"):
		creature.movement_controller.replace_behavior_route(path)


func _acquire_hunt_target() -> void:
	# A failed acquisition must not scan the population again every physics frame.
	target_recheck_remaining = _get_staggered_target_recheck_interval()

	var candidates := find_nearest_prey_candidates(TARGET_CANDIDATE_LIMIT)
	var plan := _find_best_hunt_plan(candidates)

	if plan.is_empty():
		return

	_commit_hunt_plan(plan)


func _recheck_hunt_target() -> void:
	var candidates := find_nearest_prey_candidates(
		1,
		target_prey
	)

	if candidates.is_empty() or not _should_build_challenger_plan(candidates[0]):
		return

	var candidate_plan := _find_best_hunt_plan(candidates)

	if candidate_plan.is_empty():
		return

	var candidate_steps := int(candidate_plan.get("route_steps", 0))

	if candidate_steps + TARGET_SWITCH_ADVANTAGE_STEPS > _remaining_route_steps():
		return

	_commit_hunt_plan(candidate_plan)


func _should_build_challenger_plan(candidate: Node) -> bool:
	if candidate == null or not is_valid_prey(candidate):
		return false

	var origin_anchor: Vector2i = creature.get_navigation_anchor()
	var estimated_steps: int = _estimate_best_approach_steps(candidate, origin_anchor)
	return (
		estimated_steps < 2147483647
		and estimated_steps + TARGET_SWITCH_ADVANTAGE_STEPS <= _remaining_route_steps()
	)


func _estimate_best_approach_steps(prey: Node, origin_anchor: Vector2i) -> int:
	if _is_prey_in_duel_range_from_anchor(prey, origin_anchor):
		return 1 if creature.is_moving else 0

	if not creature.world_grid.creature_anchors.has(prey):
		return 2147483647

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	var best_estimate := 2147483647

	for approach_anchor: Vector2i in _build_side_approach_anchors(
		prey_anchor,
		prey.footprint_size
	):
		if not creature.world_grid.can_place_footprint(
			approach_anchor,
			creature.footprint_size,
			creature
		):
			continue

		best_estimate = mini(
			best_estimate,
			int(creature.world_grid.estimate_path_steps(origin_anchor, approach_anchor))
		)

	return best_estimate


func _find_best_hunt_plan(candidates: Array[Node]) -> Dictionary:
	var best_plan: Dictionary = {}
	var best_route_steps := 2147483647
	var origin_anchor: Vector2i = creature.get_navigation_anchor()
	var active_step_count := 1 if creature.is_moving else 0

	for prey: Node in candidates:
		if not is_valid_prey(prey):
			continue

		var plan: Dictionary = {}

		if _is_prey_in_duel_range_from_anchor(prey, origin_anchor):
			plan = {
				"prey": prey,
				"path": [],
				"approach_anchor": origin_anchor,
				"has_approach": true,
				"route_steps": active_step_count
			}
		else:
			plan = _find_best_approach_plan(prey, origin_anchor)

			if plan.is_empty():
				_mark_prey_temporarily_unreachable(prey)
				continue

			var path: Array = plan.get("path", []) as Array
			plan["prey"] = prey
			plan["route_steps"] = path.size() + active_step_count

		var route_steps := int(plan.get("route_steps", 0))

		if route_steps < best_route_steps:
			best_route_steps = route_steps
			best_plan = plan

	return best_plan


func _commit_hunt_plan(plan: Dictionary) -> void:
	var prey := plan.get("prey", null) as Node

	if not is_instance_valid(prey):
		return

	var path: Array = plan.get("path", []) as Array
	var approach_anchor: Vector2i = plan.get("approach_anchor", Vector2i.ZERO)
	var has_approach := bool(plan.get("has_approach", false))
	_commit_hunt_target(prey, path, approach_anchor, has_approach)


func _commit_hunt_target(
	prey: Node,
	path: Array,
	approach_anchor: Vector2i,
	has_approach: bool = true
) -> void:
	target_prey = prey
	target_recheck_remaining = _get_staggered_target_recheck_interval()
	approach_recheck_done = false
	locked_approach_anchor = approach_anchor
	has_locked_approach = has_approach
	has_hunt_route = true
	_replace_predator_route(path)


func _should_recheck_approach_side() -> bool:
	return (
		has_locked_approach
		and not approach_recheck_done
		and _remaining_route_steps() <= APPROACH_RECHECK_DISTANCE
	)


func _refresh_approach_path() -> void:
	if not is_instance_valid(target_prey):
		return

	var plan := _find_best_approach_plan(
		target_prey,
		creature.get_navigation_anchor()
	)

	if not plan.is_empty():
		var path: Array = plan.get("path", []) as Array
		has_hunt_route = true
		_replace_predator_route(path)
		locked_approach_anchor = plan.get("approach_anchor", Vector2i.ZERO)
		has_locked_approach = bool(plan.get("has_approach", false))

	approach_recheck_done = true


func _remaining_route_steps() -> int:
	if (
		creature.movement_controller != null
		and creature.movement_controller.has_method("get_remaining_route_steps")
	):
		return int(creature.movement_controller.get_remaining_route_steps())

	return 1 if creature.is_moving else 0


func _get_active_target_radius() -> int:
	if hunt_mode == HuntMode.DEFENSE and creature.species_data.is_defensive_predator():
		return maxi(int(creature.species_data.defensive_hunt_radius), 0)

	if hunt_mode == HuntMode.STRATEGIC and creature.species_data.is_attacking_predator():
		var strategic_radius := maxi(int(creature.species_data.strategic_hunt_radius), 0)

		if strategic_radius > 0:
			return strategic_radius

	return maxi(int(creature.species_data.predator_target_radius), 0)


func find_nearest_prey() -> Node:
	var candidates := find_nearest_prey_candidates(1)
	return candidates[0] if not candidates.is_empty() else null


func find_nearest_prey_candidates(
	max_candidates: int = TARGET_CANDIDATE_LIMIT,
	excluded_prey: Node = null
) -> Array[Node]:
	PerformanceStats.add_counter("predator_prey_searches")

	var result: Array[Node] = []

	if creature.world_grid == null or max_candidates <= 0:
		return result

	var ranked_candidates: Array[Dictionary] = []
	var candidate_checks := 0
	var origin_anchor: Vector2i = creature.get_navigation_anchor()
	var active_target_radius := _get_active_target_radius()

	for candidate_variant: Variant in creature.world_grid.creature_anchors.keys():
		candidate_checks += 1

		if not (candidate_variant is Node):
			continue

		var candidate := candidate_variant as Node

		if (
			candidate == excluded_prey
			or not is_valid_prey(candidate)
			or _is_prey_temporarily_unreachable(candidate)
		):
			continue

		var candidate_anchor: Vector2i = creature.world_grid.creature_anchors.get(
			candidate,
			creature.anchor_tile
		)
		var distance := int(creature.world_grid.estimate_path_steps(
			origin_anchor,
			candidate_anchor
		))

		if distance > active_target_radius:
			continue

		_insert_ranked_prey_candidate(
			ranked_candidates,
			{"prey": candidate, "distance": distance},
			max_candidates
		)

	PerformanceStats.add_counter("predator_prey_candidates", candidate_checks)

	for candidate_data: Dictionary in ranked_candidates:
		var prey := candidate_data.get("prey", null) as Node

		if is_instance_valid(prey):
			result.append(prey)

	return result


func _mark_prey_temporarily_unreachable(prey: Node) -> void:
	if prey == null or not is_instance_valid(prey):
		return

	failed_prey_recheck_remaining[prey.get_instance_id()] = FAILED_TARGET_RECHECK_INTERVAL


func _is_prey_temporarily_unreachable(prey: Node) -> bool:
	return (
		prey != null
		and is_instance_valid(prey)
		and float(failed_prey_recheck_remaining.get(prey.get_instance_id(), 0.0)) > 0.0
	)


func _update_failed_prey_cooldowns(delta: float) -> void:
	for prey_id: int in failed_prey_recheck_remaining.keys():
		var remaining := float(failed_prey_recheck_remaining.get(prey_id, 0.0)) - delta

		if remaining <= 0.0:
			failed_prey_recheck_remaining.erase(prey_id)
		else:
			failed_prey_recheck_remaining[prey_id] = remaining


func _insert_ranked_prey_candidate(
	ranked_candidates: Array[Dictionary],
	candidate_data: Dictionary,
	max_candidates: int
) -> void:
	var candidate_distance := int(candidate_data.get("distance", 2147483647))
	var insert_index := ranked_candidates.size()

	for index in range(ranked_candidates.size()):
		if candidate_distance < int(ranked_candidates[index].get("distance", 2147483647)):
			insert_index = index
			break

	if insert_index >= max_candidates:
		return

	ranked_candidates.insert(insert_index, candidate_data)

	if ranked_candidates.size() > max_candidates:
		ranked_candidates.resize(max_candidates)


func is_valid_prey(candidate: Node) -> bool:
	if candidate == null or candidate == creature or not is_instance_valid(candidate):
		return false

	if not candidate.has_method("can_be_hunted") or not candidate.can_be_hunted():
		return false

	if candidate.has_method("get_pending_duel_opponent"):
		var pending_opponent: Node = candidate.get_pending_duel_opponent()

		if pending_opponent != null and pending_opponent != creature:
			return false

	if _is_prey_claimed_by_other_hunter(candidate):
		return false

	return _is_allowed_prey_for_current_mode(candidate)


func is_prey_in_duel_range(prey: Node) -> bool:
	return _is_prey_in_duel_range_from_anchor(prey, creature.anchor_tile)


func _is_prey_in_duel_range_from_anchor(prey: Node, hunter_anchor: Vector2i) -> bool:
	if (
		creature.world_grid == null
		or not is_instance_valid(prey)
		or not creature.world_grid.creature_anchors.has(prey)
	):
		return false

	if not creature.world_grid.can_place_footprint(
		hunter_anchor,
		creature.footprint_size,
		creature
	):
		return false

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	return are_footprints_side_adjacent(
		hunter_anchor,
		creature.footprint_size,
		prey_anchor,
		prey.footprint_size
	)


func _resolve_pending_duel(prey: Node) -> void:
	if not is_instance_valid(prey):
		creature.cancel_pending_duel()
		return

	if (
		not prey.has_method("can_be_hunted")
		or not bool(prey.can_be_hunted())
		or not _is_allowed_prey_for_current_mode(prey)
	):
		_cancel_duel_settlement(prey)
		return

	if creature.is_moving or bool(prey.get("is_moving")):
		return

	if is_prey_in_duel_range(prey):
		start_duel_with(prey)
		return

	_cancel_duel_settlement(prey)


func _begin_duel_settlement(prey: Node) -> void:
	if not is_instance_valid(prey):
		return

	creature.begin_duel_settlement(prey)

	if prey.has_method("begin_duel_settlement"):
		prey.begin_duel_settlement(creature)


func _cancel_duel_settlement(prey: Node) -> void:
	creature.cancel_pending_duel(prey)

	if is_instance_valid(prey) and prey.has_method("cancel_pending_duel"):
		prey.cancel_pending_duel(creature)


func are_footprints_side_adjacent(
	a_anchor: Vector2i,
	a_size: Vector2i,
	b_anchor: Vector2i,
	b_size: Vector2i
) -> bool:
	var a_left := a_anchor.x
	var a_right := a_anchor.x + a_size.x - 1
	var a_top := a_anchor.y
	var a_bottom := a_anchor.y + a_size.y - 1
	var b_left := b_anchor.x
	var b_right := b_anchor.x + b_size.x - 1
	var b_top := b_anchor.y
	var b_bottom := b_anchor.y + b_size.y - 1

	var vertical_overlap: int = min(a_bottom, b_bottom) - max(a_top, b_top) + 1

	if vertical_overlap > 0 and (a_right + 1 == b_left or b_right + 1 == a_left):
		return true

	var horizontal_overlap: int = min(a_right, b_right) - max(a_left, b_left) + 1

	if horizontal_overlap > 0 and (a_bottom + 1 == b_top or b_bottom + 1 == a_top):
		return true

	return false


func build_path_to_prey(prey: Node) -> void:
	var plan := _find_best_approach_plan(prey, creature.get_navigation_anchor())

	if plan.is_empty():
		if has_hunt_route:
			_clear_predator_route()
		has_hunt_route = false
		return

	has_hunt_route = true
	_replace_predator_route(plan.get("path", []) as Array)


func _find_best_approach_plan(prey: Node, origin_anchor: Vector2i) -> Dictionary:
	PerformanceStats.add_counter("predator_path_rebuild_requests")

	if (
		creature.world_grid == null
		or not is_instance_valid(prey)
		or not creature.world_grid.creature_anchors.has(prey)
	):
		return {}

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	var ranked_anchors: Array[Vector2i] = []

	for candidate_anchor: Vector2i in _build_side_approach_anchors(
		prey_anchor,
		prey.footprint_size
	):
		if not creature.world_grid.can_place_footprint(
			candidate_anchor,
			creature.footprint_size,
			creature
		):
			continue

		_insert_approach_anchor_by_distance(
			ranked_anchors,
			candidate_anchor,
			origin_anchor
		)

	if ranked_anchors.is_empty():
		return {}

	var result_variant: Variant = creature.world_grid.find_path_to_any(
		origin_anchor,
		ranked_anchors,
		creature.footprint_size,
		creature,
		creature.max_path_search_tiles,
		&"predator"
	)

	if not (result_variant is Dictionary):
		return {}

	var result := result_variant as Dictionary
	var approach_anchor: Vector2i = result.get("goal_anchor", Vector2i(-2147483648, -2147483648))
	var path_variant: Variant = result.get("path", [])
	var path: Array[Vector2i] = []

	if approach_anchor not in ranked_anchors or not (path_variant is Array):
		return {}

	for step_variant: Variant in path_variant as Array:
		if step_variant is Vector2i:
			path.append(step_variant)

	if path.is_empty() and approach_anchor != origin_anchor:
		return {}

	return {
		"path": path,
		"approach_anchor": approach_anchor,
		"has_approach": true
	}


func _build_side_approach_anchors(
	prey_anchor: Vector2i,
	prey_size: Vector2i
) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var anchor_lookup: Dictionary = {}

	# Any overlap of at least one tile along a side is valid. With the current
	# shared 2x2 footprint this produces center plus +/-1 tile shifts on every
	# side, while full corner diagonals remain excluded.
	for vertical_shift in range(-(creature.footprint_size.y - 1), prey_size.y):
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			prey_anchor + Vector2i(-creature.footprint_size.x, vertical_shift)
		)
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			prey_anchor + Vector2i(prey_size.x, vertical_shift)
		)

	for horizontal_shift in range(-(creature.footprint_size.x - 1), prey_size.x):
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			prey_anchor + Vector2i(horizontal_shift, -creature.footprint_size.y)
		)
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			prey_anchor + Vector2i(horizontal_shift, prey_size.y)
		)

	return anchors


func _append_unique_anchor(
	anchors: Array[Vector2i],
	anchor_lookup: Dictionary,
	candidate_anchor: Vector2i
) -> void:
	if anchor_lookup.has(candidate_anchor):
		return

	anchor_lookup[candidate_anchor] = true
	anchors.append(candidate_anchor)


func _insert_approach_anchor_by_distance(
	ranked_anchors: Array[Vector2i],
	candidate_anchor: Vector2i,
	origin_anchor: Vector2i
) -> void:
	var candidate_distance: int = creature.world_grid.estimate_path_steps(
		origin_anchor,
		candidate_anchor
	)
	var insert_index: int = ranked_anchors.size()

	for index in range(ranked_anchors.size()):
		var current_distance: int = creature.world_grid.estimate_path_steps(
			origin_anchor,
			ranked_anchors[index]
		)

		if candidate_distance < current_distance:
			insert_index = index
			break

	ranked_anchors.insert(insert_index, candidate_anchor)


func start_duel_with(opponent: Node, intervention_allowed: bool = true) -> Duel:
	if opponent == null or opponent == creature:
		return null

	if not creature.can_fight():
		return null

	if (
		not opponent.has_method("can_be_hunted")
		or not opponent.can_be_hunted()
		or not _is_allowed_prey_for_current_mode(opponent)
	):
		return null

	if not is_prey_in_duel_range(opponent):
		return null

	creature.face_target(opponent)

	if opponent.has_method("face_target"):
		opponent.face_target(creature)

	var duel := Duel.new()
	var duel_parent := creature.get_tree().current_scene

	if duel_parent == null:
		duel_parent = creature.get_parent()

	if duel_parent == null:
		return null

	duel_parent.add_child(duel)

	var finished_callable := Callable(creature, "_on_duel_finished")

	if duel.duel_finished.is_connected(finished_callable) == false:
		duel.duel_finished.connect(finished_callable)

	duel.setup(creature, opponent, creature, 1.0, intervention_allowed)
	target_prey = null
	target_recheck_remaining = 0.0
	approach_recheck_done = false
	locked_approach_anchor = Vector2i.ZERO
	has_locked_approach = false
	has_hunt_route = false
	return duel
