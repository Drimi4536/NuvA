class_name Screen
extends Control
## Основа экрана. main — главный узел (переходы, окна, сообщения); args — что передали при переходе.
## Экран строит себя в build(); back() — что делать по Esc.

var main: Node
var args: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()


func build() -> void:
	pass


func back() -> void:
	pass


## Пересобрать экран (после изменений данных).
func rebuild() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	build()


## Прокручиваемая колонка по центру: вернёт VBox, куда класть содержимое.
func scroll_column(width := 920.0, top := 34.0) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var page := Page.new(width)
	sc.add_child(page)
	var v := UI.vbox(18)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", int(top))
	m.add_theme_constant_override("margin_bottom", 40)
	page.add_child(m)
	m.add_child(v)
	return v
