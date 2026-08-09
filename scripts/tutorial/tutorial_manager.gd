extends Node

signal tutorial_started
signal tutorial_finished

var tutorial_start_requested := false
var tutorial_active := false


func request_tutorial_start() -> void:
	tutorial_start_requested = true
	tutorial_active = false


func cancel_tutorial_start() -> void:
	tutorial_start_requested = false


func begin_requested_tutorial() -> bool:
	if not tutorial_start_requested:
		return false

	tutorial_start_requested = false
	tutorial_active = true
	tutorial_started.emit()
	return true


func finish_tutorial() -> void:
	tutorial_start_requested = false
	if not tutorial_active:
		return

	tutorial_active = false
	tutorial_finished.emit()


func is_tutorial_active() -> bool:
	return tutorial_active


func is_match_clock_suspended() -> bool:
	return tutorial_start_requested or tutorial_active
