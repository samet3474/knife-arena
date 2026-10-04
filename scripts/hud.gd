extends Control
## Ekran arayüzü: açılış ekranı, ana menü (karakter / bıçak / seviye sekmeleri),
## mobil kontroller (sanal joystick, fırlatma ve atılma butonları), oyuncu kartı,
## mini harita, skor tablosu, leş akışı, duraklatma ve oyun sonu ekranları.
## Butonlar her karede çizilirken kaydedilir; dokunuşlar bu listeye göre kontrol edilir.

const JOY_RADIUS := 85.0
const THROW_RADIUS := 86.0
const DASH_RADIUS := 54.0
const GOLD := Color(1, 0.85, 0.3)
const PANEL_BG := Color(0.05, 0.08, 0.11, 0.85)
const CARDS_PER_PAGE := 8
const CARD_COLS := 4
const SPLASH_LOAD_TIME := 1.6

var main # main.gd örneği
var joy_index := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var throw_index := -1
var buttons: Array[Dictionary] = []
var font: Font
var page := -1
var tab := "characters" # characters | knives | levels
var banner_text := ""
var banner_time := 0.0
var banner_color := Color(1, 0.4, 0.35)
var name_edit: LineEdit
var admin_edit: LineEdit
var _style_cache := {}
var _fit_cache := {}
static var perf_draw_us := 0
## Çizimin yapıldığı katman. Bilgi panelleri bu düğüme (seyrek), joystick/butonlar
## "controls" katmanına (her karede) çizilir; böylece arayüz telefonda çok daha ucuz.
var cv: CanvasItem = self
var controls: Control
var _redraw_timer := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls = Control.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls.draw.connect(_draw_controls_layer)
	_create_name_edit()
	_create_admin_edit()


## Her karede çağrılır: kontroller her karede, bilgi panelleri saniyede 20-30 kez yenilenir.
func tick(delta: float) -> void:
	controls.queue_redraw()
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / (20.0 if main.state in ["playing", "over", "won", "paused"] else 30.0)
		queue_redraw()


func _draw_controls_layer() -> void:
	if main.state != "playing" or main.player == null:
		return
	cv = controls
	var s := _screen()
	_draw_controls(s)
	# Performans göstergesi (kasma olursa sayıyla görülebilsin)
	var fps := Engine.get_frames_per_second()
	var fps_col := Color(0.5, 1, 0.6, 0.6) if fps >= 50 else (Color(1, 0.85, 0.3, 0.8) if fps >= 30 else Color(1, 0.4, 0.35, 0.9))
	_text(Vector2(s.x / 2 - 50, s.y - 8), "%d FPS" % fps, 13, fps_col, HORIZONTAL_ALIGNMENT_CENTER, 100.0)
	cv = self


## Oyuncu adı kutusu (telefonda dokununca ekran klavyesi açılır).
func _create_name_edit() -> void:
	name_edit = LineEdit.new()
	name_edit.max_length = 14
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.text = main.save["player_name"]
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.add_theme_color_override("font_color", Color.WHITE)
	name_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.45))
	name_edit.add_theme_color_override("caret_color", GOLD)
	for style_name in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = PANEL_BG
		sb.set_corner_radius_all(21)
		sb.set_border_width_all(2)
		sb.border_color = GOLD if style_name == "focus" else Color(1, 1, 1, 0.18)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		name_edit.add_theme_stylebox_override(style_name, sb)
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_on_name_focus_exited)
	add_child(name_edit)


## Yönetici şifresi kutusu (yalnızca yönetici giriş ekranında görünür).
func _create_admin_edit() -> void:
	admin_edit = LineEdit.new()
	admin_edit.secret = true
	admin_edit.max_length = 64
	admin_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	admin_edit.add_theme_font_size_override("font_size", 22)
	for style_name in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.03, 0.05)
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(2)
		sb.border_color = GOLD if style_name == "focus" else Color(1, 1, 1, 0.2)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		admin_edit.add_theme_stylebox_override(style_name, sb)
	admin_edit.text_submitted.connect(func(_t: String) -> void: _on_button("admin_go"))
	admin_edit.visible = false
	add_child(admin_edit)


func _on_name_changed(text: String) -> void:
	main.save["player_name"] = text


func _on_name_submitted(_text: String) -> void:
	name_edit.release_focus()


func _on_name_focus_exited() -> void:
	main._write_save()


func _process(delta: float) -> void:
	banner_time = maxf(0.0, banner_time - delta)
	var in_menu: bool = main.state == "menu"
	name_edit.visible = in_menu
	if in_menu:
		name_edit.placeholder_text = Loc.t("name_placeholder")
		var left_w := _left_w()
		name_edit.position = Vector2(left_w / 2.0 - 150.0, 120.0)
		name_edit.size = Vector2(300.0, 42.0)
	elif name_edit.has_focus():
		name_edit.release_focus()
	var login: bool = main.state == "admin_login"
	admin_edit.visible = login
	if login:
		admin_edit.placeholder_text = Loc.t("admin_password")
		var sz := _screen()
		admin_edit.position = Vector2(sz.x / 2 - 220, sz.y / 2 - 66)
		admin_edit.size = Vector2(440, 48)
	elif admin_edit.has_focus():
		admin_edit.release_focus()


func flash_banner(text: String, col := Color(1, 0.4, 0.35), duration := 2.2) -> void:
	banner_text = text
	banner_color = col
	banner_time = duration


func joy_vector() -> Vector2:
	if joy_index < 0:
		return Vector2.ZERO
	return ((joy_pos - joy_origin) / JOY_RADIUS).limit_length(1.0)


func throw_held() -> bool:
	return throw_index >= 0


func _screen() -> Vector2:
	return get_viewport_rect().size


func _left_w() -> float:
	return _screen().x * 0.48


func _throw_center() -> Vector2:
	var s := _screen()
	return Vector2(s.x - 150.0, s.y - 160.0)


func _dash_center() -> Vector2:
	var s := _screen()
	# Alt kenardan uzak: iPhone'da en alttaki şerit sistem hareketlerine (ana ekran) ayrılmış
	return Vector2(s.x - 320.0, s.y - 112.0)


func _joy_rest() -> Vector2:
	return Vector2(170.0, _screen().y - 170.0)


# --- Girdi -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			for b in buttons:
				if (b["rect"] as Rect2).has_point(touch.position):
					if b["enabled"]:
						joy_index = -1
						throw_index = -1
						_on_button(b["id"])
					get_viewport().set_input_as_handled()
					return
			if main.state != "playing":
				return
			if touch.position.distance_to(_throw_center()) < THROW_RADIUS + 34.0:
				throw_index = touch.index
				main.player_throw()
			elif touch.position.distance_to(_dash_center()) < DASH_RADIUS + 26.0:
				main.player_dash()
			elif joy_index == -1 and touch.position.x < _screen().x * 0.6:
				# Ekranın sol tarafında nereye dokunulursa joystick orada açılır
				joy_index = touch.index
				joy_origin = touch.position
				joy_pos = touch.position
		else:
			if touch.index == joy_index:
				joy_index = -1
			if touch.index == throw_index:
				throw_index = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == joy_index:
			joy_pos = drag.position
			var off := joy_pos - joy_origin
			if off.length() > JOY_RADIUS:
				joy_origin = joy_pos - off.normalized() * JOY_RADIUS


func _on_button(id: String) -> void:
	_redraw_timer = 0.0 # basılan butonun etkisi hemen görünsün
	match id:
		"page_prev":
			page = maxi(0, page - 1)
			main.sfx.play("select", 0.0, 0.0)
		"page_next":
			page += 1
			main.sfx.play("select", 0.0, 0.0)
		"admin_go":
			main.admin_connect(admin_edit.text.strip_edges())
			admin_edit.text = ""
		"tab_characters", "tab_knives", "tab_levels":
			tab = id.trim_prefix("tab_")
			main.sfx.play("select", 0.0, 0.0)
		_:
			main.on_button(id)


# --- Çizim yardımcıları -------------------------------------------------------

func _text(pos: Vector2, text: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	cv.draw_string_outline(font, pos, text, align, width, size, maxi(4, int(size / 6.0)), Color(0, 0, 0, 0.75 * col.a))
	cv.draw_string(font, pos, text, align, width, size, col)


## Metni verilen genişliğe sığacak şekilde küçültür (taşmayı önler).
func _fit_size(text: String, size: int, max_w: float) -> int:
	var key := "%s|%d|%d" % [text, size, int(max_w)]
	if _fit_cache.has(key):
		return _fit_cache[key]
	var s := size
	while s > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w:
		s -= 1
	if _fit_cache.size() > 2000:
		_fit_cache.clear()
	_fit_cache[key] = s
	return s


func _text_fit(pos: Vector2, text: String, size: int, col: Color, width: float) -> void:
	_text(pos, text, _fit_size(text, size, width - 8.0), col, HORIZONTAL_ALIGNMENT_CENTER, width)


func _center_text(s: Vector2, y: float, text: String, size: int, col: Color) -> void:
	_text(Vector2(0, y), text, _fit_size(text, size, s.x - 40.0), col, HORIZONTAL_ALIGNMENT_CENTER, s.x)


## Yuvarlak köşeli, isteğe bağlı kenarlıklı ve gölgeli panel.
func _panel(rect: Rect2, bg: Color, border := Color(0, 0, 0, 0), radius := 16, border_w := 0, shadow := 0) -> void:
	# Sayısal anahtar: her panelde renkleri yazıya çevirmekten çok daha ucuz
	var key := bg.to_rgba32() + border.to_rgba32() * 7919 + radius * 104729 + border_w * 1299709 + shadow * 15485863
	var sb: StyleBoxFlat = _style_cache.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(radius)
		sb.border_color = border
		sb.set_border_width_all(border_w)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 4)
		sb.anti_aliasing = true
		if _style_cache.size() > 400:
			_style_cache.clear()
		_style_cache[key] = sb
	cv.draw_style_box(sb, rect)


