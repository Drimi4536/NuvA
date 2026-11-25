class_name Page
extends Container
## Колонка по центру с наибольшей шириной (на широком окне текст не растягивается во всю ширину).

@export var max_width := 920.0
@export var side := 32.0


func _init(width := 920.0) -> void:
	max_width = width
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var w := minf(max_width, maxf(size.x - side * 2.0, 200.0))
		var x := (size.x - w) * 0.5
		for ch in get_children():
			if ch is Control:
				fit_child_in_rect(ch, Rect2(x, 0, w, size.y))


func _get_minimum_size() -> Vector2:
	var h := 0.0
	for ch in get_children():
		if ch is Control and (ch as Control).visible:
			h = maxf(h, (ch as Control).get_combined_minimum_size().y)
	return Vector2(0, h)
