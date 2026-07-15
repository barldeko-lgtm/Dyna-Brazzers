extends Node2D

# Fixed player-owned nature base. It is a static 2x2 world-grid blocker and
# will become the egg-creation point in roadmap block 0.7.
@onready var body_sprite: Sprite2D = $BodySprite
@onready var shadow_sprite: Sprite2D = $ShadowSprite

@export var footprint_size := Vector2i(2, 2)
@export var visual_target_size := Vector2(256.0, 256.0)
@export var shadow_offset := Vector2(0.0, 18.0)
@export var shadow_alpha := 0.22

var world_grid: Node = null
var anchor_tile := Vector2i.ZERO
var is_registered_as_blocker := false


func _ready() -> void:
	configure_visual()
	world_grid = find_world_grid()

	if world_grid == null:
		push_error("PlayerBase: world grid was not found.")
		return

	var requested_anchor: Vector2i = world_grid.world_to_anchor_tile(
		global_position,
		footprint_size
	)
	anchor_tile = requested_anchor

	if not world_grid.can_place_footprint(anchor_tile, footprint_size, self):
		anchor_tile = world_grid.find_nearest_valid_anchor(
			requested_anchor,
			footprint_size,
			self,
			8
		)

	if not world_grid.register_blocker(self, anchor_tile, footprint_size):
		push_error(
			"PlayerBase: cannot occupy a valid 2x2 footprint near (%d, %d)." % [
				requested_anchor.x,
				requested_anchor.y
			]
		)
		queue_free()
		return

	if anchor_tile != requested_anchor:
		push_warning(
			"PlayerBase: spawn footprint was blocked; base moved from (%d, %d) to (%d, %d)." % [
				requested_anchor.x,
				requested_anchor.y,
				anchor_tile.x,
				anchor_tile.y
			]
		)

	is_registered_as_blocker = true
	global_position = world_grid.anchor_to_world_position(anchor_tile, footprint_size)


func _exit_tree() -> void:
	if world_grid != null and is_registered_as_blocker:
		world_grid.unregister_blocker(self, footprint_size)
		is_registered_as_blocker = false


func configure_visual() -> void:
	_configure_sprite_scale()
	_configure_shadow()


func _configure_sprite_scale() -> void:
	if body_sprite == null:
		return

	# The source art is intentionally larger than its 256x256 world footprint.
	# Linear filtering with mipmaps keeps the downscaled sprite clean and leaves
	# detail available when the observer camera zooms in.
	body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	if body_sprite.texture == null:
		return

	var texture_size := body_sprite.texture.get_size()

	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var sprite_scale := Vector2(
		visual_target_size.x / texture_size.x,
		visual_target_size.y / texture_size.y
	)
	body_sprite.scale = sprite_scale

	if shadow_sprite != null:
		shadow_sprite.scale = sprite_scale


func _configure_shadow() -> void:
	if shadow_sprite == null:
		return

	if body_sprite != null:
		shadow_sprite.texture = body_sprite.texture

	shadow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	shadow_sprite.position = shadow_offset
	shadow_sprite.modulate = Color(0.0, 0.0, 0.0, shadow_alpha)


func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_blocker") and current.has_method("world_to_anchor_tile"):
			return current

		current = current.get_parent()

	return null
