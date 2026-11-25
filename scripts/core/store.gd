extends Node
## Store — весь словарь и настройки (автозагрузка).
##
## Хранится в user://dictionary.json (папка EnglishTrainer в данных пользователя):
##   {version, settings: {...}, categories: [{id, name, created, entries: [запись…]}]}
##   запись: {id, en, ru, note, created, correct, almost, wrong, level, last, next, last_result}
## Сохраняется сама после каждого изменения (раз в кадр, атомарно: сначала во временный файл).
## Раз в день при запуске — автокопия в user://backups (последние 10).
## Импорт ничего не удаляет: новые категории добавляются, в существующие — только новые записи.

signal changed

const FILE := "user://dictionary.json"
const BACKUPS := "user://backups"
const KEEP_AUTO := 10
const COLORS := 8                 # сколько цветов категорий (AppTheme.cat_color)

var path := FILE                  # тесты подменяют путь
var data: Dictionary = {}
var _dirty := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	load_data()
	auto_backup()


# ───────────────────────────── загрузка и сохранение

func empty_data() -> Dictionary:
	return {"version": 1, "settings": default_settings(), "categories": []}


func default_settings() -> Dictionary:
	return {"theme": "light", "last": {"mode": "en_ru", "cats": [], "all": true, "limit": 20, "shuffle": true,
		"only_hard": false, "only_due": false}}


func load_data() -> void:
	data = empty_data()
	var p := path
	if not FileAccess.file_exists(p) and FileAccess.file_exists(p + ".tmp"):
		p = p + ".tmp"   # сохранение прервалось на полпути — берём временный файл
	if not FileAccess.file_exists(p):
		return
	var txt := FileAccess.get_file_as_string(p)
	var parsed: Variant = JSON.parse_string(txt)
	if not parsed is Dictionary:
		# файл испорчен: не трогаем его, откладываем копию и начинаем с пустого — данные можно вернуть вручную
		var bad := path.get_base_dir().path_join("dictionary.broken-%s.json" % Dates.stamp())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(bad))
		push_warning("Словарь не читается, копия: %s" % bad)
		return
	data = parsed
	_repair()


## Достроить недостающие поля (старые файлы, импорт, ручные правки).
func _repair() -> void:
	if not data.has("settings") or not data["settings"] is Dictionary:
		data["settings"] = default_settings()
	var s: Dictionary = data["settings"]
	var d := default_settings()
	for k in d:
		if not s.has(k):
			s[k] = d[k]
	for k in d["last"]:
		if not (s["last"] as Dictionary).has(k):
			s["last"][k] = d["last"][k]
	if not data.has("categories") or not data["categories"] is Array:
		data["categories"] = []
	var good: Array = []
	for c in data["categories"]:
		if not c is Dictionary:
			continue
		if str(c.get("id", "")) == "":
			c["id"] = new_id()
		c["name"] = str(c.get("name", "Без названия"))
		c["created"] = int(c.get("created", Dates.today()))
		c["color"] = int(c.get("color", good.size() % COLORS)) % COLORS
		var ents: Array = []
		for e in c.get("entries", []):
			if e is Dictionary and str(e.get("en", "")).strip_edges() != "":
				if str(e.get("id", "")) == "":
					e["id"] = new_id()
				e["en"] = str(e["en"])
				e["ru"] = str(e.get("ru", ""))
				e["note"] = str(e.get("note", ""))
				if not e.has("created"):
					e["created"] = Dates.today()
				Srs.fresh(e)
				for k in ["created", "correct", "almost", "wrong", "level", "last", "next"]:
					e[k] = int(e[k])   # JSON читает числа дробными
				ents.append(e)
		c["entries"] = ents
		good.append(c)
	data["categories"] = good
	data["version"] = 1


## Отметить изменение: файл запишется в конце кадра (несколько правок подряд — одна запись).
func save() -> void:
	changed.emit()
	if _dirty:
		return
	_dirty = true
	_flush.call_deferred()


func _flush() -> void:
	if not _dirty:
		return
	_dirty = false
	write_now()


## Записать немедленно (атомарно: временный файл → замена).
func write_now() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось сохранить словарь: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var abs_main := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_main)
	return DirAccess.rename_absolute(abs_tmp, abs_main) == OK


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dirty:
			_dirty = false
			write_now()


# ───────────────────────────── резервные копии, экспорт, импорт

## Звуки и картинки (из колод Anki) — рядом со словарём.
func media_dir() -> String:
	return path.get_base_dir().path_join("media")


