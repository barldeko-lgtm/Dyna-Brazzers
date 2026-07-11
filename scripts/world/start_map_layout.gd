@tool
extends TileMapLayer

# Fixed 85×85 start map authored from assets/maps/start_map_layout.png.
# One character equals one 128×128 world tile.
const MAP_WIDTH := 85
const MAP_HEIGHT := 85

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



func _build_static_map() -> void:
	clear()

	var tree_anchors: Array[Vector2i] = []

	for y in range(MAP_HEIGHT):
		var row: String = MAP_ROWS[y]

		for x in range(MAP_WIDTH):
			var tile := Vector2i(x, y)
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
	return tile.x >= 0 and tile.x < MAP_WIDTH and tile.y >= 0 and tile.y < MAP_HEIGHT


func _get_layout_marker(tile: Vector2i) -> String:
	var row: String = MAP_ROWS[tile.y]
	return row.substr(tile.x, 1)


func _place_tree(anchor: Vector2i, variant: int) -> void:
	var atlas_x := variant * 2

	set_cell(anchor, TERRAIN_TREE, Vector2i(atlas_x, 0))
	set_cell(anchor + Vector2i.RIGHT, TERRAIN_TREE, Vector2i(atlas_x + 1, 0))
	set_cell(anchor + Vector2i.DOWN, TERRAIN_TREE, Vector2i(atlas_x, 1))
	set_cell(anchor + Vector2i(1, 1), TERRAIN_TREE, Vector2i(atlas_x + 1, 1))


func _variant_for_tile(tile: Vector2i, variant_count: int) -> int:
	return posmod(tile.x * 17 + tile.y * 31, variant_count)
