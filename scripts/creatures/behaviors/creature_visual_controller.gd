extends RefCounted

var creature: Node
var last_faces_left := false


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
	walk_sprite.frame = 0

	if can_use_walk_right_animation():
		walk_sprite.animation = &"default"


func can_use_walk_right_animation() -> bool:
	return _has_valid_animation(creature.species_data.walk_right_frames)


func can_use_walk_up_animation() -> bool:
	return _has_valid_animation(creature.species_data.walk_up_frames)


func can_use_walk_up_right_animation() -> bool:
	return _has_valid_animation(creature.species_data.walk_up_right_frames)


func can_use_walk_down_right_animation() -> bool:
	return _has_valid_animation(creature.species_data.walk_down_right_frames)


func can_use_eating_right_animation() -> bool:
	return _has_valid_animation(creature.species_data.eating_right_frames)


func update_sprite_visual() -> void:
	var body_sprite := _get_body_sprite()
	if body_sprite == null:
		return

	creature.set_ground_shadow_upward_diagonal(false)

	var direction: Vector2 = creature.direction
	var abs_x := absf(direction.x)
	var abs_y := absf(direction.y)
	var faces_left := direction.x < -0.01
	var faces_up := direction.y < -0.01
	var faces_down := direction.y > 0.01
	var is_vertical_dominant := abs_y > abs_x
	var is_horizontal_dominant := abs_x > abs_y

	_update_last_horizontal_facing(direction)

	body_sprite.flip_h = false
	body_sprite.visible = true

	if creature.state == creature.State.LAYING_EGG and creature.species_data.idle_texture != null:
		set_walk_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.idle_texture, false)
		return

	if creature.state == creature.State.EATING:
		if _should_play_eating_animation() and can_use_eating_right_animation():
			body_sprite.visible = false
			set_walk_animation_active(true, last_faces_left, creature.species_data.eating_right_frames, creature.species_data.eating_animation_fps)
			return

		set_walk_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.right_texture, last_faces_left)
		return

	if abs_x <= 0.01 and abs_y <= 0.01:
		set_walk_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.down_texture, false)
		return

	# Use walk_up only for upward movement where vertical motion is stronger than horizontal motion.
	# Equal 45-degree movement stays diagonal and can use the dedicated up-right animation.
	if is_vertical_dominant:
		if faces_up:
			if _should_play_walk_animation() and can_use_walk_up_animation():
				body_sprite.visible = false
				set_walk_animation_active(true, false, creature.species_data.walk_up_frames)
				return

			set_walk_animation_active(false)
			_apply_static_texture(body_sprite, creature.species_data.up_texture, false)
			return

		if faces_down:
			set_walk_animation_active(false)
			_apply_static_texture(body_sprite, creature.species_data.down_texture, false)
			return

	# Use walk_right only for horizontal-dominant movement.
	# Left is still the same animation with horizontal flip.
	if is_horizontal_dominant:
		if _should_play_walk_animation() and can_use_walk_right_animation():
			body_sprite.visible = false
			set_walk_animation_active(true, faces_left, creature.species_data.walk_right_frames)
			return

		set_walk_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.right_texture, faces_left)
		return

	# Equal diagonal movement uses diagonal sprites or animation.
	if faces_up:
		creature.set_ground_shadow_upward_diagonal(true)
		if _should_play_walk_animation() and can_use_walk_up_right_animation():
			body_sprite.visible = false
			set_walk_animation_active(true, faces_left, creature.species_data.walk_up_right_frames)
			return

		set_walk_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.up_right_texture, faces_left)
		return

	if faces_down:
		if _should_play_walk_animation() and can_use_walk_down_right_animation():
			body_sprite.visible = false
			set_walk_animation_active(true, faces_left, creature.species_data.walk_down_right_frames)
			return

		set_walk_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.down_right_texture, faces_left)
		return

	set_walk_animation_active(false)
	_apply_static_texture(body_sprite, creature.species_data.right_texture, faces_left)


func set_walk_animation_active(active: bool, flip_h: bool = false, sprite_frames: SpriteFrames = null, animation_fps: float = -1.0) -> void:
	var walk_sprite := _get_walk_sprite()
	if walk_sprite == null:
		return

	if active:
		if sprite_frames == null:
			return

		var must_restart := false

		walk_sprite.visible = true
		walk_sprite.flip_h = flip_h
		walk_sprite.speed_scale = max(_get_animation_fps(animation_fps), 0.0)

		if walk_sprite.sprite_frames != sprite_frames:
			walk_sprite.sprite_frames = sprite_frames
			must_restart = true

		if walk_sprite.animation != &"default":
			walk_sprite.animation = &"default"
			must_restart = true

		if must_restart:
			walk_sprite.stop()
			walk_sprite.frame = 0
			walk_sprite.play(&"default")
			return

		if not walk_sprite.is_playing():
			walk_sprite.play(&"default")
		return

	if not walk_sprite.visible:
		return

	walk_sprite.visible = false
	walk_sprite.stop()
	walk_sprite.frame = 0


func set_walk_right_animation_active(active: bool, flip_h: bool = false) -> void:
	set_walk_animation_active(active, flip_h, creature.species_data.walk_right_frames)


func _should_play_walk_animation() -> bool:
	if not bool(creature.is_moving):
		return false

	return creature.state == creature.State.WALK or creature.state == creature.State.SEEK_FOOD


func _should_play_eating_animation() -> bool:
	return creature.state == creature.State.EATING


func _has_valid_animation(sprite_frames: SpriteFrames) -> bool:
	if sprite_frames == null:
		return false

	if not sprite_frames.has_animation(&"default"):
		return false

	var frame_count := sprite_frames.get_frame_count(&"default")
	if frame_count <= 0:
		return false

	for frame_index in range(frame_count):
		if sprite_frames.get_frame_texture(&"default", frame_index) == null:
			return false

	return true


func _get_animation_fps(animation_fps: float) -> float:
	if animation_fps >= 0.0:
		return animation_fps

	return float(creature.species_data.walk_animation_fps)


func _update_last_horizontal_facing(direction: Vector2) -> void:
	if direction.x < -0.01:
		last_faces_left = true
		return

	if direction.x > 0.01:
		last_faces_left = false


func _apply_static_texture(body_sprite: Sprite2D, texture: Texture2D, flip_h: bool) -> void:
	if texture == null:
		return

	body_sprite.texture = texture
	body_sprite.flip_h = flip_h


func _get_body_sprite() -> Sprite2D:
	return creature.sprite as Sprite2D


func _get_walk_sprite() -> AnimatedSprite2D:
	return creature.walk_right_sprite as AnimatedSprite2D