func media_path(fname: String) -> String:
	if fname.strip_edges() == "":
		return ""
	var p := media_dir().path_join(fname.get_file())
	return p if FileAccess.file_exists(p) else ""


func backups_dir() -> String:
	return path.get_base_dir().path_join("backups") if path != FILE else BACKUPS


## Автокопия раз в день (при запуске), хранятся последние KEEP_AUTO.
func auto_backup() -> void:
	if not FileAccess.file_exists(path):
		return
	var dir := backups_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var dt := Time.get_date_dict_from_system()
	var fname := "auto-%04d-%02d-%02d.json" % [dt["year"], dt["month"], dt["day"]]
	var target := dir.path_join(fname)
	if not FileAccess.file_exists(target):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(target))
	var autos: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("auto-"):
			autos.append(f)
	autos.sort()
	while autos.size() > KEEP_AUTO:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(str(autos.pop_front()))))


## Резервная копия сейчас. Возвращает путь к файлу.
func backup_now(tag := "backup") -> String:
	write_now()
	var dir := backups_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var target := dir.path_join("%s-%s.json" % [tag, Dates.stamp()])
	export_to(target)
	return target


## Сохранить весь словарь (с прогрессом изучения) в файл.
func export_to(file: String) -> bool:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return false
	var out := data.duplicate(true)
	out["app"] = "EnglishTrainer"
	out["exported"] = Dates.stamp()
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	return true


## Добавить словарь из файла, ничего не удаляя.
## Понимает свой формат ({categories: [...]}) и простой список: [{"category": "...", "en": "...", "ru": "...", "note": "..."}].
## Перед импортом — резервная копия. Возвращает {ok, error, added, skipped, new_categories, backup}.
func import_from(file: String) -> Dictionary:
	var res := {"ok": false, "error": "", "added": 0, "skipped": 0, "new_categories": 0, "backup": ""}
	if not FileAccess.file_exists(file):
		res["error"] = "Файл не найден"
		return res
	if file.get_extension().to_lower() in ["apkg", "colpkg"]:
		return AnkiImport.import_into_store(file)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	var incoming: Array = []   # [{name, entries}]
	if parsed is Dictionary and (parsed as Dictionary).get("categories") is Array:
		for c in parsed["categories"]:
			if c is Dictionary:
				incoming.append({"name": str(c.get("name", "Импорт")), "entries": c.get("entries", [])})
	elif parsed is Array:
		var by_name := {}
		for e in parsed:
			if e is Dictionary:
				var n := str(e.get("category", "Импорт"))
				if not by_name.has(n):
					by_name[n] = []
				(by_name[n] as Array).append(e)
		for n in by_name:
			incoming.append({"name": n, "entries": by_name[n]})
	else:
		res["error"] = "Это не файл словаря (ожидается JSON со списком категорий или записей)"
		return res
	res["backup"] = backup_now("before-import")
	for inc in incoming:
		var cat := category_by_name(str(inc["name"]))
		if cat.is_empty():
			cat = add_category(str(inc["name"]), false)
			res["new_categories"] = int(res["new_categories"]) + 1
		var seen := {}
		for e in cat["entries"]:
			seen[_key(str(e["en"]), str(e["ru"]))] = true
		for e in inc["entries"]:
			if not e is Dictionary:
				continue
			var en := str(e.get("en", "")).strip_edges()
			var ru := str(e.get("ru", "")).strip_edges()
			if en == "":
				continue
			var k := _key(en, ru)
			if seen.has(k):
				res["skipped"] = int(res["skipped"]) + 1
				continue
			seen[k] = true
			var copy := (e as Dictionary).duplicate(true)
			copy["id"] = new_id()
			copy.erase("category")
			copy["en"] = en
			copy["ru"] = ru
			copy["note"] = str(e.get("note", ""))
			if not copy.has("created"):
				copy["created"] = Dates.today()
			Srs.fresh(copy)
			(cat["entries"] as Array).append(copy)
			res["added"] = int(res["added"]) + 1
	res["ok"] = true
	save()
	return res


func _key(en: String, ru: String) -> String:
	return AnswerCheck.normalize(en) + "|" + AnswerCheck.normalize(ru)


# ───────────────────────────── категории

func new_id() -> String:
	return "%x%04x" % [int(Time.get_unix_time_from_system() * 1000.0), _rng.randi() % 0xFFFF]


func categories() -> Array:
	return data["categories"]


