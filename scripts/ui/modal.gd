class_name Modal
extends Control
## Окно поверх экрана: затемнение и карточка по центру. Появляется и исчезает мягко.
## Esc или щелчок мимо карточки — отмена. done(result) — null при отмене.
##   var m := Modal.new(); m.title_text = "…"; m.body.add_child(…); main.open_modal(m); var r = await m.done

signal done(result: Variant)

var title_text := ""
var width := 520.0
var body := VBoxContainer.new()      # содержимое
var buttons := HBoxContainer.new()   # кнопки внизу (справа)
var _card := PanelContainer.new()
var _dim := ColorRect.new()
var _closing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = AppTheme.c("dim")
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close(null))
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card.theme_type_variation = "Card"
	_card.custom_minimum_size.x = width
	center.add_child(_card)
	var v := UI.vbox(18)
	_card.add_child(v)
	if title_text != "":
		v.add_child(UI.label(title_text, "Heading"))
	body.add_theme_constant_override("separation", 12)
	v.add_child(body)
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(buttons)
	# появление
	_dim.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.97, 0.97)
	_card.pivot_offset = Vector2(width * 0.5, 120)
	var tw := create_tween().set_parallel()
	tw.tween_property(_dim, "modulate:a", 1.0, 0.18)
	tw.tween_property(_card, "modulate:a", 1.0, 0.2)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func add_button(text: String, variation: String, cb: Callable) -> Button:
	var b := UI.button(text, variation, cb)
	buttons.add_child(b)
	return b


## Открыто и не закрывается.
func is_open() -> bool:
	return not _closing and not is_queued_for_deletion()


func close(result: Variant) -> void:
	if _closing:
		return
	_closing = true
	done.emit(result)
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)


## _input, а не _unhandled: поле ввода в фокусе не должно съедать Esc.
func _input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and is_open():
		get_viewport().set_input_as_handled()
		close(null)
