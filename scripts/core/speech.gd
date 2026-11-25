extends Node
## Speech — озвучка (автозагрузка).
## У записи есть звук из Anki (mp3/ogg/wav в папке media) — играет он, иначе английский читает голос системы
## (на Windows — голоса из «Параметры → Время и язык → Речь»). Русский — только голосом системы, если он есть.
## Настройки: voice_en, voice_ru (id голоса, "" — первый подходящий), rate (0.6…1.6), auto_speak.

signal playing_changed(on: bool)   ## началась/закончилась озвучка (для кнопок «Остановить»)

var _player := AudioStreamPlayer.new()
var _run := 0          # номер текущего прослушивания списка (новый — старый останавливается)
var _streams := {}     # имя файла → AudioStream (кэш)
var listing := false   # идёт «прослушать всё»


func _ready() -> void:
	add_child(_player)


# ───────────────────────────── голоса системы

var _tts_ok := -1


## Голос системы есть и работает (на Linux без speech-dispatcher — нет).
func tts_supported() -> bool:
	if _tts_ok < 0:
		_tts_ok = 1 if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) \
			and not DisplayServer.tts_get_voices().is_empty() else 0
	return _tts_ok == 1


## Голоса для языка: [{id, name}].
func voices(lang: String) -> Array:
	if not tts_supported():
		return []
	var out: Array = []
	for v in DisplayServer.tts_get_voices():
		var l := str(v.get("language", "")).to_lower()
		if l.begins_with(lang):
			out.append({"id": str(v.get("id", "")), "name": str(v.get("name", ""))})
	return out


func voice_id(lang: String) -> String:
	var vs := voices(lang)
	if vs.is_empty():
		return ""
	var want := str(Store.setting("voice_" + lang, ""))
	for v in vs:
		if v["id"] == want:
			return want
	# английский: сначала американский/британский
	if lang == "en":
		for v in vs:
			if str(v["name"]).contains("US") or str(v["name"]).contains("United States") or str(v["name"]).contains("Zira") \
					or str(v["name"]).contains("David"):
				return v["id"]
	return str(vs[0]["id"])


func has_voice(lang: String) -> bool:
	return voice_id(lang) != ""


## Сказать текст голосом системы. false — голоса для языка нет.
func say(text: String, lang := "en") -> bool:
	var vid := voice_id(lang)
	if vid == "" or text.strip_edges() == "":
		return false
	_player.stop()
	DisplayServer.tts_stop()
	var rate := clampf(float(Store.setting("rate", 1.0)), 0.5, 2.0)
	DisplayServer.tts_speak(text, vid, 100, 1.0, rate)
	return true


# ───────────────────────────── записи

## Есть чем озвучить запись (звук из Anki или английский голос).
func can_speak(e: Dictionary) -> bool:
	return Store.media_path(str(e.get("audio", ""))) != "" or has_voice("en")


## Озвучить английский записи: звук из Anki, иначе голос системы.
func speak_entry(e: Dictionary) -> bool:
	var s := stream_for(str(e.get("audio", "")))
	if s:
		if tts_supported():
			DisplayServer.tts_stop()
		_player.stream = s
		_player.pitch_scale = 1.0
		_player.play()
		return true
	return say(clean(str(e.get("en", ""))), "en")


## Звук из папки media (кэшируется).
func stream_for(fname: String) -> AudioStream:
	var p := Store.media_path(fname)
	if p == "":
		return null
	if _streams.has(p):
		return _streams[p]
	var s: AudioStream = null
	var ext := p.get_extension().to_lower()
	var abs_p := ProjectSettings.globalize_path(p)
	match ext:
		"mp3":
			var mp := AudioStreamMP3.new()
			mp.data = FileAccess.get_file_as_bytes(p)
			s = mp if mp.data.size() > 0 else null
		"ogg":
			s = AudioStreamOggVorbis.load_from_file(abs_p)
		"wav":
			s = AudioStreamWAV.load_from_file(abs_p)
	if s:
		_streams[p] = s
	return s


func is_speaking() -> bool:
	return _player.playing or (tts_supported() and DisplayServer.tts_is_speaking())


func stop() -> void:
	_run += 1
	_player.stop()
	if tts_supported():
		DisplayServer.tts_stop()
	if listing:
		listing = false
		playing_changed.emit(false)


## Прослушать список записей: английский → пауза → перевод (если есть русский голос и включено) → пауза.
## on_item(i) — какая запись звучит сейчас (подсветить).
func listen(entries: Array, on_item := Callable()) -> void:
	stop()
	_run += 1
	var run := _run
	listing = true
	playing_changed.emit(true)
	var with_ru := bool(Store.setting("listen_ru", true)) and has_voice("ru")
	for i in entries.size():
		if run != _run:
			return
		var e: Dictionary = entries[i]
		if on_item.is_valid():
			on_item.call(i)
		if speak_entry(e):
			await _wait_done(run)
		if run != _run:
			return
		await get_tree().create_timer(0.6).timeout
		if with_ru and str(e.get("ru", "")) != "" and run == _run:
			say(str(e["ru"]), "ru")
			await _wait_done(run)
		if run != _run:
			return
		await get_tree().create_timer(1.1).timeout
	if run == _run:
		listing = false
		playing_changed.emit(false)
		if on_item.is_valid():
			on_item.call(-1)


func _wait_done(run: int) -> void:
	# голос системы начинает говорить не сразу — ждём начала, потом конца
	var t := 0.0
	while run == _run and not is_speaking() and t < 1.5:
		await get_tree().process_frame
		t += get_process_delta_time()
	t = 0.0
	while run == _run and is_speaking() and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()


## Текст для голоса: без [b] и прочей разметки.
static func clean(t: String) -> String:
	var s := RegEx.create_from_string("\\[/?[a-z]+(=[^\\]]*)?\\]").sub(t.replace("[lb]", "\u0001"), "", true)
	return s.replace("\u0001", "[").strip_edges()
