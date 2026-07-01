extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world_scene: PackedScene = load("res://scenes/world/world.tscn")
	var world = world_scene.instantiate()
	root.add_child(world)
	await process_frame
	var grid = world
	print("map_min=%s map_max=%s tile_size=%s" % [str(grid.map_min), str(grid.map_max), str(grid.tile_size)])
	for child in world.get_node("Creatures").get_children():
		if child is Marker2D:
			print("marker %s tile=%s" % [child.name, str(grid.world_to_map_tile(child.global_position))])
		elif child.has_method("get"):
			print("creature %s anchor=%s world=%s" % [child.name, str(child.anchor_tile), str(child.global_position)])
	for child in world.get_node("Grasses").get_children():
		print("grass %s tile=%s world=%s" % [child.name, str(child.tile_position), str(child.global_position)])
	quit()
