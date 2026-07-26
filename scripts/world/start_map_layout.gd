@tool
extends TileMapLayer

# Fixed 85×85 start map authored from assets/maps/start_map_layout.png.
# One character equals one 128×128 world tile.
const MAP_WIDTH := 85
const MAP_HEIGHT := 85
const LEVEL_2_ID := 2
const LEVEL_2_MAP_TEXTURE := preload("res://assets/maps/level_2_map.png")
const PIXEL_MAP_PARSER := preload("res://scripts/world/pixel_map_parser.gd")
const GRASS_SCENE := preload("res://scenes/resources/grass.tscn")

const TERRAIN_GROUND := 0
const TERRAIN_WATER := 1
const TERRAIN_MOUNTAIN := 2
const TERRAIN_TREE := 3

const MAP_ROWS := [
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW...............................WW..........................................WWWWW",
	"WWWWW...............................WW..........................................WWWWW",
	"WWWWW...............................WWW.........................................WWWWW",
	"WWWWW...........................T....WW.........................................WWWWW",
	"WWWWW...........T...............................................................WWWWW",
	"WWWWW...............WW....MM....................................................WWWWW",
	"WWWWW...............WW....MM....................................................WWWWW",
	"WWWWW.....................MMM...................................................WWWWW",
	"WWWWW......MM.............MMMM..................................................WWWWW",
	"WWWWW......M...............MMM..................................................WWWWW",
	"WWWWW.....MM...............MMM..................................................WWWWW",
	"WWWWW.....MM...........T...MMM..................................................WWWWW",
	"WWWWW.....MM...............MMM..................................................WWWWW",
	"WWWWW.....MM...............MM....T..............................................WWWWW",
	"WWWWW...........T..........MM...................................................WWWWW",
	"WWWWW...............G...........................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW..........................WWWWWWWW.........................................WWWWW",
	"WWWWW..T...........T..........WWWWWWWW..........................................WWWWW",
	"WWWWW.........G...............WW................................................WWWWW",
	"WWWWW....................T....WW................................................WWWWW",
	"WWWWW.........................WW................................................WWWWW",
	"WWWWW....T..........G.........W.................................................WWWWW",
	"WWWWW...............GG..........................................................WWWWW",
	"WWWWW.........G.................................................................WWWWW",
	"WWWWW.........G.................................................................WWWWW",
	"WWWWW.....MM.............WW.....................................................WWWWW",
	"WWWWW.....MM.....T.......WW.....................................................WWWWW",
	"WWWWW......MM............W......................................................WWWWW",
	"WWWWW......MMM................T...MM............................................WWWWW",
	"WWWWW......MMM....................MMMMMM........................................WWWWW",
	"WWWWW..............GGG............MMMMMM........................................WWWWW",
	"WWWWW..................T........................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWW.....T.....................................................................WWWWW",
	"WWWWW...........................................................................WWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
]

var active_map_width := MAP_WIDTH
var active_map_height := MAP_HEIGHT
var active_map_rows: Array[String] = []


func _enter_tree() -> void:
	if _is_level_2_active():
		_build_level_2_map()
		return

	if tile_set == null:
		call_deferred("_build_map_when_ready")
		return

	_build_map_if_empty()


func _build_map_when_ready() -> void:
	if tile_set == null:
		return

	_build_map_if_empty()


func _build_map_if_empty() -> void:
	# Never overwrite a TileMap that was edited and saved in Godot.
	if not get_used_cells().is_empty():
		return

	_build_static_map()


func _build_static_map() -> void:
	_set_active_layout(MAP_ROWS, MAP_WIDTH, MAP_HEIGHT)
	clear()

	var tree_anchors: Array[Vector2i] = []

	for y in range(MAP_HEIGHT):
		var row: String = MAP_ROWS[y]

		for x in range(MAP_WIDTH):
			var tile: Vector2i = Vector2i(x, y)
			var marker: String = row.substr(x, 1)

			match marker:
				"W":
					set_cell(tile, TERRAIN_WATER, Vector2i(_get_water_atlas_x(tile), 0))
				"M":
					set_cell(tile, TERRAIN_MOUNTAIN, Vector2i(_get_mountain_atlas_x(tile), 0))
				"T":
					set_cell(tile, TERRAIN_GROUND, Vector2i.ZERO)
					tree_anchors.append(tile)
				_:
					set_cell(tile, TERRAIN_GROUND, Vector2i.ZERO)

	for anchor in tree_anchors:
		_place_tree(anchor, _variant_for_tile(anchor, 4))


