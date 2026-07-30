class_name PlayerSpeciesCatalog
extends RefCounted

# Player-facing economy and order metadata. Species resources remain focused on
# biology, visuals and survival; an enemy faction may later use the same species
# through its own catalog without inheriting player-only prices or flag text.
enum FlagBehaviourType {
	GATHER,
	PASTURE
}

const STEGOSAURUS := preload("res://data/species/stegosaurus.tres")
const TRICERATOPS := preload("res://data/species/triceratops.tres")
const TYRANNOSAURUS := preload("res://data/species/tyrannosaurus.tres")
const RAPTOR := preload("res://data/species/raptor.tres")
const PTERODACTYL := preload("res://data/species/pterodactyl.tres")
const EGG_EATER := preload("res://data/species/egg_eater.tres")

const EMPTY_ENTRY: Dictionary = {}

const STEGOSAURUS_ENTRY: Dictionary = {
	"species_data": STEGOSAURUS,
	"species_name_key": "SPECIES_STEGOSAURUS",
	"egg_purchase_cost": 350.0,
	"energy_income_per_second": 1.0,
	"flag_button_key": "FLAG_STEGOSAURUS_BUTTON",
	"flag_tooltip_key": "FLAG_STEGOSAURUS_TOOLTIP",
	"flag_behaviour_type": FlagBehaviourType.PASTURE
}
const TRICERATOPS_ENTRY: Dictionary = {
	"species_data": TRICERATOPS,
	"species_name_key": "SPECIES_TRICERATOPS",
	"egg_purchase_cost": 450.0,
	"energy_income_per_second": 0.8,
	"flag_button_key": "FLAG_TRICERATOPS_BUTTON",
	"flag_tooltip_key": "FLAG_TRICERATOPS_TOOLTIP",
	"flag_behaviour_type": FlagBehaviourType.PASTURE
}
const TYRANNOSAURUS_ENTRY: Dictionary = {
	"species_data": TYRANNOSAURUS,
	"species_name_key": "SPECIES_TYRANNOSAURUS",
	"egg_purchase_cost": 1300.0,
	"energy_income_per_second": 0.3,
	"flag_button_key": "FLAG_TYRANNOSAURUS_BUTTON",
	"flag_tooltip_key": "FLAG_TYRANNOSAURUS_TOOLTIP",
	"flag_behaviour_type": FlagBehaviourType.GATHER
}
const RAPTOR_ENTRY: Dictionary = {
	"species_data": RAPTOR,
	"species_name_key": "SPECIES_RAPTOR",
	"egg_purchase_cost": 900.0,
	"energy_income_per_second": 0.3,
	"flag_button_key": "FLAG_RAPTOR_BUTTON",
	"flag_tooltip_key": "FLAG_RAPTOR_TOOLTIP",
	"flag_behaviour_type": FlagBehaviourType.GATHER
}
const PTERODACTYL_ENTRY: Dictionary = {
	"species_data": PTERODACTYL,
	"species_name_key": "SPECIES_PTERODACTYL",
	"egg_purchase_cost": 1000.0,
	"energy_income_per_second": 0.3,
	"flag_button_key": "FLAG_PTERODACTYL_BUTTON",
	"flag_tooltip_key": "FLAG_PTERODACTYL_TOOLTIP",
	"flag_behaviour_type": FlagBehaviourType.GATHER
}
const EGG_EATER_ENTRY: Dictionary = {
	"species_data": EGG_EATER,
	"species_name_key": "SPECIES_EGG_EATER",
	"egg_purchase_cost": 1200.0,
	"energy_income_per_second": 0.3,
	"flag_button_key": "FLAG_EGG_EATER_BUTTON",
	"flag_tooltip_key": "FLAG_EGG_EATER_TOOLTIP",
	"flag_behaviour_type": FlagBehaviourType.GATHER
}

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

# Preserve the current visible order of both menus without rebuilding arrays.
const EGG_ENTRIES: Array[Dictionary] = [
	STEGOSAURUS_ENTRY,
	TRICERATOPS_ENTRY,
	EGG_EATER_ENTRY,
	RAPTOR_ENTRY,
	PTERODACTYL_ENTRY,
	TYRANNOSAURUS_ENTRY
]

const FLAG_ENTRIES: Array[Dictionary] = [
	STEGOSAURUS_ENTRY,
	TRICERATOPS_ENTRY,
	TYRANNOSAURUS_ENTRY,
	RAPTOR_ENTRY,
	PTERODACTYL_ENTRY,
	EGG_EATER_ENTRY
]


static func get_entry(species_id: StringName) -> Dictionary:
	return ENTRY_BY_ID.get(species_id, EMPTY_ENTRY) as Dictionary


static func has_species(species_id: StringName) -> bool:
	return ENTRY_BY_ID.has(species_id)


static func get_supported_ids() -> Array[StringName]:
	return SUPPORTED_IDS


static func get_egg_entries() -> Array[Dictionary]:
	return EGG_ENTRIES


static func get_flag_entries() -> Array[Dictionary]:
	return FLAG_ENTRIES
