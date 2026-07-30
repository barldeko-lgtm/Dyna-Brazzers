extends Node

signal locale_changed(locale: String)

const SETTINGS_PATH := "user://dyna_locale.cfg"
const SETTINGS_SECTION := "localization"
const SETTINGS_KEY := "locale"
const DEFAULT_LOCALE := "ru"
const SUPPORTED_LOCALES := ["ru", "en", "fr", "de", "uk"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_locale(_load_saved_locale(), false)


func get_default_locale() -> String:
	return DEFAULT_LOCALE


func get_supported_locales() -> Array:
	return SUPPORTED_LOCALES.duplicate()


func get_current_locale() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	return locale.split("_")[0].split("-")[0]


func set_locale(locale: String, persist: bool = true) -> bool:
	var normalized_locale := locale.strip_edges().to_lower()
	if not normalized_locale in SUPPORTED_LOCALES:
		return false

	TranslationServer.set_locale(normalized_locale)
	if persist:
		_save_locale(normalized_locale)
	locale_changed.emit(normalized_locale)
	return true


func _load_saved_locale() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return DEFAULT_LOCALE
	var saved_locale := String(config.get_value(
		SETTINGS_SECTION,
		SETTINGS_KEY,
		DEFAULT_LOCALE
	)).to_lower()
	return saved_locale if saved_locale in SUPPORTED_LOCALES else DEFAULT_LOCALE


func _save_locale(locale: String) -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY, locale)
	var save_error := config.save(SETTINGS_PATH)
	if save_error != OK:
		push_warning("LocalizationManager could not save locale: %s" % error_string(save_error))
