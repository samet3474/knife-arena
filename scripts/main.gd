extends Node2D
## Oyun yöneticisi: arena, botlar, bıçaklar, güçlendirmeler, çarpışmalar, daralan alan,
## efektler, menü/tur akışı, kayıt ve çok oyunculu mod.
##
## Üç çalışma modu vardır (net_mode):
##   ""       : tek oyunculu; simülasyon ve görüntü bu cihazda.
##   "server" : ekransız sunucu (--server); simülasyonu yürütür, anlık görüntü yayınlar.
##   "client" : çok oyunculu istemci; girdi gönderir, sunucudan gelen dünyayı çizer.
## Simülasyon, görsel/işitsel sonuçları _emit() ile "olay" olarak bildirir. Tek oyunculuda
## olay hemen _present() ile oynatılır; sunucuda biriktirilip istemcilere gönderilir.

const HUD_SCRIPT := preload("res://scripts/hud.gd")
const SFX_SCRIPT := preload("res://scripts/sfx.gd")
const NET_SCRIPT := preload("res://scripts/net.gd")
const WEB_SCRIPT := preload("res://scripts/web_server.gd")

const SAVE_PATH := "user://save.cfg"
const ARENA_RADIUS := 1800.0
const ZONE_MIN_RADIUS := 380.0
const ZONE_DELAY := 25.0
const ZONE_DURATION := 150.0
const ZONE_DPS := 12.0
const BOT_COUNT := 11
const PICKUP_TARGET := 150
const PICKUP_RADIUS := 42.0
const POWERUP_MAX := 6
const POWERUP_RADIUS := 46.0
const START_KNIVES := 4
const THROW_SPEED := 1150.0
const THROW_LIFE := 0.8
const THROW_DAMAGE := 22.0
const THROW_COOLDOWN := 0.3
const AIM_ASSIST_RANGE := 750.0
const AIM_ASSIST_ANGLE := 0.6
const HEARING_RANGE := 1100.0
const FX_RANGE := 1400.0
const AIM_RANGE := 650.0
const CRATE_TARGET := 22
const CRATE_SIZE := 52.0
const CRATE_HP := 3
const BUSH_COUNT := 14
const BUSH_REVEAL := 160.0
const SNAPSHOT_RATE := 20.0
const INPUT_RATE := 30.0
const MP_MIN_FIGHTERS := 10
const CONNECT_TIMEOUT := 8.0
const BOT_NAMES := [
	"Battal", "Alp", "Hançer", "Bıçkın", "Keskin", "Satır", "Bora", "Pala", "Şimşek",
	"Kasırga", "Gölge", "Yıldırım", "Kartal", "Tilki", "Tunç", "Çelik", "Kaya", "Efe",
]
const POWERUP_TYPES := ["speed", "shield", "heal", "magnet", "knives"]

var fighters: Array[Fighter] = []
var fighter_by_id := {}
var next_net_id := 1
var player: Fighter = null
var pickups: Array[Dictionary] = []
var powerups: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var kill_feed: Array[Dictionary] = []
var crates: Array[Dictionary] = []
var bushes: Array[Dictionary] = []
var hazards: Array[Dictionary] = [] # bombalar ve zehir bulutları
var coins_pickups: Array[Dictionary] = []
var player_target: Fighter = null
var cooldowns := {}
var zone_radius := ARENA_RADIUS
var zone_announced := false
var round_time := 0.0
var state := "menu" # splash | menu | connecting | playing | paused | over | won | server
var state_time := 0.0
var final_rank := 0
var unlock_message := ""
var shake := 0.0
var step_timer := 0.0
var next_event_time := 45.0
var boxes_opened := 0
var level_ups: Array[int] = [] # son maçta atlanan seviyeler (sonuç ekranı için)
var match_coins := 0
var last_reward := {}
var daily_message := ""
var save := {"skin_id": "skin_keloglan", "knife_id": "knife_steel", "total_kills": 0, "wins": 0,
	"best_rank": 0, "games": 0, "sound": true, "lang": "", "auto_aim": true,
	"coins": GameData.STARTING_COINS, "owned": [], "player_name": "", "last_daily": "",
	"level": 1, "xp": 0, "mp_host": ""}

# Çok oyunculu
var net_mode := ""
var net # net.gd örneği
var events: Array = [] # sunucu: son anlık görüntüden beri biriken olaylar
var snapshot_timer := 0.0
var input_timer := 0.0
var my_net_id := 0
var peers := {} # sunucu: bağlantı → savaşçı net_id
var dead_since := {} # sunucu: net_id → ölüm zamanı (cesetleri temizlemek için)
var bot_spawn_timer := 0.0
var server_urls: Array[String] = [] # sunucu penceresinde gösterilen telefon adresleri
var hud_timer := 0.0
var cooldown_prune_timer := 0.0
# Yönetim paneli
var bot_target := MP_MIN_FIGHTERS - 1
var server_log: Array[Dictionary] = []
var peer_info := {} # bağlantı → {"name", "ip", "since", "info"}
var total_joins := 0
var admin_peers := {} # sunucu: girişli yönetici bağlantıları
var admin_timer := 0.0
var admin_view := {} # istemci: sunucudan gelen panel verisi
var admin_pending := "" # istemci: bağlanınca gönderilecek yönetici şifresi
## Telefonda (özellikle tarayıcıda) efekt yoğunluğu ve zemin detayı azaltılır.
var low_fx := false
## Kameranın gördüğü dünya alanı; dışındaki nesneler çizilmez.
var view_rect := Rect2(-2000, -2000, 4000, 4000)
var canopy_dirty := true
## Performans ölçümü (--perf / web'de ?perf): her 2 saniyede konsola süre ve çizim istatistikleri.
var perf_log := false
var perf_timer := 0.0
static var perf_acc := {} # bölüm adı → toplam mikro saniye (2 saniyelik pencere)


## Ölçüm: perf_mark("ad", baslangic_usec) bölüm süresini biriktirir.
static func perf_mark(section: String, start_usec: int) -> void:
	if not perf_on:
		return
	perf_acc[section] = int(perf_acc.get(section, 0)) + Time.get_ticks_usec() - start_usec


static var perf_on := false

var camera: Camera2D
var ground: Node2D
var zone_layer: Node2D
var items: Node2D
var fx_low: Node2D
var fighter_layer: Node2D
var canopy: Node2D
var fx: Node2D
var hud # hud.gd örneği
var sfx # sfx.gd örneği


func _ready() -> void:
	randomize()
	var args := OS.get_cmdline_user_args()
	# Web sürümünde test seçenekleri adres çubuğundan verilebilir: ?autostart&lowfx
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			for part in String(q).trim_prefix("?").split("&", false):
				args.append("--" + part.replace("lowfx", "low-fx"))
	if "--server" in args:
		net_mode = "server"
	low_fx = OS.has_feature("web_ios") or OS.has_feature("web_android") or OS.has_feature("mobile") or "--low-fx" in args
	Fighter.low_fx = low_fx
	perf_log = "--perf" in args
	perf_on = perf_log
	GameData.use_disc = not "--nodisc" in args
	var _t0 := Time.get_ticks_msec()
	_load_save()
	if net_mode != "server":
		_check_daily_bonus()
	Loc.lang = save["lang"] if save["lang"] != "" else Loc.detect()
	RenderingServer.set_default_clear_color(Color(0.08, 0.11, 0.1))

	ground = _layer(_draw_ground)
	if net_mode != "server":
		_bake_ground()
	zone_layer = _layer(_draw_zone)
	items = _layer(_draw_items)
	fx_low = _layer(_draw_fx_low)
	fighter_layer = Node2D.new()
	add_child(fighter_layer)
	canopy = _layer(_draw_canopy)
	fx = _layer(_draw_fx)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	add_child(camera)
	camera.make_current()
	_startup_log("katmanlar+zemin", _t0)
	_t0 = Time.get_ticks_msec()
	sfx = SFX_SCRIPT.new()
	add_child(sfx)
	_startup_log("sesler", _t0)
	_t0 = Time.get_ticks_msec()
	sfx.enabled = save["sound"] and net_mode != "server"
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD_SCRIPT.new()
	hud.main = self
	layer.add_child(hud)

	net = NET_SCRIPT.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.connected.connect(_on_net_connected)
	net.connection_failed.connect(_on_net_failed)
	net.disconnected.connect(_on_net_failed)

	if net_mode == "server":
		_start_server(args)
		_screenshot_from_args(args)
		if "--admin-test" in args:
			_admin_self_test()
		return

	if daily_message != "":
		hud.flash_banner(daily_message, Color(1, 0.85, 0.3), 4.0)
	_startup_log("arayüz+ağ", _t0)
	_t0 = Time.get_ticks_msec()
	_start_round("--autostart" in args)
	_startup_log("dünya kurulumu", _t0)
	# Logolu açılış ekranını motor gösteriyor; ikinci bir açılış ekranı yok, doğrudan menü.
	# (Eski açılış ekranı --splash ile hâlâ görülebilir.)
	if state == "menu" and "--splash" in args:
		state = "splash"
	_apply_test_args(args)


func _startup_log(part: String, start_ms: int) -> void:
	if perf_log:
		print("STARTUP %s: %d ms (motor saati %d ms)" % [part, Time.get_ticks_msec() - start_ms, Time.get_ticks_msec()])