func _is_level_2_active() -> bool:
	var save_system := get_node_or_null("/root/SaveSystem")

	if save_system == null:
		return false

	return int(save_system.get("current_level_id")) == LEVEL_2_ID


func _build_level_2_map() -> void:
	if tile_set == null:
		push_error("StartMapLayout: level 2 TileSet is unavailable.")
		return

	var parser := PIXEL_MAP_PARSER.new() as RefCounted
	var map_data: Dictionary = parser.parse_image(LEVEL_2_MAP_TEXTURE.get_image())

	if not bool(map_data.get("ok", false)):
		push_error("StartMapLayout: invalid level 2 pixel map: %s" % str(map_data.get("errors", [])))
		return

	var rows_variant: Variant = map_data.get("rows", [])
	var rows: Array[String] = []

	if rows_variant is Array:
		for row_variant in rows_variant:
			rows.append(String(row_variant))

	_set_active_layout(
		rows,
		int(map_data.get("width", 0)),
		int(map_data.get("height", 0))
	)
	clear()

	var dry_ground := get_parent().get_node_or_null("DryGround") as TileMapLayer

	if dry_ground == null or dry_ground.tile_set == null:
		push_error("StartMapLayout: DryGround layer is unavailable for level 2.")
		return

	dry_ground.clear()

	for y in range(active_map_height):
		for x in range(active_map_width):
			var tile := Vector2i(x, y)
			var marker: String = _get_layout_marker(tile)

			match marker:
				"W":
					set_cell(tile, TERRAIN_WATER, Vector2i(_get_water_atlas_x(tile), 0))
				"M":
					set_cell(tile, TERRAIN_MOUNTAIN, Vector2i(_get_mountain_atlas_x(tile), 0))
				"D":
					set_cell(tile, TERRAIN_GROUND, Vector2i.ZERO)
					dry_ground.set_cell(tile, _variant_for_tile(tile, 3), Vector2i.ZERO)
				_:
					set_cell(tile, TERRAIN_GROUND, Vector2i.ZERO)

	var tree_anchors_variant: Variant = map_data.get("tree_anchors", [])

	if tree_anchors_variant is Array:
		for anchor_variant in tree_anchors_variant:
			if anchor_variant is Vector2i:
				var tree_anchor: Vector2i = anchor_variant
				_place_tree(tree_anchor, _variant_for_tile(tree_anchor, 4))

	var base_anchors_variant: Variant = map_data.get("base_anchors", [])

	if base_anchors_variant is Array and base_anchors_variant.size() == 2:
		_set_base_marker_position("CameraStart", base_anchors_variant[0])
		_set_base_marker_position("EnemyBaseStart", base_anchors_variant[1])

	var grass_tiles_variant: Variant = map_data.get("grass_tiles", [])

	if grass_tiles_variant is Array:
		_rebuild_level_2_grass(grass_tiles_variant)


func _set_active_layout(rows: Array, width: int, height: int) -> void:
	active_map_rows.clear()

	for row_variant in rows:
		active_map_rows.append(String(row_variant))

	active_map_width = width
	active_map_height = height


func _set_base_marker_position(marker_name: String, anchor_variant: Variant) -> void:
	if not (anchor_variant is Vector2i):
		return

	var marker := get_parent().get_node_or_null(marker_name) as Marker2D

	if marker == null:
		push_error("StartMapLayout: %s marker is unavailable for level 2." % marker_name)
		return

	var footprint_center_offset := Vector2(tile_set.tile_size) * 0.5
	var anchor: Vector2i = anchor_variant
	var marker_in_ground_parent: Vector2 = transform * (
		map_to_local(anchor) + footprint_center_offset
	)
	marker.position = marker_in_ground_parent


