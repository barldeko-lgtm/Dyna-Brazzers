extends Resource
class_name CreatureSpeciesData

# Технический идентификатор вида существа.
@export var species_id := "stegosaurus"

# Человекочитаемое название вида.
@export var species_name := "Стегозавр"

# Отображаемое имя существа в UI.
@export var creature_name := "Стегозавр"

# Спрайты направлений.
@export var down_texture: Texture2D
@export var up_texture: Texture2D
@export var right_texture: Texture2D
@export var up_right_texture: Texture2D
@export var down_right_texture: Texture2D

# Базовые статы вида.
@export var speed := 140.0
@export var max_health := 100.0
@export var starting_health := 100.0
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

# Яйцо и вылупление.
@export var egg_scene: PackedScene
@export var egg_stage_1_texture: Texture2D
@export var egg_stage_2_texture: Texture2D
@export var egg_laying_duration := 5.0
@export var egg_stage_1_duration := 5.0
@export var egg_expand_retry_interval := 1.0
@export var egg_stage_2_duration := 5.0
@export var hatchling_health := 100.0
@export var hatchling_hunger := 50.0

# Размножение.
@export var reproduction_min_health := 30.0
@export var reproduction_min_hunger := 70.0
@export var reproduction_min_age := 3.0
@export var reproduction_cooldown := 20.0
@export var reproduction_hunger_cost := 20.0
