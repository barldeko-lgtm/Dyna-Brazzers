extends Node

const GAMEPLAY_SCENE_PATH: String = "res://scenes/main/main.tscn"
const GAMEPLAY_MUSIC_PATH: String = "res://assets/audio/music/gameplay_theme.mp3"
const BUTTON_CLICK_PATH: String = "res://assets/audio/ui/button_click.wav"
const SETTINGS_PATH: String = "user://audio_settings.cfg"

const MASTER_BUS := &"Master"
const MUSIC_BUS := &"Music"
const SOUNDS_BUS := &"Sounds"
const AMBIENT_BUS := &"Ambient"
const SFX_BUS := &"SFX"
const UI_BUS := &"UI"

const DEFAULT_MUSIC_VOLUME: float = 0.45
const DEFAULT_SOUND_VOLUME: float = 1.0
const MUSIC_FADE_SECONDS: float = 1.25
const SILENT_VOLUME_DB: float = -80.0

var _music_player: AudioStreamPlayer = null
var _gameplay_music: AudioStream = null
var _button_click_stream: AudioStream = null
var _fade_tween: Tween = null
var _current_scene_path: String = ""
var _music_volume: float = DEFAULT_MUSIC_VOLUME
var _sound_volume: float = DEFAULT_SOUND_VOLUME


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_load_audio_settings()
	_apply_saved_volumes()
	_create_music_player()
	_load_gameplay_music()
	_load_button_click()

	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)

	call_deferred("_connect_existing_buttons")
	call_deferred("_sync_scene_audio")


func _process(_delta: float) -> void:
	var scene_path: String = _get_current_scene_path()

	if scene_path == _current_scene_path:
		return

	_current_scene_path = scene_path
	_sync_scene_audio()


func play_gameplay_music() -> void:
	if _gameplay_music == null or _music_player == null:
		return

	_kill_fade_tween()

	if _music_player.stream != _gameplay_music:
		_music_player.stream = _gameplay_music

	if not _music_player.playing:
		_music_player.volume_db = SILENT_VOLUME_DB
		_music_player.play()

	_fade_music_to(0.0, MUSIC_FADE_SECONDS, false)


func stop_music() -> void:
	_kill_fade_tween()

	if _music_player == null or not _music_player.playing:
		return

	_fade_music_to(SILENT_VOLUME_DB, MUSIC_FADE_SECONDS, true)


func play_sfx(
	stream: AudioStream,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0
) -> void:
	_play_one_shot(stream, SFX_BUS, volume_db, pitch_scale)


func play_ui_sfx(
	stream: AudioStream,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0
) -> void:
	_play_one_shot(stream, UI_BUS, volume_db, pitch_scale)


func play_button_click() -> void:
	if _button_click_stream == null:
		return

	play_ui_sfx(_button_click_stream, -4.0)


func get_music_volume() -> float:
	return _music_volume


func get_sound_volume() -> float:
	return _sound_volume


func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume_linear(MUSIC_BUS, _music_volume)
	_save_audio_settings()


func set_sound_volume(value: float) -> void:
	_sound_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume_linear(SOUNDS_BUS, _sound_volume)
	_save_audio_settings()


func set_master_volume(value: float) -> void:
	_set_bus_volume_linear(MASTER_BUS, value)


func set_ambient_volume(value: float) -> void:
	_set_bus_volume_linear(AMBIENT_BUS, value)


func set_sfx_volume(value: float) -> void:
	_set_bus_volume_linear(SFX_BUS, value)


func set_ui_volume(value: float) -> void:
	_set_bus_volume_linear(UI_BUS, value)


func _sync_scene_audio() -> void:
	_current_scene_path = _get_current_scene_path()

	if _current_scene_path == GAMEPLAY_SCENE_PATH:
		play_gameplay_music()
	else:
		stop_music()


func _get_current_scene_path() -> String:
	var current_scene: Node = get_tree().current_scene

	if current_scene == null:
		return ""

	return current_scene.scene_file_path


func _create_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = MUSIC_BUS
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)


func _load_gameplay_music() -> void:
	_gameplay_music = load(GAMEPLAY_MUSIC_PATH) as AudioStream

	if _gameplay_music == null:
		push_warning("AudioManager could not load gameplay music: %s" % GAMEPLAY_MUSIC_PATH)
		return

	if _gameplay_music is AudioStreamMP3:
		(_gameplay_music as AudioStreamMP3).loop = true


func _load_button_click() -> void:
	_button_click_stream = load(BUTTON_CLICK_PATH) as AudioStream

	if _button_click_stream == null:
		push_warning("AudioManager could not load button click: %s" % BUTTON_CLICK_PATH)


