extends Resource
class_name CreatureSpeciesData

# Static species config. Edit this file to rebalance a species.
# Identity.
@export var species_id := "stegosaurus"

@export var species_name := "Стегозавр"

@export var creature_name := "Стегозавр"

# Behavior.
@export var is_predator := false
@export var predator_target_radius := 8

# Visuals.
@export var down_texture: Texture2D
@export var up_texture: Texture2D
@export var right_texture: Texture2D
@export var up_right_texture: Texture2D
@export var down_right_texture: Texture2D
@export var walk_right_frames: SpriteFrames
@export var walk_animation_fps := 6.0

# Balance: combat and survival.
@export var speed := 140.0
@export var max_health := 100.0
@export var starting_health := 100.0
@export var max_age := 10.0
@export var starvation_health_decay_rate := 2.0
@export var well_fed_health_regen_rate := 1.0
@export var satiety_heal_threshold := 70.0
@export var attack := 10.0
@export var defense := 5.0
@export var max_hunger := 100.0
@export var starting_hunger := 100.0
@export var hunger_decay_rate := 10.0
@export var hunger_search_threshold := 70.0
@export var hunger_restore_amount := 10.0
@export var eating_duration := 3.0

# Balance: egg lifecycle.
@export var egg_scene: PackedScene
@export var egg_stage_1_texture: Texture2D
@export var egg_stage_2_texture: Texture2D
@export var egg_laying_duration := 5.0
@export var egg_stage_1_duration := 5.0
@export var egg_expand_retry_interval := 1.0
@export var egg_stage_2_duration := 5.0
@export var hatchling_health := 100.0
@export var hatchling_hunger := 50.0

# Balance: reproduction gates.
@export var reproduction_min_health := 30.0
@export var reproduction_min_hunger := 70.0
@export var reproduction_min_age := 3.0
@export var reproduction_cooldown := 20.0
@export var reproduction_hunger_cost := 20.0
