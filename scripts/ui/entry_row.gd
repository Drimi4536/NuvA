class_name EntryRow
extends PanelContainer
## Строка записи в категории: английский, перевод, заметка, уровень освоения.
## При наведении проступают «✎ изменить» и «✕ удалить»; остальное — в меню «⋯».
## compact — в одну строку («английский — перевод»), втрое больше записей на экране. Двойной щелчок — изменить.

signal action(eid: String, what: String, arg: String)   ## what: edit, copy, duplicate, move, delete

var eid := ""


func _init(e: Dictionary, other_cats: Array, compact := false) -> void:
	eid = str(e["id"])
	theme_type_variation = "Card"
	if compact:
		var sb := (AppTheme.theme.get_stylebox(&"panel", &"Card") as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		sb.content_margin_left = 18
		sb.content_margin_right = 10
		sb.shadow_size = 2
		sb.set_corner_radius_all(12)
		add_theme_stylebox_override(&"panel", sb)
	var h := UI.hbox(14 if compact else 16)
	add_child(h)
	var sp := SpeakButton.new(e)
	sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sp)
	if not compact and str(e.get("image", "")) != "":
		var pic := UI.picture(str(e["image"]), 58.0)
		if pic:
			pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(pic)
	var ru_text := str(e["ru"]) if str(e["ru"]) != "" else "— перевода нет —"
	if compact:
		var en := UI.label(str(e["en"]), "Entry")
		en.add_theme_font_size_override(&"font_size", 17)
		en.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		en.size_flags_stretch_ratio = 1.1
		en.tooltip_text = str(e["en"]) + ("\n" + str(e["note"]) if str(e["note"]) != "" else "")
		en.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(en)
		var ru := UI.label(ru_text, "Muted")
		ru.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ru.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ru.tooltip_text = ru_text
		ru.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(ru)
	else:
		var v := UI.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UI.label(str(e["en"]), "Entry", true))
		if str(e.get("ipa", "")) != "":
			v.add_child(UI.label("/%s/" % e["ipa"], "Small"))
		v.add_child(UI.label(ru_text, "Muted", true))
		if str(e["note"]) != "":
			v.add_child(UI.label(str(e["note"]), "Small", true))
		if str(e.get("ctx", "")) != "":
			v.add_child(UI.rich(UI.hl(str(e["ctx"])), 14, AppTheme.c("muted")))
	# действия при наведении
	var tools := UI.hbox(0)
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tools)
	var ed := UI.button("✎", "Icon", func() -> void: action.emit(eid, "edit", ""), "Изменить")
	var del := UI.button("✕", "Icon", func() -> void: action.emit(eid, "delete", ""), "Удалить")
	for b in [ed, del]:
		(b as Button).focus_mode = Control.FOCUS_NONE
		tools.add_child(b)
	UI.hover_reveal(self, tools)
	var right: BoxContainer = UI.hbox(4) if compact else UI.vbox(6)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(right)
	var m := Mastery.new(e)
	m.size_flags_horizontal = Control.SIZE_SHRINK_END
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(m)
	var menu := MenuButton.new()
	menu.text = "⋯"
	menu.flat = true
	menu.theme_type_variation = "Icon"
	menu.size_flags_horizontal = Control.SIZE_SHRINK_END
	menu.tooltip_text = "Ещё действия"
	var pm := menu.get_popup()
	pm.add_item("Изменить", 0)
	pm.add_item("Копировать текст", 1)
	pm.add_item("Дублировать", 2)
	if not other_cats.is_empty():
		var sub := PopupMenu.new()
		sub.name = "move"
		for i in other_cats.size():
			sub.add_item(str(other_cats[i]["name"]), i)
		sub.id_pressed.connect(func(i: int) -> void: action.emit(eid, "move", str(other_cats[i]["id"])))
		pm.add_child(sub)
		pm.add_submenu_node_item("Переместить в…", sub, 3)
	pm.add_separator()
	pm.add_item("Удалить", 4)
	pm.id_pressed.connect(_on_menu)
	right.add_child(menu)


func _on_menu(id: int) -> void:
	var what: String = {0: "edit", 1: "copy", 2: "duplicate", 4: "delete"}.get(id, "")
	if what != "":
		action.emit(eid, what, "")


func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb and mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		action.emit(eid, "edit", "")