func _button(rect: Rect2, id: String, label: String, col: Color, enabled := true, size := 30) -> void:
	var c := col if enabled else Color(0.32, 0.34, 0.4)
	_panel(Rect2(rect.position + Vector2(0, 5), rect.size), c.darkened(0.5), Color(0, 0, 0, 0), 14, 0, 6)
	_panel(rect, c, c.lightened(0.35), 14, 2)
	_panel(Rect2(rect.position + Vector2(5, 4), Vector2(rect.size.x - 10, rect.size.y * 0.42)), Color(1, 1, 1, 0.13), Color(0, 0, 0, 0), 10)
	var fs := _fit_size(label, size, rect.size.x - 20.0)
	var baseline := rect.position.y + rect.size.y * 0.5 + fs * 0.36
	_text(Vector2(rect.position.x, baseline), label, fs, Color.WHITE if enabled else Color(1, 1, 1, 0.6),
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	buttons.append({"rect": rect, "id": id, "enabled": enabled})


func _draw_lock(center: Vector2, sc: float, col := Color(0.95, 0.85, 0.55)) -> void:
	cv.draw_arc(center + Vector2(0, -7) * sc, 9.0 * sc, PI, TAU, 20, col, 4.0 * sc)
	cv.draw_line(center + Vector2(-9, -7) * sc, center + Vector2(-9, 0) * sc, col, 4.0 * sc)
	cv.draw_line(center + Vector2(9, -7) * sc, center + Vector2(9, 0) * sc, col, 4.0 * sc)
	_panel(Rect2(center + Vector2(-14, -2) * sc, Vector2(28, 22) * sc), col, Color(0, 0, 0, 0), int(5 * sc))
	GameData.disc(cv, center + Vector2(0, 7) * sc, 3.0 * sc, Color(0.2, 0.15, 0.1))


## Seviye rozeti (altın çerçeveli daire içinde seviye numarası).
func _level_badge(center: Vector2, r: float, level: int) -> void:
	GameData.disc(cv, center + Vector2(0, 2), r, Color(0, 0, 0, 0.4))
	GameData.disc(cv, center, r, Color(0.16, 0.2, 0.42))
	cv.draw_arc(center, r - 1.5, 0.0, TAU, 32, GOLD, 3.0)
	var fs := int(r * 0.95)
	_text(center + Vector2(-r, fs * 0.36), str(level), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)


func _progress_bar(rect: Rect2, ratio: float, col: Color) -> void:
	_panel(rect, Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.12), int(rect.size.y / 2.0), 1)
	if ratio > 0.0:
		var w := maxf(rect.size.y, rect.size.x * clampf(ratio, 0.0, 1.0))
		_panel(Rect2(rect.position, Vector2(w, rect.size.y)), col, Color(0, 0, 0, 0), int(rect.size.y / 2.0))
		_panel(Rect2(rect.position + Vector2(3, 2), Vector2(w - 6, rect.size.y * 0.35)), Color(1, 1, 1, 0.25),
			Color(0, 0, 0, 0), int(rect.size.y / 4.0))


func _chip(pos: Vector2, label: String, value: String) -> float:
	var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + vw + 38.0
	_panel(Rect2(pos, Vector2(w, 40)), PANEL_BG, Color(1, 1, 1, 0.1), 20, 1)
	_text(pos + Vector2(15, 26), label, 14, Color(1, 1, 1, 0.65))
	_text(pos + Vector2(w - 15 - vw, 27), value, 20, GOLD)
	return w


## Altın ikonu + miktar; genişliği döndürür.
func _coin_amount(pos: Vector2, amount: int, size := 22, col := GOLD) -> float:
	GameData.draw_coin(cv, pos + Vector2(size * 0.5, -size * 0.35), size * 0.5)
	_text(pos + Vector2(size * 1.2, 0), str(amount), size, col)
	return size * 1.2 + font.get_string_size(str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _coin_width(amount: int, size: int) -> float:
	return size * 1.2 + font.get_string_size(str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Basit kafatası ikonu (leş sayacı için).
func _skull(c: Vector2, r: float, col := Color.WHITE) -> void:
	GameData.disc(cv, c, r, col)
	cv.draw_rect(Rect2(c + Vector2(-r * 0.55, r * 0.5), Vector2(r * 1.1, r * 0.6)), col)
	GameData.disc(cv, c + Vector2(-r * 0.4, 0), r * 0.3, Color(0.1, 0.1, 0.12))
	GameData.disc(cv, c + Vector2(r * 0.4, 0), r * 0.3, Color(0.1, 0.1, 0.12))


## Karakter sprite'ını çizer. frame >= 0 ise yürüme animasyonunun o karesini kullanır.
func _draw_skin(id: String, center: Vector2, size: float, tint := Color.WHITE, frame := -1) -> void:
	var sheet := GameData.tex(id + "_walk") if frame >= 0 else null
	var dst := Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size))
	if sheet != null:
		var h := float(sheet.get_height())
		var n := int(sheet.get_width() / h)
		cv.draw_texture_rect_region(sheet, dst, Rect2((frame % n) * h, 0, h, h), tint)
		return
	var tex := GameData.tex(id)
	if tex != null:
		cv.draw_texture_rect(tex, dst, false, tint)
	else:
		GameData.disc(cv, center, size * 0.36, tint)


# --- Ekranlar ----------------------------------------------------------------

func _draw() -> void:
	var _pt := Time.get_ticks_usec()
	_draw_body()
	perf_draw_us += Time.get_ticks_usec() - _pt


func _draw_body() -> void:
	buttons.clear()
	var s := _screen()
	var state: String = main.state
	if state == "server":
		_draw_server(s)
		return
	if state == "splash":
		_draw_splash(s)
		return
	if state == "connecting" or state == "admin_wait":
		_draw_connecting(s)
		return
	if state == "admin":
		_draw_server(s)
		return
	if state == "admin_login":
		_draw_admin_login(s)
		return
	if state == "menu":
		_draw_menu(s)
		_draw_banner(s)
		return
	page = -1
	var p: Fighter = main.player
	if state == "playing" and p.alive and p.hp < 35.0:
		_draw_low_hp(s, p)
	_draw_stats(s)
	var _tk := Time.get_ticks_usec()
	if state == "playing":
		_draw_kill_feed(s)
	_draw_banner(s)
	main.perf_mark("hud_feed_banner", _tk)
	match state:
		"paused":
			cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.55))
			_center_text(s, s.y * 0.36, Loc.t("paused"), 64, Color.WHITE)
			_button(Rect2(s.x / 2 - 150, s.y * 0.48, 300, 76), "resume", Loc.t("resume"), Color(0.22, 0.68, 0.33))
			_button(Rect2(s.x / 2 - 150, s.y * 0.48 + 100, 300, 76), "menu", Loc.t("main_menu"), Color(0.3, 0.36, 0.52))
		"over":
			_draw_result(s, Loc.t("eliminated"), Loc.t("rank_line") % [main.final_rank, p.kills], Color(1, 0.4, 0.35))
		"won":
			_draw_result(s, Loc.t("won"), Loc.t("won_line") % p.kills, GOLD)


func _draw_banner(s: Vector2) -> void:
	if banner_time <= 0.0:
		return
	var a := clampf(banner_time * 2.0, 0.0, 1.0)
	var sc := 1.0 + maxf(0.0, banner_time - 1.9) * 2.0
	if main.state == "menu":
		# Menüde sol taraftaki vitrinin üstünde gösterilir (kartları kapatmasın)
		var lw := _left_w()
		_text_scaled(Vector2(lw / 2.0, 252), banner_text, _fit_size(banner_text, 28, lw - 40.0), Color(banner_color, a), sc)
		return
	_text_scaled(Vector2(s.x / 2.0, s.y * 0.3), banner_text, _fit_size(banner_text, 46, s.x - 40.0), Color(banner_color, a), sc)


