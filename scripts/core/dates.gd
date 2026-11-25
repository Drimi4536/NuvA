class_name Dates
extends RefCounted
## Даты в «днях»: номер дня по местному времени. Записи хранят дни, а не секунды —
## так проще считать «к повторению сегодня» и не зависеть от часа, в который занимались.


## Сегодняшний день (номер дня от 1970-01-01 по местному времени).
static func today() -> int:
	return day_of(Time.get_unix_time_from_system())


static func day_of(unix: float) -> int:
	var bias_min := int(Time.get_time_zone_from_system().get("bias", 0))
	return int(floor((unix + bias_min * 60.0) / 86400.0))


## «сегодня», «завтра», «через 5 дн.», «3 дн. назад».
static func relative(day: int) -> String:
	var d := day - today()
	if d == 0:
		return "сегодня"
	if d == 1:
		return "завтра"
	if d == -1:
		return "вчера"
	if d > 1:
		return "через %d %s" % [d, plural(d, "день", "дня", "дней")]
	return "%d %s назад" % [-d, plural(-d, "день", "дня", "дней")]


## Дата дня текстом: «25.11.2026».
static func text(day: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(day * 86400)
	return "%02d.%02d.%04d" % [dt["day"], dt["month"], dt["year"]]


## Метка для имён файлов: «2026-11-25_19-04».
static func stamp() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]]


## Русское множественное число: plural(5, "запись", "записи", "записей") → «записей».
static func plural(n: int, one: String, few: String, many: String) -> String:
	var a := absi(n) % 100
	if a >= 11 and a <= 14:
		return many
	match a % 10:
		1:
			return one
		2, 3, 4:
			return few
	return many


## «среда, 25 ноября» — сегодня, по часам компьютера.
static func long_today() -> String:
	var dt := Time.get_datetime_dict_from_system()
	var wd := ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
	var mo := ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
	return "%s, %d %s" % [wd[int(dt["weekday"])], int(dt["day"]), mo[int(dt["month"]) - 1]]