## Geliştirme/test için komut satırı seçenekleri.
func _apply_test_args(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--tab="):
			hud.tab = a.trim_prefix("--tab=")
		if a.begins_with("--knife=") and player != null:
			player.knife_kind = a.trim_prefix("--knife=").to_int()
			player.knives = 16
		if a.begins_with("--host="):
			save["mp_host"] = a.trim_prefix("--host=")
	if "--fragile" in args and player != null:
		player.hp = 1.0
		player.since_hit = -999.0
	if "--dummy" in args and player != null:
		var d := _spawn_bot("Test")
		d.position = player.position + Vector2(320, -60)
		d.knife_kind = 3
		d.knives = 8
	if "--mp" in args:
		on_button("mp")
	for a in args:
		if a.begins_with("--popup="):
			var which := a.trim_prefix("--popup=")
			if which == "settings":
				hud.popup = "settings"
			else:
				hud.open_shop(which)
	if "--scoreboard" in args:
		hud.scoreboard_open = true
	for a in args:
		if a.begins_with("--admin-login="):
			admin_connect(a.trim_prefix("--admin-login="))
	_screenshot_from_args(args)


## --screenshot=<dosya> verilirse (--shot-delay=<sn>, varsayılan 4) sonra ekran görüntüsü alıp kapanır.
func _screenshot_from_args(args: PackedStringArray) -> void:
	var delay := 4.0
	for a in args:
		if a.begins_with("--shot-delay="):
			delay = a.trim_prefix("--shot-delay=").to_float()
	for a in args:
		if a.begins_with("--screenshot="):
			await get_tree().create_timer(delay).timeout
			get_viewport().get_texture().get_image().save_png(a.trim_prefix("--screenshot="))
			get_tree().quit()


func _layer(draw_func: Callable) -> Node2D:
	var n := Node2D.new()
	add_child(n)
	n.draw.connect(draw_func)
	return n


# --- Kayıt -------------------------------------------------------------------

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k in save.keys():
		save[k] = cfg.get_value("player", k, save[k])


func _write_save() -> void:
	if net_mode == "server":
		return
	var cfg := ConfigFile.new()
	for k in save.keys():
		cfg.set_value("player", k, save[k])
	cfg.save(SAVE_PATH)


## Karakter veya bıçak sahibi olunmuş mu? (fiyatı 0 olanlar baştan açık)
func skin_unlocked(item: Dictionary) -> bool:
	return int(item["price"]) == 0 or (item["id"] in save["owned"])


func selected_skin() -> Dictionary:
	return GameData.SKINS[GameData.skin_index(save["skin_id"])]


## Oyunda kullanılacak karakter: seçili karakter alınmamışsa ilk ücretsiz karakter.
func playable_skin() -> Dictionary:
	var skin := selected_skin()
	return skin if skin_unlocked(skin) else GameData.SKINS[0]


## Menüde önizlenen bıçak (satın alınmamış olabilir).
func preview_knife() -> int:
	return GameData.knife_index(save["knife_id"])


## Oyunda kullanılacak bıçak: seçili bıçak alınmamışsa çelik bıçak.
func selected_knife() -> int:
	var k := preview_knife()
	return k if skin_unlocked(GameData.KNIVES[k]) else 0


## Menüde seçili olup henüz alınmamış ilk öğe (önce karakter, sonra bıçak); yoksa boş.
func pending_purchase() -> Dictionary:
	if not skin_unlocked(selected_skin()):
		return selected_skin()
	var knife: Dictionary = GameData.KNIVES[preview_knife()]
	if not skin_unlocked(knife):
		return knife
	return {}


func level_ok(item: Dictionary) -> bool:
	return int(save["level"]) >= int(item.get("level", 1))


func _buy(item: Dictionary) -> bool:
	var price := int(item["price"])
	if int(save["coins"]) < price or not level_ok(item):
		sfx.play("error", 0.0, 0.0)
		return false
	save["coins"] = int(save["coins"]) - price
	var owned: Array = save["owned"]
	owned.append(item["id"])
	save["owned"] = owned
	_write_save()
	sfx.play("buy", 0.0, 0.0)
	hud.flash_banner(Loc.t("bought"))
	return true


## Koleksiyondaki SEÇ / SATIN AL: sahip olunan öğeyi kullanır, olunmayanı satın alıp kullanır.
func equip_or_buy(id: String) -> void:
	var is_skin := id.begins_with("skin_")
	var item: Dictionary = GameData.SKINS[GameData.skin_index(id)] if is_skin else GameData.KNIVES[GameData.knife_index(id)]
	if not skin_unlocked(item) and not _buy(item):
		return
	save["skin_id" if is_skin else "knife_id"] = id
	_write_save()
	sfx.play("select", 0.0, 0.0)


func player_name() -> String:
	var n := String(save["player_name"]).strip_edges()
	return n if n != "" else Loc.t("default_name") + str(randi_range(1000, 9999))


func _check_daily_bonus() -> void:
	var today := Time.get_date_string_from_system()
	if save["last_daily"] == today:
		return
	save["last_daily"] = today
	save["coins"] = int(save["coins"]) + GameData.DAILY_BONUS
	_write_save()
	daily_message = Loc.t("daily") % GameData.DAILY_BONUS


# --- Tur akışı ---------------------------------------------------------------

## Dünyayı boşaltır (savaşçılar, eşyalar, efektler).
func _clear_world() -> void:
	Engine.time_scale = 1.0
	for f in fighters:
		f.queue_free()
	if player != null and is_instance_valid(player) and not player in fighters:
		player.queue_free()
	fighters.clear()
	fighter_by_id.clear()
	pickups.clear()
	powerups.clear()
	projectiles.clear()
	particles.clear()
	kill_feed.clear()
	crates.clear()
	bushes.clear()
	coins_pickups.clear()
	hazards.clear()
	cooldowns.clear()
	events.clear()
	dead_since.clear()
	player = null
	player_target = null
	zone_radius = ARENA_RADIUS
	zone_announced = false
	shake = 0.0
	_reset_match_stats()


## Oyuncunun bu maça ait sayaçları (her doğuşta sıfırlanır).
func _reset_match_stats() -> void:
	match_coins = 0
	boxes_opened = 0
	level_ups.clear()
	round_time = 0.0
	state_time = 0.0
	final_rank = 0
	unlock_message = ""
	next_event_time = randf_range(40.0, 50.0)


## Yeni bir arena kurar: çalılar, kutular, yerdeki bıçaklar ve güçlendirmeler.
func _build_world() -> void:
	_spawn_bushes()
	canopy_dirty = true
	while crates.size() < CRATE_TARGET:
		_spawn_crate()
	while pickups.size() < _pickup_target():
		_spawn_pickup(_random_point(ARENA_RADIUS - 60.0), Vector2.ZERO)
	for i in POWERUP_MAX / 2:
		_spawn_powerup()


func _start_round(with_player: bool) -> void:
	_clear_world()
	_build_world()
	if with_player:
		var skin := playable_skin()
		player = _spawn_fighter(player_name(), skin["id"], skin["color"], true)
		player.knife_kind = selected_knife()
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	for i in BOT_COUNT:
		_spawn_bot(names[i % names.size()])
	state = "playing" if with_player else "menu"
	if player != null:
		camera.position = player.position
		camera.reset_smoothing()


func _end_round(won: bool) -> void:
	state = "won" if won else "over"
	state_time = 0.0
	save["games"] = int(save["games"]) + 1
	save["total_kills"] = int(save["total_kills"]) + player.kills
	if won:
		save["wins"] = int(save["wins"]) + 1
	var rank := 1 if won else final_rank
	if int(save["best_rank"]) == 0 or rank < int(save["best_rank"]):
		save["best_rank"] = rank
	# Altın ödülü: toplanan + leş + sıralama + hayatta kalma süresi
	var rank_bonus: int = GameData.RANK_BONUS[rank - 1] if rank <= GameData.RANK_BONUS.size() else GameData.RANK_BONUS_REST
	last_reward = {
		"collected": match_coins,
		"kills": player.kills * GameData.COIN_PER_KILL,
		"rank": rank_bonus,
		"time": int(round_time / 20.0),
	}
	var total := 0
	for v in last_reward.values():
		total += int(v)
	last_reward["total"] = total
	save["coins"] = int(save["coins"]) + total

	# XP ve seviye: leş + sıralama + açılan kutular + hayatta kalma süresi
	var xp_rank: int = GameData.XP_RANK[rank - 1] if rank <= GameData.XP_RANK.size() else GameData.XP_RANK_REST
	var xp_gain := player.kills * GameData.XP_PER_KILL + xp_rank + boxes_opened * GameData.XP_PER_BOX + int(round_time / 10.0)
	last_reward["xp"] = xp_gain
	last_reward["level_before"] = int(save["level"])
	last_reward["xp_before"] = int(save["xp"])
	var xp := int(save["xp"]) + xp_gain
	var lvl := int(save["level"])
	var level_coins := 0
	while lvl < GameData.MAX_LEVEL and xp >= GameData.xp_needed(lvl):
		xp -= GameData.xp_needed(lvl)
		lvl += 1
		level_ups.append(lvl)
		level_coins += GameData.level_reward(lvl)
	save["xp"] = xp
	save["level"] = lvl
	save["coins"] = int(save["coins"]) + level_coins
	last_reward["level_coins"] = level_coins
	_write_save()
	sfx.play("win" if won else "lose", 0.0, 0.0)
	get_tree().create_timer(1.2).timeout.connect(func() -> void: sfx.play("coin", 0.0, 0.0))
	if not level_ups.is_empty():
		get_tree().create_timer(2.2).timeout.connect(func() -> void: sfx.play("unlock", 0.0, 0.0))


func on_button(id: String) -> void:
	if OS.is_debug_build() and "--log-buttons" in OS.get_cmdline_user_args():
		print("BUTTON %s state=%s t=%.2f" % [id, state, state_time])
	match id:
		"splash":
			state = "menu"
			sfx.play("select", 0.0, 0.0)
			return
		"dash":
			player_dash()
			return
		"play":
			sfx.play("click", 0.0, 0.0)
			_start_round(true)
			return
		"mp":
			sfx.play("click", 0.0, 0.0)
			_mp_connect()
			return
		"sound":
			save["sound"] = not save["sound"]
			sfx.enabled = save["sound"]
			_write_save()
		"lang":
			Loc.lang = "en" if Loc.lang == "tr" else "tr"
			save["lang"] = Loc.lang
			_write_save()
		"aim":
			save["auto_aim"] = not save["auto_aim"]
			_write_save()
		"fullscreen":
			_toggle_fullscreen()
		"admin_open":
			state = "admin_login"
		_ when id.begins_with("adm_") and net_mode == "server":
			_admin(id)
			hud.queue_redraw()
			return
		_ when id.begins_with("adm_") and state == "admin":
			net.c_admin_cmd.rpc_id(1, id)
			sfx.play("click", 0.0, 0.0)
			return
		"pause":
			if state == "playing" and net_mode == "":
				state = "paused"
		"resume":
			if state == "paused":
				state = "playing"
		"retry":
			if net_mode == "client":
				_mp_respawn()
			else:
				_start_round(true)
		"menu":
			_leave_multiplayer()
			_start_round(false)
		_:
			if id.begins_with("skin_"):
				save["skin_id"] = id
				_write_save()
				sfx.play("select", 0.0, 0.0)
				return
			if id.begins_with("knife_"):
				save["knife_id"] = id
				_write_save()
				sfx.play("select", 0.0, 0.0)
				return
	sfx.play("click", 0.0, 0.0)


## iPhone Safari web sayfalarına tam ekran izni vermez; orada "Ana Ekrana Ekle" yolu anlatılır.
func _toggle_fullscreen() -> void:
	if OS.has_feature("web_ios"):
		hud.flash_banner(Loc.t("ios_fullscreen"), Color(1, 0.85, 0.3), 7.0)
		return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func cycle_skin(step: int) -> void:
	var list := GameData.available_skins().filter(func(sk: Dictionary) -> bool: return skin_unlocked(sk))
	var i := 0
	for j in list.size():
		if list[j]["id"] == save["skin_id"]:
			i = j
	on_button(list[wrapi(i + step, 0, list.size())]["id"])


func _notification(what: int) -> void:
	# Telefonda uygulamadan çıkılınca oyunu duraklat (çok oyunculuda dünya durmaz)
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and net_mode == "":
		state = "paused"


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SHIFT:
			if state == "playing":
				player_dash()
		KEY_TAB:
			if state == "playing":
				hud.scoreboard_open = not hud.scoreboard_open
		KEY_SPACE, KEY_ENTER:
			if state == "splash":
				on_button("splash")
			elif state == "menu":
				on_button("play")
			elif state in ["over", "won"] and state_time > 0.8:
				on_button("retry")
			elif state == "paused":
				on_button("resume")
		KEY_ESCAPE, KEY_P:
			if state == "playing":
				on_button("pause")
			elif state == "paused":
				on_button("resume")
		KEY_LEFT, KEY_A:
			if state == "menu":
				cycle_skin(-1)
		KEY_RIGHT, KEY_D:
			if state == "menu":
				cycle_skin(1)


func _spawn_fighter(fname: String, skin_id: String, col: Color, is_player: bool) -> Fighter:
	var f := Fighter.new()
	f.net_id = next_net_id
	next_net_id += 1
	f.display_name = fname
	f.skin_id = skin_id
	f.color = col
	f.is_player = is_player
	f.knives = START_KNIVES
	f.face_dir = int(GameData.SKINS[GameData.skin_index(skin_id)]["face"])
	f.level = int(save["level"]) if is_player else clampi(int(save["level"]) + randi_range(-3, 6), 1, GameData.MAX_LEVEL)
	f.aggression = randf_range(0.3, 1.0)
	f.wander_dir = Vector2.from_angle(randf() * TAU)
	f.position = _free_spawn_point()
	fighter_layer.add_child(f)
	fighters.append(f)
	fighter_by_id[f.net_id] = f
	return f


func _spawn_bot(fname: String) -> Fighter:
	var skin: Dictionary = GameData.available_skins().pick_random()
	var f := _spawn_fighter(fname, skin["id"], Color.from_hsv(randf(), 0.6, 0.95), false)
	# Botların yarısı çelik, diğerleri rastgele efektli bıçak taşır
	f.knife_kind = 0 if randf() < 0.45 else randi_range(1, GameData.KNIVES.size() - 1)
	return f


func _spawn_bushes() -> void:
	for i in BUSH_COUNT:
		var center := _random_point(ARENA_RADIUS - 220.0)
		var blobs: Array[Vector3] = [] # x, y, yarıçap
		var radius := randf_range(70.0, 110.0)
		for k in randi_range(4, 6):
			var off := Vector2.from_angle(randf() * TAU) * randf_range(0.0, radius * 0.55)
			blobs.append(Vector3(off.x, off.y, randf_range(radius * 0.45, radius * 0.7)))
		bushes.append({"pos": center, "r": radius, "blobs": blobs, "fade": 1.0})


func _spawn_crate() -> void:
	for attempt in 10:
		var p := _random_point(minf(zone_radius, ARENA_RADIUS) - 120.0)
		var ok := true
		for f in fighters:
			if f.alive and p.distance_to(f.position) < 160.0:
				ok = false
		for c in crates:
			if p.distance_to(c["pos"]) < 140.0:
				ok = false
		if ok:
			crates.append({"pos": p, "hp": CRATE_HP, "shake": 0.0, "rot": randf_range(-0.15, 0.15)})
			return


func _free_spawn_point() -> Vector2:
	var best := Vector2.ZERO
	var best_d := -1.0
	for attempt in 12:
		var p := _random_point(zone_radius - 150.0)
		var nearest := INF
		for f in fighters:
			if f.alive:
				nearest = minf(nearest, p.distance_to(f.position))
		if nearest > best_d:
			best_d = nearest
			best = p
	return best


## Telefonda yerde daha az bıçak (simülasyon ve çizim yükü azalır).
func _pickup_target() -> int:
	return 110 if low_fx else PICKUP_TARGET


func _random_point(radius: float) -> Vector2:
	return Vector2.from_angle(randf() * TAU) * sqrt(randf()) * radius


func _spawn_pickup(pos: Vector2, vel: Vector2) -> void:
	pickups.append({"pos": pos, "vel": vel, "rot": randf() * TAU, "phase": randf() * 10.0})


func _spawn_powerup() -> void:
	powerups.append({
		"pos": _random_point(zone_radius - 120.0),
		"type": GameData.POWERUPS.keys().pick_random(),
		"phase": randf() * TAU,
	})


func _fid(id: Variant) -> Fighter:
	return fighter_by_id.get(int(id)) as Fighter


func _is_human(f: Fighter) -> bool:
	return f != null and (f.is_player or f.peer_id != 0)


# --- Ana döngü ---------------------------------------------------------------

var _first_frame_logged := false


func _process(delta: float) -> void:
	if perf_log and not _first_frame_logged:
		_first_frame_logged = true
		print("STARTUP ilk kare: motor açıldıktan %d ms sonra" % Time.get_ticks_msec())
	match net_mode:
		"server":
			# Sunucu penceresi yalnızca bilgi gösterir: saniyede iki kez yenilemek yeter
			hud_timer -= delta
			if hud_timer <= 0.0:
				hud_timer = 0.5
				hud.queue_redraw()
			_server_process(delta)
			return
	hud.tick(delta)
	if perf_log:
		_perf_report(delta)
	match net_mode:
		"client":
			_client_process(delta)
			return
	if state == "paused":
		return
	delta = minf(delta, 0.05)
	round_time += delta
	state_time += delta
	if not in_menu():
		var t := clampf((round_time - ZONE_DELAY) / ZONE_DURATION, 0.0, 1.0)
		zone_radius = lerpf(ARENA_RADIUS, ZONE_MIN_RADIUS, t)
		if state == "playing" and not zone_announced and round_time >= ZONE_DELAY:
			zone_announced = true
			sfx.play("zone", 0.0, 0.0)
			hud.flash_banner(Loc.t("zone_alert"))
		if state == "playing" and round_time >= next_event_time:
			next_event_time = round_time + randf_range(35.0, 50.0)
			_arena_event()

	var t0 := Time.get_ticks_usec()
	_update_player_input(delta)
	_simulate(delta)
	perf_mark("simulate", t0)
	t0 = Time.get_ticks_usec()
	for f in fighters:
		if f.alive:
			_fighter_visual_fx(f, delta)
	_update_hiding(delta)
	_update_target()
	_hazard_fx(delta)
	_update_particles(delta)
	_check_deaths()
	_maintain_world(delta)
	_update_camera(delta)
	_redraw_layers()
	perf_mark("fx_misc", t0)


func _redraw_layers() -> void:
	zone_layer.queue_redraw()
	items.queue_redraw()
	fx_low.queue_redraw()
	if canopy_dirty:
		canopy_dirty = false
		canopy.queue_redraw()
	fx.queue_redraw()


## Ortak simülasyon adımı (tek oyunculu ve sunucu).
func _simulate(delta: float) -> void:
	var limit := ARENA_RADIUS - Fighter.BODY_RADIUS
	for f in fighters:
		if not f.alive:
			continue
		if f.peer_id == 0 and not f.is_player:
			_update_bot(f, delta)
		elif f.peer_id != 0 and f.net_throw:
			_fighter_throw(f, _fid(f.net_target))
		f.on_screen = net_mode != "server" and in_view(f.position, f.ring_radius() + 80.0)
		f.tick(delta)
		var dist := f.position.length()
		if dist > limit:
			f.position *= limit / dist
		if dist > zone_radius:
			f.take_damage(ZONE_DPS * delta)
		# Sandıkların içinden geçilemez
		for c in crates:
			var off: Vector2 = f.position - c["pos"]
			var min_d := CRATE_SIZE * 0.5 + Fighter.BODY_RADIUS * 0.8
			if off.length_squared() < min_d * min_d:
				f.position = c["pos"] + off.normalized() * min_d
	if net_mode == "server":
		for f in fighters:
			if f.alive:
				f.in_bush = _bush_at(f.position) >= 0
	_update_pickups(delta)
	_update_coins(delta)
	_update_powerups()
	_update_crates()
	_update_hazards(delta)
	_resolve_combat()
	_update_projectiles(delta)


## Savaşçının etrafındaki sürekli görsel efektler (toz, alan dumanı, efektli bıçak parçacıkları).
func _fighter_visual_fx(f: Fighter, delta: float) -> void:
	if f.position.length() > zone_radius and randf() < delta * 6.0:
		_fx_smoke(f.position, 1, Color(1, 0.3, 0.3, 0.5))
	if f.moving and randf() < delta * 7.0 and _near_camera(f.position):
		_fx_dust(f.position + Vector2(randf_range(-10, 10), Fighter.BODY_RADIUS * 0.7))
	_knife_fx(f, delta)


# --- Olaylar: simülasyon → görüntü/ses ------------------------------------------

func _emit(ev: Dictionary) -> void:
	if net_mode == "server":
		events.append(ev)
	else:
		_present(ev)


## Bir olayın görsel ve işitsel sonuçlarını bu cihazın oyuncusuna göre oynatır.
func _present(ev: Dictionary) -> void:
	match String(ev["t"]):
		"clash":
			var a := _fid(ev["a"])
			var b := _fid(ev["b"])
			var at: Vector2 = ev["at"]
			var mine := player != null and (a == player or b == player)
			_sfx_at("clash", at, mine)
			if _near_camera(at):
				_fx_sparks(at, Color(1, 0.95, 0.6), 10, 420.0, 3.0)
				_fx_ring(at, Color(1, 1, 0.8), 34.0, 0.18, 3.0)
			if mine:
				add_shake(4.0)
		"hit":
			var vic := _fid(ev["v"])
			var att := _fid(ev["a"])
			if vic != null:
				vic.hurt_flash = 0.16
				vic.squash = 1.0
			_on_hit(vic, ev["at"], ev["dmg"], ev["dir"], att != null and att == player)
		"block":
			_on_blocked(_fid(ev["v"]), ev["at"])
		"crate_hit":
			var at: Vector2 = ev["at"]
			for c in crates:
				if (c["pos"] as Vector2).distance_to(at) < CRATE_SIZE:
					c["shake"] = 1.0
			if _near_camera(at):
				_fx_sparks(at, Color(0.85, 0.6, 0.35), 6, 260.0, 3.0)
			_sfx_at("block", at, _fid(ev["o"]) == player and player != null)
		"crate_break":
			var pos: Vector2 = ev["pos"]
			var mine := player != null and _fid(ev["o"]) == player
			if _near_camera(pos):
				for k in 10:
					var life := randf_range(0.4, 0.7)
					particles.append({"kind": "plank", "pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(150.0, 380.0),
						"life": life, "max": life, "col": Color(0.7, 0.45, 0.22), "rot": randf() * TAU, "spin": randf_range(-12.0, 12.0)})
				_fx_smoke(pos, 5, Color(0.8, 0.7, 0.55, 0.6))
				_fx_ring(pos, Color(1, 0.85, 0.6), 60.0, 0.3, 4.0)
			_sfx_at("death", pos, mine)
			if mine:
				add_shake(5.0)
		"box":
			_present_box(ev)
		"bomb":
			var pos: Vector2 = ev["pos"]
			if _near_camera(pos):
				_fx_ring(pos, Color(1, 0.8, 0.3), 190.0, 0.45, 12.0)
				_fx_ring(pos, Color(1, 0.3, 0.1), 140.0, 0.6, 8.0)
				_fx_sparks(pos, Color(1, 0.6, 0.2), 30, 600.0, 4.0)
				_fx_smoke(pos, 12, Color(0.3, 0.3, 0.3, 0.7))
				add_shake(clampf(16.0 - pos.distance_to(camera.position) / 60.0, 0.0, 12.0))
			_sfx_at("death", pos, pos.distance_to(camera.position) < 600.0)
		"event":
			sfx.play("zone", 0.0, 0.0)
			hud.flash_banner(Loc.t("event_" + String(ev["kind"])), Color(1, 0.85, 0.3), 2.6)
		"pu":
			var f := _fid(ev["f"])
			if f == null:
				return
			var info: Dictionary = GameData.POWERUPS[ev["type"]]
			if _near_camera(f.position):
				_fx_ring(f.position, info["color"], 90.0, 0.45, 6.0)
				_fx_sparks(f.position, info["color"], 14, 260.0, 3.0)
			if f == player:
				sfx.play("powerup", 0.0, 0.0)
				_fx_text(f.position + Vector2(0, -80), Loc.t("pu_" + String(ev["type"])) + "!", info["color"], 30)
		"throw":
			var f := _fid(ev["f"])
			var pos: Vector2 = ev["pos"]
			if f != null:
				f.squash = 0.5
			_sfx_at("throw", pos, f != null and f == player)
			if _near_camera(pos):
				_fx_sparks(pos, Color(1, 1, 1, 0.8), 3, 160.0, 2.0, ev["n"])
		"pick":
			if player != null and _fid(ev["f"]) == player:
				sfx.play("pickup", 0.0, 0.15)
				_fx_sparks(ev["pos"], Color(1, 1, 0.8), 4, 140.0, 2.0)
		"coin":
			if player != null and _fid(ev["f"]) == player:
				match_coins += 1
				sfx.play("coin", -6.0, 0.15)
				_fx_text(player.position + Vector2(randf_range(-20, 20), -50), "+1", Color(1, 0.85, 0.3), 20)
		"kill":
			_present_kill(ev)
		"dash":
			var f := _fid(ev["f"])
			if f == null:
				return
			if f == player:
				sfx.play("throw", 0.0, 0.0)
			if _near_camera(f.position):
				_fx_dust(f.position)
				_fx_ring(f.position, Color(1, 1, 1), 50.0, 0.25, 4.0)


func _present_box(ev: Dictionary) -> void:
	var pos: Vector2 = ev["pos"]
	var id: String = ev["id"]
	var good: bool = ev["good"]
	var opener := _fid(ev["o"])
	var mine := player != null and opener == player
	if mine:
		boxes_opened += 1
	var col := Color(0.4, 1, 0.5) if good else Color(1, 0.35, 0.3)
	if id == "coins":
		col = Color(1, 0.85, 0.3)
	if _near_camera(pos):
		for k in 10:
			var life := randf_range(0.4, 0.7)
			particles.append({"kind": "plank", "pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(150.0, 380.0),
				"life": life, "max": life, "col": Color(0.7, 0.45, 0.22), "rot": randf() * TAU, "spin": randf_range(-12.0, 12.0)})
		_fx_ring(pos, col, 80.0, 0.4, 6.0)
		_fx_sparks(pos, col, 16, 360.0, 3.0)
	if mine or (_near_camera(pos) and id in ["bomb", "poison"]):
		if id != "powerup":
			_fx_text(pos + Vector2(0, -50), Loc.t("box_" + id), col, 30)
		if mine:
			sfx.play("powerup" if good else "error", 0.0, 0.0)


func _present_kill(ev: Dictionary) -> void:
	var victim := _fid(ev["v"])
	var killer := _fid(ev["k"])
	var pos: Vector2 = ev["pos"]
	var vcol: Color = ev["vcol"]
	var mine := player != null and (victim == player or killer == player)
	kill_feed.push_front({
		"killer": ev["kname"], "victim": ev["vname"], "killer_col": ev["kcol"], "victim_col": vcol,
		"mine": mine, "time": round_time,
	})
	if kill_feed.size() > 4:
		kill_feed.pop_back()
	if _near_camera(pos):
		_fx_ring(pos, Color(1, 1, 1), 130.0, 0.4, 8.0)
		_fx_ring(pos, vcol, 90.0, 0.55, 5.0)
		_fx_sparks(pos, vcol, 22, 520.0, 4.0)
		_fx_sparks(pos, Color(1, 0.95, 0.7), 12, 380.0, 3.0)
		_fx_smoke(pos, 8, Color(0.85, 0.85, 0.85, 0.6))
		add_shake(clampf(14.0 - pos.distance_to(camera.position) / 80.0, 0.0, 10.0))
	_sfx_at("death", pos, mine)
	if player != null and killer == player:
		sfx.play("kill", 0.0, 0.0)
		_fx_text(pos + Vector2(0, -60), Loc.t("kill_popup"), Color(1, 0.4, 0.3), 38)
		if net_mode == "":
			_hitstop(0.07)
		_announce_streak(int(ev["multi"]), int(ev["streak"]))
	if net_mode == "client" and player != null and victim == player and state == "playing":
		_client_on_death()


# --- Çalılar, sandıklar, otomatik hedef ve bıçak efektleri ----------------------

func _bush_at(pos: Vector2) -> int:
	for i in bushes.size():
		if pos.distance_to(bushes[i]["pos"]) < float(bushes[i]["r"]) * 0.8:
			return i
	return -1


func _update_hiding(delta: float) -> void:
	var player_bush := _bush_at(player.position) if player != null and player.alive else -1
	for f in fighters:
		if not f.alive:
			continue
		var b := _bush_at(f.position)
		f.in_bush = b >= 0
		var near_player := player != null and player.alive and f.position.distance_to(player.position) < BUSH_REVEAL
		f.concealed = f.in_bush and f != player and b != player_bush and not near_player
	# Oyuncunun içinde olduğu çalı yarı saydam olur (yalnızca değişince yeniden çizilir)
	for i in bushes.size():
		var target := 0.45 if i == player_bush else 1.0
		var old := float(bushes[i]["fade"])
		if old != target:
			bushes[i]["fade"] = move_toward(old, target, delta * 3.0)
			canopy_dirty = true


## Görünen (çalıda saklanmayan) düşmanlar arasından en uygun hedefi seçer.
func can_see(viewer: Fighter, f: Fighter) -> bool:
	return not f.in_bush or viewer.position.distance_to(f.position) < BUSH_REVEAL


func _update_target() -> void:
	player_target = null
	if state != "playing" or player == null or not player.alive or not save["auto_aim"]:
		return
	var best_score := INF
	for f in fighters:
		if f == player or not f.alive or not can_see(player, f):
			continue
		var d := player.position.distance_to(f.position)
		if d > AIM_RANGE:
			continue
		# Yakın ve zayıf (az bıçaklı / az canlı) rakipler önceliklidir
		var score := d + f.knives * 6.0 + f.hp * 0.8
		if score < best_score:
			best_score = score
			player_target = f


func _update_crates() -> void:
	for i in range(crates.size() - 1, -1, -1):
		var c := crates[i]
		c["shake"] = maxf(0.0, float(c["shake"]) - get_process_delta_time() * 4.0)
		var cpos: Vector2 = c["pos"]
		for f in fighters:
			if not f.alive or f.knives <= 0:
				continue
			# Dönen bıçak halkası sandığa sürtünürse sandık hasar alır
			if absf(f.position.distance_to(cpos) - f.ring_radius()) < CRATE_SIZE * 0.5:
				if _ready_cd("k%d_%d" % [f.get_instance_id(), int(cpos.x * 10 + cpos.y)], 0.3):
					_hit_crate(i, cpos + (f.position - cpos).normalized() * CRATE_SIZE * 0.5, f)
					if i >= crates.size() or crates[i] != c:
						break


func _hit_crate(i: int, at: Vector2, opener: Fighter) -> void:
	var oid := opener.net_id if opener != null else 0
	var c := crates[i]
	c["hp"] = int(c["hp"]) - 1
	c["shake"] = 1.0
	_emit({"t": "crate_hit", "at": at, "o": oid})
	if int(c["hp"]) > 0:
		return
	var cpos: Vector2 = c["pos"]
	crates.remove_at(i)
	_emit({"t": "crate_break", "pos": cpos, "o": oid})
	_open_mystery(cpos, opener)


## Gizemli kutu açılınca rastgele iyi ya da kötü bir sonuç çıkar.
func _open_mystery(pos: Vector2, opener: Fighter) -> void:
	var m := GameData.roll_mystery()
	var id: String = m["id"]
	match id:
		"knives":
			for k in 8:
				_spawn_pickup(pos, Vector2.from_angle(randf() * TAU) * randf_range(120.0, 320.0))
		"coins":
			_spawn_coins(pos, randi_range(3, 6))
		"powerup":
			if opener != null:
				var type: String = ["speed", "shield", "magnet", "heal"].pick_random()
				_apply_powerup(opener, type)
		"rage":
			if opener != null:
				opener.rage_t = 7.0
		"bomb":
			hazards.append({"kind": "bomb", "pos": pos, "t": 1.1, "owner": opener.get_instance_id() if opener != null else 0})
		"slow":
			if opener != null:
				opener.slow_t = 4.0
		"thief":
			if opener != null:
				for k in mini(4, opener.knives):
					_lose_knife(opener, opener.position)
		"poison":
			hazards.append({"kind": "poison", "pos": pos, "t": 5.0})
	_emit({"t": "box", "pos": pos, "id": id, "good": m["good"], "o": opener.net_id if opener != null else 0})


func _update_hazards(delta: float) -> void:
	for i in range(hazards.size() - 1, -1, -1):
		var h := hazards[i]
		h["t"] = float(h["t"]) - delta
		var pos: Vector2 = h["pos"]
		if h["kind"] == "poison":
			# Zehir bulutu içindekilere sürekli hasar verir
			for f in fighters:
				if f.alive and f.position.distance_to(pos) < 120.0:
					f.take_damage(14.0 * delta)
		elif float(h["t"]) <= 0.0:
			# Bomba patlar: yakındaki herkese hasar ve savrulma
			var owner_f := instance_from_id(int(h["owner"])) as Fighter
			for f in fighters:
				if not f.alive:
					continue
				var d := f.position.distance_to(pos)
				if d < 170.0:
					f.knock += (f.position - pos).normalized() * 700.0
					f.take_damage(32.0 * (1.0 - d / 340.0), owner_f if owner_f != f else null)
			_emit({"t": "bomb", "pos": pos})
		if float(h["t"]) <= 0.0:
			hazards.remove_at(i)


## Zehir bulutlarının duman efekti (görüntü tarafı; tek oyunculu ve istemci).
func _hazard_fx(delta: float) -> void:
	for h in hazards:
		if h["kind"] == "poison" and randf() < delta * 12.0 and _near_camera(h["pos"]):
			particles.append({"kind": "smoke", "pos": (h["pos"] as Vector2) + _random_point(100.0), "vel": Vector2(0, -15),
				"life": 0.9, "max": 0.9, "col": Color(0.45, 0.9, 0.3, 0.35), "r": randf_range(16.0, 28.0)})


## Maç içinde ara sıra gelen rastgele olaylar (oyuncuyu canlı tutar).
func _arena_event() -> void:
	var kind: String = ["coins", "knives", "boxes"].pick_random()
	var center := player.position if player != null and player.alive else Vector2.ZERO
	match kind:
		"coins":
			for k in 12:
				coins_pickups.append({"pos": _random_point(zone_radius - 60.0).lerp(center, 0.35),
					"vel": Vector2.ZERO, "phase": randf() * TAU})
		"knives":
			for k in 40:
				_spawn_pickup(_random_point(zone_radius - 60.0), Vector2.ZERO)
		"boxes":
			for k in 8:
				_spawn_crate()
	_emit({"t": "event", "kind": kind})


func player_dash() -> void:
	if state != "playing" or player == null or not player.alive:
		return
	if net_mode == "client":
		net.c_dash.rpc_id(1)
		return
	if player.try_dash():
		_emit({"t": "dash", "f": player.net_id})


## Efektli bıçakların etrafa saçtığı parçacıklar.
func _knife_fx(f: Fighter, delta: float) -> void:
	if f.knives <= 0 or f.concealed or not _near_camera(f.position):
		return
	var fx_kind: String = GameData.KNIVES[f.knife_kind]["fx"]
	if fx_kind == "" or randf() > delta * (4.0 + f.knives * 0.3) * (0.6 if low_fx else 1.0):
		return
	var pos := f.knife_world_pos(randi() % f.knives)
	_fx_knife_particle(fx_kind, pos, f.knife_kind)


func _fx_knife_particle(fx_kind: String, pos: Vector2, kind: int) -> void:
	if net_mode == "server":
		return
	var col: Color = GameData.KNIVES[kind]["glow"]
	col.a = 1.0
	match fx_kind:
		"fire":
			particles.append({"kind": "ember", "pos": pos, "vel": Vector2(randf_range(-25, 25), randf_range(-90, -40)),
				"life": 0.55, "max": 0.55, "col": col, "col2": Color(1, 0.95, 0.5), "r": randf_range(3.0, 5.0)})
		"ice", "gold":
			particles.append({"kind": "sparkle", "pos": pos + _random_point(8.0), "vel": Vector2(0, -15),
				"life": 0.45, "max": 0.45, "col": col.lightened(0.4), "r": randf_range(4.0, 7.0)})
		"poison":
			particles.append({"kind": "bubble", "pos": pos, "vel": Vector2(randf_range(-15, 15), randf_range(-45, -20)),
				"life": 0.7, "max": 0.7, "col": col, "r": randf_range(3.0, 6.0)})
		"electric":
			var pts := PackedVector2Array([pos])
			var dir := Vector2.from_angle(randf() * TAU)
			for k in 4:
				pts.append(pts[pts.size() - 1] + dir.rotated(randf_range(-1.0, 1.0)) * randf_range(6.0, 12.0))
			particles.append({"kind": "bolt", "pos": pos, "pts": pts, "life": 0.12, "max": 0.12, "col": col.lightened(0.3)})
		"void":
			particles.append({"kind": "smoke", "pos": pos, "vel": Vector2(randf_range(-20, 20), randf_range(-30, -10)),
				"life": 0.6, "max": 0.6, "col": Color(col, 0.45), "r": randf_range(5.0, 9.0)})


## Joystick veya klavyeden hareket yönü.
func _read_move() -> Vector2:
	var v: Vector2 = hud.joy_vector()
	var k := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if k != Vector2.ZERO:
		v = k.normalized()
	return v


func _throw_pressed() -> bool:
	return hud.throw_held() or Input.is_physical_key_pressed(KEY_SPACE)


func _update_player_input(delta: float) -> void:
	if player == null:
		return
	if state != "playing" or not player.alive:
		player.move_dir = Vector2.ZERO
		return
	player.move_dir = _read_move()
	if _throw_pressed():
		player_throw()
	_footsteps(delta)


func _footsteps(delta: float) -> void:
	if player != null and player.moving:
		step_timer -= delta * (1.3 if player.speed_t > 0.0 else 1.0)
		if step_timer <= 0.0:
			step_timer = 0.3
			sfx.play("step", 0.0, 0.15)
	else:
		step_timer = 0.0


func _update_pickups(delta: float) -> void:
	var magnets: Array[Fighter] = []
	for f in fighters:
		if f.alive and f.magnet_t > 0.0:
			magnets.append(f)
	for i in range(pickups.size() - 1, -1, -1):
		var p := pickups[i]
		var vel: Vector2 = p["vel"]
		var pos: Vector2 = p["pos"]
		if vel != Vector2.ZERO:
			pos += vel * delta
			if pos.length() > ARENA_RADIUS - 20.0:
				pos = pos.normalized() * (ARENA_RADIUS - 20.0)
			p["rot"] = float(p["rot"]) + vel.length() * delta * 0.03
			vel = vel.lerp(Vector2.ZERO, minf(1.0, 5.0 * delta))
			p["vel"] = vel if vel.length() > 5.0 else Vector2.ZERO
		for m in magnets:
			if pos.distance_squared_to(m.position) < Fighter.MAGNET_RADIUS * Fighter.MAGNET_RADIUS:
				pos = pos.move_toward(m.position, 650.0 * delta)
		p["pos"] = pos
		for f in fighters:
			if f.alive and f.knives < Fighter.MAX_KNIVES \
					and pos.distance_squared_to(f.position) < PICKUP_RADIUS * PICKUP_RADIUS:
				f.knives += 1
				pickups.remove_at(i)
				if _is_human(f):
					_emit({"t": "pick", "f": f.net_id, "pos": pos})
				break


func _spawn_coins(pos: Vector2, count: int) -> void:
	for k in count:
		coins_pickups.append({"pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(100.0, 260.0),
			"phase": randf() * TAU})


func _update_coins(delta: float) -> void:
	for i in range(coins_pickups.size() - 1, -1, -1):
		var c := coins_pickups[i]
		var vel: Vector2 = c["vel"]
		var pos: Vector2 = c["pos"] + vel * delta
		c["vel"] = vel.lerp(Vector2.ZERO, minf(1.0, 5.0 * delta))
		var taken := false
		for f in fighters:
			if not f.alive:
				continue
			var d := pos.distance_to(f.position)
			# Oyunculara yakın altınlar kendiliğinden onlara doğru kayar; mıknatıs menzili artırır
			var pull := Fighter.MAGNET_RADIUS if f.magnet_t > 0.0 else (90.0 if _is_human(f) else 0.0)
			if d < pull:
				pos = pos.move_toward(f.position, 520.0 * delta)
			if d < PICKUP_RADIUS:
				taken = true
				if _is_human(f):
					_emit({"t": "coin", "f": f.net_id, "pos": pos})
				break
		if taken:
			coins_pickups.remove_at(i)
		else:
			c["pos"] = pos


func _update_powerups() -> void:
	for i in range(powerups.size() - 1, -1, -1):
		var pos: Vector2 = powerups[i]["pos"]
		for f in fighters:
			if f.alive and pos.distance_squared_to(f.position) < POWERUP_RADIUS * POWERUP_RADIUS:
				_apply_powerup(f, powerups[i]["type"])
				powerups.remove_at(i)
				break


func _apply_powerup(f: Fighter, type: String) -> void:
	var info: Dictionary = GameData.POWERUPS[type]
	match type:
		"speed":
			f.speed_t = info["duration"]
		"shield":
			f.shield_t = info["duration"]
		"magnet":
			f.magnet_t = info["duration"]
		"heal":
			f.hp = minf(f.max_hp, f.hp + 50.0)
		"knives":
			f.knives = mini(Fighter.MAX_KNIVES, f.knives + 5)
	_emit({"t": "pu", "f": f.net_id, "type": type})


# --- Dövüş -------------------------------------------------------------------

func _resolve_combat() -> void:
	var alive := _alive_fighters()
	for i in alive.size():
		var a := alive[i]
		for j in range(i + 1, alive.size()):
			var b := alive[j]
			var offset := b.position - a.position
			var d := offset.length()
			var ra := a.ring_radius()
			var rb := b.ring_radius()
			if d > ra + rb + Fighter.BODY_RADIUS:
				continue
			var dir := offset / d if d > 0.01 else Vector2.RIGHT
			# Gövdeler iç içe geçmesin
			if d < Fighter.BODY_RADIUS * 2.0:
				var push := (Fighter.BODY_RADIUS * 2.0 - d) * 0.5
				a.position -= dir * push
				b.position += dir * push
			# Bıçak halkaları çarpışırsa iki taraf da bıçak kaybeder
			if a.knives > 0 and b.knives > 0 and d <= ra + rb and d >= absf(ra - rb):
				if _ready_cd("c%d_%d" % [a.get_instance_id(), b.get_instance_id()], 0.14):
					var at := (a.position + dir * ra + b.position - dir * rb) * 0.5
					_lose_knife(a, at)
					_lose_knife(b, at)
					a.knock -= dir * 220.0
					b.knock += dir * 220.0
					_emit({"t": "clash", "at": at, "a": a.net_id, "b": b.net_id})
			_try_ring_hit(a, b, d, dir)
			_try_ring_hit(b, a, d, -dir)


## Saldıranın bıçak halkası kurbanın gövdesinden geçiyorsa hasar verir.
func _try_ring_hit(att: Fighter, vic: Fighter, d: float, dir: Vector2) -> void:
	if att.knives <= 0 or absf(d - att.ring_radius()) > Fighter.BODY_RADIUS:
		return
	if not _ready_cd("h%d_%d" % [att.get_instance_id(), vic.get_instance_id()], 0.32):
		return
	vic.knock += dir * 320.0
	var at := vic.position - dir * Fighter.BODY_RADIUS
	var dmg := (7.0 + att.knives * 0.35) * att.damage_mult()
	if vic.take_damage(dmg, att):
		_emit({"t": "hit", "v": vic.net_id, "a": att.net_id, "at": at, "dmg": dmg, "dir": dir})
	else:
		_emit({"t": "block", "v": vic.net_id, "at": at})


func _on_hit(vic: Fighter, at: Vector2, dmg: float, dir: Vector2, by_player: bool) -> void:
	var mine := by_player or (vic != null and vic == player)
	_sfx_at("hit", at, mine)
	if _near_camera(at):
		_fx_sparks(at, Color(1, 0.35, 0.25), 9, 380.0, 3.5, dir)
		_fx_sparks(at, Color(1, 1, 1), 4, 300.0, 2.0, dir)
		_fx_ring(at, Color(1, 0.5, 0.4), 40.0, 0.2, 4.0)
	if mine:
		_fx_text(at + Vector2(randf_range(-14, 14), -30), str(roundi(dmg)),
			Color(1, 0.35, 0.3) if vic == player else Color(1, 1, 1), 26)
	if vic != null and vic == player:
		add_shake(9.0)
		Input.vibrate_handheld(40)
	elif by_player:
		add_shake(3.0)


func _on_blocked(vic: Fighter, at: Vector2) -> void:
	_sfx_at("block", at, vic != null and vic == player)
	if _near_camera(at):
		_fx_sparks(at, Color(0.6, 0.85, 1), 8, 300.0, 3.0)
		_fx_ring(at, Color(0.6, 0.85, 1), 36.0, 0.2, 3.0)


func _ready_cd(key: String, duration: float) -> bool:
	if round_time < float(cooldowns.get(key, -1.0)):
		return false
	cooldowns[key] = round_time + duration
	return true


func _lose_knife(f: Fighter, at: Vector2) -> void:
	if f.knives <= 0:
		return
	f.knives -= 1
	if randf() < 0.5:
		_spawn_pickup(at, Vector2.from_angle(randf() * TAU) * randf_range(150.0, 300.0))


## Oyuncunun fırlatma isteği. Çok oyunculuda istek sunucuya girdi olarak gider.
func player_throw() -> void:
	if state != "playing" or player == null or not player.alive or net_mode == "client":
		return
	_fighter_throw(player, player_target)


## Hedef verilmişse rakibin hareketini kestirerek ona, yoksa baktığı yöndeki en yakın rakibe fırlatır.
func _fighter_throw(f: Fighter, target: Fighter) -> void:
	if f.knives <= 0 or f.throw_cooldown > 0.0:
		return
	if target != null and target.alive and target != f and can_see(f, target) \
			and f.position.distance_to(target.position) < AIM_RANGE + 150.0:
		var to := target.position - f.position
		var lead := target.move_dir * target.move_speed() * (to.length() / THROW_SPEED)
		_throw_knife(f, to + lead)
		return
	var dir := f.facing
	var best: Fighter = null
	var best_score := INF
	for o in _alive_fighters():
		if o == f or not can_see(f, o):
			continue
		var to := o.position - f.position
		var dist := to.length()
		var ang := absf(dir.angle_to(to))
		if dist > AIM_ASSIST_RANGE or ang > AIM_ASSIST_ANGLE:
			continue
		var score := dist * (1.0 + ang)
		if score < best_score:
			best_score = score
			best = o
	if best != null:
		dir = best.position - f.position
	_throw_knife(f, dir)


func _throw_knife(f: Fighter, dir: Vector2) -> void:
	if not f.alive or f.knives <= 0 or f.throw_cooldown > 0.0 or dir == Vector2.ZERO:
		return
	var n := dir.normalized()
	f.knives -= 1
	f.throw_cooldown = THROW_COOLDOWN
	f.facing = n
	if absf(n.x) > 0.2:
		f.flip = signf(n.x)
	f.squash = 0.5
	var start := f.position + n * (Fighter.BODY_RADIUS + 8.0)
	projectiles.append({
		"pos": start,
		"vel": n * THROW_SPEED,
		"owner": f.get_instance_id(),
		"life": THROW_LIFE,
		"kind": f.knife_kind,
	})
	_emit({"t": "throw", "f": f.net_id, "pos": start, "n": n})


func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p := projectiles[i]
		var vel: Vector2 = p["vel"]
		var pos: Vector2 = p["pos"]
		pos += vel * delta
		p["pos"] = pos
		p["life"] = float(p["life"]) - delta
		var owner_id: int = p["owner"]
		var owner_f := instance_from_id(owner_id) as Fighter
		var hit := false
		# Efektli bıçaklar uçarken de parçacık bırakır
		_projectile_fx(p, delta)
		for c in range(crates.size() - 1, -1, -1):
			if pos.distance_to(crates[c]["pos"]) < CRATE_SIZE * 0.55:
				_hit_crate(c, pos, owner_f)
				hit = true
				break
		for f in fighters:
			if hit:
				break
			if not f.alive or f.get_instance_id() == owner_id:
				continue
			var d := pos.distance_to(f.position)
			if f.knives > 0 and absf(d - f.ring_radius()) < 14.0 and f.knife_blocks(pos):
				_lose_knife(f, pos)
				_emit({"t": "clash", "at": pos, "a": f.net_id, "b": owner_f.net_id if owner_f != null else 0})
				hit = true
			elif d < Fighter.BODY_RADIUS + 8.0:
				f.knock += vel.normalized() * 380.0
				var dmg := THROW_DAMAGE * (owner_f.damage_mult() if owner_f != null else 1.0)
				if f.take_damage(dmg, owner_f):
					_emit({"t": "hit", "v": f.net_id, "a": owner_f.net_id if owner_f != null else 0, "at": pos,
						"dmg": dmg, "dir": vel.normalized()})
				else:
					_emit({"t": "block", "v": f.net_id, "at": pos})
				hit = true
		if hit:
			projectiles.remove_at(i)
		elif float(p["life"]) <= 0.0 or pos.length() > ARENA_RADIUS:
			if pos.length() < ARENA_RADIUS:
				_spawn_pickup(pos, vel * 0.15)
			projectiles.remove_at(i)


func _projectile_fx(p: Dictionary, delta: float) -> void:
	var fx_kind: String = GameData.KNIVES[p["kind"]]["fx"]
	if fx_kind != "" and randf() < delta * 30.0 and _near_camera(p["pos"]):
		_fx_knife_particle(fx_kind, p["pos"], p["kind"])


## Art arda leşlerde büyük duyuru (Çifte Leş, Üçlü Leş, Durdurulamaz...).
func _announce_streak(multi: int, streak: int) -> void:
	var text := ""
	if multi >= 4:
		text = Loc.t("multi_kill")
	elif multi == 3:
		text = Loc.t("triple_kill")
	elif multi == 2:
		text = Loc.t("double_kill")
	elif streak == 8:
		text = Loc.t("streak_8")
	elif streak == 5:
		text = Loc.t("streak_5")
	if text != "":
		hud.flash_banner(text, Color(1, 0.55, 0.15), 2.0)
		get_tree().create_timer(0.15).timeout.connect(func() -> void: sfx.play("unlock", -2.0, 0.0))


func _check_deaths() -> void:
	for f in fighters:
		if f.alive and f.hp <= 0.0:
			_kill(f)
	if net_mode == "" and state == "playing" and player.alive and alive_count() == 1:
		final_rank = 1
		_end_round(true)


func _kill(f: Fighter) -> void:
	f.alive = false
	f.visible = false
	dead_since[f.net_id] = round_time
	for k in f.knives + 3:
		_spawn_pickup(f.position + _random_point(12.0), Vector2.from_angle(randf() * TAU) * randf_range(150.0, 480.0))
	f.knives = 0
	_spawn_coins(f.position, mini(1 + f.kills, 5))
	var killer := instance_from_id(f.last_attacker_id) as Fighter
	if killer == f:
		killer = null
	if killer != null:
		killer.kills += 1
		killer.streak += 1
		# Leş alan iyileşir: agresif oynamayı ödüllendirir
		killer.hp = minf(killer.max_hp, killer.hp + 25.0)
		killer.multi = killer.multi + 1 if round_time - killer.last_kill_time < 4.0 else 1
		killer.last_kill_time = round_time
	_emit({
		"t": "kill", "v": f.net_id, "k": killer.net_id if killer != null else 0, "pos": f.position,
		"vname": f.display_name, "kname": killer.display_name if killer != null else "",
		"vcol": f.color, "kcol": killer.color if killer != null else Color.WHITE,
		"multi": killer.multi if killer != null else 0, "streak": killer.streak if killer != null else 0,
	})
	if net_mode == "server" and (f.peer_id != 0 or (killer != null and killer.peer_id != 0)):
		if killer != null:
			slog("%s, %s'yi eledi" % [killer.display_name, f.display_name], Color(1, 0.75, 0.6))
		else:
			slog("%s elendi" % f.display_name, Color(1, 0.75, 0.6))
	if net_mode == "" and f == player and state == "playing":
		final_rank = alive_count() + 1
		_hitstop(0.12)
		_end_round(false)


func _maintain_world(delta: float) -> void:
	if pickups.size() < _pickup_target() and randf() < 0.3:
		_spawn_pickup(_random_point(zone_radius - 40.0), Vector2.ZERO)
	if powerups.size() < POWERUP_MAX and randf() < delta / 4.0:
		_spawn_powerup()
	if crates.size() < CRATE_TARGET and randf() < delta / 3.0:
		_spawn_crate()
	# Menüdeki gösterim modunda arena hiç boşalmasın
	if in_menu() and alive_count() < 6:
		_remove_dead_fighters(0.0)
		_spawn_bot(BOT_NAMES.pick_random())


## Belirli süredir ölü olan savaşçıları sahneden kaldırır.
func _remove_dead_fighters(min_age: float) -> void:
	for i in range(fighters.size() - 1, -1, -1):
		var f := fighters[i]
		if f.alive or round_time - float(dead_since.get(f.net_id, -99.0)) < min_age:
			continue
		fighters.remove_at(i)
		fighter_by_id.erase(f.net_id)
		dead_since.erase(f.net_id)
		if f != player:
			f.queue_free()


# --- Botlar ------------------------------------------------------------------

func _update_bot(b: Fighter, delta: float) -> void:
	b.think_timer -= delta
	if b.think_timer <= 0.0:
		b.think_timer = randf_range(0.15, 0.35)
		_bot_decide(b)
	b.move_dir = b.move_dir.lerp(b.want_dir, minf(1.0, 8.0 * delta))


func _bot_decide(b: Fighter) -> void:
	var pos := b.position
	if pos.length() > zone_radius - 140.0:
		b.want_dir = -pos.normalized()
		return
	# Bombalardan ve zehir bulutlarından kaç
	for h in hazards:
		var hp_pos: Vector2 = h["pos"]
		if pos.distance_to(hp_pos) < 220.0:
			b.want_dir = (pos - hp_pos).normalized()
			return

	var enemy: Fighter = null
	var enemy_d := 650.0
	for f in fighters:
		if f == b or not f.alive or not can_see(b, f):
			continue
		var d := pos.distance_to(f.position)
		if d < enemy_d:
			enemy_d = d
			enemy = f

	if enemy != null:
		var n := (enemy.position - pos).normalized()
		var diff := b.knives - enemy.knives
		if b.knives >= 5 and enemy_d < 550.0 and randf() < 0.22 * b.aggression:
			var lead := enemy.position + enemy.move_dir * enemy.move_speed() * (enemy_d / THROW_SPEED)
			_throw_knife(b, lead - pos)
		if diff <= -3 or b.hp < 30.0 or enemy.shield_t > 0.0:
			b.want_dir = (-n + n.orthogonal() * 0.4).normalized()
			if enemy_d < 260.0 and randf() < 0.15:
				b.move_dir = b.want_dir
				if b.try_dash():
					_emit({"t": "dash", "f": b.net_id})
			return
		if diff >= 2 or b.aggression > 0.75 or b.shield_t > 0.0 or b.rage_t > 0.0:
			if enemy_d > b.ring_radius() + 60.0 and enemy_d < b.ring_radius() + 260.0 and randf() < 0.06 * b.aggression:
				b.move_dir = n
				if b.try_dash():
					_emit({"t": "dash", "f": b.net_id})
			# Halkasını rakibin gövdesine sürtecek mesafede etrafında döner
			if enemy_d > b.ring_radius():
				b.want_dir = (n + n.orthogonal() * 0.3).normalized()
			else:
				b.want_dir = n.orthogonal()
			return

	# Güçlendirmeler bıçaklardan daha cazip: mesafeleri yarı sayılır
	var found := false
	var best := Vector2.ZERO
	var best_d := 700.0 * 700.0
	for p in powerups:
		var pp: Vector2 = p["pos"]
		var d2 := pos.distance_squared_to(pp) * 0.25
		if pp.length() < zone_radius and d2 < best_d:
			best_d = d2
			best = pp
			found = true
	for p in pickups:
		var pp: Vector2 = p["pos"]
		if pp.length() > zone_radius:
			continue
		var d2 := pos.distance_squared_to(pp)
		if d2 < best_d:
			best_d = d2
			best = pp
			found = true
	if found:
		b.want_dir = (best - pos).normalized()
		return
	if randf() < 0.1:
		b.wander_dir = b.wander_dir.rotated(randf_range(-1.2, 1.2))
	b.want_dir = b.wander_dir


# --- Çok oyunculu: sunucu -------------------------------------------------------

func _start_server(args: PackedStringArray) -> void:
	state = "server"
	# Bilgisayarı yormamak için: dünya çizilmez, saniyede 30 kare yeterli
	Engine.max_fps = 30
	for layer_node in [ground, zone_layer, items, fx_low, fighter_layer, canopy, fx]:
		layer_node.visible = false
	RenderingServer.set_default_clear_color(Color(0.04, 0.06, 0.08))
	var err: Error = net.start_server()
	if err != OK:
		printerr("Oyun sunucusu başlatılamadı (port %d): %s" % [net.server_port(), error_string(err)])
	var web_dir := ProjectSettings.globalize_path("res://build/web")
	for a in args:
		if a.begins_with("--web-dir="):
			web_dir = a.trim_prefix("--web-dir=")
	var web = WEB_SCRIPT.new()
	add_child(web)
	var web_ok := false
	if FileAccess.file_exists(web_dir.path_join("index.html")):
		web_ok = web.start(web_dir) == OK
	_build_world()
	for i in bot_target:
		_spawn_bot(BOT_NAMES.pick_random())
	slog("Sunucu başlatıldı", Color(0.5, 1, 0.6))
	print("")
	print("=== KNIFE ARENA SUNUCUSU ÇALIŞIYOR ===")
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			if web_ok:
				print("Telefondan aç:  http://%s:%d" % [ip, web.PORT])
				server_urls.append("http://%s:%d" % [ip, web.PORT])
			print("Oyun sunucusu:  %s:%d" % [ip, net.server_port()])
	if not web_ok:
		print("(Web sürümü bulunamadı: %s)" % web_dir)
	print("Kapatmak için bu pencereyi kapatın.")


func _server_process(delta: float) -> void:
	delta = minf(delta, 0.05)
	round_time += delta
	# Süresi dolmuş bekleme kayıtlarını temizle (uzun süre açık kalınca bellek şişmesin)
	cooldown_prune_timer -= delta
	if cooldown_prune_timer <= 0.0:
		cooldown_prune_timer = 10.0
		for key in cooldowns.keys():
			if float(cooldowns[key]) < round_time:
				cooldowns.erase(key)
	if round_time >= next_event_time:
		next_event_time = round_time + randf_range(35.0, 50.0)
		_arena_event()
	_simulate(delta)
	_check_deaths()
	_maintain_world(delta)
	# Arenayı canlı tut: ölen botların yerine yenileri gelir, cesetler temizlenir
	_remove_dead_fighters(1.5)
	# Bot sayısını paneldeki hedefe yaklaştır (fazlası sessizce çıkar, eksiği yavaşça gelir)
	var bots: Array[Fighter] = []
	for f in fighters:
		if f.alive and f.peer_id == 0:
			bots.append(f)
	bot_spawn_timer -= delta
	if bots.size() < bot_target and bot_spawn_timer <= 0.0:
		bot_spawn_timer = 1.0
		_spawn_bot(BOT_NAMES.pick_random())
	elif bots.size() > bot_target:
		var extra := bots[bots.size() - 1]
		extra.alive = false
		extra.visible = false
		dead_since[extra.net_id] = round_time
	# Girişli yöneticilere panel verisi (saniyede 2 kez)
	admin_timer -= delta
	if admin_timer <= 0.0 and not admin_peers.is_empty():
		admin_timer = 0.5
		var view := admin_data()
		for ap in admin_peers.keys():
			net.s_admin_state.rpc_id(ap, view)
	snapshot_timer += delta
	if snapshot_timer >= 1.0 / SNAPSHOT_RATE:
		snapshot_timer = 0.0
		if not multiplayer.get_peers().is_empty():
			net.s_snapshot.rpc(_build_snapshot())
		events.clear()


func server_join(peer: int, info: Dictionary) -> void:
	var skin_id := String(info.get("skin", "skin_keloglan"))
	if GameData.skin_index(skin_id) == 0 and skin_id != GameData.SKINS[0]["id"]:
		skin_id = GameData.SKINS[0]["id"]
	var skin: Dictionary = GameData.SKINS[GameData.skin_index(skin_id)]
	var fname := String(info.get("name", "Oyuncu")).strip_edges().left(14)
	if fname == "":
		fname = "Oyuncu"
	# Aynı bağlantının eski savaşçısı yaşıyorsa kaldır
	if peers.has(peer):
		var old := _fid(peers[peer])
		if old != null and old.alive:
			old.alive = false
			old.visible = false
			dead_since[old.net_id] = round_time
	var f := _spawn_fighter(fname, skin["id"], skin["color"], false)
	f.peer_id = peer
	f.knife_kind = clampi(int(info.get("knife", 0)), 0, GameData.KNIVES.size() - 1)
	f.level = clampi(int(info.get("level", 1)), 1, GameData.MAX_LEVEL)
	var first_join := not peer_info.has(peer)
	peers[peer] = f.net_id
	peer_info[peer] = {"name": fname, "ip": net.peer_ip(peer), "info": info,
		"since": peer_info[peer]["since"] if not first_join else Time.get_ticks_msec()}
	var bush_data := []
	for b in bushes:
		bush_data.append({"pos": b["pos"], "r": b["r"], "blobs": b["blobs"]})
	net.s_welcome.rpc_id(peer, {"id": f.net_id, "bushes": bush_data})
	if first_join:
		total_joins += 1
		slog("%s katıldı (%s)" % [fname, peer_info[peer]["ip"]], Color(0.5, 1, 0.6))
	else:
		slog("%s yeniden doğdu" % fname, Color(0.7, 0.85, 1))


func server_input(peer: int, move: Vector2, aim: Vector2, throw_held: bool, target: int) -> void:
	var f := _fid(peers.get(peer, 0))
	if f == null or not f.alive:
		return
	f.move_dir = move.limit_length(1.0)
	if move.length() < 0.15 and aim != Vector2.ZERO:
		f.facing = aim.normalized()
	f.net_throw = throw_held
	f.net_target = target


func server_dash(peer: int) -> void:
	var f := _fid(peers.get(peer, 0))
	if f != null and f.alive and f.try_dash():
		_emit({"t": "dash", "f": f.net_id})


func server_remove_peer(peer: int) -> void:
	if admin_peers.has(peer):
		admin_peers.erase(peer)
		slog("Yönetici ayrıldı", Color(0.8, 0.8, 1))
	var f := _fid(peers.get(peer, 0))
	if f != null and f.alive:
		f.alive = false
		f.visible = false
		dead_since[f.net_id] = round_time
	peers.erase(peer)
	if peer_info.has(peer):
		slog("%s ayrıldı" % peer_info[peer]["name"], Color(1, 0.5, 0.45))
		peer_info.erase(peer)


## Sunucu paneli günlüğüne kayıt ekler (en yeni üstte).
func slog(text: String, col := Color.WHITE) -> void:
	server_log.push_front({"time": Time.get_time_string_from_system(), "text": text, "col": col})
	if server_log.size() > 40:
		server_log.pop_back()
	print("[%s] %s" % [server_log[0]["time"], text])


## Yönetim paneli komutları.
func _admin(id: String) -> void:
	if id == "adm_reset":
		_server_reset_arena()
	elif id == "adm_bot_plus":
		bot_target = mini(bot_target + 1, 20)
		slog("Bot hedefi: %d" % bot_target, Color(0.8, 0.8, 1))
	elif id == "adm_bot_minus":
		bot_target = maxi(bot_target - 1, 0)
		slog("Bot hedefi: %d" % bot_target, Color(0.8, 0.8, 1))
	elif id == "adm_event":
		_arena_event()
		slog("Arena olayı başlatıldı", Color(1, 0.85, 0.3))
	else:
		# Oyuncuya yönelik komutlar: adm_<işlem>_<bağlantı>
		var parts := id.split("_")
		if parts.size() < 3:
			return
		var peer := parts[2].to_int()
		if not peer_info.has(peer):
			return
		var pname: String = peer_info[peer]["name"]
		var f := _fid(peers.get(peer, 0))
		match parts[1]:
			"coins":
				net.s_grant.rpc_id(peer, 100, 0)
				slog("%s: +100 altın verildi" % pname, Color(1, 0.85, 0.3))
			"level":
				net.s_grant.rpc_id(peer, 0, 1)
				if f != null:
					f.level = mini(f.level + 1, GameData.MAX_LEVEL)
				slog("%s: +1 seviye verildi" % pname, Color(0.6, 0.85, 1))
			"heal":
				if f != null and f.alive:
					f.hp = f.max_hp
					f.knives = mini(f.knives + 10, Fighter.MAX_KNIVES)
					slog("%s: can dolduruldu, +10 bıçak" % pname, Color(0.5, 1, 0.6))
			"kick":
				slog("%s oyundan atıldı" % pname, Color(1, 0.4, 0.35))
				net.kick(peer)


## Test: yönetim komutlarını sırayla dener (--admin-test).
func _admin_self_test() -> void:
	await get_tree().create_timer(5.0).timeout
	for peer in peer_info.keys():
		for act in ["coins", "level", "heal"]:
			_admin("adm_%s_%d" % [act, peer])
	_admin("adm_bot_plus")
	_admin("adm_event")
	await get_tree().create_timer(2.0).timeout
	_admin("adm_reset")


## Arenayı sıfırlar: yeni harita, yeni botlar; bağlı oyuncular yeni arenada yeniden doğar.
func _server_reset_arena() -> void:
	_clear_world()
	_build_world()
	for i in bot_target:
		_spawn_bot(BOT_NAMES.pick_random())
	for peer in peer_info.keys():
		server_join(peer, peer_info[peer]["info"])
	slog("Arena sıfırlandı", Color(1, 0.85, 0.3))


func _build_snapshot() -> Dictionary:
	var f_rows := []
	for f in fighters:
		f_rows.append([f.net_id, f.display_name, f.skin_id, f.color, f.level, f.knife_kind, f.position, f.hp,
			f.knives, f.kills, f.alive, f.move_dir, f.facing, f.shield_t, f.speed_t, f.magnet_t, f.rage_t,
			f.slow_t, f.dash_t, f.peer_id])
	var p := PackedFloat32Array()
	for pk in pickups:
		var pos: Vector2 = pk["pos"]
		p.append_array([pos.x, pos.y, float(pk["rot"])])
	var c := PackedVector2Array()
	for co in coins_pickups:
		c.append(co["pos"])
	var k := PackedFloat32Array()
	for cr in crates:
		var pos: Vector2 = cr["pos"]
		k.append_array([pos.x, pos.y, float(cr["hp"]), float(cr["rot"])])
	var u := []
	for pu in powerups:
		u.append([pu["pos"], POWERUP_TYPES.find(pu["type"]), pu["phase"]])
	var h := []
	for hz in hazards:
		h.append([hz["kind"], hz["pos"], hz["t"]])
	var j := []
	for pr in projectiles:
		j.append([pr["pos"], pr["vel"], pr["kind"]])
	return {"f": f_rows, "p": p, "c": c, "k": k, "u": u, "h": h, "j": j, "e": events.duplicate()}


# --- Çok oyunculu: istemci ------------------------------------------------------

## Web sürümünde sayfanın geldiği bilgisayar, masaüstünde kayıtlı adres (varsayılan bu bilgisayar).
## İnternetteki oyun sunucusunun adresi (yayınlama betiği server_url.txt dosyasına yazar).
func _public_server() -> String:
	var f := FileAccess.open("res://server_url.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else ""


## Hangi sunucuya bağlanılacak:
##  - Web sürümü yerel ağdaki bilgisayardan açıldıysa (192.168.x.x) o bilgisayardaki sunucu,
##  - internetten (GitHub Pages) açıldıysa internetteki sunucu,
##  - masaüstünde: kayıtlı adres, yoksa internetteki sunucu, o da yoksa bu bilgisayar.
func _mp_host() -> String:
	if OS.has_feature("web"):
		var hv = JavaScriptBridge.eval("window.location.hostname", true)
		var h: String = hv if hv is String else ""
		if h != "":
			var local: bool = h == "localhost" or h.begins_with("127.") or h.begins_with("192.168.") or h.begins_with("10.") or h.begins_with("172.")
			if local or _public_server() == "":
				return h
		return _public_server()
	if String(save["mp_host"]) != "":
		return String(save["mp_host"])
	return _public_server() if _public_server() != "" else "127.0.0.1"


func _mp_connect() -> void:
	_clear_world()
	net_mode = "client"
	state = "connecting"
	state_time = 0.0
	var err: Error = net.connect_to(_mp_host())
	if err != OK:
		_on_net_failed()


func _join_info() -> Dictionary:
	return {"name": player_name(), "skin": playable_skin()["id"], "knife": selected_knife(), "level": int(save["level"])}


func _on_net_connected() -> void:
	if net_mode != "client":
		return
	if admin_pending != "":
		net.c_admin_login.rpc_id(1, admin_pending)
	else:
		net.c_join.rpc_id(1, _join_info())


func _on_net_failed() -> void:
	if net_mode != "client":
		return
	_leave_multiplayer()
	_start_round(false)
	hud.flash_banner(Loc.t("mp_failed"), Color(1, 0.4, 0.35), 3.5)


func _leave_multiplayer() -> void:
	admin_pending = ""
	admin_view = {}
	if net_mode == "client":
		net.close()
	net_mode = ""
	my_net_id = 0


func _mp_respawn() -> void:
	state = "connecting"
	state_time = 0.0
	net.c_join.rpc_id(1, _join_info())


func client_welcome(data: Dictionary) -> void:
	if net_mode != "client":
		return
	my_net_id = int(data["id"])
	if player != null and is_instance_valid(player) and not player in fighters:
		player.queue_free()
	player = null
	# Arena sıfırlanınca da buraya gelinir: yeni karakter görünene kadar bekleme ekranı
	if state != "menu":
		state = "connecting"
		state_time = 0.0
	_reset_match_stats()
	bushes.clear()
	for b in data["bushes"]:
		bushes.append({"pos": b["pos"], "r": b["r"], "blobs": b["blobs"], "fade": 1.0})
	canopy_dirty = true


## Sunucu yöneticisinden gelen hediye (altın / seviye) kendi kaydımıza yazılır.
func client_grant(coins: int, levels: int) -> void:
	if coins > 0:
		save["coins"] = int(save["coins"]) + coins
		hud.flash_banner(Loc.t("gift_coins") % coins, Color(1, 0.85, 0.3), 3.0)
	if levels > 0:
		save["level"] = mini(int(save["level"]) + levels, GameData.MAX_LEVEL)
		save["xp"] = 0
		hud.flash_banner(Loc.t("gift_level") % int(save["level"]), Color(0.6, 0.85, 1), 3.0)
	_write_save()
	sfx.play("unlock", 0.0, 0.0)


func client_snapshot(d: Dictionary) -> void:
	if net_mode != "client" or state == "admin" or state == "admin_wait":
		return
	var _pt := Time.get_ticks_usec()
	_client_snapshot_body(d)
	perf_mark("snapshot", _pt)


func _client_snapshot_body(d: Dictionary) -> void:
	var seen := {}
	for row in d["f"]:
		var id := int(row[0])
		seen[id] = true
		var f := _fid(id)
		if f == null:
			if not row[10]:
				continue
			f = Fighter.new()
			f.net_id = id
			f.display_name = row[1]
			f.skin_id = row[2]
			f.color = row[3]
			f.face_dir = int(GameData.SKINS[GameData.skin_index(row[2])]["face"])
			f.position = row[6]
			f.net_pos = row[6]
			fighter_layer.add_child(f)
			fighters.append(f)
			fighter_by_id[id] = f
			if id == my_net_id:
				f.is_player = true
				player = f
				state = "playing"
				state_time = 0.0
				camera.position = f.position
				camera.reset_smoothing()
		f.level = row[4]
		f.knife_kind = row[5]
		f.net_pos = row[6]
		f.hp = row[7]
		f.knives = row[8]
		f.kills = row[9]
		f.alive = row[10]
		f.visible = f.alive
		f.move_dir = row[11]
		if f.move_dir.length() < 0.15:
			f.facing = row[12]
		f.shield_t = row[13]
		f.speed_t = row[14]
		f.magnet_t = row[15]
		f.rage_t = row[16]
		f.slow_t = row[17]
		f.dash_t = row[18]
		f.peer_id = row[19]
	# Artık sunucuda olmayan savaşçıları kaldır (kendi ölü karakterimiz sonuç ekranı için kalır)
	for i in range(fighters.size() - 1, -1, -1):
		var f := fighters[i]
		if not seen.has(f.net_id):
			fighters.remove_at(i)
			fighter_by_id.erase(f.net_id)
			if f != player:
				f.queue_free()

	pickups.clear()
	var p: PackedFloat32Array = d["p"]
	for i in range(0, p.size(), 3):
		pickups.append({"pos": Vector2(p[i], p[i + 1]), "vel": Vector2.ZERO, "rot": p[i + 2], "phase": p[i + 2] * 3.0})
	coins_pickups.clear()
	var c: PackedVector2Array = d["c"]
	for i in c.size():
		coins_pickups.append({"pos": c[i], "vel": Vector2.ZERO, "phase": float(i)})
	var old_crates := crates.duplicate()
	crates.clear()
	var k: PackedFloat32Array = d["k"]
	for i in range(0, k.size(), 4):
		var pos := Vector2(k[i], k[i + 1])
		var shake_v := 0.0
		for oc in old_crates:
			if (oc["pos"] as Vector2).distance_squared_to(pos) < 1.0:
				shake_v = oc["shake"]
		crates.append({"pos": pos, "hp": int(k[i + 2]), "rot": k[i + 3], "shake": shake_v})
	powerups.clear()
	for u in d["u"]:
		powerups.append({"pos": u[0], "type": POWERUP_TYPES[int(u[1])], "phase": u[2]})
	hazards.clear()
	for h in d["h"]:
		hazards.append({"kind": h[0], "pos": h[1], "t": h[2]})
	projectiles.clear()
	for j in d["j"]:
		projectiles.append({"pos": j[0], "vel": j[1], "kind": j[2], "life": 1.0})
	for ev in d["e"]:
		_present(ev)


func _client_process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_client_process_body(delta)
	perf_mark("client_frame", _pt)


func _client_process_body(delta: float) -> void:
	delta = minf(delta, 0.05)
	round_time += delta
	state_time += delta
	if (state == "connecting" or state == "admin_wait") and state_time > CONNECT_TIMEOUT and my_net_id == 0:
		_on_net_failed()
		return
	# Girdiyi sunucuya gönder
	input_timer += delta
	if input_timer >= 1.0 / INPUT_RATE and net.is_online() and player != null and player.alive and state == "playing":
		input_timer = 0.0
		var target_id := player_target.net_id if player_target != null else 0
		net.c_input.rpc_id(1, _read_move(), player.facing, _throw_pressed(), target_id)
	# Konumları yumuşakça sunucudaki değerlere yaklaştır; animasyonları ilerlet
	for f in fighters:
		if not f.alive:
			continue
		if f.position.distance_to(f.net_pos) > 250.0:
			f.position = f.net_pos
		else:
			f.position = f.position.lerp(f.net_pos, minf(1.0, delta * 14.0))
		f.on_screen = in_view(f.position, f.ring_radius() + 80.0)
		f.visual_tick(delta)
		_fighter_visual_fx(f, delta)
	# Uçan bıçaklar bir sonraki görüntüye kadar ilerlemeye devam eder
	for pr in projectiles:
		pr["pos"] = (pr["pos"] as Vector2) + (pr["vel"] as Vector2) * delta
		_projectile_fx(pr, delta)
	for cr in crates:
		cr["shake"] = maxf(0.0, float(cr["shake"]) - delta * 4.0)
	if state == "playing":
		_footsteps(delta)
	_update_hiding(delta)
	_update_target()
	_hazard_fx(delta)
	_update_particles(delta)
	if player != null and (player.alive or state != "connecting"):
		_update_camera(delta)
	else:
		camera.position = camera.position.lerp(Vector2.ZERO, delta)
	_redraw_layers()


## Kendi karakterimiz öldü: sıralama = bizden çok leş alan canlı oyuncu sayısı + 1.
func _client_on_death() -> void:
	var better := 0
	for f in fighters:
		if f != player and f.alive and f.kills > player.kills:
			better += 1
	final_rank = better + 1
	_end_round(false)


# --- Yardımcılar (HUD de kullanır) --------------------------------------------

func _alive_fighters() -> Array[Fighter]:
	var out: Array[Fighter] = []
	for f in fighters:
		if f.alive:
			out.append(f)
	return out


func alive_count() -> int:
	return _alive_fighters().size()


func human_count() -> int:
	var n := 0
	for f in fighters:
		if f.alive and (f.peer_id != 0 or f.is_player):
			n += 1
	return n


## Liderler: bıçak sayısına, eşitlikte leşe göre sıralı canlı savaşçılar.
func leaderboard(n: int) -> Array[Fighter]:
	var list := _alive_fighters()
	list.sort_custom(func(a: Fighter, b: Fighter) -> bool: return a.knives > b.knives)
	return list.slice(0, n)


func zone_status() -> String:
	if state != "playing" or net_mode != "":
		return ""
	if round_time < ZONE_DELAY:
		return Loc.t("zone_wait") % ceili(ZONE_DELAY - round_time)
	if zone_radius > ZONE_MIN_RADIUS + 1.0:
		return Loc.t("zone_shrink")
	return ""


# --- Ses, kamera ve efektler ---------------------------------------------------

func in_menu() -> bool:
	return state == "menu" or state == "splash" or state == "admin_login"


## Sesi kameraya uzaklığına göre kısarak çalar; oyuncuyla ilgili sesler her zaman duyulur.
func _sfx_at(sound: String, pos: Vector2, important := false) -> void:
	if in_menu() or net_mode == "server":
		return
	var dist := pos.distance_to(camera.position)
	if not important and dist > HEARING_RANGE:
		return
	var vol := 0.0 if important else lerpf(-5.0, -22.0, dist / HEARING_RANGE)
	sfx.play(sound, vol)


func _near_camera(pos: Vector2) -> bool:
	return net_mode != "server" and in_view(pos, 200.0)


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


## Vuruş anında oyunu çok kısa süre yavaşlatır; darbelere ağırlık katar.
func _hitstop(duration: float) -> void:
	Engine.time_scale = 0.08
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)


func _update_camera(delta: float) -> void:
	var z := 0.55
	if in_menu():
		camera.position = Vector2.from_angle(round_time * 0.06) * 500.0
	else:
		var target: Fighter = player if player != null and player.alive else _leader()
		if target != null:
			camera.position = target.position + target.move_dir * 70.0
			z = clampf(1.05 - (target.ring_radius() - 60.0) * 0.006, 0.6, 1.05)
	camera.zoom = camera.zoom.lerp(Vector2(z, z), minf(1.0, 2.0 * delta))
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	shake = lerpf(shake, 0.0, minf(1.0, 9.0 * delta))
	var size := get_viewport_rect().size / camera.zoom
	view_rect = Rect2(camera.get_screen_center_position() - size / 2.0, size)


func _perf_report(delta: float) -> void:
	perf_timer -= delta
	if perf_timer > 0.0:
		return
	perf_timer = 2.0
	print("PERF fps=%d script_ms=%.1f frame_ms=%.1f draw_calls=%d primitives=%d objects=%d nodes=%d particles=%d" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		1000.0 / maxf(1.0, Engine.get_frames_per_second()),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		particles.size()])
	perf_acc["fighters_draw"] = Fighter.perf_draw_us
	Fighter.perf_draw_us = 0
	perf_acc["hud_draw"] = hud.perf_draw_us
	hud.perf_draw_us = 0
	var frames := maxf(1.0, Engine.get_frames_per_second() * 2.0)
	var parts := PackedStringArray()
	for k in perf_acc.keys():
		parts.append("%s=%.2f" % [k, float(perf_acc[k]) / frames / 1000.0])
	print("PERF ms/kare: " + ", ".join(parts))
	perf_acc.clear()


