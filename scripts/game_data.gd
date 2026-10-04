class_name GameData
extends RefCounted
## Karakterler, bıçak türleri, güçlendirmeler ve sprite yükleme.
## İsim/açıklamalar loc.gd içinde.

## price: altın cinsinden fiyat (0 = baştan açık). level: satın almak için gereken seviye.
## face: yürüme animasyonunda karakterin baktığı yön (1 = sağ, -1 = sol, 0 = önden).
const SKINS := [
	{"id": "skin_keloglan", "price": 0, "level": 1, "face": 0, "color": Color(0.9, 0.3, 0.25)},
	{"id": "skin_ninja", "price": 0, "level": 1, "face": 0, "color": Color(0.85, 0.2, 0.2)},
	{"id": "skin_knight", "price": 0, "level": 1, "face": -1, "color": Color(0.3, 0.5, 0.95)},
	{"id": "skin_frog", "price": 80, "level": 1, "face": -1, "color": Color(0.3, 0.8, 0.3)},
	{"id": "skin_pehlivan", "price": 120, "level": 2, "face": 0, "color": Color(0.75, 0.5, 0.25)},
	{"id": "skin_pirate", "price": 160, "level": 3, "face": 1, "color": Color(0.75, 0.15, 0.25)},
	{"id": "skin_hoca", "price": 220, "level": 4, "face": 0, "color": Color(0.35, 0.7, 0.4)},
	{"id": "skin_zeybek", "price": 280, "level": 5, "face": 0, "color": Color(0.85, 0.2, 0.3)},
	{"id": "skin_samurai", "price": 350, "level": 7, "face": 0, "color": Color(0.95, 0.4, 0.1)},
	{"id": "skin_yeniceri", "price": 450, "level": 9, "face": 1, "color": Color(0.3, 0.45, 0.9)},
	{"id": "skin_viking", "price": 550, "level": 11, "face": 0, "color": Color(0.9, 0.65, 0.2)},
	{"id": "skin_gokturk", "price": 700, "level": 14, "face": 0, "color": Color(0.3, 0.75, 0.95)},
	{"id": "skin_sultan", "price": 900, "level": 18, "face": 0, "color": Color(1.0, 0.8, 0.25)},
]

## Bıçak türleri (görsel). tex: sprite adı; yoksa çelik bıçak "color" ile boyanır.
## glow: bıçağın arkasındaki parlama, fx: etrafa saçtığı parçacık türü.
const KNIVES := [
	{"id": "knife_steel", "tex": "knife", "color": Color(1, 1, 1), "glow": Color(1, 1, 1, 0.0), "fx": "", "price": 0, "level": 1},
	{"id": "knife_fire", "tex": "knife_fire", "color": Color(1, 0.6, 0.3), "glow": Color(1, 0.45, 0.1, 0.55), "fx": "fire", "price": 100, "level": 2},
	{"id": "knife_ice", "tex": "knife_ice", "color": Color(0.6, 0.9, 1), "glow": Color(0.4, 0.85, 1, 0.5), "fx": "ice", "price": 150, "level": 3},
	{"id": "knife_poison", "tex": "knife_poison", "color": Color(0.5, 1, 0.4), "glow": Color(0.35, 1, 0.3, 0.45), "fx": "poison", "price": 200, "level": 4},
	{"id": "knife_yatagan", "tex": "knife_yatagan", "color": Color(1, 0.85, 0.4), "glow": Color(1, 0.8, 0.25, 0.5), "fx": "gold", "price": 300, "level": 6},
	{"id": "knife_thunder", "tex": "knife", "color": Color(1, 0.95, 0.45), "glow": Color(1, 0.95, 0.3, 0.55), "fx": "electric", "price": 400, "level": 8},
	{"id": "knife_void", "tex": "knife", "color": Color(0.75, 0.5, 1), "glow": Color(0.6, 0.3, 1, 0.6), "fx": "void", "price": 550, "level": 11},
	{"id": "knife_crimson", "tex": "knife", "color": Color(1, 0.35, 0.35), "glow": Color(1, 0.15, 0.2, 0.55), "fx": "fire", "price": 750, "level": 15},
]

const POWERUPS := {
	"speed": {"icon": "pu_speed", "color": Color(1, 0.85, 0.2), "duration": 6.0},
	"shield": {"icon": "pu_shield", "color": Color(0.35, 0.7, 1), "duration": 5.0},
	"heal": {"icon": "pu_heal", "color": Color(1, 0.3, 0.35), "duration": 0.0},
	"magnet": {"icon": "pu_magnet", "color": Color(0.85, 0.45, 0.95), "duration": 8.0},
	"knives": {"icon": "", "color": Color(1, 1, 1), "duration": 0.0},
}

