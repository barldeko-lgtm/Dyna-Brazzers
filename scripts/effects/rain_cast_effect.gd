extends Node2D

const FRAME_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/effects/rain/rain_cast_01.png"),
	preload("res://assets/sprites/effects/rain/rain_cast_02.png"),
	preload("res://assets/sprites/effects/rain/rain_cast_03.png"),
	preload("res://assets/sprites/effects/rain/rain_cast_04.png"),
]

@export_range(0.1, 10.0, 0.1) var duration_seconds: float = 1.0

@onready var effect_sprite: Sprite2D = $EffectSprite

var started_at_msec: int = 0
var displayed_frame: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_at_msec = Time.get_ticks_msec()
	set_process(true)
	_show_frame(0)


func _process(_delta: float) -> void:
	if duration_seconds <= 0.0:
		queue_free()
		return

	var elapsed_seconds: float = float(Time.get_ticks_msec() - started_at_msec) / 1000.0

	if elapsed_seconds >= duration_seconds:
		queue_free()
		return

	var progress: float = clampf(
		elapsed_seconds / duration_seconds,
		0.0,
		0.999999
	)
	var frame_index: int = clampi(
		int(progress * float(FRAME_TEXTURES.size())),
		0,
		FRAME_TEXTURES.size() - 1
	)
	_show_frame(frame_index)


func _show_frame(frame_index: int) -> void:
	if effect_sprite == null:
		return

	if frame_index == displayed_frame:
		return

	displayed_frame = frame_index
	effect_sprite.texture = FRAME_TEXTURES[frame_index]
