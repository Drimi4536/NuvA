extends Screen
## Главный экран: приветствие, сколько в словаре и сколько повторить сегодня,
## «Продолжить обучение», «Начать занятие», «Повторить сложные», категории карточками.

var _file_dialog: FileDialog
var _query := ""              # что в поиске (переживает пересборку экрана)
var _search: LineEdit
var _results: VBoxContainer
var _main_part: VBoxContainer


func build() -> void:
	var v := scroll_column(980.0)
	# шапка
	var head := UI.hbox(8)
	v.add_child(head)
	var hv := UI.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UI.label(_greeting(), "Title"))
	hv.add_child(UI.label(Dates.long_today(), "Muted"))
	var theme_btn := UI.button("☀" if AppTheme.dark else "☾", "Icon",
		func() -> void: AppTheme.set_dark(not AppTheme.dark), "Светлая тема" if AppTheme.dark else "Тёмная тема")
	theme_btn.add_theme_font_size_override(&"font_size", 22)
	theme_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(theme_btn)
	var menu := MenuButton.new()
	menu.text = "Словарь  ▾"
	menu.flat = false
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pm := menu.get_popup()
	pm.add_item("Импорт из Anki (.apkg)…", 4)
	var last_dir := str(Store.setting("anki_dir", ""))
	if last_dir != "":
		pm.add_item("Обновить из Anki — новейший .apkg в «%s»" % last_dir.get_file(), 5)
	pm.add_item("Экспорт для Anki (.txt)…", 6)
	pm.add_separator()
	pm.add_item("Экспорт в файл…", 0)
	pm.add_item("Импорт из файла…", 1)
	pm.add_separator()
	pm.add_item("Озвучка…", 7)
	pm.add_separator()
	pm.add_item("Создать резервную копию", 2)
	pm.add_item("Открыть папку с данными", 3)
	pm.add_separator()
	var sc := PopupMenu.new()
	for i in main.SCALES.size():
		sc.add_radio_check_item("%d %%" % roundi(float(main.SCALES[i]) * 100.0), i)
		sc.set_item_checked(i, is_equal_approx(float(main.SCALES[i]), main.ui_scale()))
	sc.id_pressed.connect(func(i: int) -> void: main.set_ui_scale(float(main.SCALES[i])))
	pm.add_child(sc)
	pm.add_submenu_node_item("Масштаб интерфейса", sc, 10)
	pm.id_pressed.connect(_on_menu)
	head.add_child(menu)
	# поиск по всему словарю (он же — быстрое добавление)
	_search = LineEdit.new()
	_search.theme_type_variation = "BigInput"
	_search.add_theme_font_size_override(&"font_size", 19)
	_search.placeholder_text = "Найти или добавить фразу…   Ctrl+F"
	_search.clear_button_enabled = true
	_search.text = _query
	_search.text_changed.connect(func(t: String) -> void:
		_query = t
		_fill_results())
	_search.text_submitted.connect(_on_search_enter)
	v.add_child(_search)
	_results = UI.vbox(8)
	v.add_child(_results)
	_main_part = UI.vbox(18)
	v.add_child(_main_part)
	_build_main(_main_part)
	_fill_results()
	if _query != "":
		_search.grab_focus.call_deferred()
		_search.set_caret_column.call_deferred(_query.length())


