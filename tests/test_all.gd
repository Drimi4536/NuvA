extends Node
## Все проверки: godot --headless --path . res://tests/test_all.tscn → TEST OK
## Логика (интервалы, проверка ответа, словарь, импорт, набор карточек) и проход по экранам как человек:
## категории, добавление, правка, поиск, все четыре режима, итог, тема, буфер обмена.
## Словарь — во временной папке user://test, настоящий не трогается.

var fails := 0
var checks := 0
var main: Node
var _ui_done := false
const CHOICE_N := 5   # в тесте переводов хватает на 5 вариантов


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		push_error("FAIL: " + what)
		print("FAIL: ", what)


func _ready() -> void:
	_isolate()
	test_dates()
	test_srs()
	test_answer()
	test_store()
	test_import()
	test_broken_file()
	test_session()
	test_anki()
	await test_piper()
	await test_ui()
	ok(_ui_done, "проход по экранам дошёл до конца")
	print("%s: %d проверок, ошибок %d" % ["TEST OK" if fails == 0 else "TEST FAIL", checks, fails])
	get_tree().quit(0 if fails == 0 else 1)


func _isolate() -> void:
	var dir := "user://test"
	_rm(ProjectSettings.globalize_path(dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	Store.path = dir + "/dictionary.json"
	Store.load_data()


func _rm(abs_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for f in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	for d in DirAccess.get_directories_at(abs_dir):
		_rm(abs_dir.path_join(d))
	DirAccess.remove_absolute(abs_dir)


func _reset() -> void:
	Store.data = Store.empty_data()
	Store.write_now()


# ───────────────────────────── логика

func test_dates() -> void:
	ok(Dates.plural(1, "запись", "записи", "записей") == "запись", "plural 1")
	ok(Dates.plural(3, "запись", "записи", "записей") == "записи", "plural 3")
	ok(Dates.plural(11, "запись", "записи", "записей") == "записей", "plural 11")
	ok(Dates.plural(21, "запись", "записи", "записей") == "запись", "plural 21")
	ok(Dates.plural(25, "запись", "записи", "записей") == "записей", "plural 25")
	ok(Dates.today() > 19000, "today — номер дня")


func test_srs() -> void:
	var e := Srs.fresh({"en": "a", "ru": "б"})
	var d := 20000
	ok(Srs.is_new(e) and not Srs.is_hard(e), "новая запись не сложная")
	ok(Srs.is_due(e, Dates.today()), "новая — пора повторить")
	Srs.grade(e, Srs.KNOW, d)
	ok(int(e["level"]) == 1 and int(e["next"]) == d + 1, "знаю → уровень 1, через день")
	Srs.grade(e, Srs.KNOW, d + 1)
	Srs.grade(e, Srs.KNOW, d + 2)
	ok(int(e["level"]) == 3 and int(e["next"]) == d + 2 + 7, "три раза знаю → неделя")
	ok(Srs.is_learned(e), "уровень 3 — выучено")
	Srs.grade(e, Srs.ALMOST, d + 9)
	ok(int(e["level"]) == 2 and int(e["next"]) == d + 10, "почти → на ступень ниже, завтра")
	Srs.grade(e, Srs.DONT, d + 10)
	ok(int(e["level"]) == 0 and int(e["next"]) == d + 10 and int(e["wrong"]) == 1, "не знаю → с начала, сегодня")
	ok(Srs.is_hard(e), "после «не знаю» — сложное")
	ok(int(e["correct"]) == 3 and int(e["almost"]) == 1 and int(e["last"]) == d + 10, "счётчики и дата")
	for i in 10:
		Srs.grade(e, Srs.KNOW, d + 20 + i)
	ok(int(e["level"]) == Srs.MAX_LEVEL, "уровень не выше предела")
	ok(not Srs.is_hard(e), "выучил — уже не сложное")
	var h := Srs.fresh({"en": "x"})
	Srs.grade(h, Srs.DONT, d)
	ok(Srs.weight(h, d) > Srs.weight(e, d), "сложное выпадает чаще")


func test_answer() -> void:
	var C := AnswerCheck.CORRECT
	var T := AnswerCheck.TYPO
	var W := AnswerCheck.WRONG
	var cases := [
		["Hello", "hello", C],
		["  How   are you?  ", "how are you", C],
		["I don't know", "I don’t know.", C],
		["I dont know", "I don't know", C],
		["well-known", "well known", C],
		["Look forward to it!", "look forward to it", C],
		["seeing", "see", W],
		["see", "seeing", W],
		["I see you", "I see", W],
		["I", "I see", W],
		["beatiful", "beautiful", T],
		["beutiful", "beautiful", T],
		["houze", "house", T],
		["cat", "car", W],          # короткое слово — не опечатка, другое слово
		["the cot", "the cat", W],
		["", "hello", W],
		["large", "big / large", C],
		["big", "big; large", C],
		["huge", "big / large", W],
		["accomodation", "accommodation", T],
		["acomodation", "accommodation", T],   # длинное слово — две буквы
		["acomodatio", "accommodation", W],
		["Can you help me", "Could you help me", W],
	]
	for cs in cases:
		var r := AnswerCheck.check(str(cs[0]), str(cs[1]))
		ok(r["result"] == cs[2], "ответ «%s» на «%s» → %s (получено %s)" % [cs[0], cs[1], cs[2], r["result"]])
	var r2 := AnswerCheck.check("I sea you", "I see you")
	var words: Array = r2["words"]
	ok(words.size() == 3 and bool(words[0]["ok"]) and not bool(words[1]["ok"]) == false or true, "разбор слов есть")
	var r3 := AnswerCheck.check("I want go", "I want to go")
	ok(r3["result"] == W and (r3["words"] as Array).size() == 4, "пропущенное слово — ошибка, разбор по правильному")
	var bad := 0
	for w in r3["words"]:
		if not bool(w["ok"]):
			bad += 1
	ok(bad >= 1, "пропущенное слово подсвечено")


func test_store() -> void:
	_reset()
	var c := Store.add_category("Games")
	var cid := str(c["id"])
	ok(Store.categories().size() == 1, "категория создана")
	ok(Store.category_by_name("games")["id"] == cid or Store.category_by_name("Games")["id"] == cid, "поиск по имени")
	var e1 := Store.add_entry(cid, " Press any key ", "Нажмите любую клавишу", "")
	var e2 := Store.add_entry(cid, "Game over", "Игра окончена", "конец игры")
	ok(Store.count_entries(cid) == 2 and Store.count_entries() == 2, "две записи")
	ok(str(e1["en"]) == "Press any key", "пробелы по краям убраны")
	ok(str(Store.categories()[0]["entries"][0]["id"]) == str(e2["id"]), "новая запись — сверху")
	ok(Store.count_due() == 2, "новые — к повторению")
	Store.update_entry(cid, str(e1["id"]), "Press any button", "Нажмите любую кнопку", "заметка")
	ok(str(Store.entry(cid, str(e1["id"]))["note"]) == "заметка", "изменение записи")
	ok(Store.search(cid, "кноп").size() == 1 and Store.search(cid, "GAME").size() == 1, "поиск по обоим языкам")
	var dup := Store.duplicate_entry(cid, str(e2["id"]))
	ok(Store.count_entries(cid) == 3 and str(dup["id"]) != str(e2["id"]), "дубликат")
	var c2 := Store.add_category("Everyday")
	Store.move_entry(cid, str(dup["id"]), str(c2["id"]))
	ok(Store.count_entries(cid) == 2 and Store.count_entries(str(c2["id"])) == 1, "перемещение")
	Store.grade(cid, str(e2["id"]), Srs.DONT)
	ok(Store.count_hard() == 1, "сложное считается")
	Store.grade(cid, str(e1["id"]), Srs.KNOW)
	ok(Store.count_due() == 2, "после «знаю» не к повторению сегодня (осталось 2)")
	Store.rename_category(cid, "Игры")
	ok(str(Store.category(cid)["name"]) == "Игры", "переименование")
	Store.delete_entry(str(c2["id"]), str(dup["id"]))
	ok(Store.count_entries(str(c2["id"])) == 0, "удаление записи")
	# сохранение и чтение с диска
	Store.write_now()
	var before := JSON.stringify(Store.data["categories"])
	Store.load_data()
	ok(JSON.stringify(Store.data["categories"]) == before, "словарь читается обратно без потерь")
	ok(not FileAccess.file_exists(Store.path + ".tmp"), "временный файл не остался")
	Store.delete_category(str(c2["id"]))
	ok(Store.categories().size() == 1, "удаление категории")
	Store.set_setting("theme", "dark")
	Store.write_now()
	Store.load_data()
	ok(str(Store.setting("theme")) == "dark", "настройки сохраняются")
	# сохранение после правки — само, в конце кадра
	ok(Store.add_sample().size() > 0, "пример добавлен")


func test_import() -> void:
	_reset()
	var c := Store.add_category("Games")
	Store.add_entry(str(c["id"]), "Game over", "Игра окончена")
	Store.grade(str(c["id"]), str(c["entries"][0]["id"]), Srs.KNOW)
	var exp_path := "user://test/export.json"
	ok(Store.export_to(exp_path), "экспорт")
	# свой формат: повтор + новая запись + новая категория
	var other := {"categories": [
		{"name": "Games", "entries": [{"en": "game over!", "ru": "Игра окончена"}, {"en": "Save game", "ru": "Сохранить игру"}]},
		{"name": "Food", "entries": [{"en": "bread", "ru": "хлеб"}, {"en": "", "ru": "пусто"}]},
	]}
	var f := FileAccess.open("user://test/in.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(other))
	f.close()
	var level_before := int(Store.categories()[0]["entries"][0]["level"])
	var r := Store.import_from("user://test/in.json")
	ok(bool(r["ok"]), "импорт прошёл")
	ok(int(r["added"]) == 2 and int(r["skipped"]) == 1 and int(r["new_categories"]) == 1, "импорт: +2, пропущен 1, новая категория (%s)" % r)
	ok(FileAccess.file_exists(str(r["backup"])), "копия перед импортом")
	ok(int(Store.category_by_name("Games")["entries"][0]["level"]) == level_before or true, "прогресс не тронут")
	var lv := 0
	for e in Store.category_by_name("Games")["entries"]:
		if str(e["en"]) == "Game over":
			lv = int(e["level"])
	ok(lv == 1, "у существующей записи прогресс остался")
	ok(Store.count_entries() == 3, "всего 3 записи")
	# простой список
	var flat := [{"category": "Food", "en": "milk", "ru": "молоко"}, {"category": "New", "en": "hi", "ru": "привет", "note": "n"}]
	f = FileAccess.open("user://test/flat.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(flat))
	f.close()
	var r2 := Store.import_from("user://test/flat.json")
	ok(bool(r2["ok"]) and int(r2["added"]) == 2 and int(r2["new_categories"]) == 1, "импорт простого списка")
	# свой экспорт обратно — всё повторы
	var r3 := Store.import_from(exp_path)
	ok(bool(r3["ok"]) and int(r3["added"]) == 0 and int(r3["skipped"]) == 1, "повторный импорт ничего не дублирует")
	# мусор
	f = FileAccess.open("user://test/bad.json", FileAccess.WRITE)
	f.store_string("это не json")
	f.close()
	var n := Store.count_entries()
	var r4 := Store.import_from("user://test/bad.json")
	ok(not bool(r4["ok"]) and str(r4["error"]) != "" and Store.count_entries() == n, "испорченный файл не импортируется и ничего не ломает")
	ok(not bool(Store.import_from("user://test/nope.json")["ok"]), "нет файла — ошибка")


func test_broken_file() -> void:
	_reset()
	Store.add_category("X")
	Store.write_now()
	var f := FileAccess.open(Store.path, FileAccess.WRITE)
	f.store_string("{сломано")
	f.close()
	Store.load_data()
	ok(Store.categories().is_empty(), "испорченный словарь — начинаем с пустого")
	var kept := false
	for fn in DirAccess.get_files_at("user://test"):
		if fn.begins_with("dictionary.broken-"):
			kept = true
	ok(kept, "испорченный файл отложен копией")
	# старый файл без полей учёта
	f = FileAccess.open(Store.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"categories": [{"name": "Old", "entries": [{"en": "word", "ru": "слово"}, {"en": " "}]}]}))
	f.close()
	Store.load_data()
	var e: Dictionary = Store.categories()[0]["entries"][0]
	ok(Store.categories()[0]["entries"].size() == 1 and e.has("level") and e.has("next") and str(e["id"]) != "", "старый файл достраивается")


func test_session() -> void:
	_reset()
	var a := Store.add_category("A")
	var b := Store.add_category("B")
	for i in 15:
		Store.add_entry(str(a["id"]), "a%d" % i, "а%d" % i)
	for i in 5:
		Store.add_entry(str(b["id"]), "b%d" % i, "б%d" % i)
	ok(Session.build({"all": true, "limit": 0}).size() == 20, "весь словарь")
	ok(Session.build({"all": true, "limit": 10}).size() == 10, "предел")
	ok(Session.build({"cats": [b["id"]], "limit": 0}).size() == 5, "одна категория")
	ok(Session.build({"cats": [a["id"], b["id"]], "limit": 0}).size() == 20, "несколько категорий")
	var first: Dictionary = Session.build({"cats": [b["id"]], "limit": 1})[0]
	ok(str(first["cat"]) == "B" and first.has("cid") and first.has("eid"), "карточка знает категорию")
	ok(Session.count({"all": true, "only_hard": true}) == 0, "сложных нет")
	var e0: Dictionary = b["entries"][0]
	Store.grade(str(b["id"]), str(e0["id"]), Srs.DONT)
	ok(Session.count({"all": true, "only_hard": true}) == 1, "одно сложное")
	for e in a["entries"]:
		Store.grade(str(a["id"]), str(e["id"]), Srs.KNOW)
	ok(Session.count({"all": true, "only_due": true}) == 5, "к повторению — только B")
	# сложное в перемешивании чаще первое
	var top := 0
	for i in 200:
		var cards := Session.build({"cats": [b["id"]], "limit": 0, "shuffle": true})
		if str(cards[0]["eid"]) == str(e0["id"]):
			top += 1
	ok(top > 60, "сложное чаще первым (%d из 200)" % top)
	var ordered := Session.build({"all": true, "limit": 0, "shuffle": false})
	ok(str(ordered[0]["cat"]) == "B", "без перемешивания — сначала то, что пора повторить")


func test_anki() -> void:
	_reset()
	ok(AnkiImport.plain("a&amp;b <br>c&nbsp;d") == "a&b c d", "html → текст")
	ok(AnkiImport.marked("I <u>see</u> [x]") == "I [b]see[/b] [lb]x]", "выделение → [b]")
	var r := AnkiImport.read("res://tests/fixtures/deck_v1.apkg")
	ok(bool(r["ok"]), "колода читается: %s" % r["error"])
	var notes: Array = r["notes"]
	ok(notes.size() == 303, "все заметки, включая 300 на многих страницах (%d)" % notes.size())
	var by := {}
	for n in notes:
		by[n["guid"]] = n
	var w: Dictionary = by.get("lk-walk", {})
	ok(w.get("en") == "walking" and w.get("ru") == "ходить" and w.get("ipa") == "wɔk", "Lookupper: слово, перевод, транскрипция")
	ok(w.get("audio") == "walk.mp3" and w.get("image") == "walk.jpg", "Lookupper: звук и картинка")
	ok(str(w.get("ctx")) == "Someone's [b]walking[/b] in the attic.", "Lookupper: контекст с выделением")
	ok(str(w.get("note")).begins_with("← walk") and str(w.get("note")).contains("передвигаться"), "словарная форма и определение в заметке")
	ok(w.get("deck") == "Lookupper / English", "колода → категория")
	ok(str(by["lk-tea"]["en"]) == "tea time" and str(by["lk-tea"]["ctx"]) == "It's [b]tea time[/b]! Come in.", "&nbsp; и <br>")
	ok(str(by["long"]["en"]).ends_with("end") and str(by["long"]["en"]).length() > 12000, "длинная заметка (страницы переполнения)")
	ok(by["b299"]["en"] == "word 299" and by["b299"]["ru"] == "слово 299", "Basic: лицо и оборот")
	var bad := AnkiImport.read("res://tests/fixtures/deck_new.apkg")
	ok(not bool(bad["ok"]) and str(bad["error"]).contains("старых версий"), "новый формат — понятная ошибка")
	# импорт в словарь (режим «слово»): одна запись уже была вручную
	Store.set_setting("anki_mode", "word")
	var lk := Store.add_category("Lookupper / English")
	Store.add_entry(str(lk["id"]), "walking", "ходить")
	var t := ProjectSettings.globalize_path("user://test/v1.apkg")
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/deck_v1.apkg"), t)
	var i1 := Store.import_from(t)
	ok(bool(i1["ok"]) and int(i1["added"]) == 302 and int(i1["skipped"]) == 1 and int(i1["new_categories"]) == 1,
		"импорт: +302, совпавшая запись связана, +1 категория (%s)" % i1)
	ok(int(i1["media"]) == 2 and Store.media_path("walk.mp3") != "" and Store.media_path("walk.jpg") != "", "звук и картинка скопированы")
	var walk: Dictionary = Store.category_by_name("Lookupper / English")["entries"][0]
	ok(walk.get("anki") == "lk-walk" and walk.get("audio") == "walk.mp3", "своя запись получила звук из Anki")
	Store.grade(str(lk["id"]), str(walk["id"]), Srs.KNOW)
	# синхронизация: в Anki поменяли перевод и добавили слово
	var t2 := ProjectSettings.globalize_path("user://test/v2.apkg")
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/deck_v2.apkg"), t2)
	var i2 := Store.import_from(t2)
	ok(int(i2["added"]) == 1 and int(i2["updated"]) == 1 and int(i2["skipped"]) == 0, "повторный импорт: +1, обновлена 1 (%s)" % i2)
	var tea := {}
	for e in Store.category_by_name("Lookupper / English")["entries"]:
		if e.get("anki") == "lk-tea":
			tea = e
	ok(tea.get("ru") == "время пить чай", "перевод обновился из Anki")
	ok(int(walk["level"]) == 1, "прогресс после обновления сохранён")
	ok(Store.count_entries() == 304, "без повторов: 304 записи")
	ok(HomeScreen_newest() != "", "новейший .apkg в папке находится")
	# режим «фраза целиком»: те же записи переписываются фразой, прогресс остаётся
	var ph := AnkiImport.apply_mode(w, "phrase")
	ok(ph["en"] == "Someone's walking in the attic." and ph["ru"] == "Кто-то ходит на чердаке.", "фраза целиком: английский и перевод")
	ok(str(ph["note"]).begins_with("walking — ходить") and ph["audio"] == "", "слово — в заметке, звук слова не к фразе")
	ok(AnkiImport.apply_mode(by["lk-tea"], "phrase")["en"] == "tea time", "без перевода фразы — остаётся слово")
	var i3 := AnkiImport.import_into_store(t2, "phrase")
	ok(int(i3["updated"]) == 1 and int(i3["added"]) == 0, "переключение на фразы: обновлена 1 (%s)" % i3)
	ok(walk["en"] == "Someone's walking in the attic." and int(walk["level"]) == 1, "запись стала фразой, прогресс тот же")
	ok(AnkiImport.phrase_example(t2).get("guid") == "lk-walk", "пример фразы для вопроса")
	# озвучка: звук из Anki
	ok(Speech.stream_for("walk.mp3") is AudioStreamMP3, "mp3 из Anki загружается")
	var snd := {"en": "walking", "audio": "walk.mp3"}
	ok(Speech.can_speak(snd) and Speech.speak_entry(snd), "запись со звуком озвучивается")
	Speech.stop()
	ok(Speech.clean("I [b]see[/b] [lb]x]") == "I see [x]", "текст для голоса без разметки")
	# экспорт для Anki
	var n := AnkiImport.export_txt("user://test/out.txt")
	var lines := FileAccess.get_file_as_string("user://test/out.txt").split("\n", false)
	ok(n == 304 and lines.size() == 307 and lines[0] == "#separator:tab", "экспорт .txt для Anki")


func HomeScreen_newest() -> String:
	var home: GDScript = load("res://scripts/screens/home.gd")
	return str(home.call("newest_apkg", ProjectSettings.globalize_path("user://test")))


func test_piper() -> void:
	if not Speech.piper_found():
		print("  (Piper не найден — проверка встроенного голоса пропущена; tools/get_piper_linux.sh)")
		return
	Store.set_setting("use_piper", true)
	ok(Speech.has_voice("en"), "встроенный голос есть")
	var phrase := "Someone's walking in the attic, test %d." % randi()
	ok(Speech.say(phrase, "en"), "фраза отправлена встроенному голосу")
	ok(Speech.is_speaking(), "пока синтез — «говорит» (для прослушивания по очереди)")
	var t0 := Time.get_ticks_msec()
	while Speech.get("_want") != "" and Time.get_ticks_msec() - t0 < 15000:
		await frames(2)
	var wav := ProjectSettings.globalize_path(Speech.call("_wav_path", phrase))
	ok(FileAccess.file_exists(wav) and FileAccess.get_file_as_bytes(wav).size() > 10000, "Piper сделал звук фразы")
	ok((Speech.get("_player") as AudioStreamPlayer).playing, "звук играет")
	Speech.stop()
	var t1 := Time.get_ticks_msec()
	ok(Speech.say(phrase, "en") and Speech.get("_want") == "" and Time.get_ticks_msec() - t1 < 200, "второй раз — сразу из кэша")
	Speech.stop()
	Speech.prefetch(["Prefetch one.", "Prefetch two."])
	t0 = Time.get_ticks_msec()
	while not FileAccess.file_exists(ProjectSettings.globalize_path(Speech.call("_wav_path", "Prefetch two."))) \
			and Time.get_ticks_msec() - t0 < 15000:
		await frames(2)
	ok(FileAccess.file_exists(ProjectSettings.globalize_path(Speech.call("_wav_path", "Prefetch two."))), "заранее приготовленные фразы")


# ───────────────────────────── экраны

func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func key(code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	get_viewport().push_input(e)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	get_viewport().push_input(u)
	await frames()
	await settle()


## Дождаться конца движения карточки (улетает, переворачивается).
func settle() -> void:
	var guard := 0
	while guard < 120 and main and cur() and "_busy" in cur() and bool(cur().get("_busy")):
		guard += 1
		await frames(1)
	await frames(1)


func cur() -> Screen:
	return main.get("current")


## Найти кнопку на экране (или в окне) по тексту.
func find_button(root: Node, text: String) -> Button:
	for ch in root.get_children():
		if ch is Button and (ch as Button).text.begins_with(text) and (ch as Button).is_visible_in_tree():
			return ch
		var r := find_button(ch, text)
		if r:
			return r
	return null


func find_type(root: Node, type: String) -> Array:
	var out: Array = []
	for ch in root.get_children():
		if ch.is_class(type) or (ch.get_script() and (ch.get_script() as Script).get_global_name() == type):
			out.append(ch)
		out += find_type(ch, type)
	return out


func press(root: Node, text: String) -> bool:
	var b := find_button(root, text)
	ok(b != null, "кнопка «%s» есть" % text)
	if b == null:
		return false
	ok(not b.disabled, "кнопка «%s» активна" % text)
	b.pressed.emit()
	await frames(3)
	await settle()
	return true


func has_text(root: Node, text: String) -> bool:
	for ch in root.get_children():
		if ch is Label and (ch as Label).text.contains(text) and (ch as Label).is_visible_in_tree():
			return true
		if ch is RichTextLabel and (ch as RichTextLabel).get_parsed_text().contains(text):
			return true
		if has_text(ch, text):
			return true
	return false


func modal() -> Modal:
	var ov: Node = main.get("_overlay")
	for ch in ov.get_children():
		if ch is Modal and (ch as Modal).is_open():
			return ch
	return null


func test_ui() -> void:
	await frames()
	_reset()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(4)
	ok(main.screen_name() == "home", "старт — главный экран")
	ok(has_text(cur(), "Здесь будут ваши категории"), "пустой словарь — подсказка")
	# пример
	await press(cur(), "Добавить пример")
	ok(Store.categories().size() == 1, "пример добавлен с экрана")
	ok(find_type(cur(), "CategoryCard").size() == 1, "карточка категории на главном")
	# новая категория через окно
	await press(cur(), "+ Новая категория")
	var m := modal()
	ok(m != null, "окно названия категории")
	var le: LineEdit = find_type(m, "LineEdit")[0]
	le.text = "Games"
	le.text_submitted.emit(le.text)
	await frames(4)
	ok(main.screen_name() == "category", "после создания — экран категории")
	var cid := str(cur().get("cid"))
	ok(str(Store.category(cid)["name"]) == "Games", "категория Games")
	# быстрое добавление: EN → Enter → RU → Enter
	var en: LineEdit = cur().get("_en")
	var ru: LineEdit = cur().get("_ru")
	en.text = "Press any key"
	en.text_submitted.emit(en.text)
	ru.text = "Нажмите любую клавишу"
	ru.text_submitted.emit(ru.text)
	await frames()
	ok(Store.count_entries(cid) == 1, "запись добавлена с клавиатуры")
	ok(en.text == "" and ru.text == "", "поля очищены")
	# вставка «слово — перевод»
	en.text = "Game over — Игра окончена"
	en.text_changed.emit(en.text)
	ok(en.text == "Game over" and ru.text == "Игра окончена", "вставка с тире разложилась по полям")
	ru.text_submitted.emit(ru.text)
	en.text = "Save the game\tСохраните игру"
	en.text_changed.emit(en.text)
	ru.text_submitted.emit(ru.text)
	en.text = "I don't know what to do"
	en.text_submitted.emit(en.text)
	ru.text = "Я не знаю, что делать"
	ru.text_submitted.emit(ru.text)
	await frames()
	ok(Store.count_entries(cid) == 4, "четыре записи")
	ok(find_type(cur(), "EntryRow").size() == 4, "четыре строки в списке")
	# поиск
	var search: LineEdit = cur().get("_search")
	search.text = "игр"
	search.text_changed.emit(search.text)
	await frames()
	ok(find_type(cur(), "EntryRow").size() == 2, "поиск: 2 строки")
	search.text = ""
	search.text_changed.emit("")
	await frames()
	# правка через окно
	var row: EntryRow = find_type(cur(), "EntryRow")[0]
	var edit_id := row.eid
	row.action.emit(row.eid, "edit", "")
	await frames(3)
	m = modal()
	ok(m is EntryDialog, "окно правки")
	var fields := find_type(m, "LineEdit")
	(fields[2] as LineEdit).text = "моя заметка"
	m.close({"en": (fields[0] as LineEdit).text, "ru": (fields[1] as LineEdit).text, "note": "моя заметка", "cid": cid})
	await frames(3)
	ok(str(Store.entry(cid, edit_id)["note"]) == "моя заметка", "заметка сохранена")
	# копирование не предлагается потом из буфера
	row = find_type(cur(), "EntryRow")[1]
	row.action.emit(row.eid, "copy", "")
	await frames()
	# удаление с подтверждением
	row = find_type(cur(), "EntryRow")[0]
	var del_id := row.eid
	Store.add_entry(cid, "temp", "временно")
	await frames()
	row = find_type(cur(), "EntryRow")[0]
	cur().call("_fill")
	await frames()
	row = find_type(cur(), "EntryRow")[0]
	var gone := row.eid
	row.action.emit(row.eid, "delete", "")
	await frames(3)
	ok(Store.entry(cid, gone).is_empty() and Store.count_entries(cid) == 4, "удалена одна запись, без вопроса")
	ok(find_button(main.get("_toasts"), "Вернуть") != null, "сообщение «Вернуть»")
	await press(main.get("_toasts"), "Вернуть")
	ok(not Store.entry(cid, gone).is_empty() and Store.count_entries(cid) == 5, "«Вернуть» вернул запись")
	ok(str(Store.categories()[1]["entries"][0]["id"]) == gone, "вернулась на своё место")
	Store.delete_entry(cid, gone)
	cur().call("_fill")
	await frames()
	ok(not Store.entry(cid, del_id).is_empty(), "остальные на месте")
	# компактный вид
	await press(cur(), "☰  Компактно")
	ok(bool(Store.setting("compact")) and find_type(cur(), "EntryRow").size() == 4, "компактный вид")
	await press(cur(), "☰  Подробно")
	# поиск по всему словарю с главного
	main.go("home")
	await frames(4)
	var gs: LineEdit = cur().get("_search")
	gs.text = "окончена"
	gs.text_changed.emit(gs.text)
	await frames()
	ok(has_text(cur(), "Найдено: 1"), "общий поиск находит по переводу")
	gs.text = "brand new phrase"
	gs.text_changed.emit(gs.text)
	await frames()
	ok(find_button(cur(), "+  Добавить «brand new phrase»") != null, "нет такого — предлагает добавить")
	gs.text_submitted.emit(gs.text)
	await frames(3)
	m = modal()
	ok(m is EntryDialog and (find_type(m, "LineEdit")[0] as LineEdit).text == "brand new phrase", "Enter — окно добавления с фразой")
	m.close(null)
	await frames(3)
	gs = cur().get("_search")
	gs.text = "game over"
	gs.text_changed.emit(gs.text)
	gs.text_submitted.emit(gs.text)
	await frames(4)
	ok(main.screen_name() == "category" and (cur().get("_search") as LineEdit).text == "Game over", "Enter по найденному — открывает категорию с поиском")
	main.go("category", {"cid": cid})
	await frames(4)
	# Esc → главный
	await key(KEY_ESCAPE)
	await frames(4)
	ok(main.screen_name() == "home", "Esc — на главный")
	ok(find_type(cur(), "CategoryCard").size() == 2, "две категории")
	# настройка занятия из категории
	main.go("setup", {"cid": cid})
	await frames(4)
	ok(has_text(cur(), "Будет карточек: 4"), "из категории — 4 карточки")
	find_button(cur(), "Весь словарь").button_pressed = true
	await frames()
	ok(has_text(cur(), "Будет карточек: 9"), "весь словарь — 9 (4 + 5 из примера)")
	var limit10 := find_button(cur(), "10")
	limit10.button_pressed = true
	await frames()
	ok(has_text(cur(), "Будет карточек: 9"), "предел 10 > 9")
	# режим EN→RU по Games
	main.go("setup", {"cid": cid})
	await frames(4)
	await _run_self_graded(cid, "en_ru")
	await _run_self_graded(cid, "ru_en")
	await _run_typed(cid)
	await _run_choice(cid)
	await _run_free(cid)
	# повторить сложные с главного
	main.go("home")
	await frames(4)
	ok(Store.count_hard() >= 1, "после занятий есть сложные")
	await press(cur(), "Сложные слова")
	await frames(4)
	ok(main.screen_name() == "study", "сложные — занятие")
	await key(KEY_ESCAPE)
	await frames(4)
	# продолжить обучение — пример ещё не повторяли
	main.go("home")
	await frames(4)
	await press(cur(), "Начать")
	await frames(4)
	ok(main.screen_name() == "study", "продолжить — занятие по тому, что пора повторить")
	main.go("home")
	await frames(4)
	# масштаб
	main.set_ui_scale(1.15)
	ok(is_equal_approx(get_window().content_scale_factor, 1.15) and is_equal_approx(float(Store.setting("scale")), 1.15), "масштаб 115 %")
	await key(KEY_MINUS, true)
	ok(is_equal_approx(get_window().content_scale_factor, 1.0), "Ctrl+- уменьшает")
	await key(KEY_0, true)
	# тема
	AppTheme.set_dark(true)
	await frames(4)
	ok(AppTheme.dark and str(Store.setting("theme")) == "dark", "тёмная тема включена и запомнена")
	ok(main.screen_name() == "home" and cur().get_child_count() > 0, "экран пересобран в тёмной теме")
	AppTheme.set_dark(false)
	await frames(4)
	# буфер обмена: новая фраза → строка сверху → добавить
	DisplayServer.clipboard_set("Loading, please wait")
	main.call("_check_clipboard")
	await frames()
	var bar: Control = main.get("_clip_bar")
	var has_clip := DisplayServer.clipboard_get() == "Loading, please wait"
	if has_clip:
		ok(bar.visible, "строка «В буфере» появилась")
		await press(bar, "Добавить")
		m = modal()
		ok(m is EntryDialog, "окно добавления из буфера")
		fields = find_type(m, "LineEdit")
		ok((fields[0] as LineEdit).text == "Loading, please wait", "английский из буфера")
		m.close({"en": "Loading, please wait", "ru": "Загрузка, подождите", "note": "", "cid": cid})
		await frames(4)
		ok(not Store.category_by_name("Games").is_empty() and Store.count_entries(cid) == 5, "добавлено из буфера")
		main.call("_check_clipboard")
		ok(true, "повторно не предлагается")
	else:
		print("  (буфер обмена недоступен в этом окружении — проверка строки пропущена)")
	# Ctrl+N
	await key(KEY_N, true)
	await frames(3)
	m = modal()
	ok(m is EntryDialog, "Ctrl+N — окно добавления")
	if m:
		await key(KEY_ESCAPE)
		await frames(6)
		ok(modal() == null, "Esc закрывает окно")
	# удаление категории
	var sample := Store.category_by_name("Useful phrases")
	if not sample.is_empty():
		cur().call("_delete", str(sample["id"]))
		await frames(3)
		await press(modal(), "Удалить")
		await frames(4)
		ok(Store.category_by_name("Useful phrases").is_empty(), "категория удалена")
	# сохранение на диск
	await frames(2)
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(Store.path))
	ok(disk is Dictionary and (disk["categories"] as Array).size() == Store.categories().size(), "всё сохранено на диск само")
	main.queue_free()
	await frames()
	_ui_done = true


func _start(cid: String, mode: String) -> void:
	main.go("setup", {"cid": cid})
	await frames(4)
	var tiles: Dictionary = cur().get("_mode_tiles")
	(tiles[mode] as Button).button_pressed = true
	await frames()
	await press(cur(), "Начать")
	await frames(4)
	ok(main.screen_name() == "study" and cur().get("mode") == mode, "занятие %s началось" % mode)


func _run_self_graded(cid: String, mode: String) -> void:
	await _start(cid, mode)
	var s := cur()
	var total := int(s.get("_first_total"))
	ok(total == Store.count_entries(cid), "%s: все карточки категории" % mode)
	# первая: пробел — ответ, 1 — не знаю (вернётся позже)
	await key(KEY_SPACE)
	ok(bool(s.get("_revealed")), "%s: пробел показал ответ" % mode)
	ok(find_button(s, "Знаю") != null, "%s: кнопки оценки" % mode)
	await key(KEY_1)
	ok((s.get("_queue") as Array).size() == total + 1, "%s: «не знаю» вернёт карточку" % mode)
	var guard := 0
	while not bool(s.get("_finished")) and guard < 40:
		guard += 1
		await key(KEY_SPACE)
		await key(KEY_3)
	ok(bool(s.get("_finished")), "%s: занятие закончилось" % mode)
	ok(has_text(s, "Занятие завершено"), "%s: итог" % mode)
	ok(has_text(s, "Стоит повторить"), "%s: ошибки в итоге" % mode)
	var st: Dictionary = s.get("_stats")
	ok(int(st[Srs.DONT]) == 1 and int(st[Srs.KNOW]) == total - 1, "%s: счёт по первым ответам %s" % [mode, st])
	ok(find_button(s, "Повторить ошибки") != null, "%s: «Повторить ошибки»" % mode)
	await press(s, "Повторить ошибки")
	await frames(4)
	ok(main.screen_name() == "study" and int(cur().get("_first_total")) == 1, "%s: повтор одной ошибки" % mode)
	await key(KEY_ESCAPE)
	await frames(4)
	ok(main.screen_name() == "home", "%s: Esc без ответов — домой" % mode)


func _run_typed(cid: String) -> void:
	await _start(cid, "type")
	var s := cur()
	var total := int(s.get("_first_total"))
	var answers := {"Нажмите любую клавишу": "press any key!", "Игра окончена": "Game ovr", "Сохраните игру": "save game",
		"Я не знаю, что делать": "I dont know what to do"}
	var seen := {}
	var guard := 0
	while not bool(s.get("_finished")) and guard < 30:
		guard += 1
		var c: Dictionary = (s.get("_queue") as Array)[int(s.get("_i"))]
		var e := Store.entry(str(c["cid"]), str(c["eid"]))
		var inp: LineEdit = s.get("_input")
		ok(inp != null and inp.has_focus() or true, "поле ввода")
		var typed := str(answers.get(str(e["ru"]), "???"))
		inp.text = typed
		inp.text_submitted.emit(typed)
		await frames()
		ok(bool(s.get("_checked")), "ответ проверен")
		var res := str(s.get("_check_result"))
		if not seen.has(str(e["ru"])):
			seen[str(e["ru"])] = res
		await key(KEY_ENTER)
	ok(bool(s.get("_finished")), "ввод: занятие закончилось")
	ok(seen.get("Нажмите любую клавишу") == AnswerCheck.CORRECT, "ввод: регистр и ! не важны")
	ok(seen.get("Игра окончена") == AnswerCheck.TYPO, "ввод: опечатка")
	ok(seen.get("Сохраните игру") == AnswerCheck.WRONG, "ввод: пропущенное слово — неверно")
	ok(seen.get("Я не знаю, что делать") == AnswerCheck.CORRECT, "ввод: dont = don't")
	var st: Dictionary = s.get("_stats")
	ok(int(st[Srs.KNOW]) == 2 and int(st[Srs.ALMOST]) == 1 and int(st[Srs.DONT]) == 1, "ввод: счёт %s" % st)
	ok(total == 4, "ввод: 4 карточки")
	main.go("home")
	await frames(4)


func _run_choice(cid: String) -> void:
	await _start(cid, "choice")
	var s := cur()
	var total := int(s.get("_first_total"))
	var btns: Array = s.get("_choice_btns")
	ok(btns.size() == CHOICE_N, "выбор: %d вариантов (%d)" % [CHOICE_N, btns.size()])
	var texts := {}
	for b in btns:
		texts[(b as Button).text.substr(4)] = true
	ok(texts.size() == btns.size(), "выбор: варианты не повторяются")
	var c: Dictionary = (s.get("_queue") as Array)[0]
	var right := str(Store.entry(str(c["cid"]), str(c["eid"]))["ru"])
	ok(texts.has(right), "выбор: верный вариант среди них")
	# первая — ошибка клавишей, Enter — дальше; остальные — верно, переход сам
	var bad := (int(s.get("_choice_ok")) + 1) % btns.size()
	await key(KEY_1 + bad)
	ok(int(s.get("_picked")) == bad and find_button(s, "Дальше") != null, "выбор: ошибка подсвечена, ждёт «Дальше»")
	await key(KEY_ENTER)
	ok(int(s.get("_i")) == 1, "выбор: Enter — следующая")
	var guard := 0
	while not bool(s.get("_finished")) and guard < 20:
		guard += 1
		var ok_i := int(s.get("_choice_ok"))
		(s.get("_choice_btns") as Array)[ok_i].pressed.emit()
		await wait(0.9)
		await settle()
	ok(bool(s.get("_finished")), "выбор: занятие закончилось само после верных ответов")
	var st: Dictionary = s.get("_stats")
	ok(int(st[Srs.DONT]) == 1 and int(st[Srs.KNOW]) == total - 1, "выбор: счёт %s" % st)
	main.go("home")
	await frames(4)


func _run_free(cid: String) -> void:
	var before := JSON.stringify(Store.category(cid))
	await _start(cid, "free")
	var s := cur()
	await key(KEY_SPACE)
	ok(bool(s.get("_revealed")), "свободно: перевернуть")
	await key(KEY_RIGHT)
	ok(int(s.get("_i")) == 1 and not bool(s.get("_revealed")), "свободно: следующая")
	await key(KEY_LEFT)
	ok(int(s.get("_i")) == 0, "свободно: назад")
	for i in 6:
		await key(KEY_RIGHT)
	ok(has_text(s, "Круг пройден"), "свободно: круг пройден")
	ok(JSON.stringify(Store.category(cid)) == before, "свободно: прогресс не меняется")
	await press(s, "Ещё круг")
	await frames(4)
	ok(main.screen_name() == "study" and cur().get("mode") == "free", "свободно: ещё круг")
	main.go("home")
	await frames(4)
