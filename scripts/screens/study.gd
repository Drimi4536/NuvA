extends Screen
## Занятие. args: cards ([{cid, eid, cat}] из Session.build), mode (en_ru | ru_en | type | free), options.
##
## en_ru / ru_en: Пробел — показать ответ; 1 — не знаю, 2 — почти, 3 — знаю.
## type: пишете английский, Enter — проверить, Enter — дальше.
## choice: выбрать перевод из пяти (1–5 или щелчок); верно — дальше само, ошибка — Enter.
## free: Пробел или щелчок — перевернуть, ← → — листать, без оценок.
## «Не знаю» возвращает карточку через пару других (не больше двух раз), в прогресс идёт только первый ответ.

const REPEAT_GAP := 3
const REPEAT_MAX := 2
const CHOICES := 5
const CHOICE_DELAY := 0.75   # после верного выбора — пауза и дальше само

var mode := "en_ru"
var _queue: Array = []        # [{cid, eid, cat, rep}]
var _i := 0
var _first_total := 0         # сколько разных карточек
var _done_first := 0
var _revealed := false
var _checked := false
var _check_result := ""
var _stats := {Srs.KNOW: 0, Srs.ALMOST: 0, Srs.DONT: 0}
var _mistakes: Array = []     # [{cid, eid, cat}]
var _graded := {}             # cid/eid → результат первого ответа
var _finished := false

var _progress: ProgressBar
var _counter: Label
var _card_holder: VBoxContainer
var _card: PanelContainer
var _stack: CardStack
var _busy := false            # карточка улетает или переворачивается — клавиши ждут
var _t0 := 0                  # начало занятия (мс)
var _answer_box: VBoxContainer
var _buttons: HBoxContainer
var _input: LineEdit
var _choice_btns: Array[Button] = []
var _choice_ok := -1          # номер верного варианта
var _picked := -1             # что выбрали (-1 — ещё нет)
var _token := 0               # номер показа карточки (чтобы отложенный переход не сработал на другой)


func build() -> void:
	mode = str(args.get("mode", "en_ru"))
	if not Session.MODES.has(mode):
		mode = "en_ru"
	if _queue.is_empty() and not _finished:
		for c in args.get("cards", []):
			var e := Store.entry(str(c["cid"]), str(c["eid"]))
			if e.is_empty():
				continue
			# без перевода нечего спрашивать в «русский → английский» и при вводе
			if mode in ["ru_en", "type", "choice"] and str(e["ru"]).strip_edges() == "":
				continue
			var q: Dictionary = (c as Dictionary).duplicate()
			q["rep"] = 0
			_queue.append(q)
		_first_total = _queue.size()
		_t0 = Time.get_ticks_msec()
	var root := UI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# верхняя полоса
	var top_m := MarginContainer.new()
	for side in ["left", "right"]:
		top_m.add_theme_constant_override("margin_" + side, 28)
	top_m.add_theme_constant_override("margin_top", 20)
	root.add_child(top_m)
	var top := UI.vbox(10)
	top_m.add_child(top)
	var bar := UI.hbox(12)
	top.add_child(bar)
	var fin := UI.button("←  Закончить", "Ghost", back, "Esc")
	fin.focus_mode = Control.FOCUS_NONE
	bar.add_child(fin)
	var mt := UI.label(str(Session.MODES[mode]), "Muted")
	mt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(mt)
	_counter = UI.label("", "Muted")
	_counter.custom_minimum_size.x = 120
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_counter)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 6
	_progress.max_value = 1.0
	_progress.step = 0.0
	top.add_child(_progress)
	# поле карточки
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	_card_holder = VBoxContainer.new()
	_card_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(_card_holder)
	if _finished or _queue.is_empty():
		_show_summary()
	else:
		_show_card()


# ───────────────────────────── карточка

func _cur() -> Dictionary:
	return _queue[_i]


func _entry() -> Dictionary:
	return Store.entry(str(_cur()["cid"]), str(_cur()["eid"]))


func _update_progress() -> void:
	if mode == "free":
		_counter.text = "%d / %d" % [_i + 1, _queue.size()]
		_progress.value = float(_i + 1) / maxf(1.0, _queue.size())
	else:
		_counter.text = "%d / %d" % [mini(_done_first + 1, _first_total), _first_total]
		_progress.value = float(_done_first) / maxf(1.0, _first_total)