## Yazıyı sabit boyutta çizip ölçekler. Yazı boyutunu her karede değiştirmek (büyüme
## animasyonu) harflerin baştan üretilmesine yol açar; web/telefonda çok pahalıdır.
func _text_scaled(center: Vector2, text: String, size: int, col: Color, scale_f: float) -> void:
	cv.draw_set_transform(center, 0.0, Vector2(scale_f, scale_f))
	_text(Vector2(-1500, 0), text, size, col, HORIZONTAL_ALIGNMENT_CENTER, 3000.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_low_hp(s: Vector2, p: Fighter) -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
	var strength := (1.0 - p.hp / 35.0) * 0.5 + 0.15
	for i in 6:
		var w := 14.0 + i * 14.0
		var c := Color(0.9, 0.05, 0.05, strength * pulse * 0.16)
		cv.draw_rect(Rect2(0, 0, w, s.y), c)
		cv.draw_rect(Rect2(s.x - w, 0, w, s.y), c)
		cv.draw_rect(Rect2(0, 0, s.x, w), c)
		cv.draw_rect(Rect2(0, s.y - w, s.x, w), c)


# --- Açılış ekranı ------------------------------------------------------------

func _draw_splash(s: Vector2) -> void:
	var t: float = main.state_time
	var now := Time.get_ticks_msec() / 1000.0
	# Koyu arka plan ve ortada sıcak bir parlama
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.06, 0.08, 0.92))
	var c := Vector2(s.x / 2.0, s.y * 0.4)
	for i in 8:
		GameData.disc(cv, c, 340.0 - i * 38.0, Color(1, 0.55, 0.15, 0.025))

	# Logonun etrafında farklı türde dönen bıçaklar
	var appear := clampf(t / 0.6, 0.0, 1.0)
	var count := GameData.KNIVES.size() * 2
	for i in count:
		var a := now * 0.9 + TAU * i / count
		var p := c + Vector2(cos(a) * 300.0, sin(a) * 120.0) * appear
		KnifeArt.draw(cv, p, Vector2(cos(a), sin(a) * 0.4).angle() + PI / 2.0, 1.3, i % GameData.KNIVES.size())

	# Logo: hafif "pop" girişi
	var pop := 1.0 + maxf(0.0, 0.35 - t) * 1.5
	var k := pop * appear
	if k > 0.08:
		_text_scaled(Vector2(s.x / 2.0, c.y - 10), "KNIFE", 96, GOLD, k)
		_text_scaled(Vector2(s.x / 2.0, c.y - 10 + 86.0 * k), "ARENA", 77, Color.WHITE, k)

	# Altta yürüyen üç karakter
	var skins := ["skin_keloglan", "skin_yeniceri", "skin_ninja"]
	for i in skins.size():
		var x := s.x / 2.0 + (i - 1) * 110.0
		_draw_skin(skins[i], Vector2(x, s.y * 0.72), 100.0, Color(1, 1, 1, appear), 1 + int(now * 10.0 + i * 3) % 8)

	# Yükleniyor çubuğu, sonra "Başlamak için dokun"
	var bar := Rect2(s.x / 2.0 - 180.0, s.y - 92.0, 360.0, 14.0)
	var loaded := clampf(t / SPLASH_LOAD_TIME, 0.0, 1.0)
	if loaded < 1.0:
		_progress_bar(bar, loaded, GOLD)
		_text(Vector2(0, bar.position.y - 12), Loc.t("loading"), 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, s.x)
	else:
		var pulse := 0.55 + 0.45 * sin(now * 4.0)
		_text(Vector2(0, bar.position.y + 10), Loc.t("tap_to_start"), 30, Color(1, 1, 1, pulse), HORIZONTAL_ALIGNMENT_CENTER, s.x)
		buttons.append({"rect": Rect2(Vector2.ZERO, s), "id": "splash", "enabled": true})
	_text(Vector2(s.x - 90, s.y - 16), "v0.5", 14, Color(1, 1, 1, 0.35))


## Süreyi "1sa 05dk" / "05:12" biçiminde yazar.
func _fmt_duration(sec: int) -> String:
	if sec >= 3600:
		return "%dsa %02ddk" % [sec / 3600, (sec % 3600) / 60]
	return "%02d:%02d" % [sec / 60, sec % 60]


## Yönetim paneli: sunucu penceresinde ve uzaktan giriş yapan yöneticide aynı görünür.
## Veriler main.admin_data() sözlüğünden gelir (sunucuda yerel, istemcide sunucudan gelen).
func _draw_server(s: Vector2) -> void:
	var d: Dictionary = main.admin_data()
	var remote: bool = main.net_mode == "client"
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0.035, 0.05, 0.07))
	# Başlık şeridi
	_panel(Rect2(0, 0, s.x, 60), Color(0.06, 0.09, 0.13), Color(0, 0, 0, 0), 0, 0, 6)
	_text(Vector2(24, 40), "KNIFE ARENA  •  YÖNETİM PANELİ", 26, GOLD)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0)
	var online := not d.is_empty()
	GameData.disc(cv, Vector2(s.x - (450 if remote else 300), 31), 7.0, Color(0.3, 1, 0.4, pulse) if online else Color(1, 0.6, 0.3, pulse))
	_text(Vector2(s.x - (436 if remote else 286), 38), ("Çalışıyor  •  " + _fmt_duration(int(d.get("uptime", 0)))) if online else "Veri bekleniyor...",
		18, Color(0.6, 1, 0.7))
	if remote:
		_button(Rect2(s.x - 150, 10, 130, 40), "menu", Loc.t("logout"), Color(0.55, 0.25, 0.25), true, 16)

	var lx := 20.0
	var lw := 400.0
	# Adres kutusu
	var box := Rect2(lx, 76, lw, 104)
	_panel(box, PANEL_BG, GOLD, 16, 2)
	var urls: Array = d.get("urls", [])
	if remote:
		_text(Vector2(box.position.x + 16, box.position.y + 28), "Bağlı sunucu:", 15, Color(1, 1, 1, 0.7))
		var host: String = main._mp_host()
		_text(Vector2(box.position.x + 16, box.position.y + 70), host, _fit_size(host, 22, lw - 32.0), Color.WHITE)
	else:
		_text(Vector2(box.position.x + 16, box.position.y + 28), "Telefondan katıl (aynı Wi-Fi):", 15, Color(1, 1, 1, 0.7))
		if urls.is_empty():
			_text(Vector2(box.position.x + 16, box.position.y + 70), "Web sürümü bulunamadı", 20, Color(1, 0.5, 0.45))
		else:
			_text(Vector2(box.position.x + 16, box.position.y + 72), urls[0], _fit_size(urls[0], 28, lw - 32.0), Color.WHITE)
		_text(Vector2(box.position.x + 16, box.end.y - 10), "PC'den: oyunu aç > ÇOK OYUNCULU", 12, Color(1, 1, 1, 0.45))

	# İstatistikler
	var players: Array = d.get("players", [])
	var st := Rect2(lx, 194, lw, 112)
	_panel(st, PANEL_BG, Color(1, 1, 1, 0.08), 16, 1)
	var stats := [["Bağlı oyuncu", str(players.size())], ["Bot (canlı / hedef)", "%d / %d" % [int(d.get("bots", 0)), int(d.get("bot_target", 0))]],
		["Arenadaki savaşçı", str(d.get("alive", 0))], ["Toplam giriş / yönetici", "%d / %d" % [int(d.get("joins", 0)), int(d.get("admins", 0))]]]
	for i in stats.size():
		var y := st.position.y + 26 + i * 24
		_text(Vector2(st.position.x + 16, y), stats[i][0], 15, Color(1, 1, 1, 0.7))
		_text(Vector2(st.position.x, y), stats[i][1], 16, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, st.size.x - 16)

	# Arena kontrolleri
	var ct := Rect2(lx, 320, lw, 128)
	_panel(ct, PANEL_BG, Color(1, 1, 1, 0.08), 16, 1)
	_text(Vector2(ct.position.x + 16, ct.position.y + 30), "Bot sayısı", 17, Color.WHITE)
	_text(Vector2(ct.position.x + 16, ct.position.y + 48), "(yalnızca ÇOK OYUNCULU arenası)", 11, Color(1, 1, 1, 0.45))
	_button(Rect2(ct.end.x - 160, ct.position.y + 8, 48, 42), "adm_bot_minus", "-", Color(0.55, 0.25, 0.25), true, 24)
	_text(Vector2(ct.end.x - 112, ct.position.y + 37), str(d.get("bot_target", 0)), 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 56.0)
	_button(Rect2(ct.end.x - 58, ct.position.y + 8, 48, 42), "adm_bot_plus", "+", Color(0.22, 0.6, 0.33), true, 24)
	_button(Rect2(ct.position.x + 12, ct.position.y + 66, 182, 48), "adm_reset", "ARENAYI SIFIRLA", Color(0.7, 0.3, 0.2), true, 15)
	_button(Rect2(ct.end.x - 194, ct.position.y + 66, 182, 48), "adm_event", "OLAY BAŞLAT", Color(0.75, 0.55, 0.12), true, 15)

	# Olay günlüğü
	var lg := Rect2(lx, 462, lw, s.y - 482)
	_panel(lg, PANEL_BG, Color(1, 1, 1, 0.08), 16, 1)
	_text(Vector2(lg.position.x + 16, lg.position.y + 26), "Günlük (giren / çıkan / leşler)", 15, GOLD)
	var log: Array = d.get("log", [])
	var rows := int((lg.size.y - 40) / 20)
	for i in mini(rows, log.size()):
		var e: Dictionary = log[i]
		var y := lg.position.y + 50 + i * 20
		_text(Vector2(lg.position.x + 14, y), e["time"], 12, Color(1, 1, 1, 0.4))
		var txt: String = e["text"]
		_text(Vector2(lg.position.x + 80, y), txt, _fit_size(txt, 14, lw - 96.0), e["col"])

	_draw_server_players(Rect2(lx + lw + 20, 76, s.x - lw - lx * 2 - 20, s.y - 96), players)


