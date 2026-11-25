class_name CardStack
extends Container
## Карточка занятия «стопкой»: под ней выглядывают края следующих (их число — depth, 0…2).

const STEP := 9.0     # насколько ниже каждый следующий край
const SHRINK := 18.0  # насколько уже с каждой стороны

var depth := 2:
	set(v):
		depth = clampi(v, 0, 2)
		queue_sort()
		queue_redraw()


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for ch in get_children():
		if ch is Control and (ch as Control).visible:
			m = m.max((ch as Control).get_combined_minimum_size())
	return m + Vector2(0, STEP * 2.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for ch in get_children():
			if ch is Control:
				fit_child_in_rect(ch, Rect2(0, 0, size.x, size.y - STEP * 2.0))
		queue_redraw()


func _draw() -> void:
	var sb := get_theme_stylebox(&"panel", &"Card") as StyleBoxFlat
	if sb == null:
		return
	var front_h := size.y - STEP * 2.0
	for i in range(depth, 0, -1):
		var r := Rect2(SHRINK * i, STEP * i, size.x - SHRINK * 2.0 * i, front_h)
		var c := sb.duplicate() as StyleBoxFlat
		c.bg_color = c.bg_color.lerp(AppTheme.c("bg"), 0.3 * i)
		c.shadow_size = 4
		c.draw(get_canvas_item(), r)