## Nokta kamera görüş alanında mı (margin kadar genişletilmiş)?
func in_view(p: Vector2, margin := 120.0) -> bool:
	return view_rect.grow(margin).has_point(p)


func _leader() -> Fighter:
	var board := leaderboard(1)
	return board[0] if not board.is_empty() else null


## Kıvılcım çizgileri. dir verilirse o yöne doğru yayılır.
func _fx_sparks(pos: Vector2, col: Color, count: int, speed: float, width: float, dir := Vector2.ZERO) -> void:
	if net_mode == "server":
		return
	if low_fx:
		count = ceili(count * 0.7)
	for i in count:
		var a := dir.angle() + randf_range(-0.9, 0.9) if dir != Vector2.ZERO else randf() * TAU
		var life := randf_range(0.18, 0.4)
		particles.append({"kind": "spark", "pos": pos, "vel": Vector2.from_angle(a) * speed * randf_range(0.4, 1.0),
			"life": life, "max": life, "col": col, "w": width})


func _fx_ring(pos: Vector2, col: Color, radius: float, life: float, width: float) -> void:
	if net_mode == "server":
		return
	particles.append({"kind": "ring", "pos": pos, "r": radius, "life": life, "max": life, "col": col, "w": width})


func _fx_smoke(pos: Vector2, count: int, col: Color) -> void:
	if net_mode == "server":
		return
	if low_fx:
		count = ceili(count * 0.6)
	for i in count:
		var life := randf_range(0.5, 0.9)
		particles.append({"kind": "smoke", "pos": pos + _random_point(14.0),
			"vel": Vector2.from_angle(randf() * TAU) * randf_range(20.0, 90.0) + Vector2(0, -20),
			"life": life, "max": life, "col": col, "r": randf_range(10.0, 20.0)})


