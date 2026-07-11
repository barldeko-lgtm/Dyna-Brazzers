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

const GRASS_ALLOWED_TILES := [Vector2i(20, 59), Vector2i(14, 63), Vector2i(20, 66), Vector2i(20, 67), Vector2i(21, 67), Vector2i(14, 68), Vector2i(14, 69), Vector2i(19, 75), Vector2i(20, 75), Vector2i(21, 75)]


func _enter_tree() -> void:
	if tile_set == null:
		call_deferred("_build_map_when_ready")
		return

	_build_map_and_sync()


func _build_map_when_ready() -> void:
	if tile_set == null:
		return

	_build_map_and_sync()


func _build_map_and_sync() -> void:
	_build_static_map()

	# In the editor we only need the terrain preview.
	if Engine.is_editor_hint():
		return

	var world_grid: Node = get_parent()
	if world_grid != null and world_grid.has_method("set_grass_allowed_tiles"):
		world_grid.set_grass_allowed_tiles(GRASS_ALLOWED_TILES)


func _build_static_map() -> void:
	clear()

	var tree_anchors: Array[Vector2i] = []

	for y in range(MAP_HEIGHT):
		var row: String = MAP_ROWS[y]

		for x in range(MAP_WIDTH):
			var tile := Vector2i(x, y)
			var marker := row.substr(x, 1)

			match marker:
				"W":
					set_cell(tile, TERRAIN_WATER, Vector2i(_variant_for_tile(tile, 9), 0))
				"M":
					set_cell(tile, TERRAIN_MOUNTAIN, Vector2i(_variant_for_tile(tile, 9), 0))
				"T":
					set_cell(tile, TERRAIN_GROUND, Vector2i.ZERO)
					tree_anchors.append(tile)
				_:
					set_cell(tile, TERRAIN_GROUND, Vector2i.ZERO)

	for anchor in tree_anchors:
		_place_tree(anchor, _variant_for_tile(anchor, 4))


func _place_tree(anchor: Vector2i, variant: int) -> void:
	var atlas_x := variant * 2

	set_cell(anchor, TERRAIN_TREE, Vector2i(atlas_x, 0))
	set_cell(anchor + Vector2i.RIGHT, TERRAIN_TREE, Vector2i(atlas_x + 1, 0))
	set_cell(anchor + Vector2i.DOWN, TERRAIN_TREE, Vector2i(atlas_x, 1))
	set_cell(anchor + Vector2i(1, 1), TERRAIN_TREE, Vector2i(atlas_x + 1, 1))


func _variant_for_tile(tile: Vector2i, variant_count: int) -> int:
	return posmod(tile.x * 17 + tile.y * 31, variant_count)
