extends Node
## Speech — озвучка (автозагрузка).
## Английский: звук из Anki (mp3/ogg/wav в папке media), иначе встроенный голос Piper (папка voice: piper.exe и
## модель .onnx, без интернета; готовые фразы кэшируются в user://tts), иначе голос системы.
## Русский — только голосом системы, если он есть.
## Настройки: use_piper, voice_en, voice_ru (id голоса системы), rate (0.6…1.6), auto_speak, listen_ru.

signal playing_changed(on: bool)   ## началась/закончилась озвучка (для кнопок «Остановить»)

var _player := AudioStreamPlayer.new()
var _run := 0          # номер текущего прослушивания списка (новый — старый останавливается)
var _streams := {}     # имя файла → AudioStream (кэш)
var listing := false   # идёт «прослушать всё»


func _ready() -> void:
	add_child(_player)
	_find_piper()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_mutex.lock()
		_quit = true
		_mutex.unlock()
		_sem.post()
		_thread.wait_to_finish()


# ───────────────────────────── встроенный голос Piper

var _piper := {}           # {exe, model} — нашёлся
var _thread: Thread
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _queue: Array = []     # тексты на синтез (в начале — срочные)
var _quit := false
var _want := ""            # что озвучить, как только будет готово
var _failed := {}          # тексты, которые Piper не смог (не пытаться снова)


var last_error := ""        # почему встроенный голос не работает (для «Озвучка…» и сообщений)


## Папка voice: рядом с программой (собранная игра) или в проекте.
func _find_piper() -> void:
	_piper = {}
	var exe_name := "piper/piper.exe" if OS.get_name() == "Windows" else "piper-linux/piper"
	var dirs := [ProjectSettings.globalize_path("res://voice"), OS.get_executable_path().get_base_dir().path_join("voice")]
	var why: Array = []
	for d in dirs:
		if not DirAccess.dir_exists_absolute(d):
			why.append("нет папки %s" % d)
			continue
		var exe := str(d).path_join(exe_name)
		if not FileAccess.file_exists(exe):
			why.append("нет файла %s (антивирус мог убрать его в карантин)" % exe)
			continue
		var model := ""
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".onnx") and FileAccess.file_exists(str(d).path_join(f + ".json")):
				model = str(d).path_join(f)
		if model == "":
			why.append("в папке %s нет модели голоса (.onnx и .onnx.json)" % d)
			continue
		_piper = {"exe": exe, "model": model}
		last_error = ""
		return
	last_error = "Встроенный голос не найден: " + "; ".join(why)
	push_warning(last_error)


func piper_ok() -> bool:
	return not _piper.is_empty() and bool(Store.setting("use_piper", true))


func piper_found() -> bool:
	return not _piper.is_empty()


func _tts_key(text: String) -> String:
	return ("%s|%.2f|%s" % [str(_piper.get("model", "")).get_file(), float(Store.setting("rate", 1.0)), text]).md5_text()


func _wav_path(text: String) -> String:
	return "user://tts".path_join(_tts_key(text) + ".wav")


## Готовый звук фразы (или null — ещё нет).
func _cached(text: String) -> AudioStream:
	var p := _wav_path(text)
	if _streams.has(p):
		return _streams[p]
	if not FileAccess.file_exists(p):
		return null
	var s := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(p))
	if s:
		_streams[p] = s
	return s


## Озвучить английский голосом Piper: готово — сразу, нет — синтез в фоне и сыграть, как только будет.
func _piper_say(text: String) -> bool:
	if text == "" or _failed.has(text):
		return false
	var s := _cached(text)
	if s:
		_play(s)
		return true
	_want = text
	_enqueue([text], true)
	return true


## Заранее приготовить фразы (следующие карточки, «Прослушать»).
func prefetch(texts: Array) -> void:
	if not piper_ok():
		return
	var need: Array = []
	for t in texts:
		var c := clean(str(t))
		if c != "" and not FileAccess.file_exists(_wav_path(c)) and not _failed.has(c):
			need.append(c)
	_enqueue(need, false)


func _enqueue(texts: Array, urgent: bool) -> void:
	if texts.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tts"))
	if _thread == null:
		_thread = Thread.new()
		_thread.start(_worker)
	_mutex.lock()
	for t in texts:
		var job := {"text": t, "out": ProjectSettings.globalize_path(_wav_path(t)),
			"scale": 1.0 / clampf(float(Store.setting("rate", 1.0)), 0.5, 2.0)}
		if urgent:
			_queue.push_front(job)
		else:
			_queue.append(job)
	_mutex.unlock()
	for t in texts:
		_sem.post()


## Фоновый поток: по одной фразе запускает piper (текст — в stdin, звук — в файл).
func _worker() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		var quit := _quit
		var job: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_mutex.unlock()
		if quit:
			return
		if job.is_empty():
			continue
		var ok := FileAccess.file_exists(str(job["out"])) or _run_piper(str(job["text"]), str(job["out"]), float(job["scale"]))
		_on_synth.call_deferred(str(job["text"]), ok)


