class_name Srs
extends RefCounted
## Простое интервальное повторение.
##
## У записи есть уровень освоения 0…6. Каждый уровень — через сколько дней показать снова:
##   0 — сегодня же, 1 — завтра, 2 — через 3 дня, 3 — через неделю, 4 — через 2 недели, 5 — через месяц, 6 — через 2 месяца.
## «Знаю» — уровень вверх. «Почти знаю» — показать завтра, высокий уровень чуть снижается.
## «Не знаю» — уровень 0, запись вернётся сегодня же (и ещё раз в этом же занятии).
## Логика намеренно простая: её легко поменять здесь, в одном месте.

const INTERVALS := [0, 1, 3, 7, 14, 30, 60]
const MAX_LEVEL := 6
const KNOW := "know"
const ALMOST := "almost"
const DONT := "dont"


## Новая запись: поля учёта с нулями, «повторить» — сегодня.
static func fresh(entry: Dictionary) -> Dictionary:
	for k in ["correct", "almost", "wrong", "level"]:
		if not entry.has(k):
			entry[k] = 0
	if not entry.has("last"):
		entry["last"] = -1          # день последнего повторения (-1 — ещё не повторяли)
	if not entry.has("next"):
		entry["next"] = Dates.today()   # день, когда пора повторить
	if not entry.has("last_result"):
		entry["last_result"] = ""
	return entry


## Отметить ответ. result — KNOW / ALMOST / DONT.
static func grade(entry: Dictionary, result: String, today := -1) -> void:
	var day := today if today >= 0 else Dates.today()
	var level := int(entry.get("level", 0))
	match result:
		KNOW:
			entry["correct"] = int(entry.get("correct", 0)) + 1
			level = mini(level + 1, MAX_LEVEL)
			entry["next"] = day + int(INTERVALS[level])
		ALMOST:
			entry["almost"] = int(entry.get("almost", 0)) + 1
			if level >= 3:
				level -= 1
			level = maxi(level, 1)
			entry["next"] = day + 1
		_:
			entry["wrong"] = int(entry.get("wrong", 0)) + 1
			level = 0
			entry["next"] = day
	entry["level"] = level
	entry["last"] = day
	entry["last_result"] = result


## Пора повторить: день «next» наступил.
static func is_due(entry: Dictionary, today := -1) -> bool:
	var day := today if today >= 0 else Dates.today()
	return int(entry.get("next", day)) <= day


## Ни разу не отвечали.
static func is_new(entry: Dictionary) -> bool:
	return int(entry.get("correct", 0)) + int(entry.get("almost", 0)) + int(entry.get("wrong", 0)) == 0


## Сложная запись: в последний раз не знал, или ошибок не меньше, чем верных ответов, или застряла на низком уровне с ошибками.
static func is_hard(entry: Dictionary) -> bool:
	if is_new(entry):
		return false
	var wrong := int(entry.get("wrong", 0))
	var correct := int(entry.get("correct", 0))
	if str(entry.get("last_result", "")) == DONT:
		return true
	if wrong > 0 and wrong >= correct:
		return true
	return wrong > 0 and int(entry.get("level", 0)) <= 1


## Выучено: уровень 3 и выше (держится неделю и дольше).
static func is_learned(entry: Dictionary) -> bool:
	return int(entry.get("level", 0)) >= 3


## Вес для перемешивания: часто забываемые и просроченные выпадают чаще, выученные — реже.
static func weight(entry: Dictionary, today := -1) -> float:
	var day := today if today >= 0 else Dates.today()
	var w := 1.0
	w += int(entry.get("wrong", 0)) * 1.5
	if is_hard(entry):
		w += 3.0
	if is_due(entry, day):
		w += 2.0 + clampf(float(day - int(entry.get("next", day))) * 0.3, 0.0, 3.0)
	w -= int(entry.get("level", 0)) * 0.6
	return maxf(w, 0.25)


## Подпись уровня для интерфейса.
static func level_name(entry: Dictionary) -> String:
	if is_new(entry):
		return "новое"
	match int(entry.get("level", 0)):
		0:
			return "не запомнено"
		1, 2:
			return "запоминается"
		3, 4:
			return "знаю"
	return "твёрдо знаю"
