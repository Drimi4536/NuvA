class_name SqliteReader
extends RefCounted
## Чтение файла SQLite без сторонних библиотек (только чтение, только таблицы) — для колод Anki.
##   var db := SqliteReader.new(); if db.open_bytes(bytes): var rows := db.rows("notes")  # [{столбец: значение}]
## Формат: https://www.sqlite.org/fileformat.html — страницы B-дерева, записи, страницы переполнения.

var _b := PackedByteArray()
var _page := 4096
var _usable := 4096
var error := ""
var _tables := {}   # имя → {root, cols: [имена], pk: имя столбца INTEGER PRIMARY KEY или ""}


func open_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		error = "файл не найден"
		return false
	return open_bytes(FileAccess.get_file_as_bytes(path))


func open_bytes(b: PackedByteArray) -> bool:
	_b = b
	if b.size() < 100 or b.slice(0, 15).get_string_from_ascii() != "SQLite format 3":
		error = "это не база SQLite"
		return false
	_page = (b[16] << 8) | b[17]
	if _page == 1:
		_page = 65536
	_usable = _page - b[20]
	if b[56] > 1 and b[59] != 0:
		pass   # кодировка UTF-16 — у Anki не бывает, текст ниже читается как UTF-8
	_tables.clear()
	for r in _scan(1):
		var rec: Array = r["rec"]
		if rec.size() >= 5 and str(rec[0]) == "table":
			_tables[str(rec[1])] = {"root": int(rec[3]), "cols": _columns(str(rec[4]))}
	return true


func has_table(t: String) -> bool:
	return _tables.has(t)


## Все строки таблицы: [{столбец: значение}]. Столбец INTEGER PRIMARY KEY берётся из rowid.
func rows(table: String) -> Array:
	if not _tables.has(table):
		return []
	var info: Dictionary = _tables[table]
	var cols: Array = info["cols"]
	var out: Array = []
	for r in _scan(int(info["root"])):
		var rec: Array = r["rec"]
		var d := {}
		for i in cols.size():
			var c: Dictionary = cols[i]
			var v: Variant = rec[i] if i < rec.size() else null
			if v == null and bool(c["pk"]):
				v = r["rowid"]
			d[c["name"]] = v
		out.append(d)
	return out


# ───────────────────────────── B-дерево

## Обход таблицы с корня: [{rowid, rec}].
func _scan(root: int) -> Array:
	var out: Array = []
	var stack: Array = [root]
	var guard := 0
	while not stack.is_empty() and guard < 1000000:
		guard += 1
		var pg: int = stack.pop_back()
		var base := (pg - 1) * _page
		var hdr := base + (100 if pg == 1 else 0)
		if hdr >= _b.size():
			continue
		var kind := _b[hdr]
		var n := _u16(hdr + 3)
		if kind == 5:   # внутренняя страница таблицы: дети слева направо, правый — последним
			var children: Array = []
			for i in n:
				var cell := base + _u16(hdr + 12 + i * 2)
				children.append(_u32(cell))
			children.append(_u32(hdr + 8))
			children.reverse()
			stack.append_array(children)
		elif kind == 13:   # лист таблицы
			for i in n:
				var cell := base + _u16(hdr + 8 + i * 2)
				var p := _varint(cell)
				var size: int = p[0]
				var r := _varint(p[1])
				var rowid: int = r[0]
				out.append({"rowid": rowid, "rec": _record(_payload(r[1], size))})
	return out


## Содержимое ячейки с учётом страниц переполнения.
func _payload(at: int, size: int) -> PackedByteArray:
	var x := _usable - 35
	if size <= x:
		return _b.slice(at, at + size)
	var m := ((_usable - 12) * 32 / 255) - 23
	var k := m + ((size - m) % (_usable - 4))
	var local := k if k <= x else m
	var out := _b.slice(at, at + local)
	var next := _u32(at + local)
	var left := size - local
	var guard := 0
	while next != 0 and left > 0 and guard < 100000:
		guard += 1
		var base := (next - 1) * _page
		var take := mini(left, _usable - 4)
		out.append_array(_b.slice(base + 4, base + 4 + take))
		left -= take
		next = _u32(base)
	return out


## Запись: заголовок с типами, затем значения.
func _record(p: PackedByteArray) -> Array:
	var vals: Array = []
	if p.is_empty():
		return vals
	var h := _varint_in(p, 0)
	var hsize: int = h[0]
	var pos: int = h[1]
	var types: Array = []
	while pos < hsize:
		var t := _varint_in(p, pos)
		types.append(t[0])
		pos = t[1]
	var at := hsize
	for t in types:
		var st: int = t
		match st:
			0:
				vals.append(null)
			1, 2, 3, 4, 5, 6:
				var w: int = [0, 1, 2, 3, 4, 6, 8][st]
				var v := 0
				for i in w:
					v = (v << 8) | p[at + i]
				if w < 8 and (p[at] & 0x80) != 0:
					v -= 1 << (w * 8)
				vals.append(v)
				at += w
			7:
				var f := p.slice(at, at + 8)
				f.reverse()
				vals.append(f.decode_double(0))
				at += 8
			8:
				vals.append(0)
			9:
				vals.append(1)
			_:
				if st >= 12:
					var n := (st - 12) / 2
					var chunk := p.slice(at, at + n)
					vals.append(chunk.get_string_from_utf8() if st % 2 == 1 else chunk)
					at += n
				else:
					vals.append(null)
	return vals


## Имена столбцов из CREATE TABLE (простой разбор, хватает для Anki).
func _columns(sql: String) -> Array:
	var a := sql.find("(")
	var b := sql.rfind(")")
	if a < 0 or b <= a:
		return []
	var body := sql.substr(a + 1, b - a - 1)
	var parts: Array = []
	var depth := 0
	var cur := ""
	for ch in body:
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		if ch == "," and depth == 0:
			parts.append(cur)
			cur = ""
		else:
			cur += ch
	parts.append(cur)
	var cols: Array = []
	for part in parts:
		var t := str(part).replace("\t", " ").replace("\r", " ").replace("\n", " ").strip_edges()
		while t.contains("  "):
			t = t.replace("  ", " ")
		var up := t.to_upper()
		if up.begins_with("PRIMARY KEY") or up.begins_with("UNIQUE") or up.begins_with("FOREIGN") \
				or up.begins_with("CHECK") or up.begins_with("CONSTRAINT"):
			continue
		var nm := t.split(" ", false)[0]
		for q in ["\"", "`", "[", "]"]:
			nm = nm.replace(q, "")
		cols.append({"name": nm, "pk": up.contains("INTEGER PRIMARY KEY")})
	return cols


# ───────────────────────────── числа

func _u16(i: int) -> int:
	return (_b[i] << 8) | _b[i + 1]


func _u32(i: int) -> int:
	return (_b[i] << 24) | (_b[i + 1] << 16) | (_b[i + 2] << 8) | _b[i + 3]


func _varint(i: int) -> Array:
	return _varint_in(_b, i)


## Varint SQLite: [значение, позиция после него].
static func _varint_in(b: PackedByteArray, i: int) -> Array:
	var v := 0
	for k in 8:
		var c := b[i + k]
		v = (v << 7) | (c & 0x7f)
		if c < 0x80:
			return [v, i + k + 1]
	v = (v << 8) | b[i + 8]
	return [v, i + 9]
