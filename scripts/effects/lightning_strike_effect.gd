extends Node2D

@export var lifetime := 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if animated_sprite != null:
		animated_sprite.play(&"default")

	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(_queue_free_safely)


func _queue_free_safely() -> void:
	if is_queued_for_deletion():
		return

	queue_free()
