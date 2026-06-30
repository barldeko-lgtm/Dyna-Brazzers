extends CanvasLayer

# Панель со статами существа в углу экрана.
@onready var panel: PanelContainer = $CreatureStatsPanel

# Заголовок панели.
@onready var title_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/TitleLabel

# Подпись блока сытости.
@onready var hunger_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HungerLabel

# Подпись блока здоровья.
@onready var health_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HealthLabel

# Горизонтальная шкала здоровья.
@onready var health_bar: ProgressBar = $CreatureStatsPanel/MarginContainer/VBoxContainer/HealthBar

# Горизонтальная шкала сытости.
@onready var hunger_bar: ProgressBar = $CreatureStatsPanel/MarginContainer/VBoxContainer/HungerBar

# Метка с текущим FPS в нижнем углу экрана.
@onready var fps_label: Label = $FpsLabel

# Существо, которое сейчас показывается в панели.
var current_creature: Node = null


# Подготавливает панель и скрывает её до наведения мыши.
func _ready() -> void:
	add_to_group("creature_stats_ui")
	panel.visible = false


# Обновляет панель каждый кадр, пока мышка наведена на существо.
func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	if not is_instance_valid(current_creature):
		hide_creature_stats()
		return

	update_stats_text()


# Показывает панель и привязывает её к выбранному существу.
func show_creature_stats(creature: Node) -> void:
	if creature == null:
		return

	current_creature = creature
	panel.visible = true
	update_stats_text()


# Скрывает панель и очищает ссылку на существо.
func hide_creature_stats() -> void:
	current_creature = null
	panel.visible = false


# Перерисовывает текст статов по текущему существу.
func update_stats_text() -> void:
	if not is_instance_valid(current_creature):
		return

	if current_creature.has_method("get_creature_name"):
		title_label.text = current_creature.get_creature_name()
	else:
		title_label.text = "Существо"

	health_label.text = "Здоровье"
	hunger_label.text = "Сытость"

	if current_creature.has_method("get_health_percent"):
		health_bar.value = current_creature.get_health_percent()
	else:
		health_bar.value = 0.0

	if current_creature.has_method("get_hunger_percent"):
		hunger_bar.value = current_creature.get_hunger_percent()
		return

	hunger_bar.value = 0.0
