extends Node
class_name Duel

signal duel_finished(duel: Duel, winner: Node, loser: Node)
signal attack_started(duel: Duel, attacker: Node, defender: Node)

const ATTACK_HIT_DELAY := 0.5

var fighter_a: Node = null
var fighter_b: Node = null
var initiator: Node = null
var current_attacker: Node = null
var tick_interval := 1.0
var tick_remaining := 0.0
var attack_in_progress := false
var is_active := false
var intervention_allowed := true
var intervention_reserver: Node = null
var intervention_protected_fighter: Node = null


func setup(
	new_fighter_a: Node,
	new_fighter_b: Node,
	new_initiator: Node,
	new_tick_interval: float = 1.0,
	new_intervention_allowed: bool = true
) -> void:
	fighter_a = new_fighter_a
	fighter_b = new_fighter_b
	initiator = new_initiator
	tick_interval = max(new_tick_interval, 0.01)
	intervention_allowed = new_intervention_allowed
	intervention_reserver = null
	intervention_protected_fighter = null
	current_attacker = initiator
	attack_in_progress = true
	tick_remaining = minf(ATTACK_HIT_DELAY, tick_interval)

	if fighter_a != null and fighter_a.has_method("attach_duel"):
		fighter_a.attach_duel(self)

	if fighter_b != null and fighter_b.has_method("attach_duel"):
		fighter_b.attach_duel(self)

	is_active = true
	set_process(true)
	emit_signal("attack_started", self, current_attacker, _get_other_fighter(current_attacker))


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if not is_active:
		return

	if not _is_fighter_available(fighter_a) or not _is_fighter_available(fighter_b):
		finish_from_current_state()
		return

	var remaining_delta := delta
	while is_active:
		tick_remaining -= remaining_delta
		if tick_remaining > 0.000001:
			return

		remaining_delta = maxf(-tick_remaining, 0.0)
		if attack_in_progress:
			resolve_next_turn()
		else:
			begin_next_turn()

		if remaining_delta <= 0.0:
			return


func resolve_next_turn() -> void:
	if not is_active:
		return

	var attacker: Node = current_attacker
	var defender: Node = _get_other_fighter(attacker)

	if not _is_fighter_available(attacker) or not _is_fighter_available(defender):
		finish_from_current_state()
		return

	var attack_value: float = get_combat_stat(attacker, "attack")
	var defense_value: float = get_combat_stat(defender, "defense")
	var damage: float = max(1.0, attack_value - defense_value)

	if defender.has_method("take_duel_damage"):
		defender.take_duel_damage(damage, attacker)

	if not _is_fighter_available(defender):
		finish_duel(attacker, defender)
		return

	if _complete_reserved_intervention():
		return

	attack_in_progress = false
	tick_remaining = maxf(tick_interval - minf(ATTACK_HIT_DELAY, tick_interval), 0.0)


func begin_next_turn() -> void:
	if not is_active:
		return

	current_attacker = _get_other_fighter(current_attacker)
	attack_in_progress = true
	tick_remaining = minf(ATTACK_HIT_DELAY, tick_interval)
	emit_signal("attack_started", self, current_attacker, _get_other_fighter(current_attacker))


func reserve_intervention(intervener: Node, protected_fighter: Node) -> bool:
	if (
		not is_active
		or not intervention_allowed
		or is_instance_valid(intervention_reserver)
		or not is_instance_valid(intervener)
		or protected_fighter == initiator
		or (protected_fighter != fighter_a and protected_fighter != fighter_b)
	):
		return false

	if intervener.has_method("can_fight") and not bool(intervener.can_fight()):
		return false

	intervention_reserver = intervener
	intervention_protected_fighter = protected_fighter
	return true


func cancel_intervention(intervener: Node) -> void:
	if intervention_reserver != intervener:
		return

	intervention_reserver = null
	intervention_protected_fighter = null


func get_intervention_reserver() -> Node:
	if intervention_reserver != null and not is_instance_valid(intervention_reserver):
		intervention_reserver = null
		intervention_protected_fighter = null

	return intervention_reserver


func can_accept_intervention() -> bool:
	return is_active and intervention_allowed and get_intervention_reserver() == null


func _complete_reserved_intervention() -> bool:
	var intervener := get_intervention_reserver()
	var protected_fighter := intervention_protected_fighter

	if intervener == null:
		return false

	var attacker := _get_other_fighter(protected_fighter)

	if (
		not _is_fighter_available(protected_fighter)
		or not _is_fighter_available(attacker)
		or (intervener.has_method("can_fight") and not bool(intervener.can_fight()))
	):
		cancel_intervention(intervener)
		return false

	is_active = false
	set_process(false)

	if fighter_a != null and fighter_a.has_method("detach_duel"):
		fighter_a.detach_duel(self)

	if fighter_b != null and fighter_b.has_method("detach_duel"):
		fighter_b.detach_duel(self)

	intervention_reserver = null
	intervention_protected_fighter = null

	if intervener.has_method("complete_duel_intervention"):
		intervener.complete_duel_intervention(attacker, self)

	emit_signal("duel_finished", self, null, null)
	queue_free()
	return true


func get_combat_stat(fighter: Node, stat_name: String) -> float:
	if fighter == null or not is_instance_valid(fighter):
		return 0.0

	var getter_name := "get_%s" % stat_name
	if fighter.has_method(getter_name):
		return float(fighter.call(getter_name))

	var fighter_species: Resource = fighter.get("species_data")
	if fighter_species != null:
		return float(fighter_species.get(stat_name))

	var legacy_value = fighter.get(stat_name)
	if legacy_value == null:
		return 0.0

	return float(legacy_value)


func handle_fighter_death(dead_fighter: Node) -> void:
	if not is_active:
		return

	var winner: Node = _get_other_fighter(dead_fighter)
	finish_duel(winner, dead_fighter)


func finish_from_current_state() -> void:
	var fighter_a_alive: bool = _is_fighter_available(fighter_a)
	var fighter_b_alive: bool = _is_fighter_available(fighter_b)

	if fighter_a_alive and not fighter_b_alive:
		finish_duel(fighter_a, fighter_b)
		return

	if fighter_b_alive and not fighter_a_alive:
		finish_duel(fighter_b, fighter_a)
		return

	finish_duel(null, null)


func finish_duel(winner: Node, loser: Node) -> void:
	if not is_active:
		return

	is_active = false
	set_process(false)

	if fighter_a != null and fighter_a.has_method("detach_duel"):
		fighter_a.detach_duel(self)

	if fighter_b != null and fighter_b.has_method("detach_duel"):
		fighter_b.detach_duel(self)

	emit_signal("duel_finished", self, winner, loser)
	queue_free()


func _get_other_fighter(fighter: Node) -> Node:
	if fighter == fighter_a:
		return fighter_b

	return fighter_a


func _is_fighter_available(fighter: Node) -> bool:
	if not is_instance_valid(fighter):
		return false

	if fighter.has_method("can_continue_duel"):
		return fighter.can_continue_duel(self)

	return true