func _clear_holder() -> void:
	for ch in _card_holder.get_children():
		_card_holder.remove_child(ch)
		ch.queue_free()


## Место под карточку: по центру, чуть ниже верхней полосы (не в середине пустоты).
func _slot() -> CenterContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", int(clampf(size.y * 0.07, 16.0, 70.0)))
	wrap.add_theme_constant_override("margin_bottom", 32)
	_card_holder.add_child(wrap)
	var center := CenterContainer.new()
	wrap.add_child(center)
	return center


func _show_card() -> void:
	_clear_holder()
	_busy = false
	_revealed = false
	_checked = false
	_check_result = ""
	_input = null
	_choice_btns.clear()
	_picked = -1
	_token += 1
	var e := _entry()
	if e.is_empty():   # запись удалили во время занятия
		_advance()
		return
	_update_progress()
	_stack = CardStack.new()
	_stack.depth = _queue.size() - _i - 1
	_slot().add_child(_stack)
	_card = UI.card("Card")
	_card.custom_minimum_size = Vector2(minf(720.0, size.x - 80.0), 300)
	_stack.add_child(_card)
	var v := UI.vbox(18)
	_card.add_child(v)
	# метка категории и пометка «ещё раз»
	var tags := UI.hbox(8)
	v.add_child(tags)
	var tag := UI.label(str(_cur()["cat"]), "Small")
	tags.add_child(tag)
	if int(_cur()["rep"]) > 0:
		tags.add_child(UI.label("·  ещё раз", "Accent"))
	tags.add_child(UI.spacer())
	if Srs.is_hard(e):
		var hl := UI.label("сложное", "Small")
		hl.tooltip_text = "Это слово часто забывается"
		hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tags.add_child(hl)
	if _en_first():
		tags.add_child(SpeakButton.new(e))
	# вопрос
	var prompt_text := str(e["ru"]) if mode == "ru_en" or mode == "type" else str(e["en"])
	var p := UI.label(prompt_text, "Big", true)
	if prompt_text.length() <= 40:
		p.add_theme_font_size_override(&"font_size", 38)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.custom_minimum_size.y = 110
	p.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(p)
	if _en_first() and str(e.get("ipa", "")) != "":
		var ipa := UI.label("/%s/" % e["ipa"], "Muted")
		ipa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ipa)
	if mode == "type":
		var hint := UI.label("Напишите по-английски", "Muted")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hint)
		_input = LineEdit.new()
		_input.theme_type_variation = "BigInput"
		_input.placeholder_text = "Ваш ответ"
		_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_input.text_submitted.connect(func(_t: String) -> void: _on_enter())
		v.add_child(_input)
	if mode == "choice":
		v.add_child(_make_choices(e))
	# ответ (появится)
	_answer_box = UI.vbox(10)
	_answer_box.visible = false
	v.add_child(_answer_box)
	# кнопки
	_buttons = UI.hbox(10)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_buttons)
	_fill_buttons()
	if mode == "free":
		_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_card.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_flip())
	_card_in()
	_prefetch_next()
	if _en_first():
		_auto_speak(e)
	if _input:
		_input.grab_focus.call_deferred()


func _fill_buttons() -> void:
	for ch in _buttons.get_children():
		_buttons.remove_child(ch)
		ch.queue_free()
	match mode:
		"free":
			var prev := _btn("←", "", _prev, "Предыдущая (←)")
			prev.disabled = _i == 0
			_buttons.add_child(prev)
			_buttons.add_child(_kbtn("Скрыть ответ" if _revealed else "Перевернуть", "Пробел", "Primary", _flip))
			_buttons.add_child(_btn("→", "", _next_free, "Следующая (→)"))
		"choice":
			if _picked < 0:
				_buttons.add_child(_btn("Не знаю", "Ghost", func() -> void: _pick(-2), "Показать верный вариант"))
			elif _picked != _choice_ok:
				_buttons.add_child(_kbtn("Дальше", "Enter", "Primary", _next_choice))
		"type":
			if not _checked:
				_buttons.add_child(_btn("Не помню", "Ghost", _give_up, "Показать ответ"))
				_buttons.add_child(_kbtn("Проверить", "Enter", "Primary", _check))
			else:
				if _check_result != AnswerCheck.CORRECT:
					_buttons.add_child(_btn("Засчитать как верный", "Ghost", _override, "Если ваш вариант тоже правильный"))
				_buttons.add_child(_kbtn("Дальше", "Enter", "Primary", _next_typed))
		_:
			if not _revealed:
				_buttons.add_child(_kbtn("Показать ответ", "Пробел", "Primary", _reveal))
			else:
				_buttons.add_child(_kbtn("Не знаю", "1", "Dont", func() -> void: _grade(Srs.DONT)))
				_buttons.add_child(_kbtn("Почти знаю", "2", "", func() -> void: _grade(Srs.ALMOST)))
				_buttons.add_child(_kbtn("Знаю", "3", "Know", func() -> void: _grade(Srs.KNOW)))