## Bağlı oyuncular tablosu ve oyuncu başına yönetim butonları.
func _draw_server_players(r: Rect2, players: Array) -> void:
	_panel(r, PANEL_BG, Color(1, 1, 1, 0.08), 16, 1)
	_text(Vector2(r.position.x + 18, r.position.y + 30), "OYUNCULAR", 18, GOLD)
	var cols := [["Oyuncu", 64.0], ["Sv", 190.0], ["IP adresi", 222.0], ["Leş", 330.0], ["Bıçak", 370.0], ["Durum", 422.0], ["Süre", 482.0]]
	for c in cols:
		_text(Vector2(r.position.x + float(c[1]), r.position.y + 58), c[0], 13, Color(1, 1, 1, 0.5))
	cv.draw_line(Vector2(r.position.x + 12, r.position.y + 68), Vector2(r.end.x - 12, r.position.y + 68), Color(1, 1, 1, 0.1), 1.0)
	if players.is_empty():
		_text(Vector2(r.position.x, r.position.y + r.size.y / 2.0), "Henüz bağlı oyuncu yok", 20, Color(1, 1, 1, 0.5),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_text(Vector2(r.position.x, r.position.y + r.size.y / 2.0 + 28), "Oyuncular ÇOK OYUNCULU'ya basınca burada görünür", 15,
			Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var row_h := 60.0
	for i in players.size():
		var y := r.position.y + 76 + i * row_h
		if y + row_h > r.end.y:
			break
		var pl: Dictionary = players[i]
		var peer := int(pl["peer"])
		var row := Rect2(r.position.x + 10, y, r.size.x - 20, row_h - 6)
		_panel(row, Color(1, 1, 1, 0.04) if i % 2 == 0 else Color(1, 1, 1, 0.02), Color(0, 0, 0, 0), 10)
		var mid := row.position.y + row.size.y / 2.0
		if String(pl["skin"]) != "":
			_draw_skin(pl["skin"], Vector2(row.position.x + 28, mid - 2), 50.0)
		var x0 := r.position.x
		var pname := String(pl["name"])
		_text(Vector2(x0 + 64, mid + 6), pname, _fit_size(pname, 16, 120.0), Color.WHITE)
		_text(Vector2(x0 + 190, mid + 6), str(pl["level"]), 15, Color(0.6, 0.85, 1))
		_text(Vector2(x0 + 222, mid + 6), String(pl["ip"]), _fit_size(String(pl["ip"]), 13, 104.0), Color(1, 1, 1, 0.7))
		_text(Vector2(x0 + 330, mid + 6), str(pl["kills"]), 15, Color(1, 0.6, 0.5))
		_text(Vector2(x0 + 370, mid + 6), str(pl["knives"]), 15, Color.WHITE)
		var alive: bool = pl["alive"]
		_text(Vector2(x0 + 422, mid + 6), "Canlı" if alive else "Ölü", 14, Color(0.5, 1, 0.6) if alive else Color(1, 0.5, 0.45))
		_text(Vector2(x0 + 482, mid + 6), _fmt_duration(int(pl["since"])), 13, Color(1, 1, 1, 0.6))
		# İşlem butonları (sağa yaslı)
		var acts := [["coins", "+100", Color(0.75, 0.55, 0.12)], ["level", "+1 Sv", Color(0.3, 0.45, 0.85)],
			["heal", "Can", Color(0.22, 0.6, 0.33)], ["kick", "At", Color(0.7, 0.25, 0.22)]]
		var bx := row.end.x - acts.size() * 58.0
		if bx < x0 + 550:
			bx = x0 + 550
		for a in acts:
			_button(Rect2(bx, row.position.y + 7, 52, 40), "adm_%s_%d" % [a[0], peer], a[1], a[2], true, 13)
			bx += 58.0


## Menüden açılan yönetici girişi ekranı (şifre kutusu).
func _draw_admin_login(s: Vector2) -> void:
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.05, 0.07, 0.92))
	var box := Rect2(s.x / 2 - 260, s.y / 2 - 170, 520, 300)
	_panel(box, PANEL_BG, GOLD, 20, 2, 12)
	_text(Vector2(box.position.x, box.position.y + 52), Loc.t("admin_title"), 30, GOLD, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	_text(Vector2(box.position.x, box.position.y + 84), String(main._mp_host()), 14, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	# (Şifre kutusu box.y+104..148 arasında LineEdit olarak çizilir)
	_text_fit(Vector2(box.position.x, box.position.y + 176), Loc.t("admin_hint"), 12, Color(1, 1, 1, 0.45), box.size.x)
	_button(Rect2(box.position.x + 30, box.end.y - 90, 210, 64), "menu", Loc.t("cancel"), Color(0.3, 0.36, 0.52), true, 20)
	_button(Rect2(box.end.x - 240, box.end.y - 90, 210, 64), "admin_go", Loc.t("login"), Color(0.75, 0.55, 0.12), true, 22)

func _draw_connecting(s: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.06, 0.08, 0.85))
	var c := Vector2(s.x / 2.0, s.y * 0.42)
	for i in 8:
		var a := now * 3.0 + TAU * i / 8.0
		KnifeArt.draw(cv, c + Vector2.from_angle(a) * 60.0, a + PI / 2.0, 1.2, i % GameData.KNIVES.size())
	var msg := Loc.t("joining") if main.my_net_id != 0 else Loc.t("connecting")
	_center_text(s, c.y + 120, msg, 28, Color.WHITE)
	_center_text(s, c.y + 152, String(main._mp_host()), 16, Color(1, 1, 1, 0.5))
	_button(Rect2(s.x / 2 - 120, s.y - 120, 240, 64), "menu", Loc.t("cancel"), Color(0.3, 0.36, 0.52), true, 24)


# --- Ana menü ----------------------------------------------------------------

func _draw_menu(s: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var skin: Dictionary = main.selected_skin()
	var sel_id: String = skin["id"]
	var skin_col: Color = skin["color"]
	var owned: bool = main.skin_unlocked(skin)

	# Arka plan: arena hafifçe görünür, kenarlara doğru koyulaşır
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.06, 0.05, 0.62))
	for i in 8:
		var w := 40.0 + i * 22.0
		cv.draw_rect(Rect2(0, 0, w, s.y), Color(0, 0, 0, 0.04))
		cv.draw_rect(Rect2(s.x - w, 0, w, s.y), Color(0, 0, 0, 0.04))

	_draw_menu_left(s, t, skin, sel_id, skin_col, owned)
	_draw_menu_top_bar(s)
	_draw_menu_panel(s, t, sel_id)


