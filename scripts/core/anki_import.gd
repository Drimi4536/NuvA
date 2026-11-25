class_name AnkiImport
extends RefCounted
## Колоды Anki (.apkg, .colpkg) → словарь. Повторный импорт той же колоды — синхронизация:
## новые карточки добавляются, изменённые в Anki обновляются (по guid заметки), прогресс в словаре не трогается.
##
## Поля берутся по названиям (Lookupper, Basic, «Front/Back», свои типы): английский, перевод, заметка, контекст,
## перевод контекста, транскрипция, звук [sound:…], картинка <img>. Не нашлось по названию — первое поле —
## английский, второе — перевод. Звук и картинки копируются в папку media рядом со словарём.
## Новый формат Anki (только collection.anki21b, сжатие zstd) не читается: в Anki при экспорте нужна галочка
## «Support older Anki versions» / «Поддержка старых версий».

const EN := ["word", "front", "english", "en", "expression", "term", "vocabulary", "phrase", "question", "лицо", "слово"]
const RU := ["wordtranslation", "back", "russian", "ru", "translation", "meaning", "answer", "перевод", "оборот", "значение"]
const NOTE := ["definition", "notes", "note", "comment", "extra", "explanation", "заметка", "пояснение"]
const CTX := ["context", "example", "sentence", "контекст", "пример"]
const CTX_RU := ["contexttranslation", "exampletranslation", "sentencetranslation", "переводконтекста", "переводпримера"]
const IPA := ["ipa", "pronunciation", "transcription", "транскрипция"]
const AUDIO := ["wordsound", "sound", "audio", "звук"]
const IMAGE := ["image", "picture", "img", "картинка"]
const DICT := ["dictionaryform", "lemma"]
const FIELDS := ["en", "ru", "note", "ctx", "ctx_ru", "ipa", "audio", "image"]


## Отпечаток заметки: изменилась ли она в Anki с прошлого импорта.
static func row_hash(row: Dictionary) -> String:
	var parts: Array = []
	for f in FIELDS:
		parts.append(str(row.get(f, "")))
	return "\u001f".join(parts).md5_text()


## Прочитать колоду: {ok, error, notes: [{guid, deck, en, ru, note, ctx, ctx_ru, ipa, audio, image}], media: {имя: номер в архиве}}.
static func read(path: String) -> Dictionary:
	var res := {"ok": false, "error": "", "notes": [], "media": {}}
	var z := ZIPReader.new()
	if z.open(path) != OK:
		res["error"] = "Не удалось открыть файл — это точно колода Anki (.apkg)?"
		return res
	var files := z.get_files()
	var coll := ""
	for nm in ["collection.anki21", "collection.anki2"]:
		if files.has(nm):
			coll = nm
			break
	if files.has("collection.anki21b") and not files.has("collection.anki21"):
		res["error"] = "Колода сохранена в новом формате Anki, его прочитать нельзя.\nВ Anki: Файл → Экспорт → отметьте «Поддержка старых версий Anki» (Support older Anki versions) и экспортируйте снова."
		z.close()
		return res
	if coll == "":
		res["error"] = "В файле нет коллекции Anki."
		z.close()
		return res
	var db := SqliteReader.new()
	if not db.open_bytes(z.read_file(coll)):
		res["error"] = "Коллекция не читается: " + db.error
		z.close()
		return res
	# карта медиа: номер файла в архиве → имя
	if files.has("media"):
		var m: Variant = JSON.parse_string(z.read_file("media").get_string_from_utf8())
		if m is Dictionary:
			for k in m:
				res["media"][str(m[k])] = str(k)
	z.close()
	var col: Array = db.rows("col")
	if col.is_empty():
		res["error"] = "Пустая коллекция."
		return res
	var models: Variant = JSON.parse_string(str(col[0].get("models", "{}")))
	var decks: Variant = JSON.parse_string(str(col[0].get("decks", "{}")))
	if not models is Dictionary:
		models = {}
	if not decks is Dictionary:
		decks = {}
	var deck_of := {}   # id заметки → id колоды (первой карточки)
	for c in db.rows("cards"):
		var nid := str(c["nid"])
		if not deck_of.has(nid) or int(c.get("ord", 0)) == 0:
			deck_of[nid] = str(c["did"])
	for n in db.rows("notes"):
		var mdl: Dictionary = (models as Dictionary).get(str(n["mid"]), {})
		var names: Array = []
		for f in mdl.get("flds", []):
			names.append(str(f["name"]))
		var vals := str(n["flds"]).split(char(0x1f))
		var deck_name := "Anki"
		var dk: Variant = (decks as Dictionary).get(str(deck_of.get(str(n["id"]), "")), null)
		if dk is Dictionary:
			deck_name = str(dk.get("name", "Anki"))
		var row := _map(names, vals)
		if row["en"] == "":
			continue
		row["guid"] = str(n["guid"])
		row["deck"] = deck_title(deck_name)
		(res["notes"] as Array).append(row)
	res["ok"] = true
	return res


