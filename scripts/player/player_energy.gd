extends Node

# Session-owned player energy and population income.
signal energy_changed(current_energy: float, max_energy: float)

const PLAYER_SPECIES_CATALOG := preload("res://scripts/catalogs/player_species_catalog.gd")
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const DEAD_CREATURE_STATE := 6
const ENERGY_TICK_INTERVAL := 1.0

@export var max_energy := 9999.0
@export var starting_energy := 2000.0

var current_energy := 0.0
var current_income_per_second := 0.0
var income_timer: Timer = null


func _ready() -> void:
	add_to_group("player_energy")
	current_energy = clampf(starting_energy, 0.0, max_energy)
	_setup_income_timer()
	energy_changed.emit(current_energy, max_energy)


func _setup_income_timer() -> void:
	income_timer = Timer.new()
	income_timer.wait_time = ENERGY_TICK_INTERVAL
	income_timer.one_shot = false
	income_timer.timeout.connect(_on_income_tick)
	add_child(income_timer)
	income_timer.start()


func _on_income_tick() -> void:
	_refresh_income()

	if current_income_per_second > 0.0:
		add_energy(current_income_per_second)


func can_spend(amount: float) -> bool:
	return amount >= 0.0 and current_energy >= amount


func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true

	if not can_spend(amount):
		return false

	_set_energy(current_energy - amount)
	return true


func add_energy(amount: float) -> void:
	if amount <= 0.0:
		return

	_set_energy(current_energy + amount)


func restore_energy(saved_energy: float) -> void:
	_set_energy(saved_energy)


func get_energy() -> float:
	return current_energy


func get_max_energy() -> float:
	return max_energy


func get_income_per_second() -> float:
	return current_income_per_second


func _set_energy(value: float) -> void:
	var clamped_energy := clampf(value, 0.0, max_energy)

	if current_energy == clamped_energy:
		return

	current_energy = clamped_energy
	energy_changed.emit(current_energy, max_energy)


func _refresh_income() -> void:
	var total_income := 0.0

	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		if not _is_living_creature(creature):
			continue

		if CREATURE_FACTION.get_id(creature) != CREATURE_FACTION.PLAYER:
			continue

		var species_data := creature.get("species_data") as CreatureSpeciesData

		if species_data == null:
			continue

		var species_id := StringName(species_data.species_id)
		var catalog_entry := PLAYER_SPECIES_CATALOG.get_entry(species_id)

		if catalog_entry.is_empty():
			continue

		total_income += maxf(
			float(catalog_entry.get("energy_income_per_second", 0.0)),
			0.0
		)

	current_income_per_second = total_income


func _is_living_creature(creature: Node) -> bool:
	return (
		is_instance_valid(creature)
		and not creature.is_queued_for_deletion()
		and int(creature.get("state")) != DEAD_CREATURE_STATE
	)
