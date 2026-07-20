extends RefCounted

var creature: Node
var last_faces_left := false
var ground_shadow_sprite: Sprite2D = null
var ground_shadow_uses_upward_diagonal := false
var ground_shadow_offset_y := 0.0
var ground_shadow_base_scale_y := 0.36
var ground_shadow_diagonal_rotation_degrees := 0.0
var ground_shadow_diagonal_scale_y := 0.0


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


func configure_ground_shadow() -> void:
	ground_shadow_offset_y = (
		90.0 if creature.species_data != null and creature.species_data.is_predator() else 72.0
	)
	# Diagonal poses rotate the shadow instead of squishing it straight down.
	ground_shadow_diagonal_rotation_degrees = -30.0
	ground_shadow_diagonal_scale_y = 0.48

	ground_shadow_sprite = Sprite2D.new()
	ground_shadow_sprite.name = "GroundShadow"
	ground_shadow_sprite.position = Vector2(0.0, ground_shadow_offset_y)
	ground_shadow_sprite.scale = Vector2(1.0, ground_shadow_base_scale_y)
	ground_shadow_sprite.flip_v = true
	ground_shadow_sprite.modulate = Color(0.08, 0.06, 0.04, 0.34)
	ground_shadow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground_shadow_sprite.z_as_relative = false
	ground_shadow_sprite.z_index = 0
	creature.add_child(ground_shadow_sprite)
	creature.move_child(ground_shadow_sprite, 0)

	var walk_sprite := _get_walk_sprite()
	var frame_changed_callable := Callable(self, "sync_ground_shadow_from_current_visual")
	if walk_sprite != null and not walk_sprite.frame_changed.is_connected(frame_changed_callable):
		walk_sprite.frame_changed.connect(frame_changed_callable)


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

	set_ground_shadow_upward_diagonal(false)

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
			set_walk_animation_active(
				true,
				last_faces_left,
				creature.species_data.eating_right_frames,
				creature.species_data.eating_animation_fps
			)
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
		set_ground_shadow_upward_diagonal(true)
		if _should_play_walk_animation() and can_use_walk_up_right_animation():
			body_sprite.visible = false
			set_walk_animation_active(
				true,
				faces_left,
				creature.species_data.walk_up_right_frames
			)
			return
		set_walk_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.up_right_texture, faces_left)
		return

	if faces_down:
		if _should_play_walk_animation() and can_use_walk_down_right_animation():
			body_sprite.visible = false
			set_walk_animation_active(
				true,
				faces_left,
				creature.species_data.walk_down_right_frames
			)
			return
		set_walk_animation_active(false)
		_apply_static_texture(body_sprite, creature.species_data.down_right_texture, faces_left)
		return

	set_walk_animation_active(false)
	_apply_static_texture(body_sprite, creature.species_data.right_texture, faces_left)


func show_death_visual() -> void:
	set_ground_shadow_upward_diagonal(false)
	set_walk_animation_active(false)

	var body_sprite := _get_body_sprite()
	if body_sprite == null:
		return

	body_sprite.visible = true
	body_sprite.flip_h = false

	if creature.species_data != null and creature.species_data.death_texture != null:
		body_sprite.texture = creature.species_data.death_texture
	elif creature.species_data != null and creature.species_data.right_texture != null:
		body_sprite.texture = creature.species_data.right_texture

	sync_ground_shadow_from_current_visual()


func set_walk_animation_active(
	active: bool,
	flip_h: bool = false,
	sprite_frames: SpriteFrames = null,
	animation_fps: float = -1.0
) -> void:
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


func set_ground_shadow_upward_diagonal(enabled: bool) -> void:
	ground_shadow_uses_upward_diagonal = enabled


func sync_ground_shadow_from_current_visual() -> void:
	if ground_shadow_sprite == null:
		return

	var walk_sprite := _get_walk_sprite()
	if walk_sprite != null and walk_sprite.visible and walk_sprite.sprite_frames != null:
		var frames := walk_sprite.sprite_frames
		var animation := walk_sprite.animation
		if frames.has_animation(animation):
			ground_shadow_sprite.texture = frames.get_frame_texture(animation, walk_sprite.frame)
			ground_shadow_sprite.flip_h = _get_ground_shadow_flip_h(walk_sprite.flip_h)
			ground_shadow_sprite.visible = ground_shadow_sprite.texture != null
			_apply_ground_shadow_pose(ground_shadow_sprite.flip_h)
			return

	var body_sprite := _get_body_sprite()
	if body_sprite == null:
		ground_shadow_sprite.visible = false
		return

	ground_shadow_sprite.texture = body_sprite.texture
	ground_shadow_sprite.flip_h = _get_ground_shadow_flip_h(body_sprite.flip_h)
	ground_shadow_sprite.visible = body_sprite.visible and ground_shadow_sprite.texture != null
	_apply_ground_shadow_pose(ground_shadow_sprite.flip_h)


func _ground_shadow_is_diagonal() -> bool:
	if ground_shadow_uses_upward_diagonal:
		return true

	var body_sprite := _get_body_sprite()
	var walk_sprite := _get_walk_sprite()
	if creature.species_data != null and body_sprite != null:
		if (
			body_sprite.texture == creature.species_data.up_right_texture
			and creature.species_data.up_right_texture != null
		):
			return true
		if (
			walk_sprite != null
			and walk_sprite.visible
			and walk_sprite.sprite_frames == creature.species_data.walk_up_right_frames
			and creature.species_data.walk_up_right_frames != null
		):
			return true

	return false


func _get_ground_shadow_flip_h(source_flip_h: bool) -> bool:
	# Diagonal poses use rotation, so their shadow mirrors exactly like the body.
	return source_flip_h


func _apply_ground_shadow_pose(flip_h: bool) -> void:
	if ground_shadow_sprite == null:
		return

	ground_shadow_sprite.position = Vector2(0.0, ground_shadow_offset_y)

	if _ground_shadow_is_diagonal():
		var rotation_sign := -1.0 if flip_h else 1.0
		ground_shadow_sprite.rotation = (
			deg_to_rad(ground_shadow_diagonal_rotation_degrees) * rotation_sign
		)
		ground_shadow_sprite.scale = Vector2(1.0, ground_shadow_diagonal_scale_y)
		return

	ground_shadow_sprite.rotation = 0.0
	ground_shadow_sprite.scale = Vector2(1.0, ground_shadow_base_scale_y)


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
