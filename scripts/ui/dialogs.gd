class_name Dialogs
extends RefCounted
## Готовые окна: подтверждение и ввод строки. Возвращают Modal — его результат ждут через await m.done.


## Подтверждение. Результат: true или null.
static func confirm(title: String, text: String, ok_text := "Да", danger := false) -> Modal:
	var m := Modal.new()
	m.title_text = title
	m.width = 460.0
	m.body.add_child(UI.label(text, "Muted", true))
	m.add_button("Отмена", "Ghost", func() -> void: m.close(null))
	var ok := m.add_button(ok_text, "Danger" if danger else "Primary", func() -> void: m.close(true))
	ok.ready.connect(ok.grab_focus)
	return m


## Ввод строки (название категории и т. п.). Результат: строка или null.
static func prompt(title: String, placeholder: String, value := "", ok_text := "Сохранить") -> Modal:
	var m := Modal.new()
	m.title_text = title
	m.width = 460.0
	var e := UI.line(placeholder, value)
	m.body.add_child(e)
	var submit := func() -> void:
		if e.text.strip_edges() != "":
			m.close(e.text.strip_edges())
	e.text_submitted.connect(func(_t: String) -> void: submit.call())
	m.add_button("Отмена", "Ghost", func() -> void: m.close(null))
	m.add_button(ok_text, "Primary", submit)
	e.ready.connect(func() -> void:
		e.grab_focus()
		e.select_all())
	return m


## Выбор цвета категории. Результат: номер цвета или null.
static func color_pick(current: int) -> Modal:
	var m := Modal.new()
	m.title_text = "Цвет категории"
	m.width = 420.0
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	m.body.add_child(grid)
	for i in Store.COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(80, 56)
		b.tooltip_text = str(AppTheme.CAT_NAMES[i])
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = AppTheme.cat_soft(i) if st != "hover" else AppTheme.cat_soft(i).lerp(AppTheme.cat_color(i), 0.15)
			sb.set_corner_radius_all(14)
			sb.border_color = AppTheme.cat_color(i)
			sb.set_border_width_all(3 if i == current else (1 if st == "hover" else 0))
			if st == "focus":
				sb.bg_color = Color(0, 0, 0, 0)
			b.add_theme_stylebox_override(st, sb)
		var dot := Panel.new()
		var ds := StyleBoxFlat.new()
		ds.bg_color = AppTheme.cat_color(i)
		ds.set_corner_radius_all(11)
		dot.add_theme_stylebox_override(&"panel", ds)
		dot.custom_minimum_size = Vector2(22, 22)
		dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
		b.pressed.connect(func() -> void: m.close(i))
		grid.add_child(b)
	m.add_button("Отмена", "Ghost", func() -> void: m.close(null))
	return m