func category(id: String) -> Dictionary:
	for c in data["categories"]:
		if c["id"] == id:
			return c
	return {}


func category_by_name(cat_name: String) -> Dictionary:
	var n := cat_name.strip_edges().to_lower()
	for c in data["categories"]:
		if str(c["name"]).strip_edges().to_lower() == n:
			return c
	return {}


func add_category(cat_name: String, do_save := true) -> Dictionary:
	var c := {"id": new_id(), "name": cat_name.strip_edges() if cat_name.strip_edges() != "" else "Новая категория",
		"created": Dates.today(), "color": (data["categories"] as Array).size() % COLORS, "entries": []}
	(data["categories"] as Array).append(c)
	if do_save:
		save()
	return c


func rename_category(id: String, cat_name: String) -> void:
	var c := category(id)
	if c.is_empty() or cat_name.strip_edges() == "":
		return
	c["name"] = cat_name.strip_edges()
	save()


func set_category_color(id: String, color: int) -> void:
	var c := category(id)
	if c.is_empty():
		return
	c["color"] = posmod(color, COLORS)
	save()


## Удалить категорию. Возвращает {cat, index} — для «Вернуть».
func delete_category(id: String) -> Dictionary:
	var cats: Array = data["categories"]
	for i in cats.size():
		if cats[i]["id"] == id:
			var c: Dictionary = cats[i]
			cats.remove_at(i)
			save()
			return {"cat": c, "index": i}
	return {}


## Вернуть удалённую категорию на место.
func restore_category(undo: Dictionary) -> void:
	if undo.is_empty() or not category(str(undo["cat"]["id"])).is_empty():
		return
	var cats: Array = data["categories"]
	cats.insert(mini(int(undo["index"]), cats.size()), undo["cat"])
	save()


# ───────────────────────────── записи

func add_entry(cid: String, en: String, ru: String, note := "") -> Dictionary:
	var c := category(cid)
	if c.is_empty() or en.strip_edges() == "":
		return {}
	var e := {"id": new_id(), "en": en.strip_edges(), "ru": ru.strip_edges(), "note": note.strip_edges(), "created": Dates.today()}
	Srs.fresh(e)
	(c["entries"] as Array).insert(0, e)   # новое — сверху
	save()
	return e


func entry(cid: String, eid: String) -> Dictionary:
	var c := category(cid)
	if c.is_empty():
		return {}
	for e in c["entries"]:
		if e["id"] == eid:
			return e
	return {}


func update_entry(cid: String, eid: String, en: String, ru: String, note: String) -> void:
	var e := entry(cid, eid)
	if e.is_empty() or en.strip_edges() == "":
		return
	e["en"] = en.strip_edges()
	e["ru"] = ru.strip_edges()
	e["note"] = note.strip_edges()
	save()


## Удалить запись. Возвращает {cid, entry, index} — для «Вернуть».
func delete_entry(cid: String, eid: String) -> Dictionary:
	var c := category(cid)
	if c.is_empty():
		return {}
	var ents: Array = c["entries"]
	for i in ents.size():
		if ents[i]["id"] == eid:
			var e: Dictionary = ents[i]
			ents.remove_at(i)
			save()
			return {"cid": cid, "entry": e, "index": i}
	return {}


## Вернуть удалённую запись на прежнее место (с прогрессом).
func restore_entry(undo: Dictionary) -> void:
	if undo.is_empty():
		return
	var c := category(str(undo["cid"]))
	if c.is_empty() or not entry(str(undo["cid"]), str(undo["entry"]["id"])).is_empty():
		return
	var ents: Array = c["entries"]
	ents.insert(mini(int(undo["index"]), ents.size()), undo["entry"])
	save()


## Копия записи (прогресс — заново) — рядом с оригиналом.
func duplicate_entry(cid: String, eid: String) -> Dictionary:
	var c := category(cid)
	var e := entry(cid, eid)
	if e.is_empty():
		return {}
	var copy := {"id": new_id(), "en": e["en"], "ru": e["ru"], "note": e["note"], "created": Dates.today()}
	for k in ["ctx", "ctx_ru", "ipa", "audio", "image"]:
		if e.has(k):
			copy[k] = e[k]
	Srs.fresh(copy)
	var ents: Array = c["entries"]
	ents.insert(ents.find(e) + 1, copy)
	save()
	return copy


## Перенести запись в другую категорию (с прогрессом).
func move_entry(cid: String, eid: String, to_cid: String) -> void:
	var e := entry(cid, eid)
	var to := category(to_cid)
	if e.is_empty() or to.is_empty() or cid == to_cid:
		return
	(category(cid)["entries"] as Array).erase(e)
	(to["entries"] as Array).insert(0, e)
	save()


