extends Node2D
class_name BaseEggLaunchEffect

# Short-lived visual-only projectile used when a faction base creates an egg.
# The real egg already exists at the destination, but remains hidden and paused
# until this effect reports the landing.
var egg_sprite: Sprite2D = null
var landing_egg: Node = null
var launch_texture: Texture2D = null
var start_world_position := Vector2.ZERO
var target_world_position := Vector2.ZERO
var launch_duration := 1.5
var elapsed := 0.0
var arc_height := 160.0
var rotation_direction := 1.0
var rotation_turns := 2.0
var configured := false


func _ready() -> void:
	# Run independently of inherited process settings. Delta still follows
	# Engine.time_scale, so speed controls accelerate the flight and time_scale 0
	# freezes it with the in-game menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_egg_sprite()
	_apply_launch_texture()
	set_process(configured)


func configure(
	start_position: Vector2,
	target_position: Vector2,
	texture: Texture2D,
	duration: float,
	target_egg: Node
) -> bool:
	if texture == null or target_egg == null or not is_instance_valid(target_egg):
		return false

	start_world_position = start_position
	target_world_position = target_position
	launch_texture = texture
	launch_duration = maxf(duration, 0.05)
	landing_egg = target_egg
	elapsed = 0.0
	configured = true
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The Sprite2D already exists in the instantiated scene even if this method
	# happens before @ready-style initialization. Resolve it explicitly instead
	# of relying on an @onready field being populated at this exact moment.
	_resolve_egg_sprite()

	if egg_sprite == null:
		configured = false
		return false

	_apply_launch_texture()
	global_position = start_world_position

	var travel_distance := start_world_position.distance_to(target_world_position)
	arc_height = clampf(travel_distance * 0.35, 120.0, 280.0)
	rotation_direction = -1.0 if target_world_position.x < start_world_position.x else 1.0
	set_process(true)
	queue_redraw()
	return true


func _process(delta: float) -> void:
	if not configured:
		return

	if landing_egg == null or not is_instance_valid(landing_egg) or landing_egg.is_queued_for_deletion():
		queue_free()
		return

	elapsed += maxf(delta, 0.0)
	var progress := clampf(elapsed / launch_duration, 0.0, 1.0)
	var eased_progress := smoothstep(0.0, 1.0, progress)
	global_position = start_world_position.lerp(target_world_position, eased_progress)

	var arc_offset := -4.0 * arc_height * progress * (1.0 - progress)
	var landing_squash := 0.0

	if progress > 0.88:
		landing_squash = sin((progress - 0.88) / 0.12 * PI) * 0.12

	_resolve_egg_sprite()

	if egg_sprite != null:
		egg_sprite.position = Vector2(0.0, arc_offset)
		egg_sprite.rotation = rotation_direction * TAU * rotation_turns * progress
		egg_sprite.scale = Vector2(1.0 + landing_squash, 1.0 - landing_squash)

	queue_redraw()

	if progress >= 1.0:
		_finish_landing()


func _draw() -> void:
	if egg_sprite == null:
		return

	var height_ratio := clampf(-egg_sprite.position.y / maxf(arc_height, 1.0), 0.0, 1.0)
	var shadow_scale := lerpf(1.0, 0.55, height_ratio)
	var shadow_alpha := lerpf(0.24, 0.08, height_ratio)
	draw_set_transform(Vector2(0.0, 30.0), 0.0, Vector2(shadow_scale, shadow_scale * 0.34))
	draw_circle(Vector2.ZERO, 34.0, Color(0.0, 0.0, 0.0, shadow_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _resolve_egg_sprite() -> void:
	if egg_sprite != null and is_instance_valid(egg_sprite):
		return

	egg_sprite = get_node_or_null("EggSprite") as Sprite2D


func _apply_launch_texture() -> void:
	if egg_sprite == null:
		return

	egg_sprite.texture = launch_texture
	egg_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	egg_sprite.visible = launch_texture != null


func _finish_landing() -> void:
	configured = false
	set_process(false)

	if landing_egg != null and is_instance_valid(landing_egg):
		if landing_egg.has_method("complete_base_landing"):
			landing_egg.call("complete_base_landing")

	queue_free()
