extends Node
## Снимки экранов в обеих темах: xvfb-run -a godot --path . --resolution 1180x780 res://tools/shots.tscn
## OUT=папка (по умолчанию out/shots). Словарь — временный, с примером, настоящий не трогается.

var main: Node
var out := "out/shots"


func _ready() -> void:
	if OS.get_environment("OUT") != "":
		out = OS.get_environment("OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Store.path = "user://shots/dictionary.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shots"))
	for f in DirAccess.get_files_at("user://shots"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shots".path_join(f)))
	Store.data = Store.empty_data()
	_seed()
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	for dark in [false, true]:
		AppTheme.set_dark(dark)
		var t := "dark" if dark else "light"
		main.go("home")
		await _snap("home_" + t)
		var cid := str(Store.category_by_name("Games")["id"])
		main.go("category", {"cid": cid})
		await _snap("category_" + t)
		Store.set_setting("compact", true)
		main.go("category", {"cid": cid})
		await _snap("category_compact_" + t)
		Store.set_setting("compact", false)
		main.go("home")
		await _wait(0.3)
		var hs: LineEdit = main.current.get("_search")
		hs.text = "game"
		hs.text_changed.emit("game")
		await _snap("home_search_" + t)
		hs.text = ""
		hs.text_changed.emit("")
		main.go("setup", {"cid": cid})
		await _snap("setup_" + t)
		var cards := Session.build({"cats": [cid], "limit": 0, "shuffle": false})
		main.go("study", {"cards": cards, "mode": "en_ru"})
		await _snap("study_question_" + t)
		main.current.call("_reveal")
		await _snap("study_answer_" + t)
		main.current.call("_grade", Srs.KNOW)
		await _wait(0.1)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("study_fly_" + t + ".png"))
		main.go("study", {"cards": cards, "mode": "choice"})
		await _snap("study_choice_" + t)
		var cs: Node = main.current
		cs.call("_pick", (int(cs.get("_choice_ok")) + 2) % 5)
		await _snap("study_choice_wrong_" + t)
		main.go("study", {"cards": cards, "mode": "type"})
		await _wait(0.4)
		var s: Node = main.current
		var e := Store.entry(str(cards[0]["cid"]), str(cards[0]["eid"]))
		var inp: LineEdit = s.get("_input")
		inp.text = str(e["en"]).replace("any", "ani")
		s.call("_check")
		await _snap("study_typo_" + t)
		inp = s.get("_input")
		s.call("_next_typed")
		await _wait(0.3)
		inp = s.get("_input")
		inp.text = "I wanna go"
		s.call("_check")
		await _snap("study_wrong_" + t)
		s.set("_stats", {Srs.KNOW: 5, Srs.ALMOST: 2, Srs.DONT: 1})
		s.set("_done_first", 8)
		s.set("_first_total", 8)
		(s.get("_mistakes") as Array).append({"cid": cards[1]["cid"], "eid": cards[1]["eid"], "cat": "Games"})
		s.call("_finish")
		await _snap("study_summary_" + t)
		var lk := Store.category_by_name("Lookupper / English")
		if not lk.is_empty():
			main.go("category", {"cid": lk["id"]})
			await _snap("anki_category_" + t)
			var lcards := Session.build({"cats": [lk["id"]], "limit": 0, "shuffle": false})
			main.go("study", {"cards": lcards, "mode": "en_ru"})
			await _wait(0.5)
			main.current.call("_reveal")
			await _snap("anki_study_" + t)
			main.go("study", {"cards": lcards, "mode": "type"})
			await _wait(0.4)
			main.current.call("_give_up")
			await _snap("anki_type_" + t)
		main.go("home")
		await _wait(0.3)
		main.open_modal(VoiceDialog.new())
		await _snap("voice_" + t)
		main.get("_overlay").get_child(0).call("close", null)
		await _wait(0.3)
		main.current.call("_new_category")
		await _snap("modal_" + t)
		main.get("_overlay").get_child(0).call("close", null)
		main.set("_last_clip", "")
		DisplayServer.clipboard_set("Are you sure you want to quit?")
		main.call("_check_clipboard")
		await _snap("clipboard_" + t)
		main.call("_hide_clip_bar")
		main.toast("Удалено: «Game over»", 6.0, "Вернуть", func() -> void: pass)
		await _snap("undo_" + t)
	print("SHOTS OK -> ", out)
	get_tree().quit()


func _seed() -> void:
	var g := Store.add_category("Games", false)
	var gid := str(g["id"])
	for p in [["Press any key to continue", "Нажмите любую клавишу, чтобы продолжить", ""],
			["I want to go home", "Я хочу домой", ""],
			["Your progress has been saved", "Ваш прогресс сохранён", "has been — пассивный залог"],
			["Game over", "Игра окончена", ""], ["Quest completed", "Задание выполнено", ""],
			["Watch out!", "Берегись!", "предупреждение, не «смотри наружу»"]]:
		Store.add_entry(gid, p[0], p[1], p[2])
	var es: Array = g["entries"]
	Srs.grade(es[0], Srs.KNOW); Srs.grade(es[0], Srs.KNOW); Srs.grade(es[0], Srs.KNOW)
	Srs.grade(es[1], Srs.DONT)
	Srs.grade(es[2], Srs.ALMOST)
	var ev := Store.add_category("Everyday English", false)
	for p in [["How's it going?", "Как дела?"], ["I'm on my way", "Я уже в пути"], ["No worries", "Не переживай"],
			["Could you say that again?", "Можете повторить?"]]:
		Store.add_entry(str(ev["id"]), p[0], p[1])
	Store.add_sample()
	# колода Anki: APKG=путь (иначе тестовая)
	var apkg := OS.get_environment("APKG")
	if apkg == "":
		apkg = ProjectSettings.globalize_path("res://tests/fixtures/deck_v1.apkg")
	AnkiImport.import_into_store(apkg)
	var big := Store.category_by_name("Big / Deck")
	if not big.is_empty():
		Store.delete_category(str(big["id"]))
	var m := Store.add_category("Movies", false)
	Store.add_entry(str(m["id"]), "May the odds be ever in your favor", "Пусть удача всегда будет на вашей стороне")
	Store.write_now()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _snap(fname: String) -> void:
	await _wait(0.6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(fname + ".png"))
