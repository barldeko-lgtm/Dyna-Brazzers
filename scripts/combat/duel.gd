extends Node
class_name Duel

signal duel_finished(duel: Duel, winner: Node, loser: Node)

var fighter_a: Node = null
var fighter_b: Node = null
var initiator: Node = null
var current_attacker: Node = null
var tick_interval := 1.0
var tick_remaining := 0.0
var is_active := false


func setup(new_fighter_a: Node, new_fighter_b: Node, new_initiator: Node, new_tick_interval: float = 1.0) -> void:
	fighter_a = new_fighter_a
	fighter_b = new_fighter_b
	initiator = new_initiator
	tick_interval = max(new_tick_interval, 0.01)
	current_attacker = initiator
	tick_remaining = 0.0

	if fighter_a != null and fighter_a.has_method("attach_duel"):
		fighter_a.attach_duel(self)

	if fighter_b != null and fighter_b.has_method("attach_duel"):
		fighter_b.attach_duel(self)

	is_active = true
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if not is_active:
		return

	if not _is_fighter_available(fighter_a) or not _is_fighter_available(fighter_b):
		finish_from_current_state()
		return

	tick_remaining -= delta

	if tick_remaining > 0.0:
		return

	resolve_next_turn()


func resolve_next_turn() -> void:
	if not is_active:
		return

	var attacker: Node = current_attacker
	var defender: Node = _get_other_fighter(attacker)

	if not _is_fighter_available(attacker) or not _is_fighter_available(defender):
		finish_from_current_state()
		return

	var attack_value: float = float(attacker.get("attack"))
	var defense_value: float = float(defender.get("defense"))
	var damage: float = max(1.0, attack_value - defense_value)

	if defender.has_method("take_duel_damage"):
		defender.take_duel_damage(damage, attacker)

	if not _is_fighter_available(defender):
		finish_duel(attacker, defender)
		return

	current_attacker = defender
	tick_remaining = tick_interval


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
