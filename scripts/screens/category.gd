extends Screen
## Категория: быстрое добавление сверху (английский → Enter → перевод → Enter — сохранено),
## поиск и список записей с действиями (изменить, копировать, дублировать, переместить, удалить).
## Вставили строку «word — перевод» или «word<Tab>перевод» — разделится на два поля сама.

const SHOW_MAX := 300   # больше — просим уточнить поиск (список остаётся быстрым)

var cid := ""
var _en: LineEdit
var _ru: LineEdit
var _note: LineEdit
var _note_btn: Button
var _search: LineEdit
var _found: Label
var _list: VBoxContainer
var _title: Label
var _count: Label
var _listen_btn: Button
var _fresh_id := ""   # только что добавленная — мягко проявится


func build() -> void:
	cid = str(args.get("cid", ""))
	var cat := Store.category(cid)
	if cat.is_empty():
		main.go.call_deferred("home")
		return
	var v := scroll_column(860.0, 26.0)
	# шапка
	var head := UI.hbox(12)
	v.add_child(head)
	var back_btn := UI.button("←  Назад", "Ghost", back)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back_btn)
	head.add_child(UI.spacer())
	var learn := UI.button("Учить", "Primary", func() -> void: main.go("setup", {"cid": cid}))
	learn.disabled = Store.count_entries(cid) == 0
	head.add_child(learn)
	var menu := MenuButton.new()
	menu.text = "⋯"
	menu.flat = false
	menu.tooltip_text = "Действия с категорией"
	menu.get_popup().add_item("Переименовать", 0)
	menu.get_popup().add_item("Удалить категорию", 1)
	menu.get_popup().id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_rename()
		else:
			_delete())
	head.add_child(menu)
	var tv := UI.vbox(2)
	_title = UI.label(str(cat["name"]), "Title")
	tv.add_child(_title)
	_count = UI.label("", "Muted")
	tv.add_child(_count)
	v.add_child(tv)
	# быстрое добавление
	var add := UI.card("Card")
	v.add_child(add)
	var av := UI.vbox(12)
	add.add_child(av)
	var row := UI.hbox(10)
	av.add_child(row)
	_en = UI.line("English — слово или предложение")
	_ru = UI.line("Перевод")
	row.add_child(_en)
	row.add_child(_ru)
	_note = UI.line("Заметка или пояснение (необязательно)")
	_note.visible = false
	av.add_child(_note)
	var row2 := UI.hbox(10)
	av.add_child(row2)
	_note_btn = UI.button("+ Заметка", "Ghost", func() -> void:
		_note.visible = true
		_note_btn.visible = false
		_note.grab_focus())
	row2.add_child(_note_btn)
	var hint := UI.label("Enter — к переводу, ещё Enter — сохранить", "Small")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(hint)
	row2.add_child(UI.button("Добавить", "Primary", _add))
	_en.text_submitted.connect(func(_t: String) -> void:
		if _en.text.strip_edges() != "":
			_ru.grab_focus())
	_en.text_changed.connect(_split_paste)
	_ru.text_submitted.connect(func(_t: String) -> void: _add())
	_note.text_submitted.connect(func(_t: String) -> void: _add())
	# поиск и список
	var sh := UI.hbox(12)
	v.add_child(sh)
	_search = UI.line("Поиск по английскому или переводу")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	sh.add_child(_search)
	_found = UI.label("", "Muted")
	_found.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(_found)
	var compact := bool(Store.setting("compact", false))
	var view := UI.button("☰  Подробно" if compact else "☰  Компактно", "Ghost", func() -> void:
		Store.set_setting("compact", not bool(Store.setting("compact", false)))
		rebuild(), "Вид списка")
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(view)
	_listen_btn = UI.button("", "Ghost", _toggle_listen, "Прослушать все записи по очереди: английский, потом перевод")
	_listen_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(_listen_btn)
	_sync_listen()
	if not Speech.playing_changed.is_connected(_on_playing):
		Speech.playing_changed.connect(_on_playing)
	_list = UI.vbox(6 if compact else 10)
	v.add_child(_list)
	if args.has("q"):   # пришли из поиска на главном
		_search.text = str(args["q"])
		args.erase("q")
	_fill()
	_en.grab_focus.call_deferred()


func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


## Перерисовать список (после добавления, правки, поиска).
func _fill() -> void:
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	var total := Store.count_entries(cid)
	_count.text = UI.n_entries(total) + (" · к повторению: %d" % Store.count_due(cid) if total > 0 else "")
	var items := Store.search(cid, _search.text)
	_found.text = "" if _search.text.strip_edges() == "" else "найдено: %d" % items.size()
	_found.visible = _found.text != ""
	if total == 0:
		var e := UI.card("Soft")
		e.add_child(UI.label("Здесь пока пусто. Скопируйте слово или фразу из игры, фильма или книги, вставьте в поле выше и добавьте перевод.", "Muted", true))
		_list.add_child(e)
		return
	if items.is_empty():
		_list.add_child(UI.label("Ничего не нашлось.", "Muted"))
		return
	var others: Array = []
	for c in Store.categories():
		if c["id"] != cid:
			others.append(c)
	var shown := 0
	for e in items:
		if shown >= SHOW_MAX:
			_list.add_child(UI.label("Показаны первые %d из %d — уточните поиск." % [SHOW_MAX, items.size()], "Muted"))
			break
		var r := EntryRow.new(e, others, bool(Store.setting("compact", false)))
		r.action.connect(_on_action)
		_list.add_child(r)
		if str(e["id"]) == _fresh_id:
			r.modulate.a = 0.0
			r.create_tween().tween_property(r, "modulate:a", 1.0, 0.35)
		shown += 1
	_fresh_id = ""


