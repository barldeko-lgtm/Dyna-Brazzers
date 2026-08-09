extends RefCounted


static func apply(
	button: Button,
	text: String,
	preferred_font_size: int,
	minimum_font_size: int
) -> void:
	if button == null:
		return

	button.text = text
	var preferred_size := maxi(preferred_font_size, 1)
	var minimum_size := clampi(minimum_font_size, 1, preferred_size)
	var font := button.get_theme_font("font")
	var stylebox := button.get_theme_stylebox("normal")
	var horizontal_padding := stylebox.get_minimum_size().x if stylebox != null else 0.0
	var available_width := maxf(button.custom_minimum_size.x - horizontal_padding - 8.0, 1.0)
	var fitted_size := preferred_size

	while (
		fitted_size > minimum_size
		and font.get_string_size(
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			fitted_size
		).x > available_width
	):
		fitted_size -= 1

	button.add_theme_font_size_override("font_size", fitted_size)