func _build_main(v: VBoxContainer) -> void:
	var total := Store.count_entries()
	var due := Store.count_due()
	var hard := Store.count_hard()
	# сегодня: одно главное действие
	var today := UI.card("Card")
	v.add_child(today)
	var tv := UI.vbox(14)
	today.add_child(tv)
	var row := UI.hbox(20)
	tv.add_child(row)
	var left := UI.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(UI.label("СЕГОДНЯ", "Small"))
	var done := int(Store.today_stats()["done"])
	var main_btn: Button
	if total == 0:
		left.add_child(UI.label("Словарь пока пуст", "Title"))
		left.add_child(UI.label("Добавьте пару фраз — и можно начинать.", "Muted"))
		main_btn = UI.button("Добавить запись", "Primary", func() -> void: main.quick_add(""), "Ctrl+N")
	elif due > 0:
		var mins := maxi(1, ceili(due * 12.0 / 60.0))
		left.add_child(UI.label("%d %s · ~%d мин" % [due, Dates.plural(due, "карточка", "карточки", "карточек"), mins], "Title"))
		left.add_child(UI.label(_due_hint(due, hard), "Muted"))
		main_btn = UI.button("Начать", "Primary", _continue, "Всё, что пора повторить, из всех категорий")
	else:
		left.add_child(UI.label("Всё повторено", "Title"))
		left.add_child(UI.label("Следующие карточки — %s. Можно спокойно полистать словарь." % _next_due_text(), "Muted"))
		main_btn = UI.button("Свободное повторение", "Primary", _free)
	main_btn.add_theme_font_size_override(&"font_size", 19)
	main_btn.custom_minimum_size = Vector2(190, 54)
	main_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(main_btn)
	if total > 0:
		var goal := done + due
		var pb := UI.bar(done, maxi(goal, 1), AppTheme.c("accent"), 8.0)
		pb.tooltip_text = "Сегодня отмечено %d из %d" % [done, goal]
		tv.add_child(pb)
		var links := UI.hbox(4)
		tv.add_child(links)
		var dl := UI.label("сделано сегодня: %d" % done if done > 0 else "сегодня ещё не занимались", "Small")
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		links.add_child(dl)
		links.add_child(UI.button("Настроить занятие", "Ghost", func() -> void: main.go("setup")))
		if hard > 0:
			links.add_child(UI.button("Сложные слова (%d)" % hard, "Ghost", _start_hard, "Слова, которые часто забываются"))
		links.add_child(UI.button("+ Запись", "Ghost", func() -> void: main.quick_add(""), "Ctrl+N"))
	# категории
	var ch := UI.hbox(12)
	var hl := UI.label("Категории", "Heading")
	ch.add_child(hl)
	if total > 0:
		var tl := UI.label("%s" % UI.n_entries(total), "Muted")
		tl.size_flags_vertical = Control.SIZE_SHRINK_END
		ch.add_child(tl)
	ch.add_child(UI.spacer())
	ch.add_child(UI.button("+ Новая категория", "", _new_category))
	v.add_child(UI.spacer(0, 4))
	v.add_child(ch)
	if Store.categories().is_empty():
		v.add_child(_empty_state())
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	v.add_child(flow)
	var i := 0
	for c in Store.categories():
		var card := CategoryCard.new(c)
		card.open_pressed.connect(func(cid: String) -> void: main.go("category", {"cid": cid}))
		card.study_pressed.connect(func(cid: String) -> void: main.go("setup", {"cid": cid}))
		card.rename_pressed.connect(_rename)
		card.color_pressed.connect(_recolor)
		card.delete_pressed.connect(_delete)
		flow.add_child(card)
		card.modulate.a = 0.0
		card.create_tween().tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.03 * i)
		i += 1


func _greeting() -> String:
	var h := int(Time.get_time_dict_from_system()["hour"])
	if h >= 5 and h < 12:
		return "Доброе утро!"
	if h >= 12 and h < 18:
		return "Добрый день!"
	if h >= 18 and h < 23:
		return "Добрый вечер!"
	return "Доброй ночи!"


func _due_hint(due: int, hard: int) -> String:
	if hard > 0 and hard <= due:
		return "Из них сложных: %d — они попадутся раньше." % hard
	return "Повторение из всех категорий, по одной карточке."


func _next_due_text() -> String:
	var best := -1
	for c in Store.categories():
		for e in c["entries"]:
			var n := int(e.get("next", 0))
			if best < 0 or n < best:
				best = n
	return Dates.relative(best) if best >= 0 else "позже"


func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


# ───────────────────────────── поиск

func _fill_results() -> void:
	for ch in _results.get_children():
		_results.remove_child(ch)
		ch.queue_free()
	var q := _query.strip_edges()
	_main_part.visible = q == ""
	_results.visible = q != ""
	if q == "":
		return
	var found := Store.search_all(q, 40)
	if not Store.has_phrase(q):
		var add := UI.button("+  Добавить «%s»" % (q if q.length() <= 60 else q.left(58) + "…"), "Primary",
			func() -> void: _add_from_search(), "Enter")
		add.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_results.add_child(add)
	if found.is_empty():
		_results.add_child(UI.label("В словаре такого нет.", "Muted"))
		return
	_results.add_child(UI.label("Найдено: %d%s" % [found.size(), " (первые 40)" if found.size() >= 40 else ""], "Small"))
	for f in found:
		_results.add_child(_result_row(f))


