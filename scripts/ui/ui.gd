class_name UI
extends RefCounted
## Мелкие помощники для сборки интерфейса кодом.


static func label(text: String, variation := "", wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, variation := "", cb: Callable = Callable(), tip := "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if cb.is_valid():
		b.pressed.connect(cb)
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer(w := 0.0, h := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if w == 0.0 and h == 0.0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func card(variation := "Card") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


static func line(placeholder: String, text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.clear_button_enabled = false
	e.select_all_on_focus = false
	return e


## Мягкое появление: из прозрачности и чуть снизу.
static func appear(c: CanvasItem, delay := 0.0, dy := 10.0) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_parallel()
	if c is Control and dy != 0.0:
		var ctl := c as Control
		var y := ctl.position.y
		ctl.position.y = y + dy
		tw.tween_property(ctl, "position:y", y, 0.26).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.22).set_delay(delay).set_trans(Tween.TRANS_SINE)


## «24 записи».
static func n_entries(n: int) -> String:
	return "%d %s" % [n, Dates.plural(n, "запись", "записи", "записей")]


## Пустая строка из пробелов → «».
static func clean(s: String) -> String:
	return s.strip_edges()


## Показывать target только при наведении на owner (мягко). Уход мыши на дочерние кнопки — не уход.
static func hover_reveal(owner: Control, target: CanvasItem, rest := 0.0) -> void:
	target.modulate.a = rest
	owner.mouse_entered.connect(func() -> void:
		target.create_tween().tween_property(target, "modulate:a", 1.0, 0.12))
	owner.mouse_exited.connect(func() -> void:
		if owner.get_global_rect().has_point(owner.get_global_mouse_position()):
			return
		target.create_tween().tween_property(target, "modulate:a", rest, 0.18))


## Кружок с числом (сколько пора повторить).
static func badge(n: int, tip := "") -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = AppTheme.c("accent")
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override(&"panel", sb)
	p.custom_minimum_size = Vector2(24, 24)
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(str(n))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", AppTheme.font("SemiBold"))
	l.add_theme_font_size_override(&"font_size", 14)
	l.add_theme_color_override(&"font_color", AppTheme.c("accent_text"))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(l)
	return p


## Кнопка с подсказкой клавиши справа: «Знаю   3».
static func key_button(text: String, key: String, variation: String, cb: Callable, tip := "") -> Button:
	var kw := 0.0
	if key != "":
		kw = AppTheme.font("Regular").get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var pad := " ".repeat(ceili((kw + 12.0) / 4.5)) if key != "" else ""
	var b := button(text + pad, variation, cb, tip)
	b.focus_mode = Control.FOCUS_NONE
	if key != "":
		var k := label(key, "Small")
		k.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		k.offset_left = -14.0 - kw
		k.offset_right = -14
		k.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		k.modulate.a = 0.75
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(k)
	return b


## Цветная полоса прогресса.
static func bar(value: float, max_value: float, col: Color, height := 8.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size.y = height
	pb.max_value = maxf(max_value, 1.0)
	pb.value = value
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(int(height * 0.5) + 1)
	pb.add_theme_stylebox_override(&"fill", fill)
	pb.mouse_filter = Control.MOUSE_FILTER_PASS
	return pb


static var _tex_cache := {}

## Картинка из папки media (кэш), null — нет файла.
static func media_texture(fname: String) -> Texture2D:
	var p := Store.media_path(fname)
	if p == "":
		return null
	if _tex_cache.has(p):
		return _tex_cache[p]
	var img := Image.load_from_file(ProjectSettings.globalize_path(p))
	if img == null or img.is_empty():
		return null
	if img.get_width() > 960:   # большие скриншоты — уменьшить (память и скорость)
		img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	var t := ImageTexture.create_from_image(img)
	_tex_cache[p] = t
	return t


## Картинка со скруглёнными углами заданной высоты.
static func picture(fname: String, max_h: float, max_w := 0.0) -> Control:
	var t := media_texture(fname)
	if t == null:
		return null
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var w := max_h * t.get_width() / maxf(1.0, t.get_height())
	if max_w > 0.0 and w > max_w:
		w = max_w
		max_h = w * t.get_height() / maxf(1.0, t.get_width())
	tr.custom_minimum_size = Vector2(w, max_h)
	tr.mouse_filter = Control.MOUSE_FILTER_PASS
	var clip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = AppTheme.c("surface2")
	sb.set_corner_radius_all(12)
	clip.add_theme_stylebox_override(&"panel", sb)
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clip.mouse_filter = Control.MOUSE_FILTER_PASS
	clip.add_child(tr)
	return clip


## Текст с [b]выделением[/b] (контекст из Anki).
static func rich(bb: String, size := 17, col := Color(), center := false) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.add_theme_font_override(&"normal_font", AppTheme.font("Regular"))
	rt.add_theme_font_override(&"bold_font", AppTheme.font("SemiBold"))
	rt.add_theme_font_size_override(&"normal_font_size", size)
	rt.add_theme_font_size_override(&"bold_font_size", size)
	rt.add_theme_color_override(&"default_color", col if col != Color() else AppTheme.c("text"))
	rt.text = ("[center]%s[/center]" % bb) if center else bb
	rt.mouse_filter = Control.MOUSE_FILTER_PASS
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rt


## [b]слово[/b] → жирным и акцентным цветом.
static func hl(bb: String) -> String:
	var hx := AppTheme.c("accent").to_html(false)
	return bb.replace("[b]", "[b][color=#%s]" % hx).replace("[/b]", "[/color][/b]")
