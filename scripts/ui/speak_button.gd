class_name SpeakButton
extends Button
## Кнопка «озвучить» (значок динамика рисуется сам, в цвет темы). Звук из Anki или голос системы.

var entry: Dictionary = {}
var text_only := ""     # озвучить просто текст (а не запись)
var lang := "en"


func _init(e: Dictionary = {}, txt := "", language := "en") -> void:
	entry = e
	text_only = txt
	lang = language
	theme_type_variation = "Icon"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(36, 32)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Озвучить"
	pressed.connect(_say)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _say() -> void:
	var ok := Speech.say(text_only, lang) if text_only != "" else Speech.speak_entry(entry)
	if not ok:
		var m := get_tree().get_first_node_in_group("main")
		if m:
			m.call("toast", (Speech.last_error.left(220) if Speech.last_error != "" else
				"Нет голоса для озвучки") + "  ·  подробнее: «Словарь ▾ → Озвучка…»", 7.0)


func _draw() -> void:
	var col := AppTheme.c("accent") if is_hovered() else AppTheme.c("muted")
	var c := size * 0.5 + Vector2(-3, 0)
	var s := 1.0
	# корпус динамика
	var body := PackedVector2Array([
		c + Vector2(-8, -3.5) * s, c + Vector2(-4, -3.5) * s, c + Vector2(1, -8) * s,
		c + Vector2(1, 8) * s, c + Vector2(-4, 3.5) * s, c + Vector2(-8, 3.5) * s])
	draw_colored_polygon(body, col)
	# волны
	draw_arc(c + Vector2(2, 0), 5.0, -0.9, 0.9, 12, col, 1.8, true)
	draw_arc(c + Vector2(2, 0), 9.0, -0.9, 0.9, 14, Color(col, 0.7), 1.8, true)
