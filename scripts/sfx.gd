extends Node
## Ses efektleri (Kenney.nl CC0 ses paketleri, assets/sounds).
## Aynı sesin birden çok varyasyonu varsa rastgele biri çalınır.

const SOUND_DIR := "res://assets/sounds/"
const VARIANTS := {"throw": 4, "pickup": 3, "step": 4, "clash": 5, "hit": 5, "death": 5, "block": 4, "coin": 2}
const SINGLES := ["click", "select", "error", "powerup", "kill", "zone", "win", "lose", "unlock", "buy"]
## Seslerin temel ses seviyeleri (dB); dosyalar arasındaki farkı dengeler.
## Sık çalan sesler (adım, bıçak çarpışması, toplama) kulağı yormasın diye kısık.
const BASE_DB := {"pickup": -17.0, "step": -21.0, "throw": -9.0, "clash": -13.0, "block": -11.0, "hit": -7.0,
	"death": -5.0, "click": -7.0, "select": -9.0, "powerup": -5.0, "kill": -4.0, "zone": -4.0, "coin": -6.0,
	"win": -3.0, "lose": -5.0, "unlock": -3.0, "buy": -4.0, "error": -8.0}
## Aynı sesin tekrar çalınabilmesi için gereken süre (ms): üst üste binen sesler cızırtı gibi duyulur.
const MIN_GAP := {"clash": 90, "pickup": 70, "step": 120, "hit": 60, "block": 90, "coin": 60}
## Aynı anda en fazla kaç kopyası çalabilir.
const MAX_SAME := 3

var enabled := true
var streams := {}
var players: Array[AudioStreamPlayer] = []
var last_played := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Not: web'de "sample" oynatma telefonlarda sesi tamamen kesti; proje ayarındaki "stream" kullanılır.
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for sound in VARIANTS:
		var list: Array[AudioStream] = []
		for i in VARIANTS[sound]:
			var s := _load_sound("%s_%d" % [sound, i + 1])
			if s != null:
				list.append(s)
		streams[sound] = list
	for sound in SINGLES:
		var s := _load_sound(sound)
		if s != null:
			streams[sound] = [s]


## Ses dosyasını .ogg ya da .wav olarak yükler (hangisi varsa).
func _load_sound(base: String) -> AudioStream:
	for ext in [".ogg", ".wav"]:
		var path: String = SOUND_DIR + base + ext
		if ResourceLoader.exists(path):
			return load(path)
	return null


func play(sound: String, volume_db := 0.0, pitch_var := 0.05) -> void:
	if not enabled or not streams.has(sound) or (streams[sound] as Array).is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(last_played.get(sound, -1000)) < int(MIN_GAP.get(sound, 40)):
		return
	var list: Array = streams[sound]
	var same := 0
	for p in players:
		if p.playing and p.stream in list:
			same += 1
	if same >= MAX_SAME:
		return
	last_played[sound] = now
	for p in players:
		if not p.playing:
			p.stream = list.pick_random()
			p.volume_db = volume_db + float(BASE_DB.get(sound, 0.0))
			p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
			p.play()
			return