## Записи категории, подходящие под поиск (по английскому, переводу и заметке, без учёта регистра).
func search(cid: String, query: String) -> Array:
	var c := category(cid)
	if c.is_empty():
		return []
	var q := query.strip_edges().to_lower()
	if q == "":
		return c["entries"]
	var out: Array = []
	for e in c["entries"]:
		if str(e["en"]).to_lower().contains(q) or str(e["ru"]).to_lower().contains(q) or str(e["note"]).to_lower().contains(q):
			out.append(e)
	return out


## Поиск по всему словарю: [{cid, cat, entry}]; сначала те, где английский начинается с запроса.
func search_all(query: String, limit := 50) -> Array:
	var q := query.strip_edges().to_lower()
	if q == "":
		return []
	var first: Array = []
	var rest: Array = []
	for c in data["categories"]:
		for e in c["entries"]:
			var en := str(e["en"]).to_lower()
			if en.begins_with(q):
				first.append({"cid": c["id"], "cat": c["name"], "entry": e})
			elif en.contains(q) or str(e["ru"]).to_lower().contains(q) or str(e["note"]).to_lower().contains(q):
				rest.append({"cid": c["id"], "cat": c["name"], "entry": e})
	return (first + rest).slice(0, limit)


## Есть ли уже такая английская фраза (без учёта регистра и знаков).
func has_phrase(en: String) -> bool:
	var n := AnswerCheck.normalize(en)
	if n == "":
		return false
	for c in data["categories"]:
		for e in c["entries"]:
			if AnswerCheck.normalize(str(e["en"])) == n:
				return true
	return false


## Отметить ответ на занятии (и посчитать в «сегодня сделано»).
func grade(cid: String, eid: String, result: String) -> void:
	var e := entry(cid, eid)
	if e.is_empty():
		return
	Srs.grade(e, result)
	var t := today_stats()
	t["done"] = int(t["done"]) + 1
	data["settings"]["today"] = t
	save()


## Сколько карточек отмечено сегодня: {day, done}.
func today_stats() -> Dictionary:
	var t: Variant = setting("today", {})
	if not t is Dictionary or int((t as Dictionary).get("day", -1)) != Dates.today():
		return {"day": Dates.today(), "done": 0}
	return {"day": int(t["day"]), "done": int(t.get("done", 0))}


# ───────────────────────────── счётчики

func count_entries(cid := "") -> int:
	if cid != "":
		return (category(cid).get("entries", []) as Array).size()
	var n := 0
	for c in data["categories"]:
		n += (c["entries"] as Array).size()
	return n


func count_due(cid := "") -> int:
	var n := 0
	var today := Dates.today()
	for c in data["categories"]:
		if cid != "" and c["id"] != cid:
			continue
		for e in c["entries"]:
			if Srs.is_due(e, today):
				n += 1
	return n


func count_hard(cid := "") -> int:
	var n := 0
	for c in data["categories"]:
		if cid != "" and c["id"] != cid:
			continue
		for e in c["entries"]:
			if Srs.is_hard(e):
				n += 1
	return n


func count_learned(cid := "") -> int:
	var n := 0
	for c in data["categories"]:
		if cid != "" and c["id"] != cid:
			continue
		for e in c["entries"]:
			if Srs.is_learned(e):
				n += 1
	return n


# ───────────────────────────── настройки

func setting(key: String, def: Variant = null) -> Variant:
	return (data["settings"] as Dictionary).get(key, def)


func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value
	save()


## Пример для первого запуска: категория с несколькими фразами (можно удалить).
func add_sample() -> Dictionary:
	var c := add_category("Useful phrases", false)
	var rows := [
		["I am looking forward to seeing you.", "Я с нетерпением жду встречи с тобой.", "Говорим о приятном ожидании события."],
		["It's up to you.", "Решать тебе.", ""],
		["Never mind.", "Неважно / не бери в голову.", ""],
		["I'm running late.", "Я опаздываю.", "Когда уже в пути, но не успеваешь."],
		["Could you say that again?", "Можешь повторить?", "Вежливо переспросить."],
	]
	for r in rows:
		var e := {"id": new_id(), "en": r[0], "ru": r[1], "note": r[2], "created": Dates.today()}
		Srs.fresh(e)
		(c["entries"] as Array).append(e)
	save()
	return c
