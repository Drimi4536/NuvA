extends Node
## AppTheme — оформление (автозагрузка): светлая и тёмная тема с тёплым оранжевым акцентом.
## Тема собирается кодом в один Theme; экраны берут вид через вариации:
##   Label: Title, Heading, Big, Muted, Small, Accent, Good, Bad
##   Button: Primary, Ghost, Danger, Chip (переключатель), Tile (карточка-выбор)
##   PanelContainer: Card, CardHover, Soft, Banner
## Смена темы — dark = true/false: тема пересобирается, сигнал changed.

signal changed

const LIGHT := {
	"bg": Color("fbf6ee"), "surface": Color("ffffff"), "surface2": Color("f6eee3"), "text": Color("2b2622"),
	"muted": Color("8a7e72"), "border": Color("eadfd2"), "accent": Color("e8792b"), "accent_hover": Color("f08a3e"),
	"accent_soft": Color("fde7d6"), "accent_text": Color("ffffff"), "good": Color("4f9a62"), "good_soft": Color("e3f2e6"),
	"bad": Color("c8553d"), "bad_soft": Color("f8e1db"), "shadow": Color(0.35, 0.22, 0.1, 0.08), "dim": Color(0.16, 0.12, 0.08, 0.32),
}
const DARK := {
	"bg": Color("1e1b19"), "surface": Color("2a2623"), "surface2": Color("332e2a"), "text": Color("f3ece4"),
	"muted": Color("a59a8f"), "border": Color("3d3631"), "accent": Color("f08a3c"), "accent_hover": Color("f79c55"),
	"accent_soft": Color("4a3121"), "accent_text": Color("1e1b19"), "good": Color("74c189"), "good_soft": Color("26372a"),
	"bad": Color("e6826b"), "bad_soft": Color("41281f"), "shadow": Color(0, 0, 0, 0.25), "dim": Color(0, 0, 0, 0.5),
}

const CAT_LIGHT := ["e8792b", "4f9a62", "4a86c5", "9a62c4", "d1567d", "c49a1f", "3a9e9b", "8a7e72"]
const CAT_DARK := ["f08a3c", "74c189", "71a8e0", "b98ae0", "e77d9d", "e0b84a", "5cc2be", "a59a8f"]
const CAT_NAMES := ["Оранжевый", "Зелёный", "Синий", "Фиолетовый", "Розовый", "Горчичный", "Бирюзовый", "Серый"]

var dark := false
var theme: Theme
var _fonts := {}
var _check_on: Texture2D
var _check_off: Texture2D


func _ready() -> void:
	dark = str(Store.setting("theme", "light")) == "dark"
	theme = build()
	RenderingServer.set_default_clear_color(c("bg"))


func set_dark(on: bool) -> void:
	if on == dark:
		return
	dark = on
	Store.set_setting("theme", "dark" if on else "light")
	theme = build()
	RenderingServer.set_default_clear_color(c("bg"))
	changed.emit()


## Цвет текущей темы по имени.
func c(key: String) -> Color:
	return (DARK if dark else LIGHT)[key]


## Цвет категории (номер 0…7) и его мягкий вариант для подложки.
func cat_color(i: int) -> Color:
	var arr: Array = CAT_DARK if dark else CAT_LIGHT
	return Color(str(arr[posmod(i, arr.size())]))


func cat_soft(i: int) -> Color:
	return c("surface").lerp(cat_color(i), 0.16 if not dark else 0.22)


func font(weight := "Regular") -> Font:
	if not _fonts.has(weight):
		_fonts[weight] = load("res://assets/fonts/Inter-%s.otf" % weight)
	return _fonts[weight]


