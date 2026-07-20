extends "res://scripts/flags/player_flag_system.gd"

# Active PlayerFlags facade. Catalog data and placement revisions remain here;
# UI targeting and creature assignment are delegated to dedicated controllers.
const PLAYER_SPECIES_CATALOG := preload("res://scripts/catalogs/player_species_catalog.gd")
const FLAG_ASSIGNMENT_SERVICE := preload("res://scripts/flags/player_flag_assignment_service.gd")

var flag_revisions: Dictionary = {}
var assignment_service: RefCounted = null


func _ready() -> void:
	assignment_service = FLAG_ASSIGNMENT_SERVICE.new(self)
	super._ready()


func _get_flag_menu_entries() -> Array[Dictionary]:
	var menu_entries: Array[Dictionary] = []

	for entry: Dictionary in PLAYER_SPECIES_CATALOG.get_flag_entries():
		var species_data := entry.get("species_data") as CreatureSpeciesData

		if species_data == null:
			continue

		menu_entries.append({
			"species_id": species_data.species_id,
			"button_text": String(entry.get("flag_button_text", "Флаг\nвида")),
			"tooltip": String(
				entry.get("flag_tooltip", "Поставить или перенести флаг вида")
			)
		})

	return menu_entries


func _is_supported_species(species_id: StringName) -> bool:
	return PLAYER_SPECIES_CATALOG.has_species(species_id)


func set_flag(species_id: StringName, tile: Vector2i) -> void:
	if not _is_supported_species(species_id):
		return

	# Moving one flag invalidates only routes and retries for its own species.
	assignment_service.call("cancel_species", species_id)
	flags[species_id] = tile
	flag_revisions[species_id] = assignment_service.call(
		"get_next_revision",
		species_id,
		int(flag_revisions.get(species_id, 0))
	)
	_sync_flag_visual()


func remove_flag(species_id: StringName) -> void:
	assignment_service.call("cancel_species", species_id)
	flags.erase(species_id)
	_sync_flag_visual()


func clear_all_flags() -> void:
	if assignment_service != null:
		assignment_service.call("clear_runtime", true)

	flags.clear()
	flag_revisions.clear()
	_sync_flag_visual()


func get_save_data() -> Dictionary:
	var saved_flags: Array[Dictionary] = []

	for species_id_variant: Variant in flags.keys():
		var tile_variant: Variant = flags.get(species_id_variant)

		if not (tile_variant is Vector2i):
			continue

		var species_id := StringName(species_id_variant)
		var tile: Vector2i = tile_variant
		saved_flags.append({
			"species_id": String(species_id),
			"tile_x": tile.x,
			"tile_y": tile.y,
			"revision": get_flag_revision(species_id)
		})

	return {"flags": saved_flags}


func restore_save_data(save_data: Dictionary) -> void:
	if assignment_service != null:
		assignment_service.call("clear_runtime", true)

	flags.clear()
	flag_revisions.clear()
	var saved_flags_variant: Variant = save_data.get("flags", [])

	if saved_flags_variant is Array:
		for record_variant: Variant in saved_flags_variant:
			if not (record_variant is Dictionary):
				continue

			var record := record_variant as Dictionary
			var species_id := StringName(String(record.get("species_id", "")))

			if not _is_supported_species(species_id):
				continue

			flags[species_id] = Vector2i(
				int(record.get("tile_x", 0)),
				int(record.get("tile_y", 0))
			)
			flag_revisions[species_id] = max(int(record.get("revision", 1)), 1)

	_sync_flag_visual()


func get_flag_revision(species_id: StringName) -> int:
	return max(int(flag_revisions.get(species_id, 1)), 1)


func _update_creature_flag_behaviour() -> void:
	if assignment_service != null:
		assignment_service.call("update")


func _reset_behaviour_runtime() -> void:
	if assignment_service != null:
		assignment_service.call("clear_runtime", true)


func get_creature_flag_debug_data(creature: Node) -> Dictionary:
	if assignment_service == null:
		return super.get_creature_flag_debug_data(creature)

	return assignment_service.call("get_debug_data", creature) as Dictionary
