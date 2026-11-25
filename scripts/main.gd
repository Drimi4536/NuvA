extends Control
## Главный узел: экраны (мягкая смена), окна поверх, сообщения внизу, быстрое добавление.
##
## Быстрое добавление из буфера: скопировали фразу где угодно (Ctrl+C) → вернулись в окно словаря →
## сверху строка «В буфере: …» с кнопкой «Добавить». Или Ctrl+N — окно добавления, английский уже из буфера,
## курсор в переводе. Esc — назад.

const SCREENS := {
	"home": "res://scenes/screens/home.tscn",
	"category": "res://scenes/screens/category.tscn",
	"setup": "res://scenes/screens/study_setup.tscn",
	"study": "res://scenes/screens/study.tscn",
}
const CLIP_MAX := 400   # длиннее — это уже не фраза для словаря
const SCALES := [0.9, 1.0, 1.15, 1.3]   # масштаб интерфейса (Ctrl+= / Ctrl+- / Ctrl+0)

var current: Screen
var _bg := ColorRect.new()
var _holder := Control.new()
var _overlay := Control.new()
var _toasts := VBoxContainer.new()
var _clip_bar: PanelContainer
var _clip_label: Label
var _clip_text := ""
var _last_clip := ""        # что уже предлагали (или скопировали сами) — второй раз не предлагаем
var _current_name := ""


func _ready() -> void:
	add_to_group("main")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = AppTheme.theme
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.color = AppTheme.c("bg")
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_build_clip_bar()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.offset_bottom = -28
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	AppTheme.changed.connect(_on_theme)
	get_window().min_size = Vector2i(820, 600)
	_restore_window()
	_apply_scale()
	get_window().size_changed.connect(_remember_window_soon)
	# текст, который уже лежал в буфере при запуске, не предлагаем — только новый
	_last_clip = _clipboard()
	go("home")


# ───────────────────────────── экраны

## Перейти на экран: go("category", {"cid": …}).
func go(screen: String, args := {}) -> void:
	var scene: PackedScene = load(SCREENS[screen])
	var s: Screen = scene.instantiate()
	s.main = self
	s.args = args
	var old := current
	current = s
	_current_name = screen
	_holder.add_child(s)
	# мягкая смена: новый проступает, старый гаснет
	s.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(s, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	if old:
		old.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tw.tween_property(old, "modulate:a", 0.0, 0.14)
		tw.chain().tween_callback(old.queue_free)


func screen_name() -> String:
	return _current_name


func _on_theme() -> void:
	theme = AppTheme.theme
	_bg.color = AppTheme.c("bg")
	_clip_bar.queue_free()
	_build_clip_bar()
	if current:
		current.rebuild()


# ───────────────────────────── окно и масштаб

func ui_scale() -> float:
	var v := float(Store.setting("scale", 1.0))
	var best: float = SCALES[1]
	for sc in SCALES:
		if absf(float(sc) - v) < absf(best - v):
			best = sc
	return best


func set_ui_scale(v: float) -> void:
	Store.set_setting("scale", v)
	_apply_scale()
	toast("Масштаб: %d %%" % roundi(v * 100.0), 1.4)


func _apply_scale() -> void:
	get_window().content_scale_factor = ui_scale()


## Положение и размер окна с прошлого раза (если окно попадает на экран).
func _restore_window() -> void:
	var w: Variant = Store.setting("window", {})
	if not w is Dictionary or (w as Dictionary).is_empty() or DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if bool(w.get("max", false)):
		win.mode = Window.MODE_MAXIMIZED
		return
	var rect := Rect2i(int(w.get("x", 0)), int(w.get("y", 0)), int(w.get("w", 1180)), int(w.get("h", 780)))
	for i in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(i).grow(40).encloses(rect):
			win.position = rect.position
			win.size = rect.size
			return


var _win_timer: SceneTreeTimer


func _remember_window_soon() -> void:
	if _win_timer:
		return
	_win_timer = get_tree().create_timer(0.8)
	_win_timer.timeout.connect(func() -> void:
		_win_timer = null
		_remember_window())


func _remember_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if win.mode == Window.MODE_MINIMIZED:
		return
	var w := {"max": win.mode == Window.MODE_MAXIMIZED}
	if win.mode == Window.MODE_WINDOWED:
		w.merge({"x": win.position.x, "y": win.position.y, "w": win.size.x, "h": win.size.y})
	else:
		var old: Variant = Store.setting("window", {})
		if old is Dictionary:
			w.merge(old as Dictionary)
			w["max"] = win.mode == Window.MODE_MAXIMIZED
	if w != Store.setting("window", {}):
		Store.set_setting("window", w)


# ───────────────────────────── окна и сообщения

func open_modal(m: Modal) -> Modal:
	_overlay.add_child(m)
	return m


func has_modal() -> bool:
	for ch in _overlay.get_children():
		if ch is Modal and (ch as Modal).is_open():
			return true
	return false


## Короткое сообщение внизу, само исчезает. С действием — кнопка справа («Вернуть»).
func toast(text: String, sec := 2.6, action_text := "", action := Callable()) -> void:
	for t in _toasts.get_children():   # то же сообщение уже висит — второе не добавляем
		if t.has_meta("text") and str(t.get_meta("text")) == text and not t.is_queued_for_deletion():
			return
	var p := UI.card("Toast")
	p.set_meta("text", text)
	var h := UI.hbox(14)
	p.add_child(h)
	var l := UI.label(text, "ToastLabel")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	if action_text != "" and action.is_valid():
		var b := UI.button(action_text, "Ghost")
		b.add_theme_color_override(&"font_color", AppTheme.c("accent"))
		b.add_theme_color_override(&"font_hover_color", AppTheme.c("accent_hover"))
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			action.call()
			b.disabled = true
			var tw2 := p.create_tween()
			tw2.tween_property(p, "modulate:a", 0.0, 0.2)
			tw2.tween_callback(p.queue_free))
		h.add_child(b)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(sec)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
	tw.tween_callback(p.queue_free)