func _run_piper(text: String, out: String, scale: float) -> bool:
	if OS.get_name() == "Windows":
		return _run_piper_windows(text, out, scale)
	var tmp := out + ".part.wav"
	var args := ["--model", str(_piper["model"]), "--output_file", tmp, "--length_scale", "%.2f" % scale, "--quiet"]
	var p := OS.execute_with_pipe(str(_piper["exe"]), PackedStringArray(args), false)
	if p.is_empty():
		_set_error.call_deferred("Не удалось запустить %s" % _piper["exe"])
		return false
	var io: FileAccess = p["stdio"]
	io.store_buffer((text.replace("\n", " ") + "\n").to_utf8_buffer())
	io.close()   # конец ввода — piper начинает говорить
	var err: FileAccess = p.get("stderr")
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(int(p["pid"])) and Time.get_ticks_msec() - t0 < 20000:
		OS.delay_msec(10)
	if OS.is_process_running(int(p["pid"])):
		OS.kill(int(p["pid"]))
	if not FileAccess.file_exists(tmp) or FileAccess.get_file_as_bytes(tmp).size() <= 44:
		var msg := ""
		if err:
			msg = err.get_as_text().strip_edges().right(300)
		_set_error.call_deferred("Piper не сделал звук (код %d). %s" % [OS.get_process_exit_code(int(p["pid"])), msg])
		DirAccess.remove_absolute(tmp)
		if err:
			err.close()
		return false
	if err:
		err.close()
	DirAccess.remove_absolute(out)
	return DirAccess.rename_absolute(tmp, out) == OK


## Windows: piper.exe не открывает файлы, если в пути есть не латинские буквы (C:\Users\Имя\…) —
## поэтому запускаем его из его папки (cmd: cd) и даём только короткие относительные имена: модель, словари
## espeak, текст и звук — в voice\cache. Готовый звук переносим в кэш словаря.
func _run_piper_windows(text: String, out: String, scale: float) -> bool:
	var voice := str(_piper["exe"]).get_base_dir().get_base_dir()   # …\voice
	var cache := voice.path_join("cache")
	DirAccess.make_dir_recursive_absolute(cache)
	var key := out.get_file().get_basename()
	var txt := cache.path_join(key + ".txt")
	var wav := cache.path_join(key + ".wav")
	var f := FileAccess.open(txt, FileAccess.WRITE)
	if f == null:
		_set_error.call_deferred("Нельзя писать в папку %s (нужна для озвучки)" % cache)
		return false
	f.store_string(text.replace("\n", " ") + "\n")
	f.close()
	var line := "cd /d %s && piper\\piper.exe --model %s --espeak_data piper\\espeak-ng-data --length_scale %.2f --quiet --output_file cache\\%s.wav < cache\\%s.txt" \
		% [voice.replace("/", "\\"), str(_piper["model"]).get_file(), scale, key, key]
	var output: Array = []
	var code := OS.execute("cmd.exe", PackedStringArray(["/d", "/s", "/c", line]), output, true)
	DirAccess.remove_absolute(txt)
	if not FileAccess.file_exists(wav) or FileAccess.get_file_as_bytes(wav).size() <= 44:
		var msg := " ".join(PackedStringArray(output)).strip_edges().right(300)
		_set_error.call_deferred("Piper не сделал звук (код %d). %s" % [code, msg])
		DirAccess.remove_absolute(wav)
		return false
	DirAccess.remove_absolute(out)
	var ok := DirAccess.rename_absolute(wav, out) == OK
	if not ok:   # другой диск — копировать
		ok = DirAccess.copy_absolute(wav, out) == OK
		DirAccess.remove_absolute(wav)
	return ok


func _set_error(msg: String) -> void:
	last_error = msg
	push_warning(msg)


func _on_synth(text: String, ok: bool) -> void:
	if not ok:
		_failed[text] = true
		if _want == text:
			_want = ""
			if not say_system(text, "en"):   # Piper не справился — хоть голосом системы
				var m := get_tree().get_first_node_in_group("main")
				if m:
					m.call("toast", "Озвучка не удалась: " + last_error.left(160), 6.0)
		return
	if _want == text:
		_want = ""
		var s := _cached(text)
		if s:
			_play(s)


func _play(s: AudioStream) -> void:
	if tts_supported():
		DisplayServer.tts_stop()
	_player.stream = s
	_player.pitch_scale = 1.0
	_player.play()


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
	if lang == "en" and piper_ok():
		return true
	return voice_id(lang) != ""


## Сказать текст: английский — Piper (если есть), иначе голос системы. false — нечем.
func say(text: String, lang := "en") -> bool:
	if lang == "en" and piper_ok():
		_player.stop()
		return _piper_say(clean(text))
	return say_system(text, lang)


func say_system(text: String, lang := "en") -> bool:
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
		_want = ""
		_play(s)
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
	return _want != "" or _player.playing or (tts_supported() and DisplayServer.tts_is_speaking())


func stop() -> void:
	_run += 1
	_want = ""
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
	var texts: Array = []
	for e in entries:
		if Store.media_path(str(e.get("audio", ""))) == "":
			texts.append(str(e.get("en", "")))
	prefetch(texts)
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
	while run == _run and not is_speaking() and t < 0.5:
		await get_tree().process_frame
		t += get_process_delta_time()
	t = 0.0
	while run == _run and is_speaking() and t < 40.0:
		await get_tree().process_frame
		t += get_process_delta_time()


## Текст для голоса: без [b] и прочей разметки.
static func clean(t: String) -> String:
	var s := RegEx.create_from_string("\\[/?[a-z]+(=[^\\]]*)?\\]").sub(t.replace("[lb]", "\u0001"), "", true)
	return s.replace("\u0001", "[").strip_edges()
