class_name EnemySpeciesCatalog
extends RefCounted

# Enemy roster only selects enemy-specific biological resources. Production
# costs, population goals and AI priorities belong to the future enemy logic.
const STEGOSAURUS := preload("res://data/species/enemy/stegosaurus.tres")
const TRICERATOPS := preload("res://data/species/enemy/triceratops.tres")
const TYRANNOSAURUS := preload("res://data/species/enemy/tyrannosaurus.tres")
const RAPTOR := preload("res://data/species/enemy/raptor.tres")
const PTERODACTYL := preload("res://data/species/enemy/pterodactyl.tres")
const EGG_EATER := preload("res://data/species/enemy/egg_eater.tres")

const EMPTY_ENTRY: Dictionary = {}

const STEGOSAURUS_ENTRY: Dictionary = {"species_data": STEGOSAURUS}
const TRICERATOPS_ENTRY: Dictionary = {"species_data": TRICERATOPS}
const TYRANNOSAURUS_ENTRY: Dictionary = {"species_data": TYRANNOSAURUS}
const RAPTOR_ENTRY: Dictionary = {"species_data": RAPTOR}
const PTERODACTYL_ENTRY: Dictionary = {"species_data": PTERODACTYL}
const EGG_EATER_ENTRY: Dictionary = {"species_data": EGG_EATER}

const ENTRY_BY_ID: Dictionary = {
	&"stegosaurus": STEGOSAURUS_ENTRY,
	&"triceratops": TRICERATOPS_ENTRY,
	&"tyrannosaurus": TYRANNOSAURUS_ENTRY,
	&"raptor": RAPTOR_ENTRY,
	&"pterodactyl": PTERODACTYL_ENTRY,
	&"egg_eater": EGG_EATER_ENTRY
}

const SUPPORTED_IDS: Array[StringName] = [
	&"stegosaurus",
	&"triceratops",
	&"tyrannosaurus",
	&"raptor",
	&"pterodactyl",
	&"egg_eater"
]

const SPECIES_ENTRIES: Array[Dictionary] = [
	STEGOSAURUS_ENTRY,
	TRICERATOPS_ENTRY,
	EGG_EATER_ENTRY,
	RAPTOR_ENTRY,
	PTERODACTYL_ENTRY,
	TYRANNOSAURUS_ENTRY
]


static func get_entry(species_id: StringName) -> Dictionary:
	return ENTRY_BY_ID.get(species_id, EMPTY_ENTRY) as Dictionary


static func get_species_data(species_id: StringName) -> CreatureSpeciesData:
	var entry := get_entry(species_id)
	return entry.get("species_data") as CreatureSpeciesData


static func has_species(species_id: StringName) -> bool:
	return ENTRY_BY_ID.has(species_id)


static func get_supported_ids() -> Array[StringName]:
	return SUPPORTED_IDS


static func get_species_entries() -> Array[Dictionary]:
	return SPECIES_ENTRIES
