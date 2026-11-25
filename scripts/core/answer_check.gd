class_name AnswerCheck
extends RefCounted
## Проверка введённого ответа.
##
## Не важны: регистр, пробелы по краям и подряд, обычная пунктуация (. , ! ? ; : кавычки скобки тире),
## вид апострофа (don't = don’t), дефис (well-known = well known).
## Опечатка — одна лишняя/пропущенная/заменённая буква в слове от 4 букв (в длинном слове от 9 букв — две),
## и таких слов немного. Другое слово («see» вместо «seeing»), пропущенное или лишнее слово — ошибка.
## Если правильных вариантов несколько, их пишут через « / » или «;»: «big / large».

const CORRECT := "correct"
const TYPO := "typo"
const WRONG := "wrong"

const _STRIP := ".,!?;:\"«»“”„()[]{}…"


## Привести к виду для сравнения.
static func normalize(s: String) -> String:
	var t := s.to_lower().strip_edges()
	for ch in ["’", "‘", "`", "´"]:
		t = t.replace(ch, "'")
	t = t.replace("'", "")
	for ch in ["—", "–", "-"]:
		t = t.replace(ch, " ")
	var out := ""
	for i in t.length():
		var c := t[i]
		if _STRIP.contains(c):
			continue
		out += c
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


## Варианты правильного ответа: «big / large» → ["big", "large"].
static func variants(expected: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var raw := expected.replace(";", " / ")
	if raw.contains(" / ") or (raw.contains("/") and not raw.contains(" ")):
		for p in raw.split("/", false):
			if p.strip_edges() != "":
				parts.append(p.strip_edges())
	if parts.is_empty():
		parts.append(expected.strip_edges())
	return parts


## Проверить ответ. Возвращает {result: correct|typo|wrong, matched: вариант, words: [{w, ok}] — разбор слов варианта}.
static func check(answer: String, expected: String) -> Dictionary:
	var best := {"result": WRONG, "matched": variants(expected)[0], "words": []}
	var a := normalize(answer)
	if a == "":
		best["words"] = _mark_all(str(best["matched"]), false)
		return best
	var rank := {WRONG: 0, TYPO: 1, CORRECT: 2}
	for v in variants(expected):
		var r := _check_one(a, v)
		if int(rank[r["result"]]) > int(rank[best["result"]]):
			best = r
		if best["result"] == CORRECT:
			break
	if best["result"] == WRONG and (best["words"] as Array).is_empty():
		best = _check_one(a, variants(expected)[0])
	return best


static func _check_one(a: String, variant: String) -> Dictionary:
	var e := normalize(variant)
	var res := {"result": WRONG, "matched": variant, "words": []}
	if a == e:
		res["result"] = CORRECT
		res["words"] = _mark_all(variant, true)
		return res
	var aw := a.split(" ", false)
	var ew := e.split(" ", false)
	var shown := variant.split(" ", false)   # слова варианта как написаны (для подсветки)
	var marks: Array = []
	if aw.size() != ew.size():
		# слово пропущено или лишнее — ошибка; подсветим слова, которых нет в ответе
		for i in ew.size():
			marks.append({"w": shown[i] if i < shown.size() else ew[i], "ok": aw.has(ew[i])})
		res["words"] = marks
		return res
	var typos := 0
	var bad := 0
	for i in ew.size():
		var d := distance(aw[i], ew[i])
		var ok := true
		if d > 0:
			var allowed := 0
			if ew[i].length() >= 9:
				allowed = 2
			elif ew[i].length() >= 4:
				allowed = 1
			if d <= allowed:
				typos += 1
			else:
				bad += 1
			ok = false
		marks.append({"w": shown[i] if i < shown.size() else ew[i], "ok": ok})
	res["words"] = marks
	if bad == 0 and typos <= maxi(1, ew.size() / 4):
		res["result"] = TYPO
	return res


static func _mark_all(text: String, ok: bool) -> Array:
	var out: Array = []
	for w in text.split(" ", false):
		out.append({"w": w, "ok": ok})
	return out


## Расстояние Левенштейна (сколько букв вставить, удалить или заменить).
static func distance(a: String, b: String) -> int:
	if a == b:
		return 0
	if a.is_empty():
		return b.length()
	if b.is_empty():
		return a.length()
	var prev := PackedInt32Array()
	prev.resize(b.length() + 1)
	for j in b.length() + 1:
		prev[j] = j
	for i in a.length():
		var cur := PackedInt32Array()
		cur.resize(b.length() + 1)
		cur[0] = i + 1
		for j in b.length():
			var cost := 0 if a[i] == b[j] else 1
			cur[j + 1] = mini(mini(cur[j] + 1, prev[j + 1] + 1), prev[j] + cost)
		prev = cur
	return prev[b.length()]
