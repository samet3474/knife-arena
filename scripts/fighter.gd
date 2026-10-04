class_name Fighter
extends Node2D
## Arenadaki bir savaşçı (oyuncu veya bot). Etrafında bıçaklar döner.
## Çizim katmanları: gölge + arkadaki bıçaklar (_draw) → karakter sprite'ı (body) →
## öndeki bıçaklar, kalkan, isim ve can barı (overlay).

const FLASH_SHADER := preload("res://shaders/flash.gdshader")
const BODY_RADIUS := 28.0
const MAX_KNIVES := 60
const BASE_SPEED := 335.0
const SPRITE_SIZE := 98.0
const MAGNET_RADIUS := 280.0
const WALK_FPS := 12.0
const DASH_SPEED := 950.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 2.0

## Telefonda daha hafif çizim (bıçak hareket izleri ve parlamaları çizilmez). main.gd ayarlar.
static var low_fx := false

## Kamera görüş alanında değilse yeniden çizilmez (main.gd her karede ayarlar).
var on_screen := true
## Ölçüm: çizime harcanan toplam mikro saniye (main.gd performans raporu okur)
static var perf_draw_us := 0

var net_id := 0 # ağ üzerinde savaşçıyı tanımlayan numara
var peer_id := 0 # çok oyunculuda bu savaşçıyı yöneten oyuncunun bağlantısı (0 = bot)
var net_throw := false # sunucu: uzak oyuncu fırlatma tuşunu basılı tutuyor mu
var net_target := 0 # sunucu: uzak oyuncunun kilitlendiği hedefin net_id'si
var net_pos := Vector2.ZERO # istemci: sunucudan gelen son konum (yumuşak geçiş için)
var display_name := ""
var skin_id := ""
var face_dir := 0 # sprite'ın doğal bakış yönü (GameData.SKINS "face")
var level := 1
var streak := 0 # ölmeden alınan leş sayısı
var last_kill_time := -99.0
var multi := 0 # kısa sürede art arda alınan leş sayısı
var knife_kind := 0
var accessory := 0 # GameData.ACCESSORIES sırası (seviye eşyası)
var bombs := 0 # elde tutulan bomba sayısı; fırlatınca önce bomba atılır
var skin_fx := "" # karaktere özel parçacık efekti
var aura_col := Color(0, 0, 0, 0) # ayak altındaki parlayan halka rengi (efektli karakterler)
var boss := false # Dev Boss: büyük gövde, çok can, yavaş

const BOSS_SCALE := 1.5
const KNIFE_REGEN_MAX := 6 # bu sayının altındayken bıçak kendiliğinden gelir
const KNIFE_REGEN_TIME := 2.5 # saniyede bir
const MAX_BOMBS := 3


## Gövde yarıçapı (boss daha iri, vurulması da kolay).
func body_r() -> float:
	return BODY_RADIUS * (BOSS_SCALE if boss else 1.0)
var in_bush := false
var concealed := false # çalıda ve oyuncuya uzak: ismi gizlenir
var color := Color.WHITE
var is_player := false
var alive := true
var max_hp := 100.0
var hp := 100.0
var knives := 4
var kills := 0
var orbit_angle := 0.0
var move_dir := Vector2.ZERO
var facing := Vector2.RIGHT
var flip := 1.0
var knock := Vector2.ZERO
var hurt_flash := 0.0
var squash := 0.0
var since_hit := 99.0
var throw_cooldown := 0.0
var last_attacker_id := 0
var moving := false
var anim_time := 0.0
var idle_time := 0.0

# Güçlendirme süreleri (saniye)
var speed_t := 0.0
var shield_t := 0.0
var magnet_t := 0.0
var rage_t := 0.0 # gizemli kutu: hasar x1.6
var inf_t := 0.0 # sınırsız bıçak (∞) güçlendirmesi
var regen_timer := 0.0 # bıçak yenilenmesi
var slow_t := 0.0 # gizemli kutu: yavaşlama
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.ZERO
var afterimages: Array[Dictionary] = [] # atılırken bırakılan hayalet izler

# Bot yapay zekası
var think_timer := 0.0
var want_dir := Vector2.ZERO
var wander_dir := Vector2.RIGHT
var aggression := 0.5

var body: Sprite2D
var overlay: Node2D
var _walk_frames := 1
var _base_scale := 1.0