func _rebuild_level_2_grass(grass_tiles: Array) -> void:
	var grasses := get_parent().get_node_or_null("Grasses") as Node2D

	if grasses == null:
		push_error("StartMapLayout: Grasses container is unavailable for level 2.")
		return

	for authored_grass in grasses.get_children():
		authored_grass.free()

	for tile_variant in grass_tiles:
		if not (tile_variant is Vector2i):
			continue

		var tile: Vector2i = tile_variant
		var grass := GRASS_SCENE.instantiate() as Node2D

		if grass == null:
			continue

		grass.name = "Level2Grass_%02d_%02d" % [tile.x, tile.y]
		var tile_in_world: Vector2 = transform * map_to_local(tile)
		grass.position = grasses.transform.affine_inverse() * tile_in_world
		grasses.add_child(grass)


# The water atlas uses:
# 0 full water;
# 1/2/3/4 shore toward north/south/west/east land;
# 5/6/7/8 the matching two-sided shore corners.
func _get_water_atlas_x(tile: Vector2i) -> int:
	var land_mask: int = 0

	if _is_land_next_to_water(tile + Vector2i.UP):
		land_mask |= 1
	if _is_land_next_to_water(tile + Vector2i.RIGHT):
		land_mask |= 2
	if _is_land_next_to_water(tile + Vector2i.DOWN):
		land_mask |= 4
	if _is_land_next_to_water(tile + Vector2i.LEFT):
		land_mask |= 8

	match land_mask:
		0:
			return 0
		1:
			return 1
		4:
			return 2
		8:
			return 3
		2:
			return 4
		9:
			return 5
		3:
			return 6
		12:
			return 7
		6:
			return 8
		# The atlas has no three-sided or channel tiles.
		# Use the edge facing the only open water direction.
		7:
			return 4
		14:
			return 2
		11:
			return 1
		13:
			return 3
		_:
			return 0


# The mountain atlas uses:
# 4 full mountains;
# the other eight tiles are edges/corners facing surrounding ground.
func _get_mountain_atlas_x(tile: Vector2i) -> int:
	var exposed_mask: int = 0

	if _is_mountain_edge(tile + Vector2i.UP):
		exposed_mask |= 1
	if _is_mountain_edge(tile + Vector2i.RIGHT):
		exposed_mask |= 2
	if _is_mountain_edge(tile + Vector2i.DOWN):
		exposed_mask |= 4
	if _is_mountain_edge(tile + Vector2i.LEFT):
		exposed_mask |= 8

	match exposed_mask:
		0:
			return 4
		1:
			return 8
		2:
			return 5
		4:
			return 1
		8:
			return 6
		3:
			return 7
		9:
			return 0
		6:
			return 2
		12:
			return 3
		# The atlas has no three-sided or one-tile corridor pieces.
		# Keep the mountain connected toward its only mountain neighbour.
		7:
			return 5
		14:
			return 1
		11:
			return 8
		13:
			return 6
		_:
			return 4


func _is_land_next_to_water(tile: Vector2i) -> bool:
	if not _is_inside_layout(tile):
		return false

	return _get_layout_marker(tile) != "W"


func _is_mountain_edge(tile: Vector2i) -> bool:
	if not _is_inside_layout(tile):
		return true

	return _get_layout_marker(tile) != "M"


func _is_inside_layout(tile: Vector2i) -> bool:
	return (
		tile.x >= 0
		and tile.x < active_map_width
		and tile.y >= 0
		and tile.y < active_map_height
	)


func _get_layout_marker(tile: Vector2i) -> String:
	var row: String = active_map_rows[tile.y]
	return row.substr(tile.x, 1)


func _place_tree(anchor: Vector2i, variant: int) -> void:
	var atlas_x: int = variant * 2

	set_cell(anchor, TERRAIN_TREE, Vector2i(atlas_x, 0))
	set_cell(anchor + Vector2i.RIGHT, TERRAIN_TREE, Vector2i(atlas_x + 1, 0))
	set_cell(anchor + Vector2i.DOWN, TERRAIN_TREE, Vector2i(atlas_x, 1))
	set_cell(anchor + Vector2i(1, 1), TERRAIN_TREE, Vector2i(atlas_x + 1, 1))


func _variant_for_tile(tile: Vector2i, variant_count: int) -> int:
	return posmod(tile.x * 17 + tile.y * 31, variant_count)