## «Lookupper::English» → «Lookupper / English»; «Default» → «Anki».
static func deck_title(deck: String) -> String:
	if deck == "Default" or deck.strip_edges() == "":
		return "Anki"
	return deck.replace("::", " / ")


## Поля заметки → запись словаря.
static func _map(names: Array, vals: PackedStringArray) -> Dictionary:
	var by := {}
	for i in mini(names.size(), vals.size()):
		by[str(names[i]).to_lower().replace(" ", "").replace("_", "")] = vals[i]
	var used := {}
	var pick := func(keys: Array) -> String:
		for k in keys:
			if by.has(k) and str(by[k]).strip_edges() != "":
				used[k] = true
				return str(by[k])
		return ""
	var raw_en: String = pick.call(EN)
	var raw_ru: String = pick.call(RU)
	if raw_en == "" and vals.size() > 0:
		raw_en = vals[0]
	if raw_ru == "" and vals.size() > 1 and vals[1] != raw_en:
		raw_ru = vals[1]
	var row := {
		"en": plain(raw_en), "ru": plain(raw_ru), "note": plain(pick.call(NOTE)),
		"ctx": marked(pick.call(CTX)), "ctx_ru": marked(pick.call(CTX_RU)), "ipa": plain(pick.call(IPA)),
		"audio": sound_of(pick.call(AUDIO)), "image": image_of(pick.call(IMAGE)),
	}
	var dict_form := plain(pick.call(DICT))
	if dict_form != "" and dict_form.to_lower() != str(row["en"]).to_lower():
		row["note"] = ("← " + dict_form + ("  ·  " + str(row["note"]) if row["note"] != "" else "")).strip_edges()
	# звук и картинка где угодно в заметке, если своих полей нет
	if row["audio"] == "" or row["image"] == "":
		for v in vals:
			if row["audio"] == "":
				row["audio"] = sound_of(v)
			if row["image"] == "":
				row["image"] = image_of(v)
	return row


## Текст без разметки: теги, [sound:…], сущности HTML.
static func plain(html: String) -> String:
	var t := html
	var rx := RegEx.create_from_string("\\[sound:[^\\]]*\\]")
	t = rx.sub(t, "", true)
	t = RegEx.create_from_string("(?i)<br\\s*/?>|</div>|</p>|</li>").sub(t, " ", true)
	t = RegEx.create_from_string("<[^>]*>").sub(t, "", true)
	return _entities(t).replace("\n", " ").strip_edges().replace("  ", " ")


## Как plain, но подчёркнутое/жирное (слово в контексте) → [b]…[/b] для RichTextLabel.
static func marked(html: String) -> String:
	var t := html.replace("[", "⟦")
	t = RegEx.create_from_string("(?i)<(u|b|strong)(\\s[^>]*)?>").sub(t, "⟪", true)
	t = RegEx.create_from_string("(?i)</(u|b|strong)>").sub(t, "⟫", true)
	t = plain(t)
	return t.replace("⟦", "[lb]").replace("⟪", "[b]").replace("⟫", "[/b]")


static func sound_of(s: String) -> String:
	var m := RegEx.create_from_string("\\[sound:([^\\]]+)\\]").search(s)
	return m.get_string(1).strip_edges() if m else ""


static func image_of(s: String) -> String:
	var m := RegEx.create_from_string("(?i)<img[^>]*src=[\"']?([^\"' >]+)").search(s)
	return m.get_string(1).strip_edges() if m else ""