func _ready() -> void:
	idle_time = randf() * 10.0
	body = Sprite2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	body.material = mat
	add_child(body)
	overlay = Node2D.new()
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	_setup_sprite()


func _setup_sprite() -> void:
	# Karaktere özel efekt ve aura rengi (GameData.SKINS "fx" / "aura")
	var info: Dictionary = GameData.SKINS[GameData.skin_index(skin_id)]
	skin_fx = String(info.get("fx", ""))
	aura_col = info.get("aura", Color(0, 0, 0, 0))
	var sheet := GameData.tex(skin_id + "_walk")
	if sheet != null:
		body.texture = sheet
		_walk_frames = maxi(1, sheet.get_width() / sheet.get_height())
		body.hframes = _walk_frames
		_base_scale = SPRITE_SIZE / sheet.get_height()
	else:
		body.texture = GameData.tex(skin_id)
		_walk_frames = 1
		body.hframes = 1
		_base_scale = SPRITE_SIZE / body.texture.get_height() if body.texture != null else 1.0


func ring_radius() -> float:
	return body_r() + 32.0 + mini(knives, MAX_KNIVES) * 1.2


func move_speed() -> float:
	var s := BASE_SPEED - mini(knives, MAX_KNIVES) * 1.7
	if speed_t > 0.0:
		s *= 1.45
	if slow_t > 0.0:
		s *= 0.55
	if boss:
		s *= 0.82
	return s


func damage_mult() -> float:
	return 1.6 if rage_t > 0.0 else 1.0


func try_dash() -> bool:
	if dash_cd > 0.0 or not alive:
		return false
	dash_dir = move_dir.normalized() if move_dir.length() > 0.15 else facing
	dash_t = DASH_TIME
	dash_cd = DASH_COOLDOWN
	squash = 0.6
	return true


## Verilen noktayı en yakın bıçak engelliyor mu? (fırlatılan bıçaklar için)
func knife_blocks(point: Vector2) -> bool:
	if knives <= 0:
		return false
	var step := TAU / knives
	var rel := fposmod((point - position).angle() - orbit_angle, step)
	return minf(rel, step - rel) * ring_radius() < 10.0


func tick(delta: float) -> void:
	orbit_angle = wrapf(orbit_angle + (3.4 + knives * 0.035) * delta, 0.0, TAU)
	moving = move_dir.length() > 0.15
	if moving:
		facing = move_dir.normalized()
		if absf(facing.x) > 0.2:
			flip = signf(facing.x)
		position += move_dir.limit_length(1.0) * move_speed() * delta
		anim_time += delta * WALK_FPS * (1.3 if speed_t > 0.0 else 1.0)
	else:
		anim_time = 0.0
	if dash_t > 0.0:
		dash_t -= delta
		position += dash_dir * DASH_SPEED * delta
		moving = true
		if absf(dash_dir.x) > 0.2:
			flip = signf(dash_dir.x)
		afterimages.append({"pos": position, "life": 0.25, "frame": body.frame if body != null else 0})
	for i in range(afterimages.size() - 1, -1, -1):
		afterimages[i]["life"] = float(afterimages[i]["life"]) - delta
		if float(afterimages[i]["life"]) <= 0.0:
			afterimages.remove_at(i)
	dash_cd = maxf(0.0, dash_cd - delta)
	rage_t = maxf(0.0, rage_t - delta)
	slow_t = maxf(0.0, slow_t - delta)
	idle_time += delta
	position += knock * delta
	knock = knock.lerp(Vector2.ZERO, minf(1.0, 7.0 * delta))
	hurt_flash = maxf(0.0, hurt_flash - delta)
	squash = move_toward(squash, 0.0, delta * 4.0)
	throw_cooldown = maxf(0.0, throw_cooldown - delta)
	speed_t = maxf(0.0, speed_t - delta)
	shield_t = maxf(0.0, shield_t - delta)
	inf_t = maxf(0.0, inf_t - delta)
	# Knife.io'daki gibi: bıçağı az olan oyuncunun bıçakları zamanla yenilenir (oyundan kopmasın)
	if knives < KNIFE_REGEN_MAX:
		regen_timer += delta
		if regen_timer >= KNIFE_REGEN_TIME:
			regen_timer = 0.0
			knives += 1
	else:
		regen_timer = 0.0
	magnet_t = maxf(0.0, magnet_t - delta)
	since_hit += delta
	if since_hit > 3.0:
		hp = minf(max_hp, hp + 4.0 * delta)
	_update_sprite()
	if on_screen:
		queue_redraw()
		overlay.queue_redraw()