func _result_row(f: Dictionary) -> Control:
	var e: Dictionary = f["entry"]
	var row := UI.card("Card")
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := (AppTheme.theme.get_stylebox(&"panel", &"Card") as StyleBoxFlat).duplicate() as StyleBoxFlat
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_size = 4
	row.add_theme_stylebox_override(&"panel", sb)
	var h := UI.hbox(16)
	row.add_child(h)
	h.add_child(SpeakButton.new(e))
	var en := UI.label(str(e["en"]), "Entry", true)
	en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	en.size_flags_stretch_ratio = 1.1
	en.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(en)
	var ru := UI.label(str(e["ru"]), "Muted", true)
	ru.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ru.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(ru)
	var cat := Store.category(str(f["cid"]))
	var tag := UI.label(str(f["cat"]), "Small")
	tag.add_theme_color_override(&"font_color", AppTheme.cat_color(int(cat.get("color", 0))))
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(tag)
	row.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_found(str(f["cid"]), str(e["en"])))
	return row


func _open_found(cid: String, en: String) -> void:
	_query = ""
	main.go("category", {"cid": cid, "q": en})


func _on_search_enter(_t: String) -> void:
	var q := _query.strip_edges()
	if q == "":
		return
	if not Store.has_phrase(q):
		_add_from_search()
		return
	var found := Store.search_all(q, 1)
	if not found.is_empty():
		_open_found(str(found[0]["cid"]), str(found[0]["entry"]["en"]))


func _add_from_search() -> void:
	var q := _query.strip_edges()
	var parts := _split(q)
	_query = ""
	_search.text = ""
	_fill_results()
	main.quick_add(parts[0], parts[1])


## «phrase — перевод» → [phrase, перевод].
func _split(t: String) -> Array:
	for sep in ["\t", " — ", " – "]:
		var i := t.find(sep)
		if i > 0:
			return [t.left(i).strip_edges(), t.substr(i + sep.length()).strip_edges()]
	return [t, ""]


func _empty_state() -> Control:
	var c := UI.card("Soft")
	var v := UI.vbox(12)
	c.add_child(v)
	v.add_child(UI.label("Здесь будут ваши категории", "Heading"))
	v.add_child(UI.label("Например: Everyday English, Games, Useful phrases. Внутри — слова и фразы с переводом, "
		+ "которые вы встретили в игре, фильме или книге.", "Muted", true))
	var h := UI.hbox(10)
	h.add_child(UI.button("Создать категорию", "Primary", _new_category))
	h.add_child(UI.button("Добавить пример", "", func() -> void:
		Store.add_sample()
		rebuild()))
	v.add_child(h)
	return c


# ───────────────────────────── действия

func _continue() -> void:
	var last: Dictionary = (Store.setting("last", {}) as Dictionary).duplicate()
	var mode := str(last.get("mode", "en_ru"))
	if mode == "free":
		mode = "en_ru"
	var opts := {"mode": mode, "all": true, "cats": [], "limit": int(last.get("limit", 20)), "shuffle": true, "only_due": true}
	var cards := Session.build(opts)
	if cards.is_empty():
		main.toast("Сегодня всё повторено. Можно начать свободное занятие.")
		return
	main.go("study", {"cards": cards, "mode": mode, "options": opts})


func _free() -> void:
	var opts := {"mode": "free", "all": true, "cats": [], "limit": 0, "shuffle": true}
	var cards := Session.build(opts)
	if not cards.is_empty():
		main.go("study", {"cards": cards, "mode": "free", "options": opts})


func _start_hard() -> void:
	var last: Dictionary = Store.setting("last", {})
	var mode := str(last.get("mode", "en_ru"))
	if mode == "free":
		mode = "en_ru"
	var opts := {"mode": mode, "all": true, "cats": [], "limit": 0, "shuffle": true, "only_hard": true}
	var cards := Session.build(opts)
	if cards.is_empty():
		main.toast("Сложных слов пока нет.")
		return
	main.go("study", {"cards": cards, "mode": mode, "options": opts})