static func _entities(t: String) -> String:
	var s := t.replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"") \
		.replace("&#39;", "'").replace("&apos;", "'").replace("&#x27;", "'")
	var rx := RegEx.create_from_string("&#(\\d+);")
	for m in rx.search_all(s):
		s = s.replace(m.get_string(0), char(int(m.get_string(1))))
	return s.replace("&amp;", "&")


## Импорт в словарь. Возвращает {ok, error, added, updated, skipped, new_categories, media, backup}.
static func import_into_store(path: String) -> Dictionary:
	var out := {"ok": false, "error": "", "added": 0, "updated": 0, "skipped": 0, "new_categories": 0, "media": 0, "backup": ""}
	var r := read(path)
	if not bool(r["ok"]):
		out["error"] = r["error"]
		return out
	out["backup"] = Store.backup_now("before-anki")
	# что уже пришло из Anki раньше
	var by_guid := {}
	for c in Store.categories():
		for e in c["entries"]:
			if str(e.get("anki", "")) != "":
				by_guid[str(e["anki"])] = e
	var need_media := {}
	for n in r["notes"]:
		var row: Dictionary = n
		var e: Dictionary = by_guid.get(str(row["guid"]), {})
		var h := row_hash(row)
		if not e.is_empty():
			# в Anki заметка изменилась с прошлого импорта — переносим; не менялась — ваши правки в словаре остаются
			if str(e.get("anki_hash", "")) != h:
				var changed := false
				for k in FIELDS:
					if str(e.get(k, "")) != str(row[k]):
						e[k] = row[k]
						changed = true
				e["anki_hash"] = h
				if changed:
					out["updated"] = int(out["updated"]) + 1
		else:
			var cat := Store.category_by_name(str(row["deck"]))
			if cat.is_empty():
				cat = Store.add_category(str(row["deck"]), false)
				out["new_categories"] = int(out["new_categories"]) + 1
			var dup := {}
			var k := AnswerCheck.normalize(str(row["en"])) + "|" + AnswerCheck.normalize(str(row["ru"]))
			for x in cat["entries"]:
				if AnswerCheck.normalize(str(x["en"])) + "|" + AnswerCheck.normalize(str(x["ru"])) == k:
					dup = x
					break
			if not dup.is_empty():
				dup["anki"] = row["guid"]   # та же запись, что уже была, — теперь связана с Anki
				dup["anki_hash"] = h
				for f in FIELDS:
					if str(dup.get(f, "")) == "" and str(row[f]) != "":
						dup[f] = row[f]
				out["skipped"] = int(out["skipped"]) + 1
			else:
				var ne := {"id": Store.new_id(), "created": Dates.today(), "anki": row["guid"], "anki_hash": h}
				for f in FIELDS:
					ne[f] = row[f]
				Srs.fresh(ne)
				(cat["entries"] as Array).append(ne)
				by_guid[str(row["guid"])] = ne
				out["added"] = int(out["added"]) + 1
		for f in ["audio", "image"]:
			if str(row[f]) != "":
				need_media[str(row[f])] = true
	out["media"] = _copy_media(path, r["media"], need_media)
	out["ok"] = true
	Store.save()
	return out


## Скопировать нужные звуки и картинки в папку media. Возвращает, сколько файлов скопировано.
static func _copy_media(path: String, index: Dictionary, need: Dictionary) -> int:
	if need.is_empty():
		return 0
	var dir := Store.media_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return 0
	var n := 0
	for nm in need:
		var safe := str(nm).get_file()
		if not index.has(nm) or safe == "" or safe.begins_with("."):
			continue
		var target := dir.path_join(safe)
		if FileAccess.file_exists(target):
			continue
		var data := z.read_file(str(index[nm]))
		if data.is_empty():
			continue
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
			n += 1
	z.close()
	return n


## Словарь → текстовый файл, который Anki импортирует сам (Файл → Импорт): английский, перевод, заметка.
static func export_txt(path: String, cid := "") -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_string("#separator:tab\n#html:false\n#columns:English\tRussian\tNote\n")
	var n := 0
	for c in Store.categories():
		if cid != "" and c["id"] != cid:
			continue
		for e in c["entries"]:
			var cells: Array = []
			for k in ["en", "ru", "note"]:
				cells.append(str(e.get(k, "")).replace("\t", " ").replace("\n", " ").replace("\r", ""))
			f.store_string("\t".join(cells) + "\n")
			n += 1
	f.close()
	return n
