class_name VoiceDialog
extends Modal
## Настройки озвучки: голос для английского и русского, скорость, автоозвучка, перевод при прослушивании.


func _init() -> void:
	title_text = "Озвучка"
	width = 520.0
	body.add_theme_constant_override("separation", 14)
	var en := Speech.voices("en")
	var ru := Speech.voices("ru")
	if Speech.piper_found():
		var pc := _check("Встроенный английский голос (Piper, без интернета)", "use_piper", true)
		pc.tooltip_text = "Читает любые фразы. Выключите — будет голос Windows"
		pc.toggled.connect(func(_on: bool) -> void: Speech.stop())
		body.add_child(pc)
	if Speech.last_error != "":
		var w2 := UI.card("BadBox")
		var wl := UI.label(Speech.last_error, "", true)
		wl.custom_minimum_size.x = 460
		w2.add_child(wl)
		body.add_child(w2)
	if Speech.piper_ok():
		pass
	elif en.is_empty():
		var warn := UI.card("AccentBox")
		warn.add_child(UI.label("Английский голос системы не найден. Слова со звуком из Anki всё равно озвучиваются.\n"
			+ "Голос можно добавить: Windows → Параметры → Время и язык → Речь → «Добавить голоса» → English (United States).",
			"", true))
		body.add_child(warn)
		var all: Array = []
		if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
			for v in DisplayServer.tts_get_voices():
				all.append("%s (%s)" % [v.get("name", "?"), v.get("language", "?")])
		body.add_child(UI.label("Голоса, которые видит приложение: " + (", ".join(all) if not all.is_empty() else "ни одного"),
			"Small", true))
	else:
		body.add_child(_row("Английский голос", _voices(en, "voice_en")))
	if not ru.is_empty():
		body.add_child(_row("Русский голос", _voices(ru, "voice_ru")))
	var rate := HSlider.new()
	rate.min_value = 0.6
	rate.max_value = 1.6
	rate.step = 0.1
	rate.value = float(Store.setting("rate", 1.0))
	rate.custom_minimum_size.x = 220
	rate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rate.tooltip_text = "Только для голоса системы"
	var rl := UI.label("", "Muted")
	var upd := func(v: float) -> void: rl.text = "×%.1f" % v
	upd.call(rate.value)
	rate.value_changed.connect(func(v: float) -> void:
		upd.call(v)
		Store.set_setting("rate", v))
	var rh := UI.hbox(10)
	rh.add_child(rate)
	rh.add_child(rl)
	body.add_child(_row("Скорость речи", rh))
	body.add_child(_check("Озвучивать английский на занятиях", "auto_speak", true))
	if not ru.is_empty():
		body.add_child(_check("При «Прослушать» читать и перевод", "listen_ru", true))
	add_button("Проверить", "", func() -> void:
		if not Speech.say("Someone's walking in the attic. Hello! This is how I sound.", "en"):
			Speech.say("Привет! Вот так я звучу.", "ru"))
	add_button("Готово", "Primary", func() -> void: close(true))


func _row(caption: String, ctl: Control) -> Control:
	var h := UI.hbox(14)
	var l := UI.label(caption, "")
	l.custom_minimum_size.x = 170
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	return h


func _voices(list: Array, key: String) -> OptionButton:
	var ob := OptionButton.new()
	var cur := Speech.voice_id(key.trim_prefix("voice_"))
	for i in list.size():
		ob.add_item(str(list[i]["name"]), i)
		if list[i]["id"] == cur:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void:
		Store.set_setting(key, str(list[i]["id"]))
		Speech.say("Hello!" if key == "voice_en" else "Привет!", key.trim_prefix("voice_")))
	return ob


func _check(text: String, key: String, def: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.set_pressed_no_signal(bool(Store.setting(key, def)))
	c.toggled.connect(func(on: bool) -> void: Store.set_setting(key, on))
	return c
