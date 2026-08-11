extends RefCounted

const CREATURE_SELECTION_FRAME_TEXTURE := preload(
	"res://assets/ui/creature_selection_frame.png"
)
const LIGHTNING_TARGET_VALID_TEXTURE := preload(
	"res://assets/sprites/effects/lightning/lightning.png"
)
const LIGHTNING_TARGET_INVALID_TEXTURE := preload(
	"res://assets/sprites/effects/lightning/lightning-2.png"
)
const LIGHTNING_TARGET_FRAME_SIZE := Vector2(270.0, 270.0)

var creature: Node
var interaction_highlight_sprite: Sprite2D = null
var is_hover_highlighted := false
var is_selected_highlighted := false


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func configure(hover_area: Area2D) -> void:
	_configure_interaction_highlight()

	if hover_area == null:
		return

	var mouse_entered_callable := Callable(self, "_on_hover_area_mouse_entered")
	if not hover_area.mouse_entered.is_connected(mouse_entered_callable):
		hover_area.mouse_entered.connect(mouse_entered_callable)

	var mouse_exited_callable := Callable(self, "_on_hover_area_mouse_exited")
	if not hover_area.mouse_exited.is_connected(mouse_exited_callable):
		hover_area.mouse_exited.connect(mouse_exited_callable)

	var input_event_callable := Callable(self, "_on_hover_area_input_event")
	if not hover_area.input_event.is_connected(input_event_callable):
		hover_area.input_event.connect(input_event_callable)


func set_hover_highlighted(enabled: bool) -> void:
	if is_hover_highlighted == enabled:
		return

	is_hover_highlighted = enabled
	_refresh_interaction_highlight()


func set_selected_highlighted(enabled: bool) -> void:
	if is_selected_highlighted == enabled:
		return

	is_selected_highlighted = enabled
	_refresh_interaction_highlight()


func clear_interaction_highlights() -> void:
	is_hover_highlighted = false
	is_selected_highlighted = false
	_refresh_interaction_highlight()


func refresh_interaction_highlight() -> void:
	_refresh_interaction_highlight()


func _configure_interaction_highlight() -> void:
	interaction_highlight_sprite = Sprite2D.new()
	interaction_highlight_sprite.name = "InteractionHighlight"
	interaction_highlight_sprite.centered = true
	interaction_highlight_sprite.position = Vector2.ZERO
	interaction_highlight_sprite.visible = false
	interaction_highlight_sprite.texture_filter = (
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	)
	interaction_highlight_sprite.z_as_relative = false
	interaction_highlight_sprite.z_index = 1000
	_set_interaction_highlight_texture(
		CREATURE_SELECTION_FRAME_TEXTURE,
		creature.selection_highlight_target_size
	)

	creature.add_child(interaction_highlight_sprite)
	creature.move_child(interaction_highlight_sprite, 0)
	_refresh_interaction_highlight()


func _refresh_interaction_highlight() -> void:
	if interaction_highlight_sprite == null:
		return

	if creature.state == creature.State.DEAD:
		interaction_highlight_sprite.visible = false
		return

	var lightning_target_state := _get_lightning_target_state()
	if is_hover_highlighted and lightning_target_state >= 0:
		_set_interaction_highlight_texture(
			LIGHTNING_TARGET_VALID_TEXTURE
			if lightning_target_state == 1
			else LIGHTNING_TARGET_INVALID_TEXTURE,
			LIGHTNING_TARGET_FRAME_SIZE
		)
		interaction_highlight_sprite.modulate = Color.WHITE
		interaction_highlight_sprite.visible = true
		return

	_set_interaction_highlight_texture(
		CREATURE_SELECTION_FRAME_TEXTURE,
		creature.selection_highlight_target_size
	)
	if is_selected_highlighted:
		interaction_highlight_sprite.modulate = creature.selected_highlight_modulate
		interaction_highlight_sprite.visible = true
		return

	if is_hover_highlighted:
		interaction_highlight_sprite.modulate = creature.hover_highlight_modulate
		interaction_highlight_sprite.visible = true
		return

	interaction_highlight_sprite.visible = false


func _set_interaction_highlight_texture(texture: Texture2D, target_size: Vector2) -> void:
	interaction_highlight_sprite.texture = texture
	var texture_size := texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		interaction_highlight_sprite.scale = Vector2.ONE
		return
	interaction_highlight_sprite.scale = Vector2(
		target_size.x / texture_size.x,
		target_size.y / texture_size.y
	)


func _get_lightning_target_state() -> int:
	var nature_ui := creature.get_tree().get_first_node_in_group("player_nature_ui")
	if (
		nature_ui == null
		or not nature_ui.has_method("is_lightning_targeting_enabled")
		or not bool(nature_ui.call("is_lightning_targeting_enabled"))
	):
		return -1
	if not nature_ui.has_method("can_target_lightning_creature"):
		return 0
	return 1 if bool(nature_ui.call("can_target_lightning_creature", creature)) else 0


func _on_hover_area_mouse_entered() -> void:
	var stats_ui := _get_stats_ui()
	if stats_ui != null and stats_ui.has_method("show_creature_stats"):
		stats_ui.call("show_creature_stats", creature)


func _on_hover_area_mouse_exited() -> void:
	var stats_ui := _get_stats_ui()
	if stats_ui != null and stats_ui.has_method("hide_creature_stats"):
		stats_ui.call("hide_creature_stats", creature)


func _on_hover_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	var stats_ui := _get_stats_ui()
	if stats_ui != null and stats_ui.has_method("try_apply_lightning_to_creature"):
		if bool(stats_ui.call("try_apply_lightning_to_creature", creature)):
			creature.get_viewport().set_input_as_handled()
			return

	if stats_ui != null and stats_ui.has_method("toggle_creature_selection"):
		stats_ui.call("toggle_creature_selection", creature)
		creature.get_viewport().set_input_as_handled()


func _get_stats_ui() -> Node:
	if creature == null or not is_instance_valid(creature):
		return null

	return creature.get_tree().get_first_node_in_group("creature_stats_ui")