func _draw_menu_left(s: Vector2, t: float, skin: Dictionary, sel_id: String, skin_col: Color, owned: bool) -> void:
	var lw := _left_w()
	_text(Vector2(0, 70), "KNIFE ARENA", 52, GOLD, HORIZONTAL_ALIGNMENT_CENTER, lw)
	_text(Vector2(0, 100), Loc.t("tagline"), 15, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, lw)
	# (İsim kutusu y=120..162 arasında, LineEdit olarak çizilir)

	# Seviye ve XP çubuğu
	var lvl := int(main.save["level"])
	var need := GameData.xp_needed(lvl)
	var xp := int(main.save["xp"])
	var row_x := lw / 2.0 - 150.0
	_level_badge(Vector2(row_x + 18, 192), 18.0, lvl)
	var bar := Rect2(row_x + 44, 184, 256, 16)
	if lvl >= GameData.MAX_LEVEL:
		_progress_bar(bar, 1.0, Color(0.45, 0.75, 1))
	else:
		_progress_bar(bar, float(xp) / need, Color(0.45, 0.75, 1))
		_text(Vector2(bar.position.x, bar.end.y - 2), "%d / %d XP" % [xp, need], 12, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, bar.size.x)

	# Vitrin: seçili karakter, kaide ve etrafında dönen seçili bıçaklar
	var c := Vector2(lw * 0.5, s.y * 0.56)
	for i in 5:
		GameData.disc(cv, c + Vector2(0, 20), 230.0 - i * 24.0, Color(0.02, 0.04, 0.04, 0.12))
	for i in 6:
		GameData.disc(cv, c + Vector2(0, 10), 150.0 - i * 18.0, Color(skin_col, 0.045))
	cv.draw_set_transform(c + Vector2(0, 92), 0.0, Vector2(1.0, 0.3))
	GameData.disc(cv, Vector2.ZERO, 122.0, Color(0, 0, 0, 0.4))
	GameData.disc(cv, Vector2.ZERO, 105.0, skin_col.darkened(0.6))
	cv.draw_arc(Vector2.ZERO, 105.0, 0.0, TAU, 64, skin_col, 7.0)
	cv.draw_arc(Vector2.ZERO, 90.0, 0.0, TAU, 64, Color(skin_col, 0.35), 3.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var kind: int = main.preview_knife()
	var knife_center := c + Vector2(0, 26)
	var knife_pos: Array[Vector2] = []
	var knife_rot: Array[float] = []
	for i in 8:
		var a := t * 1.4 + TAU * i / 8.0
		knife_pos.append(knife_center + Vector2(cos(a) * 155.0, sin(a) * 48.0))
		knife_rot.append(Vector2(cos(a), sin(a) * 0.3).angle() + PI / 2.0)
	for i in 8:
		if knife_pos[i].y < knife_center.y:
			KnifeArt.draw(cv, knife_pos[i], knife_rot[i], 1.05, kind)
	_draw_skin(sel_id, c + Vector2(0, -10), 210.0, Color.WHITE, 1 + int(t * 10.0) % 8)
	for i in 8:
		if knife_pos[i].y >= knife_center.y:
			KnifeArt.draw(cv, knife_pos[i], knife_rot[i], 1.05, kind)

	if not owned:
		_price_tag(Vector2(lw / 2.0, c.y + 110), skin)
	_text_fit(Vector2(0, c.y + 158), Loc.t(sel_id + ".name"), 34, Color.WHITE, lw)
	_text_fit(Vector2(0, c.y + 184), Loc.t(sel_id + ".desc"), 16, skin_col.lightened(0.45), lw)
	var kinfo: Dictionary = GameData.KNIVES[kind]
	var kcol: Color = kinfo["color"]
	_text_fit(Vector2(0, c.y + 207), Loc.t("knife_label") % Loc.t(kinfo["id"] + ".name"), 15, kcol.lightened(0.2), lw)

	# İstatistik kutucukları (sığmazsa sonuncusu atlanır)
	var best := int(main.save["best_rank"])
	var x := 20.0
	var chips := [[Loc.t("stat_kills"), str(main.save["total_kills"])], [Loc.t("stat_wins"), str(main.save["wins"])],
		[Loc.t("stat_best"), "#%d" % best if best > 0 else "-"]]
	for ch in chips:
		var w := font.get_string_size(ch[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x \
			+ font.get_string_size(ch[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 38.0
		if x + w > lw - 140.0:
			break
		x += _chip(Vector2(x, s.y - 56), ch[0], ch[1]) + 8.0
	# Yönetim paneline giriş (şifreli)
	_button(Rect2(lw - 128, s.y - 58, 112, 44), "admin_open", Loc.t("admin"), Color(0.32, 0.26, 0.45), true, 15)


## Sağ üst: altın bakiyesi ve ayar butonları (sağdan sola dizilir, çakışmaz).
func _draw_menu_top_bar(s: Vector2) -> void:
	var x := s.x - 24.0
	var items := [
		["sound", Loc.t("sound_on") if main.save["sound"] else Loc.t("sound_off"), Color(0.25, 0.3, 0.42)],
		["lang", Loc.t("language"), Color(0.25, 0.3, 0.42)],
		["aim", Loc.t("auto_aim_on") if main.save["auto_aim"] else Loc.t("auto_aim_off"),
			Color(0.55, 0.22, 0.25) if main.save["auto_aim"] else Color(0.25, 0.3, 0.42)],
	]
	for it in items:
		var w := clampf(font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 34.0, 120.0, 190.0)
		x -= w
		_button(Rect2(x, 24, w, 46), it[0], it[1], it[2], true, 16)
		x -= 10.0
	# Tam ekran butonu (köşe işaretli simge)
	x -= 46.0
	var fr := Rect2(x, 24, 46, 46)
	_button(fr, "fullscreen", "", Color(0.25, 0.3, 0.42), true, 16)
	var fc := fr.get_center()
	for k in 4:
		var sx := -1.0 if k % 2 == 0 else 1.0
		var sy := -1.0 if k < 2 else 1.0
		var corner := fc + Vector2(sx * 11, sy * 11)
		cv.draw_polyline(PackedVector2Array([corner - Vector2(sx * 7, 0), corner, corner - Vector2(0, sy * 7)]), Color.WHITE, 3.0)
	x -= 10.0
	var coins := int(main.save["coins"])
	var cw := _coin_width(coins, 22) + 32.0
	x -= cw
	_panel(Rect2(x, 24, cw, 46), PANEL_BG, GOLD, 23, 2)
	_coin_amount(Vector2(x + 16, 55), coins, 22)


func _draw_menu_panel(s: Vector2, t: float, sel_id: String) -> void:
	var px := s.x * 0.5
	var pw := s.x * 0.5 - 24.0
	var py := 90.0
	var ph := s.y - 108.0
	_panel(Rect2(px, py, pw, ph), Color(0.05, 0.08, 0.11, 0.88), Color(1, 1, 1, 0.08), 22, 2, 14)

	# Sekmeler: Karakterler | Bıçaklar | Seviye
	var tabs := ["characters", "knives", "levels"]
	var tab_w := (pw - 44.0 - 16.0) / 3.0
	for k in tabs.size():
		var id: String = tabs[k]
		var active := tab == id
		var r := Rect2(px + 22.0 + k * (tab_w + 8.0), py + 14.0, tab_w, 42.0)
		_panel(r, Color(GOLD, 0.2) if active else Color(1, 1, 1, 0.05), GOLD if active else Color(1, 1, 1, 0.1), 12, 2 if active else 1)
		_text_fit(Vector2(r.position.x, r.position.y + 28), Loc.t("tab_" + id), 18, GOLD if active else Color(1, 1, 1, 0.6), r.size.x)
		buttons.append({"rect": r, "id": "tab_" + id, "enabled": true})

	var content := Rect2(px + 22.0, py + 66.0, pw - 44.0, ph - 66.0 - 100.0)
	match tab:
		"knives":
			_draw_knife_grid(content, t)
		"levels":
			_draw_level_table(content)
		_:
			_draw_skin_grid(content, t, sel_id)

	# Oyna / Satın al butonu ve yanında çok oyunculu butonu
	var full := Rect2(px + 22.0, py + ph - 92.0, pw - 44.0, 76.0)
	var mp_w := clampf(full.size.x * 0.36, 170.0, 230.0)
	var play_rect := Rect2(full.position, Vector2(full.size.x - mp_w - 12.0, full.size.y))
	_button(Rect2(full.end.x - mp_w, full.position.y, mp_w, full.size.y), "mp", Loc.t("multiplayer"),
		Color(0.3, 0.42, 0.85), true, 22)
	var pending: Dictionary = main.pending_purchase()
	var glow := 0.5 + 0.5 * sin(t * 4.0)
	if pending.is_empty():
		_panel(play_rect.grow(4.0 + glow * 4.0), Color(0.3, 0.9, 0.4, 0.15 + glow * 0.15), Color(0, 0, 0, 0), 18)
		_button(play_rect, "play", Loc.t("play"), Color(0.22, 0.68, 0.33), true, 36)
		return
	var price := int(pending["price"])
	var lvl_ok: bool = main.level_ok(pending)
	var can_buy: bool = lvl_ok and int(main.save["coins"]) >= price
	if can_buy:
		_panel(play_rect.grow(4.0 + glow * 4.0), Color(GOLD, 0.15 + glow * 0.15), Color(0, 0, 0, 0), 18)
		var label := Loc.t("buy") + "  " + Loc.t(pending["id"] + ".name")
		var cw := _coin_width(price, 24)
		_button(Rect2(play_rect.position, Vector2(play_rect.size.x, play_rect.size.y)), "play", label + "      ",
			Color(0.85, 0.6, 0.12), true, 26)
		_coin_amount(Vector2(play_rect.end.x - cw - 26, play_rect.position.y + play_rect.size.y * 0.5 + 9), price, 24, Color.WHITE)
	elif not lvl_ok:
		_button(play_rect, "play", Loc.t("level_req") % int(pending["level"]), Color(0.3, 0.3, 0.36), true, 26)
	else:
		_button(play_rect, "play", Loc.t("need_coins") % price, Color(0.3, 0.3, 0.36), true, 26)


func _grid_rect(content: Rect2, k: int) -> Rect2:
	var gap := 12.0
	var cw := (content.size.x - gap * (CARD_COLS - 1)) / CARD_COLS
	var ch := minf(180.0, (content.size.y - 34.0 - gap) / 2.0)
	return Rect2(content.position.x + (k % CARD_COLS) * (cw + gap), content.position.y + (k / CARD_COLS) * (ch + gap), cw, ch)


func _draw_skin_grid(content: Rect2, t: float, sel_id: String) -> void:
	var skins := GameData.available_skins()
	var sel_index := 0
	var open_count := 0
	for i in skins.size():
		if skins[i]["id"] == sel_id:
			sel_index = i
		if main.skin_unlocked(skins[i]):
			open_count += 1
	var pages := ceili(skins.size() / float(CARDS_PER_PAGE))
	if page < 0:
		page = sel_index / CARDS_PER_PAGE
	page = clampi(page, 0, pages - 1)
	var last := Rect2()
	for k in CARDS_PER_PAGE:
		var i := page * CARDS_PER_PAGE + k
		if i >= skins.size():
			break
		last = _grid_rect(content, k)
		_skin_card(last, skins[i], skins[i]["id"] == sel_id, t)
	# Sayfa satırı: < ● ● >   ve açık karakter sayısı
	var row_y := _grid_rect(content, CARD_COLS).end.y + 6.0
	var cx := content.position.x + content.size.x / 2.0
	if pages > 1:
		_button(Rect2(cx - 90, row_y, 40, 28), "page_prev", "<", Color(0.25, 0.3, 0.42), page > 0, 18)
		_button(Rect2(cx + 50, row_y, 40, 28), "page_next", ">", Color(0.25, 0.3, 0.42), page < pages - 1, 18)
		for i in pages:
			GameData.disc(cv, Vector2(cx + (i - (pages - 1) / 2.0) * 18.0, row_y + 14.0), 5.0, GOLD if i == page else Color(1, 1, 1, 0.25))
	_text(Vector2(content.position.x, row_y + 20), Loc.t("n_open") % [open_count, skins.size()], 14, Color(1, 1, 1, 0.5),
		HORIZONTAL_ALIGNMENT_RIGHT, content.size.x)


func _draw_knife_grid(content: Rect2, t: float) -> void:
	var sel_knife: int = main.preview_knife()
	for k in GameData.KNIVES.size():
		_knife_card(_grid_rect(content, k), k, k == sel_knife, t)


## Seviye tablosu: mevcut seviyenin çevresindeki seviyeler, ödülleri ve açtıkları.
func _draw_level_table(content: Rect2) -> void:
	var lvl := int(main.save["level"])
	var rows := 7
	var row_h := minf(52.0, (content.size.y - 8.0) / rows)
	var first := clampi(lvl - 1, 1, maxi(1, GameData.MAX_LEVEL - rows + 1))
	for i in rows:
		var L := first + i
		if L > GameData.MAX_LEVEL:
			break
		var r := Rect2(content.position.x, content.position.y + i * row_h, content.size.x, row_h - 6.0)
		var is_cur := L == lvl
		var done := L < lvl
		_panel(r, Color(GOLD, 0.16) if is_cur else Color(1, 1, 1, 0.04), GOLD if is_cur else Color(1, 1, 1, 0.06), 12, 2 if is_cur else 1)
		_level_badge(r.position + Vector2(26, r.size.y / 2.0), 16.0, L)
		# Bu seviyede açılan karakter/bıçaklar
		var unlocks := PackedStringArray()
		for item in GameData.SKINS + GameData.KNIVES:
			if int(item["level"]) == L and int(item["price"]) > 0:
				unlocks.append(Loc.t(item["id"] + ".name"))
		var mid := r.position.y + r.size.y / 2.0
		var reward_w := _coin_width(GameData.level_reward(L), 18) + 20.0
		var status_w := 90.0
		var text_w := r.size.x - 56.0 - reward_w - status_w
		if not unlocks.is_empty():
			var txt := Loc.t("level_unlocks") % ", ".join(unlocks)
			_text(Vector2(r.position.x + 52, mid + 6), txt, _fit_size(txt, 15, text_w), Color(1, 1, 1, 0.85))
		if is_cur:
			# Bulunulan seviye: ödül yerine bir sonraki seviyeye kalan XP
			var need := GameData.xp_needed(lvl)
			var xb := Rect2(r.end.x - status_w - reward_w - 40.0, mid - 8, reward_w + 30.0, 16)
			_progress_bar(xb, float(main.save["xp"]) / need, Color(0.45, 0.75, 1))
			_text(Vector2(xb.position.x, xb.end.y - 3), "%d/%d" % [int(main.save["xp"]), need], 11, Color.WHITE,
				HORIZONTAL_ALIGNMENT_CENTER, xb.size.x)
		else:
			_coin_amount(Vector2(r.end.x - status_w - reward_w, mid + 7), GameData.level_reward(L), 18,
				GOLD if not done else Color(1, 1, 1, 0.4))
		var status := Loc.t("current") if is_cur else (Loc.t("done") if done else "")
		if status != "":
			_text(Vector2(r.end.x - status_w, mid + 6), status, 14, GOLD if is_cur else Color(0.5, 1, 0.6),
				HORIZONTAL_ALIGNMENT_CENTER, status_w - 8.0)
		elif L > lvl:
			_draw_lock(Vector2(r.end.x - status_w / 2.0, mid), 0.6)


func _knife_card(r: Rect2, k: int, selected: bool, t: float) -> void:
	var info: Dictionary = GameData.KNIVES[k]
	var id: String = info["id"]
	var glow: Color = info["glow"]
	var col: Color = info["color"]
	var owned: bool = main.skin_unlocked(info)
	_card_base(r, Color(0.16, 0.13, 0.08), selected)
	var c := r.position + Vector2(r.size.x / 2.0, r.size.y * 0.4)
	if glow.a > 0.0:
		var pulse := 0.8 + 0.2 * sin(t * 4.0 + k)
		cv.draw_texture_rect(GameData.glow_tex(), Rect2(c - Vector2(46, 46), Vector2(92, 92)), false,
			Color(glow, glow.a * pulse * (1.0 if owned else 0.5)))
	var rot := PI / 4.0 + (sin(t * 2.0) * 0.15 if selected else 0.0)
	KnifeArt.draw(cv, c, rot, minf(2.0, r.size.y / 90.0), k, false)
	if selected and info["fx"] != "":
		for j in 3:
			var ph := fmod(t * 0.8 + j / 3.0, 1.0)
			var p := c + Vector2(cos(j * 2.1 + t) * 26.0, 20.0 - ph * 60.0)
			GameData.disc(cv, p, 3.0 * (1.0 - ph), Color(col.lightened(0.3), 1.0 - ph))
	_card_footer(r, info, owned, selected)
	buttons.append({"rect": r, "id": id, "enabled": true})


func _skin_card(r: Rect2, skin: Dictionary, selected: bool, t: float) -> void:
	var id: String = skin["id"]
	var col: Color = skin["color"]
	var owned: bool = main.skin_unlocked(skin)
	_card_base(r, col.darkened(0.62), selected)
	var sc := r.position + Vector2(r.size.x / 2.0, r.size.y * 0.38)
	cv.draw_set_transform(sc + Vector2(0, r.size.y * 0.22), 0.0, Vector2(1.0, 0.3))
	GameData.disc(cv, Vector2.ZERO, 34.0, Color(0, 0, 0, 0.3) if not selected else Color(col, 0.45))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var size := minf(r.size.x * 0.72, r.size.y * 0.58)
	var frame := (1 + int(t * 10.0) % 8) if selected else 0
	_draw_skin(id, sc, size, Color.WHITE if owned or selected else Color(0.6, 0.6, 0.65), frame)
	_card_footer(r, skin, owned, selected)
	buttons.append({"rect": r, "id": id, "enabled": true})


func _card_base(r: Rect2, sel_bg: Color, selected: bool) -> void:
	if selected:
		_panel(r.grow(3.0), Color(GOLD, 0.25), Color(0, 0, 0, 0), 17)
	_panel(r, sel_bg if selected else Color(0.11, 0.15, 0.2), GOLD if selected else Color(1, 1, 1, 0.07),
		14, 3 if selected else 1)


## Kartın alt kısmı: sahipse isim; değilse isim + fiyat (ya da seviye şartı) ve kilit.
func _card_footer(r: Rect2, item: Dictionary, owned: bool, selected: bool) -> void:
	var name_text := Loc.t(String(item["id"]) + ".name")
	if owned:
		_text_fit(Vector2(r.position.x, r.end.y - 12), name_text, 15, Color.WHITE if selected else Color(1, 1, 1, 0.85), r.size.x)
		return
	_text_fit(Vector2(r.position.x, r.end.y - 32), name_text, 13, Color(1, 1, 1, 0.65), r.size.x)
	var bar := Rect2(r.position.x + 8, r.end.y - 24, r.size.x - 16, 19)
	_draw_lock(r.position + Vector2(r.size.x - 16, 18), 0.5)
	if not main.level_ok(item):
		_panel(bar, Color(0.16, 0.2, 0.42, 0.9), Color(0.45, 0.75, 1, 0.6), 9, 1)
		_text_fit(Vector2(bar.position.x, bar.end.y - 4), Loc.t("level_short") % int(item["level"]), 13, Color(0.7, 0.85, 1), bar.size.x)
		return
	var price := int(item["price"])
	var afford := int(main.save["coins"]) >= price
	_panel(bar, Color(0, 0, 0, 0.55), Color(GOLD, 0.6) if afford else Color(0, 0, 0, 0), 9, 1)
	var w := _coin_width(price, 14)
	_coin_amount(Vector2(bar.position.x + (bar.size.x - w) / 2.0, bar.end.y - 4), price, 14, GOLD if afford else Color(1, 0.5, 0.45))


## Önizlenen (alınmamış) karakterin altındaki büyük fiyat etiketi.
func _price_tag(center: Vector2, item: Dictionary) -> void:
	var price := int(item["price"])
	var lvl_ok: bool = main.level_ok(item)
	var label := Loc.t("level_short") % int(item["level"])
	var w := (_coin_width(price, 22) if lvl_ok else font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x) + 64.0
	var rect := Rect2(center.x - w / 2.0, center.y - 19, w, 38)
	_panel(rect, Color(0.05, 0.08, 0.11, 0.92), GOLD if lvl_ok else Color(0.45, 0.75, 1), 19, 2)
	_draw_lock(rect.position + Vector2(20, 20), 0.55)
	if lvl_ok:
		_coin_amount(rect.position + Vector2(36, 27), price, 22)
	else:
		_text(rect.position + Vector2(38, 26), label, 20, Color(0.7, 0.85, 1))


# --- Oyun sonu -----------------------------------------------------------------

func _draw_result(s: Vector2, title: String, sub: String, col: Color) -> void:
	var age: float = main.state_time
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, minf(0.62, age * 1.5)))
	var pop := 1.0 + maxf(0.0, 0.3 - age) * 2.0
	_text_scaled(Vector2(s.x / 2.0, s.y * 0.17), title, _fit_size(title, 70, s.x - 40.0), col, pop)
	_center_text(s, s.y * 0.17 + 44, sub, 24, Color.WHITE)
	var reward: Dictionary = main.last_reward
	if reward.is_empty():
		return
	# Altın dökümü: satırlar sırayla belirir, toplam sayarak artar
	var box := Rect2(s.x / 2 - 220, s.y * 0.17 + 64, 440, 156)
	_panel(box, PANEL_BG, Color(GOLD, 0.5), 18, 2)
	var rows := [["reward_collected", "collected"], ["reward_kills", "kills"], ["reward_rank", "rank"], ["reward_time", "time"]]
	for i in rows.size():
		if age < 0.4 + i * 0.2:
			break
		var y := box.position.y + 30 + i * 25
		_text(Vector2(box.position.x + 22, y), Loc.t(rows[i][0]), 17, Color(1, 1, 1, 0.8))
		_text(Vector2(box.position.x, y), "+%d" % reward[rows[i][1]], 17, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 22)
	var shown := int(float(reward["total"]) * clampf((age - 1.2) / 0.8, 0.0, 1.0))
	cv.draw_line(Vector2(box.position.x + 20, box.end.y - 40), Vector2(box.end.x - 20, box.end.y - 40), Color(1, 1, 1, 0.2), 2.0)
	_text(Vector2(box.position.x + 22, box.end.y - 13), Loc.t("reward_total"), 20, Color.WHITE)
	_coin_amount(Vector2(box.end.x - 22 - _coin_width(shown, 24), box.end.y - 12), shown, 24)

	# XP çubuğu: önceki seviyeden dolarak ilerler; seviye atlandıysa duyurulur
	var xp_y := box.end.y + 18.0
	var lv_before := int(reward["level_before"])
	var lv_now := int(main.save["level"])
	var anim := clampf((age - 1.6) / 1.2, 0.0, 1.0)
	var show_lvl := lv_before if anim < 1.0 and lv_now > lv_before else lv_now
	var ratio := float(main.save["xp"]) / GameData.xp_needed(lv_now)
	if lv_now > lv_before and anim < 1.0:
		ratio = lerpf(float(reward["xp_before"]) / GameData.xp_needed(lv_before), 1.0, anim)
	elif lv_now == lv_before:
		ratio = lerpf(float(reward["xp_before"]) / GameData.xp_needed(lv_now), ratio, anim)
	_level_badge(Vector2(s.x / 2 - 200, xp_y + 14), 18.0, show_lvl)
	_progress_bar(Rect2(s.x / 2 - 172, xp_y + 6, 300, 16), ratio, Color(0.45, 0.75, 1))
	_text(Vector2(s.x / 2 + 140, xp_y + 21), Loc.t("xp_gained") % int(reward["xp"]), 18, Color(0.6, 0.85, 1))
	if not main.level_ups.is_empty() and age > 2.8:
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 160.0)
		var msg := Loc.t("level_up") % lv_now + "   " + Loc.t("level_reward") % int(reward["level_coins"])
		_panel(Rect2(s.x / 2 - 300, xp_y + 36, 600, 42), Color(GOLD, 0.18), GOLD, 21, 2)
		_center_text(s, xp_y + 64, msg, 22, Color(GOLD, pulse))
	if age > 0.8:
		_button(Rect2(s.x / 2 - 320, s.y - 104, 300, 76), "retry", Loc.t("retry"), Color(0.22, 0.68, 0.33))
		_button(Rect2(s.x / 2 + 20, s.y - 104, 300, 76), "menu", Loc.t("main_menu"), Color(0.3, 0.36, 0.52))


# --- Oyun içi arayüz ------------------------------------------------------------

func _draw_stats(s: Vector2) -> void:
	var p: Fighter = main.player
	var _t := Time.get_ticks_usec()
	_draw_player_card(p)
	main.perf_mark("hud_card", _t)
	_t = Time.get_ticks_usec()
	_draw_minimap(Rect2(16, 124, 150, 150))
	main.perf_mark("hud_minimap", _t)
	_t = Time.get_ticks_usec()

	# Aktif güçlendirme süreleri (mini haritanın sağında)
	var y := 140.0
	for entry in [["speed", p.speed_t], ["shield", p.shield_t], ["magnet", p.magnet_t], ["rage", p.rage_t], ["slow", p.slow_t]]:
		var left: float = entry[1]
		if left <= 0.0:
			continue
		var c := Vector2(198, y)
		GameData.disc(cv, c, 22.0, Color(0, 0, 0, 0.5))
		var info: Dictionary = GameData.POWERUPS.get(entry[0], {})
		var icon: Texture2D = GameData.tex(info["icon"]) if not info.is_empty() else null
		var ring_col: Color = info["color"] if not info.is_empty() else (Color(1, 0.3, 0.2) if entry[0] == "rage" else Color(0.5, 0.75, 1))
		var dur: float = info["duration"] if not info.is_empty() else (7.0 if entry[0] == "rage" else 4.0)
		if icon != null:
			cv.draw_texture_rect(icon, Rect2(c - Vector2(17, 17), Vector2(34, 34)), false)
		else:
			GameData.disc(cv, c, 12.0, ring_col)
		cv.draw_arc(c, 22.0, -PI / 2, -PI / 2 + TAU * clampf(left / dur, 0.0, 1.0), 32, ring_col, 4.0)
		_text(Vector2(c.x + 26, c.y + 6), "%d" % ceili(left), 15, Color.WHITE)
		y += 52.0

	main.perf_mark("hud_powerups", _t)
	_t = Time.get_ticks_usec()
	# Üst orta: kalan oyuncu sayısı ve alan uyarısı
	var alive_txt: String = Loc.t("online") % main.human_count() if main.net_mode == "client" else Loc.t("alive") % main.alive_count()
	var aw := font.get_string_size(alive_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 36.0
	_panel(Rect2(s.x / 2 - aw / 2, 14, aw, 38), PANEL_BG, Color(1, 1, 1, 0.1), 19, 1)
	_text(Vector2(0, 41), alive_txt, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	var zone: String = main.zone_status()
	if zone != "":
		_center_text(s, 74, zone, 16, Color(1, 0.55, 0.5))

	main.perf_mark("hud_alive", _t)
	_t = Time.get_ticks_usec()
	# Sağ üst: liderler ve duraklatma
	var board: Array[Fighter] = main.leaderboard(5)
	var lx := s.x - 236.0
	_panel(Rect2(lx - 12, 14, 232, 40 + board.size() * 27), PANEL_BG, Color(1, 1, 1, 0.08), 14, 1)
	_text(Vector2(lx, 39), Loc.t("leaders"), 18, GOLD)
	for i in board.size():
		var f := board[i]
		var col := Color(1, 0.92, 0.3) if f.is_player else Color.WHITE
		var ry := 66.0 + i * 27.0
		GameData.disc(cv, Vector2(lx + 6, ry - 6), 5.0, f.color)
		var nm := "%d. %s" % [i + 1, f.display_name]
		_text(Vector2(lx + 18, ry), nm, _fit_size(nm, 17, 150.0), col)
		_text(Vector2(lx, ry), str(f.knives), 17, col, HORIZONTAL_ALIGNMENT_RIGHT, 205.0)
	if main.state == "playing" and main.net_mode == "":
		_button(Rect2(lx - 76, 14, 54, 48), "pause", "II", Color(0.25, 0.3, 0.42), true, 22)
	main.perf_mark("hud_leaders", _t)


## Sol üst oyuncu kartı: portre + seviye, isim, can barı, bıçak/leş/altın sayaçları.
func _draw_player_card(p: Fighter) -> void:
	var card := Rect2(16, 14, 310, 100)
	_panel(card, PANEL_BG, Color(1, 1, 1, 0.1), 18, 1, 6)
	var pc := Vector2(64, 64)
	GameData.disc(cv, pc, 40.0, p.color.darkened(0.55))
	cv.draw_arc(pc, 40.0, 0.0, TAU, 40, p.color, 3.0)
	_draw_skin(p.skin_id, pc + Vector2(0, 4), 80.0)
	_level_badge(pc + Vector2(30, 30), 14.0, p.level)

	var x := 116.0
	var nm := p.display_name
	_text(Vector2(x, 38), nm, _fit_size(nm, 18, 200.0), Color.WHITE)
	# Can barı: kalan cana göre yeşilden kırmızıya döner, üstünde sayı yazar
	var ratio := clampf(p.hp / p.max_hp, 0.0, 1.0) if p.alive else 0.0
	var hp_rect := Rect2(x, 48, 196, 20)
	_progress_bar(hp_rect, ratio, Color(1, 0.25, 0.2).lerp(Color(0.3, 0.9, 0.4), ratio))
	_text(Vector2(hp_rect.position.x, hp_rect.end.y - 4), "%d / %d" % [ceili(maxf(p.hp, 0.0)), int(p.max_hp)], 14, Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER, hp_rect.size.x)
	# Sayaçlar
	var row := 96.0
	KnifeArt.draw(cv, Vector2(x + 10, row - 7), PI / 4.0, 0.75, p.knife_kind, false)
	_text(Vector2(x + 24, row), str(p.knives), 18, Color.WHITE)
	_skull(Vector2(x + 82, row - 8), 7.0, Color(1, 0.6, 0.55))
	_text(Vector2(x + 94, row), str(p.kills), 18, Color(1, 0.6, 0.55))
	_coin_amount(Vector2(x + 136, row), main.match_coins, 18)


## Mini harita: köşeleri yuvarlak kare içinde arena, daralan alan, kutular, güçlendirmeler,
## rakipler (bıçak sayısına göre büyüklük), lider (taç) ve oyuncu (yön oku).
func _draw_minimap(rect: Rect2) -> void:
	_panel(rect, Color(0.04, 0.07, 0.09, 0.82), Color(1, 1, 1, 0.12), 16, 1, 6)
	var c := rect.get_center()
	var r := rect.size.x * 0.5 - 10.0
	var k: float = r / main.ARENA_RADIUS
	GameData.disc(cv, c, r, Color(0.2, 0.42, 0.26, 0.9))
	for i in range(1, 4):
		cv.draw_arc(c, r * i / 4.0, 0.0, TAU, 40, Color(1, 1, 1, 0.06), 1.0)
	cv.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(1, 1, 1, 0.05), 1.0)
	cv.draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(1, 1, 1, 0.05), 1.0)
	var zr: float = main.zone_radius * k
	if zr < r - 0.5:
		cv.draw_arc(c, (zr + r) / 2.0, 0.0, TAU, 48, Color(0.85, 0.1, 0.15, 0.4), r - zr)
		cv.draw_arc(c, zr, 0.0, TAU, 48, Color(1, 0.45, 0.45), 2.0)
	cv.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.4), 2.0)
	for cr in main.crates:
		var cp: Vector2 = c + (cr["pos"] as Vector2) * k
		cv.draw_rect(Rect2(cp - Vector2(2, 2), Vector2(4, 4)), Color(0.85, 0.6, 0.3))
	for pu in main.powerups:
		var info: Dictionary = GameData.POWERUPS[pu["type"]]
		GameData.disc(cv, c + (pu["pos"] as Vector2) * k, 2.5, info["color"])
	var p: Fighter = main.player
	var leader: Fighter = main._leader()
	for f in main.fighters:
		if not f.alive or f == p or f.concealed:
			continue
		var fp: Vector2 = c + f.position * k
		var fr := 2.5 + minf(f.knives, 30) * 0.08
		GameData.disc(cv, fp, fr + 1.2, Color(0, 0, 0, 0.7))
		GameData.disc(cv, fp, fr, Color(1, 0.3, 0.25))
		if f == leader:
			cv.draw_colored_polygon(PackedVector2Array([fp + Vector2(-5, -5), fp + Vector2(-5, -10), fp + Vector2(-2, -7),
				fp + Vector2(0, -11), fp + Vector2(2, -7), fp + Vector2(5, -10), fp + Vector2(5, -5)]), GOLD)
	if p != null and p.alive:
		var pp := c + p.position * k
		var dir := p.facing
		var side := dir.orthogonal()
		GameData.disc(cv, pp, 7.0, Color(GOLD, 0.25))
		cv.draw_colored_polygon(PackedVector2Array([pp + dir * 7.0, pp - dir * 4.0 + side * 5.0, pp - dir * 2.0,
			pp - dir * 4.0 - side * 5.0]), GOLD)


