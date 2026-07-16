extends Node

const GAMEPLAY_SCENE_PATH := "res://scenes/main/main.tscn"
const GAMEPLAY_MUSIC_PATH := "res://assets/audio/music/gameplay_theme.mp3"

const MASTER_BUS := &"Master"
const MUSIC_BUS := &"Music"
const AMBIENT_BUS := &"Ambient"
const SFX_BUS := &"SFX"
const UI_BUS := &"UI"

const MUSIC_FADE_SECONDS := 1.25
const SILENT_VOLUME_DB := -80.0

var _music_player: AudioStreamPlayer
var _gameplay_music: AudioStream
var _fade_tween: Tween
var _current_scene_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_create_music_player()
	_load_gameplay_music()
	call_deferred("_sync_scene_audio")


func _process(_delta: float) -> void:
	var scene_path := _get_current_scene_path()
	if scene_path == _current_scene_path:
		return
	_current_scene_path = scene_path
	_sync_scene_audio()


func play_gameplay_music() -> void:
	if _gameplay_music == null:
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
	if not _music_player.playing:
		return
	_fade_music_to(SILENT_VOLUME_DB, MUSIC_FADE_SECONDS, true)


func set_master_volume(value: float) -> void:
	_set_bus_volume_linear(MASTER_BUS, value)


func set_music_volume(value: float) -> void:
	_set_bus_volume_linear(MUSIC_BUS, value)


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
	var current_scene := get_tree().current_scene
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


func _fade_music_to(target_db: float, duration: float, stop_after: bool) -> void:
	_kill_fade_tween()
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
	_music_player.stop()
	_music_player.volume_db = 0.0
	_fade_tween = null


func _kill_fade_tween() -> void:
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null


func _ensure_audio_buses() -> void:
	_ensure_audio_bus(MUSIC_BUS, -7.0)
	_ensure_audio_bus(AMBIENT_BUS, -3.0)
	_ensure_audio_bus(SFX_BUS, 0.0)
	_ensure_audio_bus(UI_BUS, -2.0)


func _ensure_audio_bus(bus_name: StringName, default_volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, String(bus_name))
	AudioServer.set_bus_send(bus_index, MASTER_BUS)
	AudioServer.set_bus_volume_db(bus_index, default_volume_db)


func _set_bus_volume_linear(bus_name: StringName, value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var normalized_value := clampf(value, 0.0, 1.0)
	var should_mute := normalized_value <= 0.001
	AudioServer.set_bus_mute(bus_index, should_mute)
	if not should_mute:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(normalized_value))
