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


func _db(v: float) -> float:
	return linear_to_db(max(0.0001, v))


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
