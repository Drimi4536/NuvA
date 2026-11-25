class_name Mastery
extends Control
## Уровень освоения записи точками (0…6): закрашено столько, сколько уровень; сложные — красная точка впереди.

var entry: Dictionary = {}


func _init(e: Dictionary) -> void:
	entry = e
	custom_minimum_size = Vector2(Srs.MAX_LEVEL * 11 + 4, 18)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = _tip()


func _tip() -> String:
	var t := Srs.level_name(entry)
	if not Srs.is_new(entry):
		t += "\nверно: %d · почти: %d · не знал: %d" % [int(entry.get("correct", 0)), int(entry.get("almost", 0)), int(entry.get("wrong", 0))]
		t += "\nповторить: " + Dates.relative(int(entry.get("next", Dates.today())))
	return t


func _draw() -> void:
	var lvl := int(entry.get("level", 0))
	var hard := Srs.is_hard(entry)
	for i in Srs.MAX_LEVEL:
		var p := Vector2(6 + i * 11, size.y * 0.5)
		var col := AppTheme.c("accent") if i < lvl else AppTheme.c("border")
		if hard and i == 0 and lvl == 0:
			col = AppTheme.c("bad")
		draw_circle(p, 4.0, col)