## Ekonomi: maç sonu ödülleri (altın).
const COIN_PER_KILL := 8
const RANK_BONUS := [60, 40, 30, 20, 20] # 1.-5. sıra; daha aşağısı RANK_BONUS_REST
const RANK_BONUS_REST := 10
const DAILY_BONUS := 50
const STARTING_COINS := 40

## Seviye sistemi: maç sonu XP ile seviye atlanır, her seviye altın ödülü verir.
const MAX_LEVEL := 50
const XP_PER_KILL := 25
const XP_RANK := [120, 80, 60, 40, 40] # 1.-5. sıra
const XP_RANK_REST := 20
const XP_PER_BOX := 6

## Gizemli kutu içerikleri. good: iyi mi kötü mü, weight: çıkma ağırlığı.
const MYSTERY := [
	{"id": "knives", "good": true, "weight": 22},
	{"id": "coins", "good": true, "weight": 18},
	{"id": "powerup", "good": true, "weight": 16},
	{"id": "rage", "good": true, "weight": 9},
	{"id": "bomb", "good": false, "weight": 14},
	{"id": "slow", "good": false, "weight": 8},
	{"id": "thief", "good": false, "weight": 7},
	{"id": "poison", "good": false, "weight": 6},
]


## Bir sonraki seviyeye geçmek için gereken XP (seviye arttıkça yavaşça artar).
static func xp_needed(level: int) -> int:
	return 100 + (level - 1) * 45


## Seviyeye ulaşınca verilen altın ödülü; her 5 seviyede bir büyük ödül.
static func level_reward(level: int) -> int:
	return 150 + level * 10 if level % 5 == 0 else 30 + level * 6


static func roll_mystery() -> Dictionary:
	var total := 0
	for m in MYSTERY:
		total += int(m["weight"])
	var r := randi() % total
	for m in MYSTERY:
		r -= int(m["weight"])
		if r < 0:
			return m
	return MYSTERY[0]

static var _tex_cache := {}
static var _glow: Texture2D
static var _disc: Texture2D


## Kenarı yumuşatılmış beyaz daire dokusu. draw_circle yerine bununla çizilen daireler
## tek seferde toplu çizilebilir (web/telefonda çizim komutu sayısını ciddi azaltır).
static func disc_tex() -> Texture2D:
	# Hazır dosya varsa onu kullan (açılışta piksel piksel üretmek web'de yavaş)
	if _disc == null and ResourceLoader.exists("res://assets/fx_disc.png"):
		_disc = load("res://assets/fx_disc.png")
	if _disc == null:
		var size := 128
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var r := size / 2.0
		for y in size:
			for x in size:
				var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(r - d, 0.0, 1.0)))
		_disc = ImageTexture.create_from_image(img)
	return _disc


## Test için kapatılabilir (web'de ?nodisc).
static var use_disc := true


## draw_circle'ın toplu çizilebilen karşılığı.
static func disc(ci: CanvasItem, pos: Vector2, r: float, col: Color) -> void:
	if use_disc:
		ci.draw_texture_rect(disc_tex(), Rect2(pos.x - r, pos.y - r, r * 2.0, r * 2.0), false, col)
	else:
		ci.draw_circle(pos, r, col)


## Altın ikonu çizer (arayüz ve arena için).
static func draw_coin(ci: CanvasItem, pos: Vector2, r: float, alpha := 1.0) -> void:
	disc(ci, pos + Vector2(0, r * 0.15), r, Color(0.55, 0.35, 0.05, alpha))
	disc(ci, pos, r, Color(1.0, 0.8, 0.2, alpha))
	disc(ci, pos, r * 0.68, Color(0.95, 0.65, 0.1, alpha))
	disc(ci, pos + Vector2(-r * 0.2, -r * 0.2), r * 0.22, Color(1, 0.95, 0.6, alpha))


## assets/sprites/<id>.png dosyasını yükler; yoksa null döner (kod çizimine geri düşülür).
static func tex(id: String) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var path := "res://assets/sprites/%s.png" % id
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[id] = t
	return t


## Yumuşak, yuvarlak parlama dokusu (kodla üretilir).
static func glow_tex() -> Texture2D:
	if _glow == null and ResourceLoader.exists("res://assets/fx_glow.png"):
		_glow = load("res://assets/fx_glow.png")
	if _glow == null:
		var size := 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var d := Vector2(x + 0.5 - size / 2.0, y + 0.5 - size / 2.0).length() / (size / 2.0)
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_glow = ImageTexture.create_from_image(img)
	return _glow


static func skin_index(id: String) -> int:
	for i in SKINS.size():
		if SKINS[i]["id"] == id:
			return i
	return 0


static func knife_index(id: String) -> int:
	for i in KNIVES.size():
		if KNIVES[i]["id"] == id:
			return i
	return 0


## Sprite'ı henüz üretilmemiş karakterleri listeden çıkarır.
static func available_skins() -> Array:
	return SKINS.filter(func(s: Dictionary) -> bool: return tex(s["id"]) != null)