func _new_category() -> void:
	var m := main.open_modal(Dialogs.prompt("Новая категория", "Например: Everyday English", "", "Создать")) as Modal
	var r: Variant = await m.done
	if r == null:
		return
	var c := Store.add_category(str(r))
	main.go("category", {"cid": c["id"]})


func _rename(cid: String) -> void:
	var c := Store.category(cid)
	var m := main.open_modal(Dialogs.prompt("Переименовать категорию", "Название", str(c["name"]))) as Modal
	var r: Variant = await m.done
	if r != null:
		Store.rename_category(cid, str(r))
		rebuild()


func _delete(cid: String) -> void:
	var c := Store.category(cid)
	var n := Store.count_entries(cid)
	var text := "Категория «%s»" % c["name"]
	text += " и %s в ней будут удалены." % UI.n_entries(n) if n > 0 else " будет удалена."
	var m := main.open_modal(Dialogs.confirm("Удалить категорию?", text, "Удалить", true)) as Modal
	var r: Variant = await m.done
	if r == true:
		Store.backup_now("before-delete")
		var undo := Store.delete_category(cid)
		rebuild()
		main.toast("Категория «%s» удалена" % c["name"], 6.0, "Вернуть", func() -> void:
			Store.restore_category(undo)
			if main.screen_name() == "home":
				main.current.rebuild())


func _recolor(cid: String) -> void:
	var m := main.open_modal(Dialogs.color_pick(int(Store.category(cid).get("color", 0)))) as Modal
	var r: Variant = await m.done
	if r != null:
		Store.set_category_color(cid, int(r))
		rebuild()


func _on_menu(id: int) -> void:
	match id:
		0:
			_file(FileDialog.FILE_MODE_SAVE_FILE, "dictionary-%s.json" % Dates.stamp().left(10))
		1:
			_file(FileDialog.FILE_MODE_OPEN_FILE, "")
		2:
			var p := Store.backup_now()
			main.toast("Резервная копия: %s" % p.get_file(), 3.5)
		3:
			OS.shell_open(ProjectSettings.globalize_path(Store.path.get_base_dir()))
		4:
			_file(FileDialog.FILE_MODE_OPEN_FILE, "", "anki")
		5:
			var f := newest_apkg(str(Store.setting("anki_dir", "")))
			if f == "":
				main.toast("В папке «%s» нет файлов .apkg" % str(Store.setting("anki_dir", "")).get_file(), 3.5)
			else:
				_import(f)
		6:
			_file(FileDialog.FILE_MODE_SAVE_FILE, "for-anki-%s.txt" % Dates.stamp().left(10), "anki_txt")
		7:
			main.open_modal(VoiceDialog.new())


## Самый свежий .apkg в папке («Обновить из Anki»: Lookupper и Anki кладут новый экспорт туда же).
static func newest_apkg(dir: String) -> String:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return ""
	var best := ""
	var best_t := -1
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in ["apkg", "colpkg"]:
			var p := dir.path_join(f)
			var t := FileAccess.get_modified_time(p)
			if t > best_t:
				best_t = t
				best = p
	return best


func _file(mode: FileDialog.FileMode, fname: String, kind := "json") -> void:
	if _file_dialog:
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = mode
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	match kind:
		"anki":
			_file_dialog.filters = PackedStringArray(["*.apkg, *.colpkg ; Колода Anki"])
			_file_dialog.title = "Колода Anki"
			if str(Store.setting("anki_dir", "")) != "":
				_file_dialog.current_dir = str(Store.setting("anki_dir", ""))
		"anki_txt":
			_file_dialog.filters = PackedStringArray(["*.txt ; Текст для Anki"])
			_file_dialog.title = "Экспорт для Anki"
		_:
			_file_dialog.filters = PackedStringArray(["*.json ; Словарь (JSON)", "*.apkg ; Колода Anki"])
			_file_dialog.title = "Сохранить словарь" if mode == FileDialog.FILE_MODE_SAVE_FILE else "Открыть словарь"
	if fname != "":
		_file_dialog.current_file = fname
	_file_dialog.file_selected.connect(func(p: String) -> void:
		if kind == "anki_txt":
			var n := AnkiImport.export_txt(p)
			if n < 0:
				main.toast("Не удалось сохранить файл", 3.5)
			else:
				main.open_modal(Dialogs.confirm("Готово для Anki", ("В файле %s.\nВ Anki: Файл → Импорт → выберите этот файл, тип записи «Basic» "
					+ "(английский — лицо, перевод — оборот).") % UI.n_entries(n), "Понятно"))
		elif mode == FileDialog.FILE_MODE_SAVE_FILE:
			main.toast("Словарь сохранён: %s" % p.get_file() if Store.export_to(p) else "Не удалось сохранить файл", 3.5)
		elif p.get_extension().to_lower() in ["apkg", "colpkg"]:
			_import_anki_ask(p)
		else:
			_import(p))
	add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(820, 560))


