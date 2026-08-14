extends Node

const START_SCREEN_SCENE_PATH := "res://scenes/ui/start_screen.tscn"
const CREATOR_TEXT := "Created by Bolto"

var release_info: VBoxContainer = null
var main_menu_center: Control = null
var tutorial_choice_layer: Control = null
var loading_layer: Control = null


func _ready() -> void:
	call_deferred("_bind_current_scene")


func _bind_current_scene() -> void:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		get_tree().process_frame.connect(_bind_current_scene, CONNECT_ONE_SHOT)
		return

	current_scene.tree_exited.connect(_on_current_scene_exited, CONNECT_ONE_SHOT)

	if current_scene.scene_file_path == START_SCREEN_SCENE_PATH:
		_attach_release_info(current_scene as Control)


func _on_current_scene_exited() -> void:
	release_info = null
	main_menu_center = null
	tutorial_choice_layer = null
	loading_layer = null
	get_tree().process_frame.connect(_bind_current_scene, CONNECT_ONE_SHOT)


func _attach_release_info(start_screen: Control) -> void:
	if start_screen == null:
		return

	var existing := start_screen.get_node_or_null("ReleaseInfo") as VBoxContainer

	if existing != null:
		release_info = existing
		return

	release_info = VBoxContainer.new()
	release_info.name = "ReleaseInfo"
	release_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	release_info.add_theme_constant_override("separation", 0)
	start_screen.add_child(release_info)

	release_info.anchor_left = 0.0
	release_info.anchor_top = 1.0
	release_info.anchor_right = 0.0
	release_info.anchor_bottom = 1.0
	release_info.offset_left = 18.0
	release_info.offset_top = -60.0
	release_info.offset_right = 300.0
	release_info.offset_bottom = -14.0

	var version_label := _create_info_label(
		"v%s" % String(ProjectSettings.get_setting("application/config/version", "0.8.0")),
		18
	)
	version_label.name = "VersionLabel"
	release_info.add_child(version_label)

	var creator_label := _create_info_label(CREATOR_TEXT, 16)
	creator_label.name = "CreatorLabel"
	release_info.add_child(creator_label)

	main_menu_center = start_screen.get_node_or_null("CenterContainer") as Control
	tutorial_choice_layer = start_screen.get_node_or_null("TutorialChoiceLayer") as Control
	loading_layer = start_screen.get_node_or_null("LoadingLayer") as Control

	for control_variant: Variant in [main_menu_center, tutorial_choice_layer, loading_layer]:
		var control := control_variant as Control
		if control != null:
			control.visibility_changed.connect(_refresh_release_info_visibility)

	_refresh_release_info_visibility()


func _create_info_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.90, 0.86))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _refresh_release_info_visibility() -> void:
	if release_info == null or not is_instance_valid(release_info):
		return

	var main_menu_visible := main_menu_center == null or main_menu_center.visible
	var tutorial_visible := tutorial_choice_layer != null and tutorial_choice_layer.visible
	var loading_visible := loading_layer != null and loading_layer.visible

	release_info.visible = main_menu_visible and not tutorial_visible and not loading_visible