func _fx_dust(pos: Vector2) -> void:
	if net_mode == "server" or (low_fx and randf() < 0.3):
		return
	var life := randf_range(0.35, 0.55)
	particles.append({"kind": "dust", "pos": pos, "vel": Vector2(randf_range(-20, 20), randf_range(-25, -5)),
		"life": life, "max": life, "col": Color(0.85, 0.9, 0.75, 0.45), "r": randf_range(5.0, 9.0)})


func _fx_text(pos: Vector2, text: String, col: Color, size: int) -> void:
	if net_mode == "server":
		return
	particles.append({"kind": "text", "pos": pos, "vel": Vector2(0, -70), "life": 0.9, "max": 0.9,
		"col": col, "text": text, "size": size})


func _update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p := particles[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			particles.remove_at(i)
			continue
		if p.has("vel"):
			var vel: Vector2 = p["vel"]
			p["pos"] = (p["pos"] as Vector2) + vel * delta
			p["vel"] = vel * (0.86 if p["kind"] in ["spark", "plank"] else 0.95)
		if p.has("spin"):
			p["rot"] = float(p["rot"]) + float(p["spin"]) * delta


# --- Çizim katmanları ---------------------------------------------------------

const GROUND_TEX_SIZE := 2048
const GROUND_EXTENT := ARENA_RADIUS + 90.0
var ground_tex: Texture2D = null


## Zemin bir kez ekran dışı bir tuvale (SubViewport) çizilip tek bir resme dönüştürülür.
## Her karede yüzlerce çim/çiçek/taş yerine tek bir resim çizilir (web'de çok büyük kazanç).
func _bake_ground() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(GROUND_TEX_SIZE, GROUND_TEX_SIZE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var painter := Node2D.new()
	painter.position = Vector2(GROUND_TEX_SIZE, GROUND_TEX_SIZE) / 2.0
	painter.scale = Vector2.ONE * (GROUND_TEX_SIZE / (GROUND_EXTENT * 2.0))
	vp.add_child(painter)
	painter.draw.connect(func() -> void: _paint_ground(painter))
	ground_tex = vp.get_texture()
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ground.queue_redraw()


func _draw_ground() -> void:
	if ground_tex != null:
		ground.draw_texture_rect(ground_tex, Rect2(-GROUND_EXTENT, -GROUND_EXTENT, GROUND_EXTENT * 2.0, GROUND_EXTENT * 2.0), false)


func _paint_ground(ci: CanvasItem) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	ci.draw_circle(Vector2.ZERO, ARENA_RADIUS + 80.0, Color(0.14, 0.2, 0.17))
	ci.draw_circle(Vector2.ZERO, ARENA_RADIUS + 20.0, Color(0.24, 0.36, 0.25))
	ci.draw_circle(Vector2.ZERO, ARENA_RADIUS, Color(0.36, 0.6, 0.36))
	# Açık ve koyu çim lekeleri
	for i in 140:
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (ARENA_RADIUS - 120.0)
		var light := rng.randf() < 0.5
		ci.draw_circle(p, rng.randf_range(60.0, 150.0),
			Color(0.45, 0.7, 0.4, 0.18) if light else Color(0.25, 0.48, 0.27, 0.2))
	# Çim tutamları, çiçekler ve taşlar
	for i in 900:
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (ARENA_RADIUS - 30.0)
		var roll := rng.randf()
		if roll < 0.75:
			var c := Color(0.24, 0.47, 0.25, 0.8) if rng.randf() < 0.6 else Color(0.5, 0.75, 0.4, 0.7)
			ci.draw_line(p, p + Vector2(-5, -9), c, 3.0)
			ci.draw_line(p, p + Vector2(0, -12), c, 3.0)
			ci.draw_line(p, p + Vector2(5, -9), c, 3.0)
		elif roll < 0.92:
			var petal: Color = [Color(1, 0.95, 0.5), Color(1, 1, 1), Color(1, 0.6, 0.7), Color(0.7, 0.75, 1)][rng.randi() % 4]
			for k in 4:
				ci.draw_circle(p + Vector2.from_angle(k * PI / 2.0) * 3.0, 2.8, petal)
			ci.draw_circle(p, 2.2, Color(1, 0.75, 0.2))
		else:
			ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.7))
			ci.draw_circle(Vector2(1, 3), rng.randf_range(6.0, 11.0), Color(0, 0, 0, 0.18))
			ci.draw_circle(Vector2.ZERO, rng.randf_range(6.0, 10.0), Color(0.6, 0.62, 0.6))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(1, 6):
		ci.draw_arc(Vector2.ZERO, ARENA_RADIUS * i / 6.0, 0.0, TAU, 128, Color(1, 1, 1, 0.04), 6.0)
	ci.draw_arc(Vector2.ZERO, ARENA_RADIUS, 0.0, TAU, 160, Color(0.12, 0.17, 0.13), 16.0)


