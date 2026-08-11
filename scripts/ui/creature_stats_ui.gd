extends Control

# Creature info window + creature selection.
# Presentation lives in creature_info_panel.tscn; this script only updates data
# and preserves hover/selection behavior.

const SATIETY_GRASS_TEXTURE := preload(
	"res://assets/ui/creature_stats/satiety_grass.png"
)
const SATIETY_MEAT_TEXTURE := preload(
	"res://assets/ui/creature_stats/satiety_meat.png"
)
const SATIETY_EGG_TEXTURE := preload(
	"res://assets/ui/creature_stats/satiety_egg.png"
)

@onready var panel: Control = self
@onready var primary_card: Control = $PrimaryCard
@onready var hover_card: Control = $HoverCard
@onready var age_label: Label = $PrimaryCard/ContentMargin/StatsVBox/AgeLabel

var current_creature: Node = null
var hovered_creature: Node = null
var selected_creature: Node = null

var last_hover_highlighted: Node = null
var last_selected_highlighted: Node = null


func _ready() -> void:
	add_to_group("creature_stats_ui")
	_refresh_localized_text()
	LocalizationManager.locale_changed.connect(_on_locale_changed)
	hover_card.visible = false
	panel.visible = false


# Selected creature stays in the primary card; a different hovered creature
# uses the comparison card to its right.
func _process(_delta: float) -> void:
	if not is_instance_valid(selected_creature):
		selected_creature = null

	if not is_instance_valid(hovered_creature):
		hovered_creature = null

	sync_creature_highlights()
	_refresh_hovered_targeting_highlight()

	if is_instance_valid(selected_creature):
		current_creature = selected_creature
		panel.visible = true
		update_stats_text()
		_update_hover_card()
		return

	hover_card.visible = false
	if is_instance_valid(hovered_creature):
		current_creature = hovered_creature
		panel.visible = true
		update_stats_text()
		return

	hide_creature_stats()


func show_creature_stats(creature: Node) -> void:
	if creature == null:
		return

	hovered_creature = creature
	sync_creature_highlights()

	if is_instance_valid(selected_creature):
		_update_hover_card()
		return

	current_creature = creature
	panel.visible = true
	hover_card.visible = false
	update_stats_text()


func hide_creature_stats(exited_creature: Node = null) -> void:
	if exited_creature != null and hovered_creature != exited_creature:
		return

	hovered_creature = null
	sync_creature_highlights()
	hover_card.visible = false

	if is_instance_valid(selected_creature):
		return

	current_creature = null
	panel.visible = false


func sync_creature_highlights() -> void:
	if not is_instance_valid(last_hover_highlighted):
		last_hover_highlighted = null

	if not is_instance_valid(last_selected_highlighted):
		last_selected_highlighted = null

	var desired_selected: Node = selected_creature if is_instance_valid(selected_creature) else null
	var desired_hover: Node = hovered_creature if is_instance_valid(hovered_creature) else null

	if desired_hover == desired_selected and not _is_lightning_targeting_enabled():
		desired_hover = null

	if last_hover_highlighted != desired_hover:
		apply_highlight_flag(last_hover_highlighted, "set_hover_highlighted", false)
		last_hover_highlighted = desired_hover
		apply_highlight_flag(last_hover_highlighted, "set_hover_highlighted", true)

	if last_selected_highlighted != desired_selected:
		apply_highlight_flag(last_selected_highlighted, "set_selected_highlighted", false)
		last_selected_highlighted = desired_selected
		apply_highlight_flag(last_selected_highlighted, "set_selected_highlighted", true)


func apply_highlight_flag(creature: Node, method_name: String, enabled: bool) -> void:
	if not is_instance_valid(creature):
		return

	if creature.has_method(method_name):
		creature.call(method_name, enabled)


func _is_lightning_targeting_enabled() -> bool:
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	return (
		nature_ui != null
		and nature_ui.has_method("is_lightning_targeting_enabled")
		and bool(nature_ui.call("is_lightning_targeting_enabled"))
	)


func _refresh_hovered_targeting_highlight() -> void:
	if (
		is_instance_valid(hovered_creature)
		and hovered_creature.has_method("refresh_interaction_highlight")
	):
		hovered_creature.call("refresh_interaction_highlight")


func update_stats_text() -> void:
	if not is_instance_valid(current_creature):
		return
	_update_card_stats(primary_card, current_creature)


func _update_hover_card() -> void:
	var should_show := (
		is_instance_valid(selected_creature)
		and is_instance_valid(hovered_creature)
		and hovered_creature != selected_creature
	)
	hover_card.visible = should_show
	if should_show:
		_update_card_stats(hover_card, hovered_creature)