## İstemci tarafı: konum sunucudan gelir; burada yalnızca animasyon ve efektler ilerler.
func visual_tick(delta: float) -> void:
	orbit_angle = wrapf(orbit_angle + (3.4 + knives * 0.035) * delta, 0.0, TAU)
	moving = move_dir.length() > 0.15 or dash_t > 0.0
	if moving:
		if move_dir.length() > 0.15:
			facing = move_dir.normalized()
		if absf(facing.x) > 0.2:
			flip = signf(facing.x)
		anim_time += delta * WALK_FPS * (1.3 if speed_t > 0.0 else 1.0)
	else:
		anim_time = 0.0
	if dash_t > 0.0:
		afterimages.append({"pos": position, "life": 0.25, "frame": body.frame if body != null else 0})
	for i in range(afterimages.size() - 1, -1, -1):
		afterimages[i]["life"] = float(afterimages[i]["life"]) - delta
		if float(afterimages[i]["life"]) <= 0.0:
			afterimages.remove_at(i)
	idle_time += delta
	hurt_flash = maxf(0.0, hurt_flash - delta)
	squash = move_toward(squash, 0.0, delta * 4.0)
	# İstemci: bekleme süreleri yalnızca düğmelerde göstermek için yerelde sayılır
	throw_cooldown = maxf(0.0, throw_cooldown - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	_update_sprite()
	if on_screen:
		queue_redraw()
		overlay.queue_redraw()


func _update_sprite() -> void:
	if moving and _walk_frames > 1:
		body.frame = 1 + int(anim_time) % (_walk_frames - 1)
	else:
		body.frame = 0
	# Nefes alma (bekleme) ve darbe sonrası ezilme
	var breathe := sin(idle_time * 3.0) * 0.025 if not moving else 0.0
	var sx := 1.0 + squash * 0.3 - breathe
	var sy := 1.0 - squash * 0.25 + breathe
	# Sprite'ın doğal bakış yönüne göre aynala: sola bakan sprite sağa giderken çevrilir.
	# Önden bakan karakterler aynalanmaz.
	var mirror := flip * face_dir if face_dir != 0 else 1.0
	var big := BOSS_SCALE if boss else 1.0
	body.scale = Vector2(_base_scale * sx * mirror, _base_scale * sy) * big
	body.modulate = Color(1.0, 0.75, 0.75) if rage_t > 0.0 else (Color(0.7, 0.8, 1.0) if slow_t > 0.0 else Color.WHITE)
	body.position = Vector2(0, (-16.0 - (breathe * 40.0)) * big)
	body.rotation = 0.0
	# Yürüme animasyonu olmayan karakterler için zıplayarak yürüme
	if moving and _walk_frames == 1:
		body.position.y -= absf(sin(anim_time * 0.6)) * 8.0
		body.rotation = sin(anim_time * 0.6) * 0.12
	(body.material as ShaderMaterial).set_shader_parameter("flash", clampf(hurt_flash * 6.0, 0.0, 1.0))


## from == null ise hasar arenadan (daralan alan) gelir; kalkan bunu engellemez.
func take_damage(amount: float, from: Fighter = null) -> bool:
	if not alive:
		return false
	if from != null and shield_t > 0.0:
		return false
	hp -= amount
	since_hit = 0.0
	if from != null:
		last_attacker_id = from.get_instance_id()
		hurt_flash = 0.16
		squash = 1.0
	return true


func _knife_angle(i: int) -> float:
	return orbit_angle + TAU * float(i) / float(knives)


## Dünya koordinatında bir bıçağın konumu (parçacık efektleri için).
func knife_world_pos(i: int) -> Vector2:
	return position + Vector2.from_angle(_knife_angle(i)) * ring_radius()


func _draw_knives(front: bool, ci: CanvasItem) -> void:
	var r := ring_radius()
	var info: Dictionary = GameData.KNIVES[knife_kind]
	var glow: Color = info["glow"]
	var trail := Color(glow, 0.3) if glow.a > 0.0 else Color(1, 1, 1, 0.1)
	for i in knives:
		var a := _knife_angle(i)
		if (sin(a) >= 0.0) != front:
			continue
		# Hareket izi: uca doğru kalınlaşan iki katman
		if not low_fx:
			ci.draw_arc(Vector2.ZERO, r, a - 0.45, a - 0.15, 6, Color(trail, trail.a * 0.5), 5.0)
			ci.draw_arc(Vector2.ZERO, r, a - 0.2, a, 4, trail, 9.0)
		KnifeArt.draw(ci, Vector2.from_angle(a) * r, a + PI / 2.0, 1.0, knife_kind)


func _draw() -> void:
	var _pt := Time.get_ticks_usec()
	_draw_body()
	perf_draw_us += Time.get_ticks_usec() - _pt


func _draw_body() -> void:
	if not alive:
		return
	if magnet_t > 0.0:
		var pulse := 0.5 + 0.5 * sin(idle_time * 6.0)
		draw_arc(Vector2.ZERO, MAGNET_RADIUS, 0.0, TAU, 64, Color(0.85, 0.45, 0.95, 0.12 + pulse * 0.1), 3.0)

	# Atılma (dash) hayalet izleri
	if body != null and body.texture != null:
		var fw := body.texture.get_width() / float(_walk_frames)
		var fh := float(body.texture.get_height())
		for a in afterimages:
			var local: Vector2 = a["pos"] - position
			var alpha := float(a["life"]) / 0.25 * 0.45
			var sz := Vector2(fw, fh) * _base_scale
			var dst := Rect2(local + Vector2(0, -16) - sz / 2.0, sz)
			draw_texture_rect_region(body.texture, dst, Rect2(int(a["frame"]) * fw, 0, fw, fh), Color(color.lightened(0.4), alpha))
	if rage_t > 0.0:
		var pulse := 0.5 + 0.5 * sin(idle_time * 10.0)
		GameData.disc(self, Vector2(0, -6), BODY_RADIUS + 14.0, Color(1, 0.15, 0.1, 0.12 + pulse * 0.1))
	if slow_t > 0.0:
		draw_arc(Vector2(0, -6), BODY_RADIUS + 10.0, 0.0, TAU, 32, Color(0.5, 0.75, 1, 0.6), 3.0)

	# Efektli karakterlerde ayak altında yavaşça nabız gibi atan renkli aura
	if aura_col.a > 0.0 and not concealed:
		var pulse := 0.5 + 0.5 * sin(idle_time * 3.0)
		draw_set_transform(Vector2(0, body_r() * 0.75), 0.0, Vector2(1.0, 0.4))
		GameData.disc(self, Vector2.ZERO, body_r() * (1.6 + pulse * 0.2), Color(aura_col, 0.16 + pulse * 0.1))
		draw_arc(Vector2.ZERO, body_r() * (1.5 + pulse * 0.25), 0.0, TAU, 40, Color(aura_col, 0.35 * (1.0 - pulse) + 0.1), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Gölge ve takım rengi halkası
	draw_set_transform(Vector2(0, body_r() * 0.75), 0.0, Vector2(1.0, 0.4))
	GameData.disc(self, Vector2.ZERO, body_r() * 1.15, Color(0, 0, 0, 0.3))
	draw_arc(Vector2.ZERO, body_r() * 1.15, 0.0, TAU, 40, Color(1, 0.2, 0.15) if boss else Color(color, 0.9), 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if accessory > 0 and not concealed:
		_draw_acc(self, true)

	# Hız ayakkabısı / hız güçlendirmesi: ayaklarda çırpınan altın kanatçıklar
	if speed_t > 0.0:
		var flap := sin(idle_time * 18.0) * 0.35
		for side in [-1.0, 1.0]:
			var base := Vector2(14.0 * side, 26.0)
			var pts := PackedVector2Array()
			for v in [Vector2(0, 0), Vector2(14, -10), Vector2(10, -2), Vector2(16, 0), Vector2(8, 4)]:
				pts.append(base + (v as Vector2).rotated(-flap * side) * Vector2(side, 1.0))
			draw_colored_polygon(pts, Color(1, 0.85, 0.3, 0.9))

	if speed_t > 0.0 and moving:
		for i in 4:
			var p := -facing * (BODY_RADIUS + 6.0 + i * 12.0) + facing.orthogonal() * sin(idle_time * 20.0 + i) * 5.0
			GameData.disc(self, p, 6.0 - i, Color(1, 0.9, 0.3, 0.45 - i * 0.1))

	if knives > 0:
		if not low_fx:
			draw_arc(Vector2.ZERO, ring_radius(), 0.0, TAU, 64, Color(1, 1, 1, 0.06), 2.0)
		# Telefonda bıçak başına parlama yerine tek bir renkli halka (çok daha ucuz)
		var glow: Color = GameData.KNIVES[knife_kind]["glow"]

		_draw_knives(false, self)


## Seviye eşyası: karakter görselinin o anki konumu/boyu/yönüyle (zıplama ve aynalama dahil).
func _draw_acc(ci: CanvasItem, back: bool) -> void:
	if body == null:
		return
	var mirror := signf(body.scale.x) if body.scale.x != 0.0 else 1.0
	GameData.draw_accessory(ci, accessory, skin_id, body.position, SPRITE_SIZE * body.scale.y / _base_scale, mirror,
		idle_time, back)


func _draw_overlay() -> void:
	var _pt := Time.get_ticks_usec()
	_draw_overlay_body()
	perf_draw_us += Time.get_ticks_usec() - _pt


func _draw_overlay_body() -> void:
	if not alive:
		return
	if accessory > 0 and not concealed:
		_draw_acc(overlay, false)
	if knives > 0:
		_draw_knives(true, overlay)

	if shield_t > 0.0:
		var blink := 1.0 if shield_t > 1.5 or fmod(shield_t, 0.3) > 0.15 else 0.3
		var wobble := sin(idle_time * 5.0) * 2.0
		GameData.disc(overlay, Vector2(0, -6), body_r() + 16.0 + wobble, Color(0.35, 0.7, 1, 0.18 * blink))
		overlay.draw_arc(Vector2(0, -6), body_r() + 16.0 + wobble, 0.0, TAU, 48, Color(0.6, 0.85, 1, 0.8 * blink), 3.0)
		overlay.draw_arc(Vector2(0, -6), BODY_RADIUS + 10.0, -2.4, -1.6, 12, Color(1, 1, 1, 0.5 * blink), 3.0)

	if concealed:
		return
	var font := ThemeDB.fallback_font
	var top := -ring_radius() - 30.0 if knives > 0 else -body_r() * 2.0 - 56.0
	var name_col := Color(1, 0.35, 0.3) if boss else color.lightened(0.35)
	overlay.draw_string_outline(font, Vector2(-80, top), display_name, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, 5, Color(0, 0, 0, 0.75))
	overlay.draw_string(font, Vector2(-80, top), display_name, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, name_col)
	# Seviye rozeti (ismin solunda)
	var nw := font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var badge := Vector2(-nw / 2.0 - 14.0, top - 6.0)
	GameData.disc(overlay, badge, 11.0, Color(1, 0.85, 0.3))
	GameData.disc(overlay, badge, 9.0, Color(0.1, 0.12, 0.2))
	overlay.draw_string(font, badge + Vector2(-10, 5), str(level), HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color.WHITE)
	# Bıçak sayısı ismin üstünde (Knife.io'daki gibi; herkes rakibin gücünü görsün). Sınırsız bıçakta ∞
	var cy := top - 20.0
	if inf_t > 0.0:
		GameData.draw_infinity(overlay, Vector2(-6, cy - 6), 0.55, Color(0.4, 0.95, 1))
		KnifeArt.draw(overlay, Vector2(14, cy - 6), 0.35, 0.42, knife_kind, false)
	else:
		var count := str(knives)
		var cw := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var cx := -(cw + 16.0) / 2.0
		overlay.draw_string_outline(font, Vector2(cx, cy), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, Color(0, 0, 0, 0.75))
		overlay.draw_string(font, Vector2(cx, cy), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		KnifeArt.draw(overlay, Vector2(cx + cw + 9, cy - 6), 0.35, 0.42, knife_kind, false)

	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	overlay.draw_rect(Rect2(-29, top + 5, 58, 8), Color(0, 0, 0, 0.6))
	overlay.draw_rect(Rect2(-28, top + 6, 56 * ratio, 6), Color(1, 0.25, 0.2).lerp(Color(0.3, 0.95, 0.4), ratio))
