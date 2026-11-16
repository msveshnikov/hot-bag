extends Node
## Sounds, loops and music (all procedurally generated WAVs in assets/audio). Autoload "Sfx".

const ONE_SHOTS = ["ui", "bell", "coin", "notify", "accept", "fail", "knock", "intercom", "crash", "whistle", "splash",
	"step", "pickup", "deliver", "phone_open", "ring", "fall", "lock", "brake", "level_up", "tram_bell", "horn"]
const LOOPS = ["motor_loop", "pedal_loop", "city_loop", "rain_loop", "birds_loop"]

var streams = {}
var players: Array[AudioStreamPlayer] = []
var loops = {}
var music: AudioStreamPlayer
var music_name = ""
var voice: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in ONE_SHOTS + LOOPS + ["music_day", "music_night", "music_menu"]:
		var s = load("res://assets/audio/%s.wav" % n)
		if s:
			streams[n] = s
	for i in 10:
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for n in LOOPS:
		if not streams.has(n):
			continue
		var s: AudioStreamWAV = streams[n].duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2
		var p = AudioStreamPlayer.new()
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		loops[n] = p
	music = AudioStreamPlayer.new()
	add_child(music)
	voice = AudioStreamPlayer.new()
	add_child(voice)


func _db(v: float) -> float:
	return linear_to_db(max(0.0001, v))


## Voice key of a line: only its letters, lower case (digits, numbers and punctuation filled in by the game are
## dropped, so "%d монет" in the code and "1000 монет" on screen give the same key). Same rule in
## tools/voice_lines.py, which writes assets/audio/voice/<speaker>/<key>.mp3 with ElevenLabs.
static func voice_key(text: String) -> String:
	var out = ""
	for ch in text.to_lower():
		var c = ch.unicode_at(0)
		if (c >= 0x61 and c <= 0x7a) or (c >= 0x430 and c <= 0x44f) or c == 0x451:
			out += ch
	return out.md5_text().substr(0, 12)


## Speak a line if a recorded voice exists for it (Михалыч is voiced; others stay silent).
func say(speaker: String, text: String) -> void:
	var path = "res://assets/audio/voice/%s/%s.mp3" % [speaker, voice_key(text)]
	if not ResourceLoader.exists(path):
		return
	voice.stop()
	voice.stream = load(path)
	voice.volume_db = _db(1.1 * float(Game.settings.get("voice", 1.0)) * max(0.35, float(Game.settings["sfx"])))
	voice.play()


func stop_voice() -> void:
	if voice:
		voice.stop()


func play(name: String, vol = 1.0, pitch = 1.0) -> void:
	if not streams.has(name):
		return
	for p in players:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = _db(vol * float(Game.settings["sfx"]))
			p.pitch_scale = pitch
			p.play()
			return


## Loop volume 0 stops it.
func set_loop(name: String, vol: float, pitch = 1.0) -> void:
	var p: AudioStreamPlayer = loops.get(name)
	if p == null:
		return
	var v = vol * float(Game.settings["sfx"])
	if v <= 0.001:
		if p.playing:
			p.stop()
		return
	p.volume_db = _db(v)
	p.pitch_scale = clamp(pitch, 0.3, 3.0)
	if not p.playing:
		p.play()


func stop_loops() -> void:
	for p in loops.values():
		p.stop()


func play_music(name: String) -> void:
	if float(Game.settings["music"]) <= 0.001:
		music_name = name
		music.stop()
		return
	if name == music_name and music.playing:
		music.volume_db = _db(0.5 * float(Game.settings["music"]))
		return
	music_name = name
	if not streams.has(name):
		music.stop()
		return
	var s: AudioStreamWAV = streams[name].duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = s.data.size() / 2
	music.stream = s
	music.volume_db = _db(0.5 * float(Game.settings["music"]))
	music.play()


func refresh_volume() -> void:
	if float(Game.settings["music"]) <= 0.001:
		music.stop()
		return
	music.volume_db = _db(0.5 * float(Game.settings["music"]))
	if not music.playing and music_name != "":
		var n = music_name
		music_name = ""
		play_music(n)