func _update_card_stats(card: Control, creature: Node) -> void:
	var stats := card.get_node("ContentMargin/StatsVBox")
	var card_age_label := stats.get_node("AgeLabel") as Label
	var card_health_bar := stats.get_node("HealthRow/HealthBar") as ProgressBar
	var card_health_label := card_health_bar.get_node("PercentLabel") as Label
	var card_hunger_bar := stats.get_node("HungerRow/HungerBar") as ProgressBar
	var card_hunger_label := card_hunger_bar.get_node("PercentLabel") as Label
	var card_reproduction_bar := stats.get_node(
		"ReproductionRow/ReproductionBar"
	) as ProgressBar
	var card_reproduction_label := card_reproduction_bar.get_node(
		"PercentLabel"
	) as Label
	var card_reproduction_icon := stats.get_node(
		"ReproductionRow/EggIconSlot/EggIcon"
	) as TextureRect

	if creature.has_method("get_age"):
		card_age_label.text = tr("CREATURE_AGE") % int(creature.get_age())
	else:
		card_age_label.text = tr("CREATURE_AGE_UNKNOWN")

	var health_percent := 0.0
	if creature.has_method("get_health_percent"):
		health_percent = clampf(float(creature.get_health_percent()), 0.0, 100.0)
	card_health_bar.value = health_percent
	card_health_label.text = "%d%%" % int(round(health_percent))

	var hunger_percent := 0.0
	if creature.has_method("get_hunger_percent"):
		hunger_percent = clampf(float(creature.get_hunger_percent()), 0.0, 100.0)
	card_hunger_bar.value = hunger_percent
	card_hunger_label.text = "%d%%" % int(round(hunger_percent))
	_update_satiety_icon(card, creature)

	var reproduction_percent := 0.0
	if creature.has_method("get_reproduction_progress_percent"):
		reproduction_percent = clampf(
			float(creature.call("get_reproduction_progress_percent")),
			0.0,
			100.0
		)
	card_reproduction_bar.value = reproduction_percent
	card_reproduction_label.text = "%d%%" % int(round(reproduction_percent))

	if creature.has_method("get_reproduction_egg_texture"):
		card_reproduction_icon.texture = creature.call(
			"get_reproduction_egg_texture"
		) as Texture2D
	else:
		card_reproduction_icon.texture = null


func _update_satiety_icon(card: Control, creature: Node) -> void:
	var card_hunger_icon := card.get_node(
		"ContentMargin/StatsVBox/HungerRow/HungerIcon"
	) as TextureRect
	if creature.has_method("is_egg_eater") and bool(creature.call("is_egg_eater")):
		card_hunger_icon.texture = SATIETY_EGG_TEXTURE
		return

	if creature.has_method("get_is_predator") and bool(creature.call("get_is_predator")):
		card_hunger_icon.texture = SATIETY_MEAT_TEXTURE
		return

	card_hunger_icon.texture = SATIETY_GRASS_TEXTURE


func _on_locale_changed(_locale: String) -> void:
	_refresh_localized_text()


func _refresh_localized_text() -> void:
	if is_instance_valid(current_creature):
		update_stats_text()
	else:
		age_label.text = tr("CREATURE_AGE_UNKNOWN")
	_update_hover_card()


# Compatibility hook for creature click input.
func try_apply_lightning_to_creature(creature: Node) -> bool:
	var player_nature_ui := get_tree().get_first_node_in_group("player_nature_ui")

	if player_nature_ui == null or not player_nature_ui.has_method("try_apply_lightning_to_creature"):
		return false

	return bool(player_nature_ui.try_apply_lightning_to_creature(creature))


func is_player_nature_targeting_enabled() -> bool:
	var player_nature_ui := get_tree().get_first_node_in_group("player_nature_ui")

	if player_nature_ui == null or not player_nature_ui.has_method("is_targeting_enabled"):
		return false

	return bool(player_nature_ui.is_targeting_enabled())


func toggle_creature_selection(creature: Node) -> void:
	if creature == null:
		return

	if selected_creature == creature:
		clear_selected_creature()
		return

	selected_creature = creature
	sync_creature_highlights()
	current_creature = creature
	panel.visible = true
	update_stats_text()
	_update_hover_card()


func clear_selected_creature() -> void:
	selected_creature = null
	sync_creature_highlights()
	hover_card.visible = false

	if is_instance_valid(hovered_creature):
		current_creature = hovered_creature
		panel.visible = true
		update_stats_text()
		return

	current_creature = null
	panel.visible = false


# Clear selection on empty click.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	if is_player_nature_targeting_enabled():
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	if not is_instance_valid(selected_creature):
		return

	clear_selected_creature()