func _draw_zone() -> void:
	var _pt := Time.get_ticks_usec()
	_draw_zone_body()
	perf_mark("_draw_zone", _pt)


func _draw_zone_body() -> void:
	if zone_radius >= ARENA_RADIUS - 1.0:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var w := ARENA_RADIUS - zone_radius
	zone_layer.draw_arc(Vector2.ZERO, zone_radius + w * 0.5, 0.0, TAU, 160, Color(0.8, 0.08, 0.15, 0.32), w)
	var pulse := 0.6 + 0.4 * sin(t * 4.0)
	zone_layer.draw_arc(Vector2.ZERO, zone_radius + 10.0, 0.0, TAU, 160, Color(1, 0.3, 0.3, 0.25 * pulse), 20.0)
	zone_layer.draw_arc(Vector2.ZERO, zone_radius, 0.0, TAU, 160, Color(1, 0.4, 0.4, 0.95), 6.0)


func _draw_crate(ci: CanvasItem, c: Dictionary) -> void:
	var shake_off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * float(c["shake"]) * 4.0
	var pos: Vector2 = c["pos"] + shake_off
	var h := CRATE_SIZE * 0.5
	ci.draw_set_transform(pos + Vector2(4, 8), c["rot"], Vector2.ONE)
	ci.draw_rect(Rect2(-h, -h, CRATE_SIZE, CRATE_SIZE), Color(0, 0, 0, 0.25))
	ci.draw_set_transform(pos, c["rot"], Vector2.ONE)
	ci.draw_rect(Rect2(-h, -h, CRATE_SIZE, CRATE_SIZE), Color(0.42, 0.25, 0.12))
	ci.draw_rect(Rect2(-h + 4, -h + 4, CRATE_SIZE - 8, CRATE_SIZE - 8), Color(0.78, 0.52, 0.27))
	for k in 3:
		var y := -h + 4 + k * (CRATE_SIZE - 8) / 3.0
		ci.draw_line(Vector2(-h + 4, y), Vector2(h - 4, y), Color(0.55, 0.34, 0.16), 2.0)
	ci.draw_line(Vector2(-h + 5, -h + 5), Vector2(h - 5, h - 5), Color(0.6, 0.38, 0.18), 5.0)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ci.draw_rect(Rect2(corner * (h - 6) - Vector2(5, 5), Vector2(10, 10)), Color(0.7, 0.72, 0.75))
	ci.draw_rect(Rect2(-h, -h, CRATE_SIZE, CRATE_SIZE), Color(0.25, 0.14, 0.06), false, 3.0)
	# Hasar çatlakları
	if int(c["hp"]) < CRATE_HP:
		ci.draw_polyline(PackedVector2Array([Vector2(-6, -h + 4), Vector2(0, -6), Vector2(-4, 4), Vector2(4, 14)]), Color(0.2, 0.1, 0.05), 2.0)
	if int(c["hp"]) < CRATE_HP - 1:
		ci.draw_polyline(PackedVector2Array([Vector2(h - 4, 2), Vector2(6, 6), Vector2(10, 16)]), Color(0.2, 0.1, 0.05), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# İçinde ne olduğu belli olmayan "?" işareti (yavaşça parlar)
	var t := Time.get_ticks_msec() / 1000.0
	var glow := 0.6 + 0.4 * sin(t * 3.0 + pos.x * 0.01)
	ci.draw_texture_rect(GameData.glow_tex(), Rect2(pos - Vector2(30, 30), Vector2(60, 60)), false, Color(1, 0.85, 0.3, 0.35 * glow))
	var font := ThemeDB.fallback_font
	ci.draw_string_outline(font, pos + Vector2(-20, 13), "?", HORIZONTAL_ALIGNMENT_CENTER, 40, 36, 7, Color(0.25, 0.12, 0.02))
	ci.draw_string(font, pos + Vector2(-20, 13), "?", HORIZONTAL_ALIGNMENT_CENTER, 40, 36, Color(1, 0.88, 0.35).lerp(Color.WHITE, glow * 0.3))


func _draw_items() -> void:
	var _pt := Time.get_ticks_usec()
	_draw_items_body()
	perf_mark("_draw_items", _pt)


func _draw_items_body() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for c in crates:
		if in_view(c["pos"], 60.0):
			_draw_crate(items, c)
	for h in hazards:
		var hpos: Vector2 = h["pos"]
		if not in_view(hpos, 200.0):
			continue
		if h["kind"] == "bomb":
			# Patlama alanı uyarısı + fitili yanan bomba
			var left := float(h["t"])
			var blink := fmod(left * (4.0 + (1.1 - left) * 10.0), 1.0) < 0.5
			GameData.disc(items, hpos, 170.0, Color(1, 0.2, 0.1, 0.12 if blink else 0.06))
			items.draw_arc(hpos, 170.0, 0.0, TAU, 64, Color(1, 0.3, 0.2, 0.7), 3.0)
			GameData.disc(items, hpos + Vector2(3, 6), 20.0, Color(0, 0, 0, 0.3))
			GameData.disc(items, hpos, 20.0, Color(0.15, 0.15, 0.18))
			GameData.disc(items, hpos + Vector2(-6, -6), 6.0, Color(1, 1, 1, 0.25))
			items.draw_line(hpos + Vector2(8, -16), hpos + Vector2(14, -26), Color(0.6, 0.5, 0.3), 3.0)
			GameData.disc(items, hpos + Vector2(14, -27), 5.0 + randf() * 3.0, Color(1, 0.8, 0.2) if blink else Color(1, 0.3, 0.1))
		else:
			var a := clampf(float(h["t"]), 0.0, 1.0)
			GameData.disc(items, hpos, 120.0, Color(0.4, 0.85, 0.25, 0.18 * a))
			items.draw_arc(hpos, 120.0, 0.0, TAU, 48, Color(0.5, 1, 0.3, 0.5 * a), 3.0)
	for c in coins_pickups:
		var pos: Vector2 = c["pos"]
		if not in_view(pos, 30.0):
			continue
		var bob := sin(t * 4.0 + float(c["phase"])) * 3.0
		items.draw_set_transform(pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.4))
		GameData.disc(items, Vector2.ZERO, 9.0, Color(0, 0, 0, 0.2))
		items.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Dönüyormuş gibi görünsün diye yatayda daralıp genişler
		var spin := absf(cos(t * 3.0 + float(c["phase"])))
		items.draw_set_transform(pos + Vector2(0, bob - 4.0), 0.0, Vector2(0.35 + 0.65 * spin, 1.0))
		GameData.draw_coin(items, Vector2.ZERO, 11.0)
		items.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for p in pickups:
		var pos: Vector2 = p["pos"]
		if not in_view(pos, 30.0):
			continue
		if not low_fx:
			items.draw_set_transform(pos + Vector2(3, 5), 0.0, Vector2(1.0, 0.5))
			GameData.disc(items, Vector2.ZERO, 12.0, Color(0, 0, 0, 0.18))
			items.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		KnifeArt.draw(items, pos, p["rot"], 0.9)
		# Ara sıra parlama
		var g := fmod(t + float(p["phase"]), 3.0)
		if g < 0.25:
			var a := 1.0 - absf(g - 0.125) / 0.125
			var c := pos + Vector2(4, -6)
			items.draw_line(c - Vector2(7, 0) * a, c + Vector2(7, 0) * a, Color(1, 1, 1, a), 2.0)
			items.draw_line(c - Vector2(0, 7) * a, c + Vector2(0, 7) * a, Color(1, 1, 1, a), 2.0)
	for p in powerups:
		var info: Dictionary = GameData.POWERUPS[p["type"]]
		var bob := sin(t * 3.0 + float(p["phase"])) * 7.0
		var pos: Vector2 = p["pos"]
		if not in_view(pos, 60.0):
			continue
		var glow: Color = info["color"]
		items.draw_set_transform(pos + Vector2(0, 26), 0.0, Vector2(1.0, 0.4))
		GameData.disc(items, Vector2.ZERO, 22.0 - bob * 0.5, Color(0, 0, 0, 0.25))
		items.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var c := pos + Vector2(0, bob - 6.0)
		GameData.disc(items, c, 34.0 + sin(t * 5.0) * 3.0, Color(glow, 0.18))
		items.draw_arc(c, 30.0, t * 2.0, t * 2.0 + PI * 1.3, 24, Color(glow, 0.7), 3.0)
		var icon: Texture2D = GameData.tex(info["icon"]) if info["icon"] != "" else null
		if icon != null:
			items.draw_texture_rect(icon, Rect2(c - Vector2(26, 26), Vector2(52, 52)), false)
		else:
			# +5 bıçak paketi: yelpaze şeklinde bıçaklar ve "x5"
			GameData.disc(items, c, 24.0, Color(0.2, 0.25, 0.35, 0.9))
			for k in 3:
				KnifeArt.draw(items, c + Vector2(0, 2), (k - 1) * 0.5, 0.75, 0, false)
			var font := ThemeDB.fallback_font
			items.draw_string_outline(font, c + Vector2(-2, 26), "x5", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
			items.draw_string(font, c + Vector2(-2, 26), "x5", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.4))