func _box(bg: Color, radius := 12, border := Color(0, 0, 0, 0), bw := 0, pad := Vector4(16, 10, 16, 10)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s


func build() -> Theme:
	var t := Theme.new()
	t.default_font = font("Regular")
	t.default_font_size = 17
	_labels(t)
	_buttons(t)
	_panels(t)
	_inputs(t)
	_misc(t)
	return t


func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", c("text"))
	t.set_font_size("font_size", "Label", 17)
	var lab := func(nm: String, weight: String, size: int, col: Color) -> void:
		t.set_type_variation(nm, "Label")
		t.set_font(&"font", nm, font(weight))
		t.set_font_size(&"font_size", nm, size)
		t.set_color(&"font_color", nm, col)
	lab.call("Title", "Bold", 32, c("text"))
	lab.call("Heading", "SemiBold", 21, c("text"))
	lab.call("Big", "SemiBold", 32, c("text"))
	lab.call("Answer", "Medium", 25, c("text"))
	lab.call("Muted", "Regular", 16, c("muted"))
	lab.call("Small", "Regular", 14, c("muted"))
	lab.call("Accent", "SemiBold", 16, c("accent"))
	lab.call("Good", "SemiBold", 20, c("good"))
	lab.call("Bad", "SemiBold", 20, c("bad"))
	lab.call("Entry", "SemiBold", 18, c("text"))


func _buttons(t: Theme) -> void:
	# обычная кнопка: светлая поверхность с тонкой рамкой
	t.set_font(&"font", "Button", font("Medium"))
	t.set_font_size(&"font_size", "Button", 17)
	t.set_color(&"font_color", "Button", c("text"))
	t.set_color(&"font_hover_color", "Button", c("text"))
	t.set_color(&"font_pressed_color", "Button", c("text"))
	t.set_color(&"font_focus_color", "Button", c("text"))
	t.set_color(&"font_disabled_color", "Button", c("muted"))
	t.set_stylebox(&"normal", "Button", _box(c("surface"), 12, c("border"), 1, Vector4(18, 11, 18, 11)))
	t.set_stylebox(&"hover", "Button", _box(c("surface2"), 12, c("border"), 1, Vector4(18, 11, 18, 11)))
	t.set_stylebox(&"pressed", "Button", _box(c("accent_soft"), 12, c("accent"), 1, Vector4(18, 11, 18, 11)))
	t.set_stylebox(&"disabled", "Button", _box(c("surface"), 12, c("border"), 1, Vector4(18, 11, 18, 11)))
	t.set_stylebox(&"focus", "Button", _box(Color(0, 0, 0, 0), 12, Color(c("accent"), 0.5), 2, Vector4(18, 11, 18, 11)))
	# главная — оранжевая
	t.set_type_variation(&"Primary", "Button")
	t.set_color(&"font_color", "Primary", c("accent_text"))
	t.set_color(&"font_hover_color", "Primary", c("accent_text"))
	t.set_color(&"font_pressed_color", "Primary", c("accent_text"))
	t.set_color(&"font_focus_color", "Primary", c("accent_text"))
	t.set_color(&"font_disabled_color", "Primary", Color(c("accent_text"), 0.7))
	t.set_font(&"font", "Primary", font("SemiBold"))
	t.set_stylebox(&"normal", "Primary", _box(c("accent"), 12, Color(0, 0, 0, 0), 0, Vector4(22, 12, 22, 12)))
	t.set_stylebox(&"hover", "Primary", _box(c("accent_hover"), 12, Color(0, 0, 0, 0), 0, Vector4(22, 12, 22, 12)))
	t.set_stylebox(&"pressed", "Primary", _box(c("accent").darkened(0.08), 12, Color(0, 0, 0, 0), 0, Vector4(22, 12, 22, 12)))
	t.set_stylebox(&"disabled", "Primary", _box(Color(c("accent"), 0.45), 12, Color(0, 0, 0, 0), 0, Vector4(22, 12, 22, 12)))
	# тихая — без рамки
	t.set_type_variation(&"Ghost", "Button")
	t.set_color(&"font_color", "Ghost", c("muted"))
	t.set_color(&"font_hover_color", "Ghost", c("text"))
	t.set_color(&"font_pressed_color", "Ghost", c("accent"))
	t.set_stylebox(&"normal", "Ghost", _box(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 0, Vector4(12, 8, 12, 8)))
	t.set_stylebox(&"hover", "Ghost", _box(c("surface2"), 10, Color(0, 0, 0, 0), 0, Vector4(12, 8, 12, 8)))
	t.set_stylebox(&"pressed", "Ghost", _box(c("accent_soft"), 10, Color(0, 0, 0, 0), 0, Vector4(12, 8, 12, 8)))
	t.set_stylebox(&"focus", "Ghost", _box(Color(0, 0, 0, 0), 10, Color(c("accent"), 0.4), 2, Vector4(12, 8, 12, 8)))
	# опасная — красный текст
	t.set_type_variation(&"Danger", "Button")
	t.set_color(&"font_color", "Danger", c("bad"))
	t.set_color(&"font_hover_color", "Danger", c("bad"))
	t.set_stylebox(&"normal", "Danger", _box(c("surface"), 12, c("border"), 1, Vector4(18, 11, 18, 11)))
	t.set_stylebox(&"hover", "Danger", _box(c("bad_soft"), 12, c("bad_soft"), 1, Vector4(18, 11, 18, 11)))
	# переключатель-«таблетка»
	t.set_type_variation(&"Chip", "Button")
	t.set_font_size(&"font_size", "Chip", 16)
	t.set_color(&"font_pressed_color", "Chip", c("accent"))
	t.set_color(&"font_hover_pressed_color", "Chip", c("accent"))
	t.set_stylebox(&"normal", "Chip", _box(c("surface"), 20, c("border"), 1, Vector4(16, 8, 16, 8)))
	t.set_stylebox(&"hover", "Chip", _box(c("surface2"), 20, c("border"), 1, Vector4(16, 8, 16, 8)))
	t.set_stylebox(&"pressed", "Chip", _box(c("accent_soft"), 20, c("accent"), 2, Vector4(16, 8, 16, 8)))
	t.set_stylebox(&"hover_pressed", "Chip", _box(c("accent_soft"), 20, c("accent"), 2, Vector4(16, 8, 16, 8)))
	# плитка выбора (режимы)
	t.set_type_variation(&"Tile", "Button")
	t.set_stylebox(&"normal", "Tile", _box(c("surface"), 16, c("border"), 1, Vector4(18, 16, 18, 16)))
	t.set_stylebox(&"hover", "Tile", _box(c("surface2"), 16, c("border"), 1, Vector4(18, 16, 18, 16)))
	t.set_stylebox(&"pressed", "Tile", _box(c("accent_soft"), 16, c("accent"), 2, Vector4(18, 16, 18, 16)))
	t.set_stylebox(&"hover_pressed", "Tile", _box(c("accent_soft"), 16, c("accent"), 2, Vector4(18, 16, 18, 16)))
	# кнопки ответа на карточке
	for v in [["Know", "good", "good_soft"], ["Dont", "bad", "bad_soft"]]:
		var nm: String = v[0]
		t.set_type_variation(nm, "Button")
		t.set_font(&"font", nm, font("SemiBold"))
		t.set_color(&"font_color", nm, c(v[1]))
		t.set_color(&"font_hover_color", nm, c(v[1]))
		t.set_color(&"font_pressed_color", nm, c(v[1]))
		t.set_stylebox(&"normal", nm, _box(c(v[2]), 12, Color(0, 0, 0, 0), 0, Vector4(22, 12, 22, 12)))
		t.set_stylebox(&"hover", nm, _box(c(v[2]), 12, Color(c(v[1]), 0.5), 1, Vector4(22, 12, 22, 12)))
		t.set_stylebox(&"pressed", nm, _box(c(v[2]).darkened(0.05), 12, c(v[1]), 1, Vector4(22, 12, 22, 12)))
	# маленькая кнопка-значок (действия в строке)
	t.set_type_variation(&"Icon", "Button")
	t.set_font_size(&"font_size", "Icon", 17)
	t.set_color(&"font_color", "Icon", c("muted"))
	t.set_color(&"font_hover_color", "Icon", c("accent"))
	t.set_color(&"font_pressed_color", "Icon", c("accent"))
	for st in ["normal", "focus"]:
		t.set_stylebox(st, "Icon", _box(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 0, Vector4(8, 4, 8, 4)))
	t.set_stylebox(&"hover", "Icon", _box(c("surface2"), 8, Color(0, 0, 0, 0), 0, Vector4(8, 4, 8, 4)))
	t.set_stylebox(&"pressed", "Icon", _box(c("accent_soft"), 8, Color(0, 0, 0, 0), 0, Vector4(8, 4, 8, 4)))
	# MenuButton / OptionButton — как обычная кнопка
	for tp in ["MenuButton", "OptionButton"]:
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			t.set_stylebox(st, tp, t.get_stylebox(st, "Button"))
		t.set_font(&"font", tp, font("Medium"))
		t.set_color(&"font_color", tp, c("text"))
		t.set_color(&"font_hover_color", tp, c("text"))


func _panels(t: Theme) -> void:
	var card := _box(c("surface"), 18, c("border"), 1, Vector4(22, 20, 22, 20))
	card.shadow_color = c("shadow")
	card.shadow_size = 10
	card.shadow_offset = Vector2(0, 3)
	t.set_type_variation(&"Card", "PanelContainer")
	t.set_stylebox(&"panel", "Card", card)
	var hover := card.duplicate() as StyleBoxFlat
	hover.border_color = Color(c("accent"), 0.6)
	hover.shadow_size = 14
	t.set_type_variation(&"CardHover", "PanelContainer")
	t.set_stylebox(&"panel", "CardHover", hover)
	t.set_type_variation(&"Soft", "PanelContainer")
	t.set_stylebox(&"panel", "Soft", _box(c("surface2"), 14, Color(0, 0, 0, 0), 0, Vector4(18, 14, 18, 14)))
	t.set_type_variation(&"Banner", "PanelContainer")
	t.set_stylebox(&"panel", "Banner", _box(c("accent_soft"), 14, Color(c("accent"), 0.35), 1, Vector4(18, 12, 12, 12)))
	t.set_type_variation(&"GoodBox", "PanelContainer")
	t.set_stylebox(&"panel", "GoodBox", _box(c("good_soft"), 14, Color(0, 0, 0, 0), 0, Vector4(18, 12, 18, 12)))
	t.set_type_variation(&"BadBox", "PanelContainer")
	t.set_stylebox(&"panel", "BadBox", _box(c("bad_soft"), 14, Color(0, 0, 0, 0), 0, Vector4(18, 12, 18, 12)))
	t.set_type_variation(&"AccentBox", "PanelContainer")
	t.set_stylebox(&"panel", "AccentBox", _box(c("accent_soft"), 14, Color(0, 0, 0, 0), 0, Vector4(18, 12, 18, 12)))
	t.set_stylebox(&"panel", "PanelContainer", StyleBoxEmpty.new())
	var toast := _box(c("text"), 14, Color(0, 0, 0, 0), 0, Vector4(20, 12, 20, 12))
	toast.shadow_color = c("shadow")
	toast.shadow_size = 12
	t.set_type_variation(&"Toast", "PanelContainer")
	t.set_stylebox(&"panel", "Toast", toast)
	t.set_type_variation(&"ToastLabel", "Label")
	t.set_color(&"font_color", "ToastLabel", c("bg"))
	t.set_font(&"font", "ToastLabel", font("Medium"))


func _inputs(t: Theme) -> void:
	for tp in ["LineEdit", "TextEdit"]:
		t.set_stylebox(&"normal", tp, _box(c("surface"), 12, c("border"), 1, Vector4(14, 11, 14, 11)))
		t.set_stylebox(&"focus", tp, _box(c("surface"), 12, c("accent"), 2, Vector4(13, 10, 13, 10)))
		t.set_stylebox(&"read_only", tp, _box(c("surface2"), 12, c("border"), 1, Vector4(14, 11, 14, 11)))
		t.set_color(&"font_color", tp, c("text"))
		t.set_color(&"font_placeholder_color", tp, Color(c("muted"), 0.8))
		t.set_color(&"caret_color", tp, c("accent"))
		t.set_color(&"selection_color", tp, Color(c("accent"), 0.3))
		t.set_font_size(&"font_size", tp, 18)
	t.set_type_variation(&"BigInput", "LineEdit")
	t.set_font_size(&"font_size", "BigInput", 24)
	t.set_stylebox(&"normal", "BigInput", _box(c("surface"), 14, c("border"), 1, Vector4(18, 14, 18, 14)))
	t.set_stylebox(&"focus", "BigInput", _box(c("surface"), 14, c("accent"), 2, Vector4(17, 13, 17, 13)))


func _misc(t: Theme) -> void:
	# галочки — рисованные, в цвет темы
	_check_on = _check_tex(true)
	_check_off = _check_tex(false)
	t.set_icon(&"checked", "CheckBox", _check_on)
	t.set_icon(&"unchecked", "CheckBox", _check_off)
	t.set_color(&"font_color", "CheckBox", c("text"))
	t.set_color(&"font_hover_color", "CheckBox", c("text"))
	t.set_color(&"font_pressed_color", "CheckBox", c("text"))
	t.set_color(&"font_hover_pressed_color", "CheckBox", c("text"))
	t.set_color(&"font_focus_color", "CheckBox", c("text"))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(st, "CheckBox", _box(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 0, Vector4(4, 6, 8, 6)))
	t.set_constant(&"h_separation", "CheckBox", 10)
	# всплывающее меню
	var pm := _box(c("surface"), 12, c("border"), 1, Vector4(6, 6, 6, 6))
	pm.shadow_color = c("shadow")
	pm.shadow_size = 12
	t.set_stylebox(&"panel", "PopupMenu", pm)
	t.set_stylebox(&"hover", "PopupMenu", _box(c("accent_soft"), 8))
	t.set_color(&"font_color", "PopupMenu", c("text"))
	t.set_color(&"font_hover_color", "PopupMenu", c("text"))
	t.set_color(&"font_disabled_color", "PopupMenu", c("muted"))
	t.set_font_size(&"font_size", "PopupMenu", 17)
	t.set_constant(&"v_separation", "PopupMenu", 10)
	t.set_constant(&"item_start_padding", "PopupMenu", 12)
	t.set_constant(&"item_end_padding", "PopupMenu", 16)
	# прокрутка — тонкая
	var grab := _box(Color(c("muted"), 0.35), 4, Color(0, 0, 0, 0), 0, Vector4(4, 4, 4, 4))
	var grab_h := _box(Color(c("muted"), 0.6), 4, Color(0, 0, 0, 0), 0, Vector4(4, 4, 4, 4))
	t.set_stylebox(&"scroll", "VScrollBar", _box(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0, Vector4(4, 0, 4, 0)))
	t.set_stylebox(&"grabber", "VScrollBar", grab)
	t.set_stylebox(&"grabber_highlight", "VScrollBar", grab_h)
	t.set_stylebox(&"grabber_pressed", "VScrollBar", grab_h)
	# полоса прогресса
	t.set_stylebox(&"background", "ProgressBar", _box(c("surface2"), 6, Color(0, 0, 0, 0), 0, Vector4(0, 0, 0, 0)))
	t.set_stylebox(&"fill", "ProgressBar", _box(c("accent"), 6, Color(0, 0, 0, 0), 0, Vector4(0, 0, 0, 0)))
	t.set_constant(&"outline_size", "ProgressBar", 0)
	t.set_font_size(&"font_size", "ProgressBar", 1)
	t.set_color(&"font_color", "ProgressBar", Color(0, 0, 0, 0))
	# подсказка
	t.set_stylebox(&"panel", "TooltipPanel", _box(c("text"), 8, Color(0, 0, 0, 0), 0, Vector4(10, 6, 10, 6)))
	t.set_color(&"font_color", "TooltipLabel", c("bg"))
	t.set_font_size(&"font_size", "TooltipLabel", 14)
	# разделитель — тонкая линия в цвет рамок
	var sep := StyleBoxLine.new()
	sep.color = c("border")
	sep.thickness = 1
	t.set_stylebox(&"separator", "HSeparator", sep)
	t.set_constant(&"separation", "HSeparator", 12)
	# SpinBox
	t.set_font_size(&"font_size", "SpinBox", 18)


## Галочка: квадрат со скруглением; включена — оранжевая с белой галкой.
func _check_tex(on: bool) -> Texture2D:
	var s := 22
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var r := 5.0
	var acc := c("accent")
	var brd := c("muted").lerp(c("surface"), 0.3)
	for y in s:
		for x in s:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			# расстояние до скруглённого квадрата
			var qx := absf(px - s * 0.5) - (s * 0.5 - r - 1.0)
			var qy := absf(py - s * 0.5) - (s * 0.5 - r - 1.0)
			var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - r
			var inside := clampf(0.5 - d, 0.0, 1.0)
			if inside <= 0.0:
				continue
			if on:
				img.set_pixel(x, y, Color(acc, inside))
			else:
				var edge := clampf(1.1 - absf(d + 1.2), 0.0, 1.0)
				var fill := c("surface")
				img.set_pixel(x, y, Color(fill.lerp(brd, edge), inside))
	if on:   # галка
		var pts := [Vector2(6, 11.5), Vector2(9.5, 15), Vector2(16, 7.5)]
		for i in 2:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			for k in 40:
				var p := a.lerp(b, k / 39.0)
				for oy in [-1, 0, 1]:
					for ox in [-1, 0, 1]:
						var q := Vector2i(int(p.x) + ox, int(p.y) + oy)
						if Vector2(q).distance_to(p) <= 1.3:
							img.set_pixelv(q, c("accent_text") if not dark else Color("1e1b19"))
	return ImageTexture.create_from_image(img)