## Вставили «english — перевод» или с табуляцией — разложить по полям.
func _split_paste(t: String) -> void:
	if _ru.text.strip_edges() != "":
		return
	for sep in ["\t", " — ", " – "]:
		var i := t.find(sep)
		if i > 0:
			_en.text = t.left(i).strip_edges()
			_ru.text = t.substr(i + sep.length()).strip_edges()
			_ru.grab_focus()
			_ru.caret_column = _ru.text.length()
			return


func _add() -> void:
	if _en.text.strip_edges() == "":
		_en.grab_focus()
		return
	var e := Store.add_entry(cid, _en.text, _ru.text, _note.text)
	main.remember_clip(_en.text)
	_fresh_id = str(e.get("id", ""))
	_en.text = ""
	_ru.text = ""
	_note.text = ""
	_note.visible = false
	_note_btn.visible = true
	_search.text = ""
	_fill()
	_en.grab_focus()


func _on_action(eid: String, what: String, arg: String) -> void:
	var e := Store.entry(cid, eid)
	match what:
		"edit":
			var d := EntryDialog.new()
			d.title_text = "Изменить запись"
			d.en = str(e["en"])
			d.ru = str(e["ru"])
			d.note = str(e["note"])
			d.cid = cid
			main.open_modal(d)
			var r: Variant = await d.done
			if r != null:
				Store.update_entry(cid, eid, str(r["en"]), str(r["ru"]), str(r["note"]))
				_fill()
		"copy":
			var t := str(e["en"]) + (" — " + str(e["ru"]) if str(e["ru"]) != "" else "")
			DisplayServer.clipboard_set(t)
			main.remember_clip(t)
			main.remember_clip(DisplayServer.clipboard_get())
			main.toast("Скопировано")
		"duplicate":
			var c := Store.duplicate_entry(cid, eid)
			_fresh_id = str(c.get("id", ""))
			_fill()
		"move":
			Store.move_entry(cid, eid, arg)
			main.toast("Перемещено в «%s»" % Store.category(arg)["name"])
			_fill()
		"delete":
			# без вопроса: удаление можно отменить из сообщения внизу
			var undo := Store.delete_entry(cid, eid)
			_fill()
			var short := str(e["en"]) if str(e["en"]).length() <= 40 else str(e["en"]).left(38) + "…"
			main.toast("Удалено: «%s»" % short, 6.0, "Вернуть", func() -> void:
				Store.restore_entry(undo)
				if main.screen_name() == "category" and str(main.current.get("cid")) == cid:
					main.current.call("_fill"))


func _rename() -> void:
	var m := main.open_modal(Dialogs.prompt("Переименовать категорию", "Название", str(Store.category(cid)["name"]))) as Modal
	var r: Variant = await m.done
	if r != null:
		Store.rename_category(cid, str(r))
		_title.text = str(Store.category(cid)["name"])


func _delete() -> void:
	var n := Store.count_entries(cid)
	var cname := str(Store.category(cid)["name"])
	var text := "Категория «%s»" % cname
	text += " и %s в ней будут удалены." % UI.n_entries(n) if n > 0 else " будет удалена."
	var m := main.open_modal(Dialogs.confirm("Удалить категорию?", text, "Удалить", true)) as Modal
	var r: Variant = await m.done
	if r == true:
		Store.backup_now("before-delete")
		var undo := Store.delete_category(cid)
		main.go("home")
		main.toast("Категория «%s» удалена" % cname, 6.0, "Вернуть", func() -> void:
			Store.restore_category(undo)
			if main.screen_name() == "home":
				main.current.rebuild())


# ───────────────────────────── прослушать всё

func _toggle_listen() -> void:
	if Speech.listing:
		Speech.stop()
		return
	var items := Store.search(cid, _search.text)
	if items.is_empty():
		return
	if not Speech.has_voice("en"):
		var with_audio := 0
		for e in items:
			if Store.media_path(str(e.get("audio", ""))) != "":
				with_audio += 1
		if with_audio == 0:
			main.toast("Нет голоса для озвучки: добавьте английский голос в настройках речи Windows", 4.0)
			return
	Speech.listen(items, _on_listen_item)


func _on_listen_item(i: int) -> void:
	if not is_instance_valid(_list):
		return
	var rows: Array = []
	for ch in _list.get_children():
		if ch is EntryRow:
			rows.append(ch)
	for j in rows.size():
		var r: Control = rows[j]
		r.create_tween().tween_property(r, "modulate:a", 1.0 if i < 0 or j == i else 0.45, 0.2)
	if i >= 0 and i < rows.size():
		var sc := get_child(0) as ScrollContainer
		if sc:
			sc.ensure_control_visible(rows[i])


func _on_playing(_on: bool) -> void:
	if is_instance_valid(_listen_btn):
		_sync_listen()
	if not _on:
		_on_listen_item(-1)


func _sync_listen() -> void:
	_listen_btn.text = "■  Остановить" if Speech.listing else "▶  Прослушать"


func _exit_tree() -> void:
	if Speech.playing_changed.is_connected(_on_playing):
		Speech.playing_changed.disconnect(_on_playing)
	Speech.stop()


func back() -> void:
	main.go("home")