# ───────────────────────────── быстрое добавление

## Окно добавления с выбором категории. text — английский (например, из буфера).
func quick_add(text := "", ru := "") -> void:
	if Store.categories().is_empty():
		Store.add_category("Разное")
	var cid := str(Store.setting("quick_cat", ""))
	if current and current.args.has("cid") and _current_name == "category":
		cid = str(current.args["cid"])
	if Store.category(cid).is_empty():
		cid = str(Store.categories()[0]["id"])
	var d := EntryDialog.new()
	d.title_text = "Новая запись"
	d.en = text
	d.ru = ru
	d.cid = cid
	d.pick_category = true
	d.ok_text = "Добавить"
	open_modal(d)
	var r: Variant = await d.done
	if r == null:
		return
	var res: Dictionary = r
	Store.add_entry(str(res["cid"]), str(res["en"]), str(res["ru"]), str(res["note"]))
	Store.set_setting("quick_cat", str(res["cid"]))
	_hide_clip_bar()
	toast("Добавлено в «%s»" % Store.category(str(res["cid"]))["name"])
	if current:
		current.rebuild()


## Текст из буфера, если он похож на фразу для словаря.
func _clipboard() -> String:
	if not DisplayServer.clipboard_has():
		return ""
	var t := DisplayServer.clipboard_get().strip_edges()
	if t.length() > CLIP_MAX:
		return ""
	return t


## Скопировали что-то сами (копирование записи) — не предлагать это добавить.
func remember_clip(t: String) -> void:
	_last_clip = t.strip_edges()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_check_clipboard()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_remember_window()
		Store.write_now()


## Вернулись в окно: в буфере новая фраза — предложить добавить.
func _check_clipboard() -> void:
	var t := _clipboard()
	if t == "" or t == _last_clip:
		return
	_last_clip = t
	if _known(t):
		return
	_clip_text = t
	_clip_label.text = "В буфере: «%s»" % (t if t.length() <= 60 else t.left(58) + "…")
	if not _clip_bar.visible:
		_clip_bar.visible = true
		_toasts.offset_bottom = -100   # сообщения — над строкой буфера
		_clip_bar.modulate.a = 0.0
		create_tween().tween_property(_clip_bar, "modulate:a", 1.0, 0.25)


func _known(t: String) -> bool:
	return Store.has_phrase(t)


func _build_clip_bar() -> void:
	_clip_bar = UI.card("Banner")
	_clip_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_clip_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clip_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_clip_bar.offset_bottom = -24
	_clip_bar.visible = false
	var h := UI.hbox(12)
	_clip_bar.add_child(h)
	_clip_label = UI.label("", "")
	h.add_child(_clip_label)
	h.add_child(UI.button("Добавить", "Primary", func() -> void: quick_add(_clip_text)))
	h.add_child(UI.button("✕", "Ghost", _hide_clip_bar, "Скрыть"))
	add_child(_clip_bar)
	move_child(_clip_bar, _overlay.get_index() if _overlay.get_parent() == self else get_child_count() - 1)


func _hide_clip_bar() -> void:
	if not _clip_bar.visible:
		return
	var tw := create_tween()
	tw.tween_property(_clip_bar, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		_clip_bar.visible = false
		_toasts.offset_bottom = -28)


# ───────────────────────────── клавиши

## _input: Esc и Ctrl+N работают, даже когда курсор стоит в поле ввода.
func _input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if has_modal():
		return
	if k.ctrl_pressed and k.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT, KEY_0, KEY_KP_0]:
		get_viewport().set_input_as_handled()
		var i := SCALES.find(ui_scale())
		if k.keycode in [KEY_0, KEY_KP_0]:
			set_ui_scale(1.0)
		elif k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			set_ui_scale(SCALES[maxi(i - 1, 0)])
		else:
			set_ui_scale(SCALES[mini(i + 1, SCALES.size() - 1)])
	elif k.keycode == KEY_F and k.ctrl_pressed and current and current.has_method("focus_search"):
		get_viewport().set_input_as_handled()
		current.call("focus_search")
	elif k.keycode == KEY_N and k.ctrl_pressed:
		get_viewport().set_input_as_handled()
		var t := _clipboard()
		quick_add(t if not _known(t) else "")
	elif k.keycode == KEY_ESCAPE and current:
		get_viewport().set_input_as_handled()
		current.back()
