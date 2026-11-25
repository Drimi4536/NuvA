extends Screen
## Настройка занятия: какие категории (одна, несколько или весь словарь), режим, сколько карточек,
## перемешать, только сложные, только то, что пора повторить. Выбор запоминается до следующего раза.

const LIMITS := [10, 20, 30, 0]   # 0 — все

var _opts := {}
var _cat_chips: Array[Button] = []
var _all_chip: Button
var _mode_tiles := {}
var _limit_chips := {}
var _count: Label
var _start: Button


func build() -> void:
	_load_options()
	var v := scroll_column(860.0, 26.0)
	var head := UI.hbox(12)
	v.add_child(head)
	head.add_child(UI.button("←  Назад", "Ghost", back))
	head.add_child(UI.spacer())
	v.add_child(UI.label("Новое занятие", "Title"))
	# категории
	v.add_child(_section("Что повторяем"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	v.add_child(flow)
	_all_chip = _chip("Весь словарь  ·  %d" % Store.count_entries(), bool(_opts["all"]))
	_all_chip.toggled.connect(func(on: bool) -> void:
		_opts["all"] = on
		if on:
			_opts["cats"] = []
		_sync())
	flow.add_child(_all_chip)
	_cat_chips.clear()
	for c in Store.categories():
		var cid := str(c["id"])
		var b := _chip("%s  ·  %d" % [c["name"], (c["entries"] as Array).size()], (_opts["cats"] as Array).has(cid))
		b.set_meta("cid", cid)
		b.toggled.connect(func(on: bool) -> void:
			var cats: Array = _opts["cats"]
			if on and not cats.has(cid):
				cats.append(cid)
			elif not on:
				cats.erase(cid)
			_opts["all"] = cats.is_empty()
			_sync())
		flow.add_child(b)
		_cat_chips.append(b)
	# режим
	v.add_child(_section("Как"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var group := ButtonGroup.new()
	for m in Session.MODES:
		var tile := _mode_tile(str(m), group)
		grid.add_child(tile)
		_mode_tiles[m] = tile
	# количество и флажки
	v.add_child(_section("Сколько карточек"))
	var lim := UI.hbox(10)
	v.add_child(lim)
	var lg := ButtonGroup.new()
	for n in LIMITS:
		var b := _chip("Все" if n == 0 else str(n), int(_opts["limit"]) == n)
		b.button_group = lg
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_opts["limit"] = n
				_sync())
		lim.add_child(b)
		_limit_chips[n] = b
	var checks := UI.vbox(6)
	v.add_child(checks)
	checks.add_child(_check("Перемешать", "shuffle", "Часто забываемые слова попадаются чаще"))
	checks.add_child(_check("Только сложные слова", "only_hard", "Те, что вы недавно не вспомнили или часто путаете"))
	checks.add_child(_check("Только то, что пора повторить сегодня", "only_due", ""))
	var sp := CheckBox.new()
	sp.text = "Озвучивать английский"
	sp.tooltip_text = "Звук из Anki или голос системы — как только английский виден"
	sp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sp.set_pressed_no_signal(bool(Store.setting("auto_speak", true)))
	sp.toggled.connect(func(on: bool) -> void: Store.set_setting("auto_speak", on))
	checks.add_child(sp)
	# итог — внизу окна, всегда виден
	var sc := get_child(0) as ScrollContainer
	sc.offset_bottom = -92
	var bar := PanelContainer.new()
	bar.theme_type_variation = "Soft"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -92
	var sb := (AppTheme.theme.get_stylebox(&"panel", &"Soft") as StyleBoxFlat).duplicate() as StyleBoxFlat
	sb.set_corner_radius_all(0)
	sb.border_width_top = 1
	sb.border_color = AppTheme.c("border")
	bar.add_theme_stylebox_override(&"panel", sb)
	add_child(bar)
	var page := Page.new(860.0)
	bar.add_child(page)
	var bh := UI.hbox(16)
	bh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.add_child(bh)
	_count = UI.label("", "Heading")
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(_count)
	_start = UI.button("Начать", "Primary", _go)
	bh.add_child(_start)
	_sync()


func _load_options() -> void:
	var last: Dictionary = Store.setting("last", {})
	_opts = {
		"mode": str(last.get("mode", "en_ru")),
		"cats": (last.get("cats", []) as Array).duplicate(),
		"all": bool(last.get("all", true)),
		"limit": int(last.get("limit", 20)),
		"shuffle": bool(last.get("shuffle", true)),
		"only_hard": bool(last.get("only_hard", false)),
		"only_due": bool(last.get("only_due", false)),
	}
	if not Session.MODES.has(_opts["mode"]):
		_opts["mode"] = "en_ru"
	if not LIMITS.has(_opts["limit"]):
		_opts["limit"] = 20
	# категорий могло уже не стать
	var alive: Array = []
	for cid in _opts["cats"]:
		if not Store.category(str(cid)).is_empty():
			alive.append(str(cid))
	_opts["cats"] = alive
	# пришли из категории — сразу она одна
	if args.has("cid") and not Store.category(str(args["cid"])).is_empty():
		_opts["cats"] = [str(args["cid"])]
		_opts["all"] = false
	if args.has("only_hard"):
		_opts["only_hard"] = bool(args["only_hard"])
	if (_opts["cats"] as Array).is_empty():
		_opts["all"] = true


func _section(text: String) -> Control:
	var l := UI.label(text, "Heading")
	return l


func _chip(text: String, on: bool) -> Button:
	var b := UI.button(text, "Chip")
	b.toggle_mode = true
	b.set_pressed_no_signal(on)
	return b


func _mode_tile(mode: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.theme_type_variation = "Tile"
	b.toggle_mode = true
	b.button_group = group
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_pressed_no_signal(_opts["mode"] == mode)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16 if side in ["left", "right"] else 14)
	b.add_child(m)
	var v := UI.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var t := UI.label(str(Session.MODES[mode]), "Entry")
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var h := UI.label(str(Session.MODE_HINTS[mode]), "Small", true)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	b.toggled.connect(func(on: bool) -> void:
		if on:
			_opts["mode"] = mode
			_sync())
	return b


func _check(text: String, key: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.set_pressed_no_signal(bool(_opts[key]))
	c.toggled.connect(func(on: bool) -> void:
		_opts[key] = on
		_sync())
	return c


## Привести кнопки к выбору и пересчитать карточки.
func _sync() -> void:
	_all_chip.set_pressed_no_signal(bool(_opts["all"]))
	for b in _cat_chips:
		b.set_pressed_no_signal(not bool(_opts["all"]) and (_opts["cats"] as Array).has(str(b.get_meta("cid"))))
	var n := Session.count(_opts)
	if n == 0:
		_count.text = "Нет подходящих карточек"
		if bool(_opts["only_due"]):
			_count.text += " — на сегодня всё повторено"
		elif bool(_opts["only_hard"]):
			_count.text += " — сложных слов нет"
	else:
		_count.text = "Будет карточек: %d" % n
	_start.disabled = n == 0


func _go() -> void:
	Store.set_setting("last", _opts.duplicate(true))
	var cards := Session.build(_opts)
	if cards.is_empty():
		return
	main.go("study", {"cards": cards, "mode": _opts["mode"], "options": _opts.duplicate(true)})


func back() -> void:
	if args.has("cid") and not Store.category(str(args["cid"])).is_empty():
		main.go("category", {"cid": args["cid"]})
	else:
		main.go("home")