func _btn(text: String, variation: String, cb: Callable, tip: String) -> Button:
	var b := UI.button(text, variation, cb, tip)
	b.focus_mode = Control.FOCUS_NONE   # пробел и Enter — наши клавиши, а не «нажать кнопку в фокусе»
	b.custom_minimum_size.x = 120
	return b


## Кнопка с клавишей справа.
func _kbtn(text: String, key: String, variation: String, cb: Callable) -> Button:
	var b := UI.key_button(text, key, variation, cb)
	b.custom_minimum_size.x = 130
	return b


# ───────────────────────────── движение карточки

## Новая карточка: проступает и чуть подрастает.
func _card_in() -> void:
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.96, 0.96)
	var c := _card
	var go := func() -> void:
		if not is_instance_valid(c):
			return
		c.pivot_offset = c.size * 0.5
		var tw := c.create_tween().set_parallel()
		tw.tween_property(c, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(c, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	go.call_deferred()


## Переворот по оси: сжать до ребра → сменить сторону → развернуть.
func _flip_anim(change: Callable) -> void:
	_busy = true
	var c := _card
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale:x", 0.0, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(change)
	tw.tween_callback(func() -> void: c.pivot_offset = c.size * 0.5)
	tw.tween_property(c, "scale:x", 1.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _busy = false)


## Карточка улетает: dir > 0 — вправо («знаю»), < 0 — влево («не знаю»), 0 — вниз («почти»).
func _fly(dir: float, then: Callable) -> void:
	_busy = true
	var c := _card
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_parallel()
	if dir == 0.0:
		tw.tween_property(c, "position:y", c.position.y + 50.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "scale", Vector2(0.92, 0.92), 0.22)
	else:
		tw.tween_property(c, "position:x", c.position.x + dir * c.size.x * 0.7, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "rotation_degrees", dir * 8.0, 0.24)
	tw.tween_property(c, "modulate:a", 0.0, 0.22)
	tw.chain().tween_callback(then)


## Показать ответ под вопросом (en_ru, ru_en, free) — с переворотом карточки.
func _reveal() -> void:
	if _revealed or _busy:
		return
	_revealed = true
	_flip_anim(_show_answer)


func _show_answer() -> void:
	var e := _entry()
	for ch in _answer_box.get_children():
		_answer_box.remove_child(ch)
		ch.queue_free()
	_answer_box.add_child(HSeparator.new())
	var ans := str(e["en"]) if mode == "ru_en" else str(e["ru"])
	if ans.strip_edges() == "":
		ans = "— перевода нет —"
	var a := UI.label(ans, "Answer", true)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_answer_box.add_child(a)
	_add_note(e)
	_answer_box.visible = true
	_fill_buttons()


## Английский виден сразу (его можно озвучить, не подсказав ответ).
func _en_first() -> bool:
	return mode in ["en_ru", "choice", "free"]


## Под ответом: транскрипция и озвучка (если английский был скрыт), заметка, контекст из Anki, картинка.
func _add_note(e: Dictionary) -> void:
	if not _en_first():
		var sp := UI.hbox(6)
		sp.alignment = BoxContainer.ALIGNMENT_CENTER
		sp.add_child(SpeakButton.new(e))
		if str(e.get("ipa", "")) != "":
			var ipa := UI.label("/%s/" % e["ipa"], "Muted")
			ipa.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sp.add_child(ipa)
		_answer_box.add_child(sp)
		_auto_speak(e)
	if str(e["note"]).strip_edges() != "":
		var n := UI.label(str(e["note"]), "Muted", true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_answer_box.add_child(n)
	if str(e.get("ctx", "")) != "":
		var box := UI.card("Soft")
		var bv := UI.vbox(4)
		box.add_child(bv)
		bv.add_child(UI.rich(UI.hl(str(e["ctx"])), 17, Color(), true))
		if str(e.get("ctx_ru", "")) != "":
			bv.add_child(UI.rich(str(e["ctx_ru"]), 15, AppTheme.c("muted"), true))
		_answer_box.add_child(box)
	if str(e.get("image", "")) != "":
		var pic := UI.picture(str(e["image"]), 150.0, minf(640.0, size.x - 140.0))
		if pic:
			_answer_box.add_child(pic)


## Заранее приготовить озвучку следующих карточек (встроенный голос — без задержки).
func _prefetch_next() -> void:
	var texts: Array = []
	for j in range(_i, mini(_i + 4, _queue.size())):
		var x := Store.entry(str(_queue[j]["cid"]), str(_queue[j]["eid"]))
		if not x.is_empty() and Store.media_path(str(x.get("audio", ""))) == "":
			texts.append(str(x["en"]))
	Speech.prefetch(texts)


## Озвучить английский сам (настройка «Озвучивать английский»).
func _auto_speak(e: Dictionary) -> void:
	if not bool(Store.setting("auto_speak", true)):
		return
	var tok := _token
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if tok == _token and not _finished:
			Speech.speak_entry(e))


# ───────────────────────────── оценки

func _grade(result: String) -> void:
	if (not _revealed and mode != "type") or _busy:
		return
	var c := _cur()
	var key := "%s/%s" % [c["cid"], c["eid"]]
	if int(c["rep"]) == 0 and not _graded.has(key):
		_graded[key] = result
		Store.grade(str(c["cid"]), str(c["eid"]), result)
		_stats[result] = int(_stats[result]) + 1
		_done_first += 1
		if result == Srs.DONT:
			_mistakes.append({"cid": c["cid"], "eid": c["eid"], "cat": c["cat"]})
	if result == Srs.DONT and int(c["rep"]) < REPEAT_MAX:
		var again: Dictionary = c.duplicate()
		again["rep"] = int(c["rep"]) + 1
		_queue.insert(mini(_i + 1 + REPEAT_GAP, _queue.size()), again)
	_fly({Srs.KNOW: 1.0, Srs.DONT: -1.0}.get(result, 0.0) as float, _advance)


func _advance() -> void:
	_i += 1
	if _i >= _queue.size():
		_finish()
	else:
		_show_card()


# ───────────────────────────── ввод ответа

func _on_enter() -> void:
	if not _checked:
		_check()
	else:
		_next_typed()


func _check() -> void:
	if _checked or _input == null:
		return
	if _input.text.strip_edges() == "":
		_shake(_input)
		return
	var e := _entry()
	var r := AnswerCheck.check(_input.text, str(e["en"]))
	_show_check(str(r["result"]), r, _input.text)


func _give_up() -> void:
	if _checked:
		return
	var e := _entry()
	var r := AnswerCheck.check("", str(e["en"]))
	_show_check(AnswerCheck.WRONG, r, "")


func _show_check(result: String, r: Dictionary, typed: String) -> void:
	_checked = true
	_check_result = result
	_input.editable = false
	var e := _entry()
	for ch in _answer_box.get_children():
		_answer_box.remove_child(ch)
		ch.queue_free()
	var banner := UI.card({AnswerCheck.CORRECT: "GoodBox", AnswerCheck.TYPO: "AccentBox"}.get(result, "BadBox"))
	var bv := UI.vbox(8)
	banner.add_child(bv)
	var title := {AnswerCheck.CORRECT: "Верно!", AnswerCheck.TYPO: "Почти — опечатка",
		AnswerCheck.WRONG: "Неверно" if typed != "" else "Правильный ответ"}[result] as String
	var tl := UI.label(title, {AnswerCheck.CORRECT: "Good", AnswerCheck.TYPO: "Accent"}.get(result, "Bad"))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(tl)
	if result != AnswerCheck.CORRECT or str(r["matched"]) != typed.strip_edges():
		# правильный вариант, неверные слова подсвечены
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.add_theme_font_override("normal_font", AppTheme.font("SemiBold"))
		rt.add_theme_font_size_override("normal_font_size", 26)
		rt.add_theme_color_override("default_color", AppTheme.c("text"))
		var parts := PackedStringArray()
		var words: Array = r.get("words", [])
		if words.is_empty() or typed == "":
			parts.append(_esc(str(e["en"])))
		else:
			for w in words:
				var t := _esc(str(w["w"]))
				parts.append(t if bool(w["ok"]) else "[color=#%s][u]%s[/u][/color]" % [AppTheme.c("bad").to_html(false), t])
		rt.text = "[center]%s[/center]" % " ".join(parts)
		bv.add_child(rt)
		if typed != "" and result != AnswerCheck.CORRECT:
			var yl := UI.label("Вы написали: " + typed.strip_edges(), "Muted", true)
			yl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bv.add_child(yl)
	if AnswerCheck.variants(str(e["en"])).size() > 1:
		var al := UI.label("Варианты: " + str(e["en"]), "Small", true)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(al)
	_answer_box.add_child(banner)
	_add_note(e)
	_answer_box.visible = true
	UI.appear(_answer_box, 0.0, 0.0)
	_fill_buttons()
	# Enter из поля ввода — «Дальше»; поле не редактируется, но фокус держим на нём
	_input.grab_focus.call_deferred()


func _override() -> void:
	_check_result = AnswerCheck.CORRECT
	_next_typed()


func _next_typed() -> void:
	if not _checked:
		return
	var g := {AnswerCheck.CORRECT: Srs.KNOW, AnswerCheck.TYPO: Srs.ALMOST}.get(_check_result, Srs.DONT) as String
	_revealed = true
	_grade(g)


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _shake(c: Control) -> void:
	var x := c.position.x
	var tw := c.create_tween()
	for d in [8.0, -6.0, 4.0, 0.0]:
		tw.tween_property(c, "position:x", x + d, 0.05)


# ───────────────────────────── выбор из вариантов

## Пять вариантов перевода: верный + похожие из той же категории, если не хватает — из всего словаря.
func _make_choices(e: Dictionary) -> Control:
	var right := str(e["ru"]).strip_edges()
	var seen := {AnswerCheck.normalize(right): true}
	var same: Array = []
	var other: Array = []
	for c in Store.categories():
		for x in c["entries"]:
			var t := str(x["ru"]).strip_edges()
			var n := AnswerCheck.normalize(t)
			if t == "" or seen.has(n):
				continue
			seen[n] = true
			(same if str(c["id"]) == str(_cur()["cid"]) else other).append(t)
	same.shuffle()
	other.shuffle()
	var wrong: Array = (same + other).slice(0, CHOICES - 1)
	var opts: Array = wrong + [right]
	opts.shuffle()
	_choice_ok = opts.find(right)
	var list := UI.vbox(8)
	for i in opts.size():
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, opts[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick.bind(i))
		list.add_child(b)
		_choice_btns.append(b)
	return list


## Выбрали вариант i (-2 — «не знаю»): подсветить верный и выбранный.
func _pick(i: int) -> void:
	if _picked != -1 or _finished or i >= _choice_btns.size():
		return
	_picked = i
	_revealed = true
	for j in _choice_btns.size():
		var b := _choice_btns[j]
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		if j == _choice_ok:
			b.theme_type_variation = "Know"
		elif j == i:
			b.theme_type_variation = "Dont"
		else:
			b.modulate.a = 0.45
	var e := _entry()
	for ch in _answer_box.get_children():
		_answer_box.remove_child(ch)
		ch.queue_free()
	_add_note(e)
	_answer_box.visible = _answer_box.get_child_count() > 0
	_fill_buttons()
	if i == _choice_ok:
		var tok := _token
		get_tree().create_timer(CHOICE_DELAY).timeout.connect(func() -> void:
			if tok == _token and not _finished:
				_next_choice())


func _next_choice() -> void:
	if _picked == -1:
		return
	_grade(Srs.KNOW if _picked == _choice_ok else Srs.DONT)


# ───────────────────────────── свободное повторение

func _flip() -> void:
	if _busy:
		return
	if _revealed:
		_revealed = false
		_flip_anim(func() -> void:
			_answer_box.visible = false
			_fill_buttons())
	else:
		_reveal()


func _next_free() -> void:
	if _busy:
		return
	if _i + 1 >= _queue.size():
		_finish()
	else:
		_fly(-0.6, func() -> void:
			_i += 1
			_show_card())


func _prev() -> void:
	if _i > 0 and not _busy:
		_fly(0.6, func() -> void:
			_i -= 1
			_show_card())


# ───────────────────────────── итог

func _finish() -> void:
	_finished = true
	_show_summary()


func _show_summary() -> void:
	_finished = true
	_clear_holder()
	_counter.text = ""
	_progress.value = 1.0 if _first_total > 0 else 0.0
	_busy = false
	var card := UI.card("Card")
	card.custom_minimum_size = Vector2(minf(640.0, size.x - 80.0), 0)
	_slot().add_child(card)
	var v := UI.vbox(18)
	card.add_child(v)
	var bh := UI.hbox(10)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	if _queue.is_empty():
		var t := UI.label("Нечего повторять", "Title")
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		var m := UI.label("В выбранных карточках нет перевода — для этого режима он нужен." if mode in ["ru_en", "type", "choice"]
			else "Выбранные записи не найдены.", "Muted", true)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(m)
		bh.add_child(_btn("Другое занятие", "Primary", func() -> void: main.go("setup"), ""))
		v.add_child(bh)
		UI.appear(card, 0.0, 0.0)
		return
	if mode == "free":
		var t2 := UI.label("Круг пройден", "Title")
		t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t2)
		var m2 := UI.label("Просмотрено карточек: %d" % _queue.size(), "Muted")
		m2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(m2)
		bh.add_child(_btn("Ещё круг", "Primary", _again_free, "Перемешать и начать снова"))
		bh.add_child(_btn("На главную", "", func() -> void: main.go("home"), ""))
		v.add_child(bh)
		UI.appear(card, 0.0, 0.0)
		return
	var done := int(_stats[Srs.KNOW]) + int(_stats[Srs.ALMOST]) + int(_stats[Srs.DONT])
	var title := "Занятие завершено" if done >= _first_total else "Занятие прервано"
	var tl := UI.label(title, "Title")
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	if done == 0:
		var m3 := UI.label("Ни одной карточки не отмечено — прогресс не изменился.", "Muted", true)
		m3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(m3)
	else:
		var row := UI.hbox(14)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(row)
		row.add_child(_stat_box(int(_stats[Srs.KNOW]), "знаю", "GoodBox", "Good"))
		row.add_child(_stat_box(int(_stats[Srs.ALMOST]), "почти", "AccentBox", "Accent"))
		row.add_child(_stat_box(int(_stats[Srs.DONT]), "не знаю", "BadBox", "Bad"))
		var say := UI.label(_human_line(done), "", true)
		say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(say)
		var t := Store.today_stats()
		var goal := int(t["done"]) + Store.count_due()
		var day := UI.vbox(6)
		v.add_child(day)
		day.add_child(UI.bar(int(t["done"]), goal, AppTheme.c("accent"), 8.0))
		var dl := UI.label("Сегодня отмечено %d из %d" % [int(t["done"]), goal] if Store.count_due() > 0
			else "На сегодня всё повторено — отмечено %d" % int(t["done"]), "Small")
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		day.add_child(dl)
	if not _mistakes.is_empty():
		v.add_child(UI.label("Стоит повторить", "Heading"))
		var list := UI.vbox(6)
		v.add_child(list)
		var shown := 0
		for m in _mistakes:
			var e := Store.entry(str(m["cid"]), str(m["eid"]))
			if e.is_empty():
				continue
			if shown >= 12:
				list.add_child(UI.label("и ещё %d…" % (_mistakes.size() - shown), "Muted"))
				break
			var h := UI.hbox(10)
			var en := UI.label(str(e["en"]), "Entry", true)
			en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			en.size_flags_stretch_ratio = 1.0
			h.add_child(en)
			var ru := UI.label(str(e["ru"]), "Muted", true)
			ru.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(ru)
			list.add_child(h)
			shown += 1
		bh.add_child(_btn("Повторить ошибки", "Primary", _repeat_mistakes, ""))
	bh.add_child(_btn("Ещё занятие", "Primary" if _mistakes.is_empty() else "", func() -> void: main.go("setup"), ""))
	bh.add_child(_btn("На главную", "Ghost", func() -> void: main.go("home"), ""))
	v.add_child(bh)
	UI.appear(card, 0.0, 0.0)


## «12 фраз за 4 минуты. Через 3 дня напомню про 5 из них.»
func _human_line(done: int) -> String:
	var mins := maxi(1, roundi((Time.get_ticks_msec() - _t0) / 60000.0))
	var out := "%d %s за %d %s." % [done, Dates.plural(done, "фраза", "фразы", "фраз"), mins,
		Dates.plural(mins, "минуту", "минуты", "минут")]
	var today := Dates.today()
	var soon := -1
	var n := 0
	for key in _graded:
		var parts := str(key).split("/")
		var e := Store.entry(parts[0], parts[1])
		var d := int(e.get("next", today))
		if e.is_empty() or d <= today:
			continue
		if soon < 0 or d < soon:
			soon = d
			n = 1
		elif d == soon:
			n += 1
	if soon > 0:
		var rel := Dates.relative(soon)
		rel = rel.left(1).to_upper() + rel.substr(1)
		if n < done:
			out += " %s напомню про %d из них." % [rel, n]
		else:
			out += " %s напомню про все." % rel
	if int(_stats[Srs.DONT]) > 0:
		out += " Ошибки вернутся ещё сегодня."
	return out


func _stat_box(n: int, caption: String, box: String, lab: String) -> Control:
	var p := UI.card(box)
	p.custom_minimum_size.x = 130
	var v := UI.vbox(0)
	p.add_child(v)
	var b := UI.label(str(n), lab)
	b.add_theme_font_size_override("font_size", 34)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	var c := UI.label(caption, "Muted")
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	return p


func _repeat_mistakes() -> void:
	var cards := _mistakes.duplicate(true)
	cards.shuffle()
	main.go("study", {"cards": cards, "mode": "en_ru" if mode == "free" else mode, "options": args.get("options", {})})


func _again_free() -> void:
	var cards: Array = []
	for c in _queue:
		cards.append({"cid": c["cid"], "eid": c["eid"], "cat": c["cat"]})
	cards.shuffle()
	main.go("study", {"cards": cards, "mode": "free", "options": args.get("options", {})})


# ───────────────────────────── клавиши

func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo or _finished:
		return
	if main and main.has_modal():
		return
	if _busy:
		get_viewport().set_input_as_handled()
		return
	var used := true
	match mode:
		"free":
			match k.keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_UP, KEY_DOWN:
					_flip()
				KEY_RIGHT:
					_next_free()
				KEY_LEFT:
					_prev()
				_:
					used = false
		"choice":
			var n := -1
			if k.keycode >= KEY_1 and k.keycode <= KEY_9:
				n = k.keycode - KEY_1
			elif k.keycode >= KEY_KP_1 and k.keycode <= KEY_KP_9:
				n = k.keycode - KEY_KP_1
			if n >= 0 and _picked == -1:
				_pick(n)
			elif k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _picked != -1:
				_next_choice()
			else:
				used = false
		"type":
			if (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and _checked:
				_next_typed()
			else:
				used = false
		_:
			match k.keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					if not _revealed:
						_reveal()
					else:
						used = false
				KEY_1, KEY_KP_1:
					if _revealed:
						_grade(Srs.DONT)
				KEY_2, KEY_KP_2:
					if _revealed:
						_grade(Srs.ALMOST)
				KEY_3, KEY_KP_3:
					if _revealed:
						_grade(Srs.KNOW)
				_:
					used = false
	if used:
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	Speech.stop()


## Esc / «Закончить»: из занятия — к итогу (если что-то отмечено), из итога — домой.
func back() -> void:
	if _finished:
		main.go("home")
		return
	if mode != "free" and _done_first > 0:
		_finish()
	else:
		main.go("home")