func _draw_kill_feed(s: Vector2) -> void:
	var y := 92.0
	var now: float = main.round_time
	for e in main.kill_feed:
		var age := now - float(e["time"])
		if age > 5.0:
			continue
		var a := clampf((5.0 - age) * 2.0, 0.0, 1.0)
		var killer: String = e["killer"]
		var victim: String = e["victim"]
		var kw := font.get_string_size(killer, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var vw := font.get_string_size(victim, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var w := kw + vw + 64.0
		var x := s.x / 2.0 - w / 2.0
		var bg := Color(0.5, 0.1, 0.1, 0.6 * a) if e["mine"] else Color(0, 0, 0, 0.45 * a)
		_panel(Rect2(x, y, w, 28), bg, Color(0, 0, 0, 0), 14)
		var kc: Color = e["killer_col"]
		var vc: Color = e["victim_col"]
		_text(Vector2(x + 14, y + 20), killer, 16, Color(kc.lightened(0.3), a))
		KnifeArt.draw(cv, Vector2(x + 14 + kw + 18, y + 14), PI / 2.0, 0.75)
		_text(Vector2(x + kw + 50, y + 20), victim, 16, Color(vc.lightened(0.3), a))
		y += 33.0


func _draw_controls(s: Vector2) -> void:
	var base := joy_origin if joy_index >= 0 else _joy_rest()
	var alpha := 1.0 if joy_index >= 0 else 0.55
	GameData.disc(cv, base, JOY_RADIUS + 6.0, Color(0, 0, 0, 0.15 * alpha))
	GameData.disc(cv, base, JOY_RADIUS, Color(1, 1, 1, 0.1 * alpha))
	cv.draw_arc(base, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35 * alpha), 3.0)
	var knob := base + joy_vector() * JOY_RADIUS
	GameData.disc(cv, knob + Vector2(0, 4), 38.0, Color(0, 0, 0, 0.2 * alpha))
	GameData.disc(cv, knob, 38.0, Color(1, 1, 1, 0.55 * alpha))
	cv.draw_arc(knob, 38.0, 0.0, TAU, 32, Color(1, 1, 1, 0.8 * alpha), 2.0)

	var p: Fighter = main.player
	var c := _throw_center()
	var ready: bool = p.knives > 0
	var col := Color(0.95, 0.3, 0.25, 0.85 if throw_held() else 0.65) if ready else Color(0.5, 0.5, 0.5, 0.4)
	var press := 4.0 if throw_held() else 0.0
	GameData.disc(cv, c + Vector2(0, 6), THROW_RADIUS, Color(0, 0, 0, 0.25))
	GameData.disc(cv, c + Vector2(0, press), THROW_RADIUS, col)
	cv.draw_arc(c + Vector2(0, press), THROW_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.6), 3.0)
	if p.throw_cooldown > 0.0:
		cv.draw_arc(c + Vector2(0, press), THROW_RADIUS - 8.0, -PI / 2,
			-PI / 2 + TAU * (1.0 - p.throw_cooldown / 0.35), 40, Color(1, 1, 1, 0.8), 5.0)
	# Hedef kilitliyse buton nabız gibi atar
	if main.player_target != null and ready:
		var pulse := fmod(Time.get_ticks_msec() / 700.0, 1.0)
		cv.draw_arc(c + Vector2(0, press), THROW_RADIUS + pulse * 22.0, 0.0, TAU, 48, Color(1, 0.3, 0.25, 1.0 - pulse), 4.0)
	KnifeArt.draw(cv, c + Vector2(0, press - 8), PI / 4.0, 2.0, p.knife_kind)
	_text(Vector2(c.x - 60, c.y + press + 50), Loc.t("throw"), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120.0)

	# Atılma (dash) butonu: bekleme süresi dolana kadar gri, dolunca parlar
	var d := _dash_center()
	var dash_ready := p.dash_cd <= 0.0
	GameData.disc(cv, d + Vector2(0, 5), DASH_RADIUS, Color(0, 0, 0, 0.25))
	GameData.disc(cv, d, DASH_RADIUS, Color(0.25, 0.55, 0.95, 0.7) if dash_ready else Color(0.3, 0.33, 0.4, 0.55))
	cv.draw_arc(d, DASH_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 2.5)
	if not dash_ready:
		cv.draw_arc(d, DASH_RADIUS - 6.0, -PI / 2, -PI / 2 + TAU * (1.0 - p.dash_cd / Fighter.DASH_COOLDOWN), 32,
			Color(1, 1, 1, 0.85), 4.0)
	for k in 3:
		var off := Vector2(-12 + k * 10, -6)
		cv.draw_polyline(PackedVector2Array([d + off + Vector2(-5, -7), d + off + Vector2(3, 0), d + off + Vector2(-5, 7)]),
			Color(1, 1, 1, 0.5 + k * 0.25), 3.5)
	_text(Vector2(d.x - 50, d.y + 24), Loc.t("dash"), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 100.0)
