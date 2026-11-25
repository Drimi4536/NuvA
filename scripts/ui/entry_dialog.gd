class_name EntryDialog
extends Modal
## Окно записи: английский, перевод, заметка и (по желанию) категория.
## Для добавления из буфера: английский уже заполнен — курсор сразу в переводе.
## Результат: {en, ru, note, cid} или null.

var en := ""
var ru := ""
var note := ""
var cid := ""                 # выбранная категория
var pick_category := false    # показать выбор категории
var ok_text := "Сохранить"
var _en := LineEdit.new()
var _ru := LineEdit.new()
var _note := LineEdit.new()
var _cat := OptionButton.new()
var _ids: Array[String] = []


func _ready() -> void:
	width = 580.0
	super._ready()
	_en = UI.line("English — слово или предложение", en)
	_ru = UI.line("Перевод", ru)
	_note = UI.line("Заметка или пояснение (необязательно)", note)
	body.add_child(_field("Английский", _en))
	body.add_child(_field("Перевод", _ru))
	body.add_child(_field("Заметка", _note))
	if pick_category:
		for c in Store.categories():
			_cat.add_item(str(c["name"]))
			_ids.append(str(c["id"]))
			if c["id"] == cid:
				_cat.select(_cat.item_count - 1)
		_cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(_field("Категория", _cat))
	_en.text_submitted.connect(func(_t: String) -> void: _ru.grab_focus())
	_ru.text_submitted.connect(func(_t: String) -> void: _submit())
	_note.text_submitted.connect(func(_t: String) -> void: _submit())
	add_button("Отмена", "Ghost", func() -> void: close(null))
	add_button(ok_text, "Primary", _submit)
	# курсор — туда, где пусто: английский уже есть (из буфера) — сразу перевод
	(_ru if en.strip_edges() != "" else _en).grab_focus.call_deferred()


func _field(caption: String, ctl: Control) -> Control:
	var v := UI.vbox(6)
	v.add_child(UI.label(caption, "Small"))
	v.add_child(ctl)
	return v


func _submit() -> void:
	if _en.text.strip_edges() == "":
		_en.grab_focus()
		return
	var pick := cid
	if pick_category and _cat.selected >= 0 and _cat.selected < _ids.size():
		pick = _ids[_cat.selected]
	close({"en": _en.text.strip_edges(), "ru": _ru.text.strip_edges(), "note": _note.text.strip_edges(), "cid": pick})
