extends SceneTree

const PlayerEnergy = preload("res://scripts/player/player_energy.gd")
const PlayerSpeciesCatalog = preload("res://scripts/catalogs/player_species_catalog.gd")
const CreatureSpeciesData = preload("res://scripts/creatures/creature_species_data.gd")

class FakeCreature extends Node:
	var state := 0
	var species_data: Resource


func _init() -> void:
	call_deferred("_run_probe")


func _run_probe() -> void:
	var world := Node.new()
	get_root().add_child(world)

	var stegosaurus := FakeCreature.new()
	var species := CreatureSpeciesData.new()
	species.species_id = &"stegosaurus"
	stegosaurus.species_data = species
	stegosaurus.add_to_group("creatures")
	world.add_child(stegosaurus)

	var energy := PlayerEnergy.new()
	world.add_child(energy)
	await process_frame
	if energy.has_method("_process") or not energy.has_method("_on_income_tick"):
		push_error("PlayerEnergy must use one-second timer ticks instead of per-frame income processing.")
		quit(1)
		return

	var expected_income_by_species: Dictionary = {
		&"stegosaurus": 0.8,
		&"triceratops": 0.6,
		&"tyrannosaurus": 0.2,
		&"raptor": 0.2,
		&"pterodactyl": 0.2,
		&"egg_eater": 0.2
	}

	for species_id: StringName in expected_income_by_species:
		var catalog_entry := PlayerSpeciesCatalog.get_entry(species_id)
		var expected_income: float = expected_income_by_species[species_id]
		var actual_income: float = float(catalog_entry.get("energy_income_per_second", 0.0))

		if not is_equal_approx(actual_income, expected_income):
			push_error("Expected %s to generate %s energy per second, got %s." % [
				species_id,
				expected_income,
				actual_income
			])
			quit(1)
			return

	var before := energy.get_energy()
	energy.call("_on_income_tick")
	var gained := energy.get_energy() - before

	if not is_equal_approx(gained, 0.8):
		push_error("Expected a stegosaurus to generate 0.8 energy per timer tick, got %s." % gained)
		quit(1)
		return

	world.queue_free()
	await process_frame

	var main_scene := load("res://scenes/main/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame

	var runtime_energy := get_first_node_in_group("player_energy")

	if runtime_energy == null:
		push_error("Main scene did not create PlayerEnergy.")
		quit(1)
		return

	var runtime_stegosaurus := FakeCreature.new()
	runtime_stegosaurus.species_data = species
	runtime_stegosaurus.add_to_group("creatures")
	main.add_child(runtime_stegosaurus)
	var runtime_before := float(runtime_energy.call("get_energy"))
	runtime_energy.call("_on_income_tick")
	var runtime_gained := float(runtime_energy.call("get_energy")) - runtime_before

	if not is_equal_approx(runtime_gained, 0.8):
		push_error("Main-scene PlayerEnergy gained %s instead of 0.8." % runtime_gained)
		quit(1)
		return

	var nature_ui := main.get_node_or_null(
		"UI/PlayerSidePanel/MarginContainer/VBoxContainer/PlayerNaturePanel"
	)
	var energy_label := nature_ui.get_node_or_null("MarginContainer/VBoxContainer/EnergyValueLabel") as Label
	for _tick in range(3):
		runtime_energy.call("_on_income_tick")
	var expected_label := str(floori(float(runtime_energy.call("get_energy"))))

	if energy_label == null or energy_label.text != expected_label:
		push_error("Nature UI did not refresh its energy label after income changed.")
		quit(1)
		return

	print("PASS: a living stegosaurus generates 0.8 energy in one second.")
	print("PASS: main scene wires PlayerEnergy to the active world.")
	print("PASS: nature UI refreshes after dinosaur income changes.")
	quit(0)
