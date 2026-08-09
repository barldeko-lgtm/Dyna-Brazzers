extends Control

@export var dim_color := Color(0.0, 0.0, 0.0, 0.6)
@export var highlight_border_color := Color(1.0, 0.86, 0.42, 0.95)
@export var highlight_border_width := 3.0

var hole_rects: Array[Rect2] = []


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func set_hole_rects(new_hole_rects: Array) -> void:
	hole_rects.clear()
	var bounds := Rect2(Vector2.ZERO, size)

	for rect_variant: Variant in new_hole_rects:
		if not (rect_variant is Rect2):
			continue
		var clipped_rect := (rect_variant as Rect2).intersection(bounds)
		if clipped_rect.size.x <= 0.0 or clipped_rect.size.y <= 0.0:
			continue
		hole_rects.append(clipped_rect)

	queue_redraw()


func get_hole_rects() -> Array[Rect2]:
	return hole_rects.duplicate()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var x_boundaries: Array[float] = [0.0, size.x]
	var y_boundaries: Array[float] = [0.0, size.y]

	for hole_rect: Rect2 in hole_rects:
		x_boundaries.append(hole_rect.position.x)
		x_boundaries.append(hole_rect.end.x)
		y_boundaries.append(hole_rect.position.y)
		y_boundaries.append(hole_rect.end.y)

	x_boundaries.sort()
	y_boundaries.sort()

	for y_index: int in range(y_boundaries.size() - 1):
		for x_index: int in range(x_boundaries.size() - 1):
			var cell := Rect2(
				Vector2(x_boundaries[x_index], y_boundaries[y_index]),
				Vector2(
					x_boundaries[x_index + 1] - x_boundaries[x_index],
					y_boundaries[y_index + 1] - y_boundaries[y_index]
				)
			)
			if cell.size.x <= 0.0 or cell.size.y <= 0.0:
				continue
			if _is_inside_any_hole(cell.get_center()):
				continue
			draw_rect(cell, dim_color, true)

	for hole_rect: Rect2 in hole_rects:
		draw_rect(hole_rect, highlight_border_color, false, highlight_border_width)


func _is_inside_any_hole(point: Vector2) -> bool:
	for hole_rect: Rect2 in hole_rects:
		if hole_rect.has_point(point):
			return true
	return false
