extends CharacterBody2D

enum State {
	IDLE,
	WALK
}

var state: State = State.WALK

@export var speed := 100.0

var direction := Vector2.ZERO
var change_timer := 0.0

func _ready():
	choose_new_direction()

func _physics_process(delta):
	match state:
		State.IDLE:
			update_idle(delta)
		State.WALK:
			update_walk(delta)

	move_and_slide()


func update_idle(delta):
	change_timer -= delta
	velocity = Vector2.ZERO

	if change_timer <= 0:
		choose_new_direction()
		state = State.WALK


func update_walk(delta):
	change_timer -= delta

	if change_timer <= 0:
		state = State.IDLE
		change_timer = randf_range(1.0, 3.0)

	velocity = direction * speed

	if change_timer <= 0:
		choose_new_direction()

	velocity = direction * speed


func choose_new_direction():
	direction = Vector2.from_angle(randf() * TAU)
	change_timer = randf_range(2.0, 5.0)
