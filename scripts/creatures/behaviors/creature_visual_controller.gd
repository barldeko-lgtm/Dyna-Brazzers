extends RefCounted

var creature: Node


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func configure_walk_animation() -> void:
	var walk_sprite := _get_walk_sprite()
	if walk_sprite == null:
		return

	walk_sprite.sprite_frames = creature.species_data.walk_right_frames
	walk_sprite.speed_scale = max(float(creature.species_data.walk_animation_fps), 0.0)
	walk_sprite.visible = false
	walk_sprite.stop()

	if can_use_walk_right_animation():
		walk_sprite.animation = &"default"


func can_use_walk_right_animation() -> bool:
	var walk_sprite := _get_walk_sprite()
	if walk_sprite == null or creature.species_data.walk_right_frames == null:
		return false

	return creature.species_data.walk_right_frames.has_animation(&"default") and creature.species_data.walk_right_frames.get_frame_count(&"default") > 0


func update_sprite_visual() -> void:
	var body_sprite := _get_body_sprite()
	if body_sprite == null:
		return

	var direction: Vector2 = creature.direction
	var abs_x := absf(direction.x)
	var abs_y := absf(direction.y)
	var faces_left := direction.x < -0.01
	var faces_up := direction.y < -0.01
	var faces_down := direction.y > 0.01

	body_sprite.flip_h = false
	body_sprite.visible = true

	if abs_x <= 0.01 and abs_y <= 0.01:
		set_walk_right_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.down_texture, false)
		return

	if abs_x <= abs_y * 0.5:
		set_walk_right_animation_active(false)

		if faces_up:
			_apply_static_texture(body_sprite, creature.species_data.up_texture, false)
			return

		if faces_down:
			_apply_static_texture(body_sprite, creature.species_data.down_texture, false)
			return

	if abs_y <= abs_x * 0.5:
		var use_walk_right_animation := _should_play_walk_animation()
		if use_walk_right_animation:
			body_sprite.visible = false
			set_walk_right_animation_active(true, faces_left)
			return

		set_walk_right_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.right_texture, faces_left)
		return

	set_walk_right_animation_active(false)

	if faces_up:
		_apply_static_texture(body_sprite, creature.species_data.up_right_texture, faces_left)
		return

	if faces_down:
		_apply_static_texture(body_sprite, creature.species_data.down_right_texture, faces_left)
		return

	_apply_static_texture(body_sprite, creature.species_data.right_texture, faces_left)


func set_walk_right_animation_active(active: bool, flip_h: bool = false) -> void:
	var walk_sprite := _get_walk_sprite()
	if walk_sprite == null:
		return

	if active:
		var was_already_active := walk_sprite.visible and walk_sprite.is_playing() and walk_sprite.animation == &"default"

		walk_sprite.visible = true
		walk_sprite.flip_h = flip_h
		walk_sprite.speed_scale = max(float(creature.species_data.walk_animation_fps), 0.0)

		if walk_sprite.sprite_frames != creature.species_data.walk_right_frames:
			walk_sprite.sprite_frames = creature.species_data.walk_right_frames
			was_already_active = false

		if walk_sprite.animation != &"default":
			walk_sprite.animation = &"default"
			was_already_active = false

		if not was_already_active:
			walk_sprite.play(&"default")
		return

	if not walk_sprite.visible:
		return

	walk_sprite.visible = false
	walk_sprite.stop()
	walk_sprite.frame = 0


func _should_play_walk_animation() -> bool:
	if not bool(creature.is_moving):
		return false

	if not can_use_walk_right_animation():
		return false

	return creature.state == creature.State.WALK or creature.state == creature.State.SEEK_FOOD


func _apply_static_texture(body_sprite: Sprite2D, texture: Texture2D, flip_h: bool) -> void:
	if texture == null:
		return

	body_sprite.texture = texture
	body_sprite.flip_h = flip_h


func _get_body_sprite() -> Sprite2D:
	return creature.sprite as Sprite2D


func _get_walk_sprite() -> AnimatedSprite2D:
	return creature.walk_right_sprite as AnimatedSprite2D
