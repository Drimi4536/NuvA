class_name CategoryCard
extends PanelContainer
## Карточка категории на главном экране: цветной знак с буквой, название, кружок «сколько пора повторить»,
## записи и выученное, полоса в цвет категории. «Учить» проступает при наведении. Щелчок — открыть.
## Меню «⋯»: переименовать, цвет, удалить.

signal open_pressed(cid: String)
signal study_pressed(cid: String)
signal rename_pressed(cid: String)
signal color_pressed(cid: String)
signal delete_pressed(cid: String)

const WIDTH := 314.0

var cid := ""


func _init(cat: Dictionary) -> void:
	cid = str(cat["id"])
	var col := int(cat.get("color", 0))
	theme_type_variation = "Card"
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := UI.vbox(12)
	add_child(v)
	var top := UI.hbox(10)
	v.add_child(top)
	var mono := Monogram.new(str(cat["name"]), col)
	top.add_child(mono)
	var nm := UI.label(str(cat["name"]), "Heading")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.tooltip_text = str(cat["name"])
	nm.mouse_filter = Control.MOUSE_FILTER_PASS
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(nm)
	var n := Store.count_entries(cid)
	var due := Store.count_due(cid)
	var menu := MenuButton.new()
	menu.text = "⋯"
	menu.flat = true
	menu.tooltip_text = "Действия"
	menu.theme_type_variation = "Icon"
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.get_popup().add_item("Переименовать", 0)
	menu.get_popup().add_item("Цвет…", 1)
	menu.get_popup().add_separator()
	menu.get_popup().add_item("Удалить", 2)
	menu.get_popup().id_pressed.connect(_on_menu)
	top.add_child(menu)
	var learned := Store.count_learned(cid)
	var info := UI.n_entries(n)
	if n > 0:
		info += " · выучено %d" % learned
	var il := UI.label(info, "Muted")
	il.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(il)
	var b := UI.bar(learned, n, AppTheme.cat_color(col), 6.0)
	b.tooltip_text = "Выучено: %d из %d" % [learned, n]
	v.add_child(b)
	var bottom := UI.hbox(8)
	v.add_child(bottom)
	if due > 0:
		bottom.add_child(UI.badge(due, "Пора повторить: %d" % due))
	var due_l := UI.label("всё повторено" if n > 0 and due == 0 else ("пусто" if n == 0 else "к повторению"), "Small")
	due_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	due_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	due_l.mouse_filter = Control.MOUSE_FILTER_PASS
	bottom.add_child(due_l)
	var learn := UI.button("Учить", "Chip", func() -> void: study_pressed.emit(cid))
	learn.disabled = n == 0
	bottom.add_child(learn)
	UI.hover_reveal(self, learn, 0.0 if due == 0 else 0.55)
	mouse_entered.connect(func() -> void: theme_type_variation = "CardHover")
	mouse_exited.connect(func() -> void:
		if not get_global_rect().has_point(get_global_mouse_position()):
			theme_type_variation = "Card")


func _on_menu(id: int) -> void:
	if id == 0:
		rename_pressed.emit(cid)
	elif id == 1:
		color_pressed.emit(cid)
	elif id == 2:
		delete_pressed.emit(cid)


func _gui_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		open_pressed.emit(cid)


## Цветной кружок с первой буквой названия.
class Monogram extends Control:
	var letter := ""
	var col := 0

	func _init(cat_name: String, color: int) -> void:
		letter = cat_name.strip_edges().left(1).to_upper()
		col = color
		custom_minimum_size = Vector2(36, 36)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var r := size.y * 0.5
		draw_circle(size * 0.5, r, AppTheme.cat_soft(col))
		var f := AppTheme.font("Bold")
		var fs := 17
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(r - w * 0.5, r + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, AppTheme.cat_color(col))