## Колода с фразами (Lookupper): спросить, что записывать — фразу целиком или слово. Выбор запоминается.
func _import_anki_ask(p: String) -> void:
	var ex := AnkiImport.phrase_example(p)
	if ex.is_empty():
		_import(p)
		return
	var m := Modal.new()
	m.title_text = "Что записывать в словарь?"
	m.width = 640.0
	m.body.add_child(UI.label("В колоде у слов есть фразы, где они встретились. Например:", "Muted", true))
	var cur := str(Store.setting("anki_mode", "phrase"))
	var phrase := AnkiImport.apply_mode(ex, "phrase")
	for opt in [["phrase", "Фразу целиком", "%s\n%s" % [phrase["en"], phrase["ru"]]],
			["word", "Только слово", "%s — %s\n(фраза — подсказкой под ответом)" % [ex["en"], ex["ru"]]]]:
		var b := Button.new()
		b.theme_type_variation = "Tile"
		b.toggle_mode = true
		b.button_pressed = opt[0] == cur
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(0, 92)
		var mc := MarginContainer.new()
		mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			mc.add_theme_constant_override("margin_" + side, 16 if side in ["left", "right"] else 12)
		b.add_child(mc)
		var v := UI.vbox(4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(v)
		var t := UI.label(str(opt[1]), "Entry")
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		var d := UI.label(str(opt[2]), "Small", true)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		var mode: String = opt[0]
		b.pressed.connect(func() -> void: m.close(mode))
		m.body.add_child(b)
	m.body.add_child(UI.label("Уже добавленные из этой колоды записи перепишутся по выбору, прогресс останется.", "Small", true))
	m.add_button("Отмена", "Ghost", func() -> void: m.close(null))
	main.open_modal(m)
	var r: Variant = await m.done
	if r == null:
		return
	Store.set_setting("anki_mode", str(r))
	_import(p)


func _import(p: String) -> void:
	var anki := p.get_extension().to_lower() in ["apkg", "colpkg"]
	if anki:
		Store.set_setting("anki_dir", p.get_base_dir())
	var r := Store.import_from(p)
	if not bool(r["ok"]):
		main.open_modal(Dialogs.confirm("Импорт не удался", str(r["error"]), "Понятно"))
		return
	var text := "Добавлено: %s." % UI.n_entries(int(r["added"]))
	if int(r.get("updated", 0)) > 0:
		text += "\nОбновлено из Anki: %d (прогресс сохранён)." % int(r["updated"])
	if int(r.get("media", 0)) > 0:
		text += "\nЗвуков и картинок: %d." % int(r["media"])
	if int(r["new_categories"]) > 0:
		text += "\nНовых категорий: %d." % int(r["new_categories"])
	if int(r["skipped"]) > 0:
		text += "\nПропущено повторов: %d (такие записи уже были)." % int(r["skipped"])
	text += ("\nКопия словаря до импорта: %s" if anki else "\nСуществующие записи не изменены. Копия словаря до импорта: %s") % str(r["backup"]).get_file()
	if anki:
		text += "\n\nВ следующий раз: «Словарь ▾ → Обновить из Anki» возьмёт самый новый .apkg из той же папки."
	main.open_modal(Dialogs.confirm("Импорт из Anki завершён" if anki else "Импорт завершён", text, "Хорошо"))
	rebuild()
