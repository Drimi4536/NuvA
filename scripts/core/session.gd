class_name Session
extends RefCounted
## Набор карточек для занятия.
##
## options: {mode, cats: [id…] (пусто или all=true — весь словарь), limit (0 — все), shuffle,
##           only_hard, only_due}
## Порядок: при «перемешать» — случайно, но часто забываемые и просроченные выпадают раньше (по весу Srs.weight);
## без перемешивания — сначала то, что пора повторить, потом остальное, внутри — как в категории.

const MODES := {
	"en_ru": "Английский → русский",
	"ru_en": "Русский → английский",
	"type": "Ввод ответа",
	"choice": "Выбор из вариантов",
	"free": "Свободное повторение",
}
const MODE_HINTS := {
	"en_ru": "Видите английский — вспоминаете перевод, потом оцениваете себя.",
	"ru_en": "Видите перевод — вспоминаете, как это по-английски.",
	"type": "Пишете английский вариант сами, приложение проверяет.",
	"choice": "Видите английский — выбираете перевод из пяти вариантов.",
	"free": "Спокойно листаете карточки в случайном порядке, без оценок.",
}


## Карточки: [{cid, eid, cat}] — cat — название категории.
static func build(options: Dictionary) -> Array:
	var today := Dates.today()
	var cats: Array = options.get("cats", [])
	var all := bool(options.get("all", false)) or cats.is_empty()
	var pool: Array = []
	for c in Store.categories():
		if not all and not cats.has(c["id"]):
			continue
		for e in c["entries"]:
			if bool(options.get("only_hard", false)) and not Srs.is_hard(e):
				continue
			if bool(options.get("only_due", false)) and not Srs.is_due(e, today):
				continue
			pool.append({"cid": c["id"], "eid": e["id"], "cat": c["name"], "_e": e})
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if bool(options.get("shuffle", true)):
		# взвешенное перемешивание: ключ = rand^(1/вес), больше вес — раньше
		for p in pool:
			p["_k"] = pow(rng.randf(), 1.0 / Srs.weight(p["_e"], today))
		pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["_k"]) > float(b["_k"]))
	else:
		var due: Array = []
		var rest: Array = []
		for p in pool:
			(due if Srs.is_due(p["_e"], today) else rest).append(p)
		pool = due + rest
	var limit := int(options.get("limit", 0))
	if limit > 0 and pool.size() > limit:
		pool.resize(limit)
	for p in pool:
		p.erase("_e")
		p.erase("_k")
	return pool


## Сколько карточек получится (для подписи «Будет карточек: N»).
static func count(options: Dictionary) -> int:
	var o := options.duplicate()
	o["shuffle"] = false
	return build(o).size()
