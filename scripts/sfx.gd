extends Node
## Ses efektleri (Kenney.nl CC0 ses paketleri, assets/sounds).
## Aynı sesin birden çok varyasyonu varsa rastgele biri çalınır.

const SOUND_DIR := "res://assets/sounds/"
const VARIANTS := {"throw": 2, "pickup": 3, "step": 4, "clash": 5, "hit": 5, "death": 5, "block": 5, "coin": 2}
const SINGLES := ["click", "select", "error", "powerup", "kill", "zone", "win", "lose", "unlock", "buy"]
## Seslerin temel ses seviyeleri (dB); dosyalar arasındaki farkı dengeler.
const BASE_DB := {"pickup": -14.0, "step": -16.0, "throw": -4.0, "clash": -6.0, "block": -6.0, "hit": -2.0,
	"death": 0.0, "click": -6.0, "select": -6.0, "powerup": -4.0, "kill": -2.0, "zone": -2.0}

var enabled := true
var streams := {}
var players: Array[AudioStreamPlayer] = []
var last_played := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for sound in VARIANTS:
		var list: Array[AudioStream] = []
		for i in VARIANTS[sound]:
			var path := SOUND_DIR + "%s_%d.ogg" % [sound, i + 1]
			if ResourceLoader.exists(path):
				list.append(load(path))
		streams[sound] = list
	for sound in SINGLES:
		var path: String = SOUND_DIR + sound + ".ogg"
		if ResourceLoader.exists(path):
			streams[sound] = [load(path)]


func play(sound: String, volume_db := 0.0, pitch_var := 0.08) -> void:
	if not enabled or not streams.has(sound) or (streams[sound] as Array).is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(last_played.get(sound, -1000)) < 35:
		return
	last_played[sound] = now
	for p in players:
		if not p.playing:
			p.stream = (streams[sound] as Array).pick_random()
			p.volume_db = volume_db + float(BASE_DB.get(sound, 0.0))
			p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
			p.play()
			return
