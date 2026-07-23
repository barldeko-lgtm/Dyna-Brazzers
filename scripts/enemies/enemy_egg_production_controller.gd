extends Node
class_name EnemyEggProductionController

# Temporary deterministic production loop. Strategic choices and population AI
# stay outside this scaffold and will replace the simple round-robin rule later.
const ENEMY_SPECIES_CATALOG := preload("res://scripts/catalogs/enemy_species_catalog.gd")

# Temporary project switch. Set this to false only when automatic enemy egg
# production must be paused without removing its save state or base plumbing.
@export var automatic_production_enabled := true
@export var production_interval := 5.0

var production_timer: Timer = null
var next_species_index := 0
var enemy_base: Node = null
var enemy_energy: Node = null


func _ready() -> void:
	add_to_group("enemy_egg_production")
	_refresh_runtime_references()
	_setup_production_timer()


func _setup_production_timer() -> void:
	production_timer = Timer.new()
	production_timer.wait_time = production_interval
	production_timer.one_shot = false
	production_timer.timeout.connect(_on_production_timer_timeout)
	add_child(production_timer)

	if automatic_production_enabled:
		production_timer.start()


func _on_production_timer_timeout() -> void:
	if not automatic_production_enabled:
		production_timer.stop()
		return

	_refresh_runtime_references()

	if enemy_base == null or enemy_energy == null:
		return

	if not enemy_base.has_method("create_enemy_egg"):
		return

	if not enemy_energy.has_method("can_spend") or not enemy_energy.has_method("spend"):
		return

	var entries := ENEMY_SPECIES_CATALOG.get_species_entries()

	if entries.is_empty():
		return

	next_species_index = posmod(next_species_index, entries.size())
	var entry: Dictionary = entries[next_species_index]
	var species_data := entry.get("species_data") as CreatureSpeciesData
	var egg_cost := maxf(float(entry.get("egg_purchase_cost", 0.0)), 0.0)

	if species_data == null:
		_advance_species(entries.size())
		return

	if not bool(enemy_energy.call("can_spend", egg_cost)):
		return

	var created_egg := enemy_base.call("create_enemy_egg", species_data) as Node2D

	if created_egg == null:
		return

	if not bool(enemy_energy.call("spend", egg_cost)):
		created_egg.queue_free()
		return

	_advance_species(entries.size())


func _advance_species(entry_count: int) -> void:
	if entry_count <= 0:
		next_species_index = 0
		return

	next_species_index = (next_species_index + 1) % entry_count


func get_save_data() -> Dictionary:
	var time_left := production_interval

	if production_timer != null and not production_timer.is_stopped():
		time_left = production_timer.time_left

	return {
		"next_species_index": next_species_index,
		"timer_time_left": time_left
	}


func restore_save_data(saved_data: Dictionary) -> void:
	var entries := ENEMY_SPECIES_CATALOG.get_species_entries()
	var entry_count := entries.size()

	if entry_count <= 0:
		next_species_index = 0
	else:
		next_species_index = posmod(
			int(saved_data.get("next_species_index", 0)),
			entry_count
		)

	if production_timer == null:
		return

	if not automatic_production_enabled:
		production_timer.stop()
		return

	var saved_time_left := float(
		saved_data.get("timer_time_left", production_interval)
	)
	production_timer.start(clampf(saved_time_left, 0.05, production_interval))


func _refresh_runtime_references() -> void:
	if enemy_base == null or not is_instance_valid(enemy_base):
		enemy_base = get_tree().get_first_node_in_group("enemy_base")

	if enemy_energy == null or not is_instance_valid(enemy_energy):
		enemy_energy = get_tree().get_first_node_in_group("enemy_energy")