func _draw_fx_low() -> void:
	var _pt := Time.get_ticks_usec()
	_draw_fx_low_body()
	perf_mark("_draw_fx_low", _pt)


func _draw_fx_low_body() -> void:
	for p in particles:
		var kind: String = p["kind"]
		if (kind != "smoke" and kind != "dust") or not in_view(p["pos"], 60.0):
			continue
		var t := float(p["life"]) / float(p["max"])
		var c: Color = p["col"]
		c.a *= t
		var r: float = p["r"] * (1.0 + (1.0 - t) * (1.5 if kind == "smoke" else 0.6))
		GameData.disc(fx_low, p["pos"], r, c)


func _draw_canopy() -> void:
	var _pt := Time.get_ticks_usec()
	_draw_canopy_body()
	perf_mark("_draw_canopy", _pt)


func _draw_canopy_body() -> void:
	for b in bushes:
		var center: Vector2 = b["pos"]
		var fade: float = b["fade"]
		for blob in b["blobs"]:
			var v: Vector3 = blob
			GameData.disc(canopy, center + Vector2(v.x, v.y + 8), v.z, Color(0.08, 0.2, 0.14, 0.5 * fade))
		for blob in b["blobs"]:
			var v: Vector3 = blob
			GameData.disc(canopy, center + Vector2(v.x, v.y), v.z, Color(0.16, 0.42, 0.3, 0.95 * fade))
		for blob in b["blobs"]:
			var v: Vector3 = blob
			var p := center + Vector2(v.x, v.y)
			GameData.disc(canopy, p + Vector2(-v.z * 0.2, -v.z * 0.25), v.z * 0.6, Color(0.24, 0.56, 0.38, 0.95 * fade))
			canopy.draw_arc(p + Vector2(-v.z * 0.15, -v.z * 0.2), v.z * 0.45, PI * 1.1, PI * 1.6, 8,
				Color(0.45, 0.78, 0.55, 0.8 * fade), 4.0)