func _on_tree_node_added(node: Node) -> void:
	_connect_button(node as BaseButton)


func _connect_existing_buttons() -> void:
	_connect_buttons_recursive(get_tree().root)


func _connect_buttons_recursive(node: Node) -> void:
	_connect_button(node as BaseButton)

	for child: Node in node.get_children():
		_connect_buttons_recursive(child)


func _connect_button(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button):
		return

	if not button.button_down.is_connected(_on_any_button_down):
		button.button_down.connect(_on_any_button_down)


func _on_any_button_down() -> void:
	play_button_click()


func _play_one_shot(
	stream: AudioStream,
	bus_name: StringName,
	volume_db: float,
	pitch_scale: float
) -> void:
	if stream == null:
		return

	var player := AudioStreamPlayer.new()
	player.name = "OneShotAudio"
	player.stream = stream
	player.bus = bus_name
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch_scale, 0.01, 4.0)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.finished.connect(_on_one_shot_finished.bind(player))
	player.play()


func _on_one_shot_finished(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player):
		player.queue_free()


func _fade_music_to(target_db: float, duration: float, stop_after: bool) -> void:
	_kill_fade_tween()

	if _music_player == null:
		return

	if duration <= 0.0:
		_music_player.volume_db = target_db

		if stop_after:
			_finish_music_stop()

		return

	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_music_player, "volume_db", target_db, duration)

	if stop_after:
		_fade_tween.tween_callback(_finish_music_stop)


func _finish_music_stop() -> void:
	if _music_player != null:
		_music_player.stop()
		_music_player.volume_db = 0.0

	_fade_tween = null


func _kill_fade_tween() -> void:
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()

	_fade_tween = null


func _ensure_audio_buses() -> void:
	_ensure_audio_bus_exists(MUSIC_BUS)
	_ensure_audio_bus_exists(SOUNDS_BUS)
	_ensure_audio_bus_exists(AMBIENT_BUS)
	_ensure_audio_bus_exists(SFX_BUS)
	_ensure_audio_bus_exists(UI_BUS)

	_move_audio_bus(MUSIC_BUS, 1)
	_move_audio_bus(SOUNDS_BUS, 2)
	_move_audio_bus(AMBIENT_BUS, 3)
	_move_audio_bus(SFX_BUS, 4)
	_move_audio_bus(UI_BUS, 5)

	_set_bus_send(MUSIC_BUS, MASTER_BUS)
	_set_bus_send(SOUNDS_BUS, MASTER_BUS)
	_set_bus_send(AMBIENT_BUS, SOUNDS_BUS)
	_set_bus_send(SFX_BUS, SOUNDS_BUS)
	_set_bus_send(UI_BUS, SOUNDS_BUS)

	_set_bus_volume_db(AMBIENT_BUS, -3.0)
	_set_bus_volume_db(SFX_BUS, 0.0)
	_set_bus_volume_db(UI_BUS, -2.0)


func _ensure_audio_bus_exists(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return

	AudioServer.add_bus()
	var bus_index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, String(bus_name))


func _move_audio_bus(bus_name: StringName, target_index: int) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index < 0 or bus_index == target_index:
		return

	AudioServer.move_bus(bus_index, target_index)


func _set_bus_send(bus_name: StringName, send_bus: StringName) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index >= 0:
		AudioServer.set_bus_send(bus_index, send_bus)


func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	var load_error: Error = config.load(SETTINGS_PATH)

	if load_error != OK:
		return

	_music_volume = clampf(
		float(config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)),
		0.0,
		1.0
	)
	_sound_volume = clampf(
		float(config.get_value("audio", "sound_volume", DEFAULT_SOUND_VOLUME)),
		0.0,
		1.0
	)


func _apply_saved_volumes() -> void:
	_set_bus_volume_linear(MUSIC_BUS, _music_volume)
	_set_bus_volume_linear(SOUNDS_BUS, _sound_volume)


func _save_audio_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", _music_volume)
	config.set_value("audio", "sound_volume", _sound_volume)

	var save_error: Error = config.save(SETTINGS_PATH)

	if save_error != OK:
		push_warning("AudioManager could not save audio settings.")


func _set_bus_volume_linear(bus_name: StringName, value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index < 0:
		return

	var normalized_value: float = clampf(value, 0.0, 1.0)
	var should_mute: bool = normalized_value <= 0.001
	AudioServer.set_bus_mute(bus_index, should_mute)

	if not should_mute:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(normalized_value))


func _set_bus_volume_db(bus_name: StringName, value_db: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, value_db)