## Otomatik hedef: oyuncudan hedefe akan kırmızı oklar ve hedefin etrafında dönen nişangah.
func _draw_target() -> void:
	if player_target == null or player == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var from := player.position
	var to := player_target.position
	var dir := (to - from).normalized()
	var start := Fighter.BODY_RADIUS + 18.0
	var length := from.distance_to(to) - Fighter.BODY_RADIUS - 30.0
	var side := dir.orthogonal()
	var d := start + fmod(t * 120.0, 22.0)
	while d < length:
		var p := from + dir * d
		var a := clampf(minf(d - start, length - d) / 40.0, 0.0, 1.0) * 0.9
		fx.draw_polyline(PackedVector2Array([p - dir * 6.0 + side * 6.0, p, p - dir * 6.0 - side * 6.0]),
			Color(1, 0.2, 0.2, a), 3.5)
		d += 22.0
	var r := Fighter.BODY_RADIUS + 14.0 + sin(t * 8.0) * 3.0
	for k in 4:
		var a0 := t * 2.5 + k * PI / 2.0
		fx.draw_arc(to, r, a0, a0 + 0.9, 8, Color(1, 0.25, 0.2, 0.95), 4.0)
	GameData.disc(fx, to + Vector2(0, -r - 14.0 - absf(sin(t * 6.0)) * 6.0), 6.0, Color(1, 0.25, 0.2))


func _draw_fx() -> void:
	var _pt := Time.get_ticks_usec()
	_draw_fx_body()
	perf_mark("_draw_fx", _pt)


func _draw_fx_body() -> void:
	_draw_target()
	for p in projectiles:
		var vel: Vector2 = p["vel"]
		var pos: Vector2 = p["pos"]
		if not in_view(pos, 80.0):
			continue
		var n := vel.normalized()
		var glow: Color = GameData.KNIVES[p["kind"]]["glow"]
		var trail := Color(glow, 1.0) if glow.a > 0.0 else Color(1, 1, 1)
		for k in 5:
			fx.draw_line(pos - n * (10.0 + k * 11.0), pos - n * (21.0 + k * 11.0), Color(trail, 0.45 - k * 0.08), 7.0 - k)
		KnifeArt.draw(fx, pos, vel.angle() + PI / 2.0, 1.25, p["kind"])
	var font := ThemeDB.fallback_font
	for p in particles:
		if not in_view(p["pos"], 60.0):
			continue
		var t := float(p["life"]) / float(p["max"])
		var c: Color = p["col"]
		match p["kind"]:
			"ember":
				var c2: Color = p["col2"]
				var ec := c2.lerp(c, 1.0 - t)
				ec.a = t
				GameData.disc(fx, p["pos"], float(p["r"]) * (0.4 + t * 0.6), ec)
			"sparkle":
				var sz: float = p["r"] * sin(t * PI)
				var sp: Vector2 = p["pos"]
				c.a = t
				fx.draw_line(sp - Vector2(sz, 0), sp + Vector2(sz, 0), c, 2.0)
				fx.draw_line(sp - Vector2(0, sz), sp + Vector2(0, sz), c, 2.0)
			"bubble":
				c.a = t * 0.9
				fx.draw_arc(p["pos"], p["r"], 0.0, TAU, 12, c, 1.5)
				GameData.disc(fx, (p["pos"] as Vector2) + Vector2(-1, -1), float(p["r"]) * 0.3, Color(1, 1, 1, t * 0.6))
			"bolt":
				c.a = t
				fx.draw_polyline(p["pts"], c, 2.5)
				fx.draw_polyline(p["pts"], Color(1, 1, 1, t), 1.0)
			"plank":
				c.a = clampf(t * 2.0, 0.0, 1.0)
				fx.draw_set_transform(p["pos"], p["rot"], Vector2.ONE)
				fx.draw_rect(Rect2(-9, -3, 18, 6), c)
				fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"spark":
				var vel: Vector2 = p["vel"]
				var pos: Vector2 = p["pos"]
				c.a *= t
				fx.draw_line(pos, pos - vel * 0.045, c, maxf(1.0, float(p["w"]) * t))
			"ring":
				c.a *= t
				var r: float = p["r"] * (1.0 - 0.7 * t * t)
				fx.draw_arc(p["pos"], r, 0.0, TAU, 32, c, float(p["w"]) * t + 1.0)
			"text":
				var age := 1.0 - t
				var sc := 1.0 + maxf(0.0, 0.25 - age) * 3.0
				c.a = clampf(t * 2.5, 0.0, 1.0)
				# Yazı boyutu sabit; büyüme ölçekle yapılır (boyut değişimi harfleri baştan üretir, çok pahalı)
				var size := int(p["size"])
				fx.draw_set_transform(p["pos"], 0.0, Vector2(sc, sc))
				fx.draw_string_outline(font, Vector2(-100, 0), p["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, 6, Color(0, 0, 0, c.a * 0.85))
				fx.draw_string(font, Vector2(-100, 0), p["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, c)
				fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Yönetim paneli (uzaktan) -----------------------------------------------------

## Sunucudaki yönetici şifresi (Render'da ADMIN_PASSWORD ortam değişkeni). Boşsa uzaktan giriş kapalı.
func _admin_password() -> String:
	return OS.get_environment("ADMIN_PASSWORD")


func server_admin_login(peer: int, password: String) -> void:
	var ok := _admin_password() != "" and password == _admin_password()
	if ok:
		admin_peers[peer] = true
		admin_timer = 0.0
		slog("Yönetici girişi (%s)" % net.peer_ip(peer), Color(1, 0.85, 0.3))
	else:
		slog("Hatalı yönetici şifresi denemesi (%s)" % net.peer_ip(peer), Color(1, 0.4, 0.35))
	net.s_admin_result.rpc_id(peer, ok)


func server_admin_cmd(peer: int, id: String) -> void:
	if admin_peers.has(peer) and id.begins_with("adm_"):
		_admin(id)
		admin_timer = 0.0


## Yönetim panelinin gösterdiği veriler (sunucu penceresi ve uzaktaki yönetici aynı veriyi kullanır).
func admin_data() -> Dictionary:
	if net_mode == "client":
		return admin_view
	var bots := 0
	for f in fighters:
		if f.alive and f.peer_id == 0:
			bots += 1
	var players := []
	var now := Time.get_ticks_msec()
	for peer in peer_info.keys():
		var info: Dictionary = peer_info[peer]
		var f := _fid(peers.get(peer, 0))
		players.append({
			"peer": peer, "name": info["name"], "ip": info["ip"], "since": (now - int(info["since"])) / 1000,
			"skin": f.skin_id if f != null else "", "level": f.level if f != null else 1,
			"kills": f.kills if f != null else 0, "knives": f.knives if f != null else 0, "alive": f != null and f.alive,
		})
	return {
		"uptime": now / 1000, "urls": server_urls, "players": players, "bots": bots, "bot_target": bot_target,
		"alive": alive_count(), "joins": total_joins, "admins": admin_peers.size(), "log": server_log.slice(0, 30),
	}


## Menüden yönetici girişi: sunucuya bağlanır, oyuncu olarak değil yönetici olarak giriş yapar.
func admin_connect(password: String) -> void:
	admin_pending = password
	_clear_world()
	net_mode = "client"
	state = "admin_wait"
	state_time = 0.0
	if net.connect_to(_mp_host()) != OK:
		_on_net_failed()


func client_admin_result(ok: bool) -> void:
	admin_pending = ""
	if ok:
		state = "admin"
		sfx.play("unlock", 0.0, 0.0)
	else:
		_leave_multiplayer()
		_start_round(false)
		hud.flash_banner(Loc.t("wrong_password"), Color(1, 0.4, 0.35), 3.0)


func client_admin_state(data: Dictionary) -> void:
	admin_view = data
