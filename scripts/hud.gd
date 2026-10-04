extends Control
## Ekran arayüzü: açılış ekranı, ana menü (karakter / bıçak / seviye sekmeleri),
## mobil kontroller (sanal joystick, fırlatma ve atılma butonları), oyuncu kartı,
## mini harita, skor tablosu, leş akışı, duraklatma ve oyun sonu ekranları.
## Butonlar her karede çizilirken kaydedilir; dokunuşlar bu listeye göre kontrol edilir.

const JOY_RADIUS := 118.0 # geniş joystick: telefonda başparmakla rahat kontrol
const JOY_KNOB := 48.0
const JOY_FULL := 0.65 # yarıçapın bu oranında tam hız (az sürüklemek yeter)
const JOY_DEAD := 0.08 # bu oranın altı yok sayılır (titreme)
const THROW_RADIUS := 96.0
const DASH_RADIUS := 60.0
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
var throw_pos := Vector2.ZERO # FIRLAT tuşuna basan parmağın son konumu
var _throw_was_cooling := false
var _throw_ready_at := -10.0
var _dash_was_cooling := false
var _dash_ready_at := -10.0
var _dash_pressed_at := -10.0
var buttons: Array[Dictionary] = []
var font: Font
var page := -1
var tab := "characters" # characters | knives | levels
var popup := "" # "" | shop | settings (menüde açılır pencere)
var shop_preview := "" # koleksiyonda önizlenen kartın id'si
var scoreboard_open := false
var bigmap_open := false # dokununca açılan büyük harita
var _swipe_from := Vector2(-9999, -9999) # koleksiyonda kaydırma başlangıcı
var lb_tab := "l" # ana menü skor tablosu kategorisi (bkz. LB_TABS)
## Sohbetteki hızlı emojiler (telefonun emoji klavyesiyle her emoji de yazılabilir)
const CHAT_EMOJIS := ["😀", "😂", "😍", "😎", "😡", "😭", "👍", "🔥", "💀", "❤"]
var lb_mode := "mp" # sp (tek oyunculu) | mp (çok oyunculu)
var banner_text := ""
var banner_time := 0.0
var banner_color := Color(1, 0.4, 0.35)
var name_edit: LineEdit
var admin_edit: LineEdit
var chat_edit: LineEdit
var say_edit: LineEdit # yönetim paneli: duyuru metni
var admin_tab := "arena" # yönetim paneli orta sütun: arena | reg | conn
var admin_page := 0
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
	_create_chat_edit()
	_create_say_edit()


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
	_text(Vector2(8, s.y - 6), "%d FPS" % fps, 12, fps_col)
	if touch_debug:
		var info := "bas:%d  kaldir:%d  surukle:%d  fare:%d  son:%s  joy:%d %s  buton:%s  ekran:%s" % [dbg["down"], dbg["up"], dbg["drag"],
			dbg["mouse"], (dbg["last"] as Vector2).round(), joy_index, joy_vector().snappedf(0.01), dbg["btn"], s.round()]
		_panel(Rect2(s.x / 2 - 420, 96, 840, 30), Color(0, 0, 0, 0.75), Color(1, 0.85, 0.3), 8, 1)
		_text(Vector2(s.x / 2 - 420, 117), info, 14, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 840.0)
		GameData.disc(cv, dbg["last"], 10.0, Color(1, 0.2, 0.2, 0.8))
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
	name_edit.focus_entered.connect(func() -> void: _web_prompt.call_deferred(name_edit, Loc.t("name_placeholder")))
	add_child(name_edit)


## Yönetim paneli duyuru kutusu.
func _create_say_edit() -> void:
	say_edit = LineEdit.new()
	say_edit.max_length = 120
	say_edit.add_theme_font_size_override("font_size", 15)
	say_edit.placeholder_text = "Herkese duyurulacak mesaj..."
	for style_name in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.03, 0.05)
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(1)
		sb.border_color = GOLD if style_name == "focus" else Color(1, 1, 1, 0.2)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		say_edit.add_theme_stylebox_override(style_name, sb)
	say_edit.text_submitted.connect(func(_t: String) -> void: _on_button("adm_say"))
	say_edit.focus_entered.connect(func() -> void: _web_prompt.call_deferred(say_edit, "Duyuru"))
	say_edit.visible = false
	add_child(say_edit)


## Ana menü sohbet yazma kutusu.
func _create_chat_edit() -> void:
	chat_edit = LineEdit.new()
	chat_edit.max_length = 80
	chat_edit.add_theme_font_size_override("font_size", 15)
	chat_edit.add_theme_color_override("font_color", Color.WHITE)
	chat_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	chat_edit.add_theme_color_override("caret_color", GOLD)
	for style_name in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.03, 0.05, 0.9)
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.45, 0.75, 1) if style_name == "focus" else Color(1, 1, 1, 0.15)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		chat_edit.add_theme_stylebox_override(style_name, sb)
	chat_edit.text_submitted.connect(func(_t: String) -> void: _on_button("chat_send"))
	chat_edit.focus_entered.connect(func() -> void: _web_prompt.call_deferred(chat_edit, Loc.t("chat_placeholder")))
	chat_edit.visible = false
	add_child(chat_edit)


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
	admin_edit.focus_entered.connect(func() -> void: _web_prompt.call_deferred(admin_edit, Loc.t("admin_password")))
	admin_edit.visible = false
	add_child(admin_edit)


## Telefon tarayıcıları ekran klavyesini yalnızca dokunuşun hemen içinde açar; Godot'nun
## yazı kutusu bunu kaçırdığı için telefonda tarayıcının kendi yazı penceresi (prompt) açılır.
func _web_prompt(edit: LineEdit, title: String) -> void:
	if not OS.has_feature("web") or not DisplayServer.is_touchscreen_available():
		return
	edit.release_focus()
	var cur := JSON.stringify(edit.text if not edit.secret else "")
	var res = JavaScriptBridge.eval("window.prompt(%s, %s)" % [JSON.stringify(title), cur], true)
	if not res is String:
		return # vazgeçildi
	edit.text = String(res).strip_edges().left(edit.max_length)
	edit.text_changed.emit(edit.text)
	edit.text_submitted.emit(edit.text)


func _on_name_changed(text: String) -> void:
	main.save["player_name"] = text


func _on_name_submitted(_text: String) -> void:
	name_edit.release_focus()
	main._write_save()
	main.name_changed()


func _on_name_focus_exited() -> void:
	main._write_save()
	main.name_changed()


func _process(delta: float) -> void:
	banner_time = maxf(0.0, banner_time - delta)
	if main.state != "playing":
		joy_index = -1
		throw_index = -1
		bigmap_open = false
	var in_menu: bool = main.state == "menu"
	if not in_menu:
		popup = ""
	name_edit.visible = in_menu
	if in_menu:
		name_edit.placeholder_text = Loc.t("name_placeholder")
		var left_w := _left_w()
		var mc := _menu_center(_screen())
		name_edit.position = Vector2(mc.x - 150.0, mc.y + 178.0)
		name_edit.size = Vector2(300.0, 42.0)
		name_edit.visible = popup == ""
	elif name_edit.has_focus():
		name_edit.release_focus()
	var panel: bool = main.state == "server" or main.state == "admin"
	say_edit.visible = panel
	if panel:
		var ss := _screen()
		say_edit.position = Vector2(ss.x - 14.0 - 360.0 + 14.0, 68.0 + 58.0)
		say_edit.size = Vector2(360.0 - 112.0, 40.0)
	elif say_edit.has_focus():
		say_edit.release_focus()
	chat_edit.visible = in_menu and popup == ""
	if chat_edit.visible:
		# İsim yazılmadan sohbete yazılamaz: kutu kilitli ve ne yapılacağını söyler
		var has_name := String(main.save["player_name"]).strip_edges() != ""
		chat_edit.editable = has_name
		chat_edit.focus_mode = Control.FOCUS_ALL if has_name else Control.FOCUS_NONE
		chat_edit.placeholder_text = Loc.t("chat_placeholder") if has_name else Loc.t("chat_name_hint")
		var cr := _chat_rect(_screen())
		chat_edit.position = Vector2(cr.position.x + 8, cr.end.y - 46)
		chat_edit.size = Vector2(cr.size.x - 66, 38)
	elif chat_edit.has_focus():
		chat_edit.release_focus()
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
	var off := (joy_pos - joy_origin) / JOY_RADIUS
	if off.length() < JOY_DEAD:
		return Vector2.ZERO
	return (off / JOY_FULL).limit_length(1.0)


func throw_held() -> bool:
	return throw_index >= 0


func _screen() -> Vector2:
	return get_viewport_rect().size


func _left_w() -> float:
	return _screen().x * 0.48


func _throw_center() -> Vector2:
	var s := _screen()
	return Vector2(s.x - 160.0, s.y - 170.0)


func _dash_center() -> Vector2:
	var s := _screen()
	# Alt kenardan uzak: iPhone'da en alttaki şerit sistem hareketlerine (ana ekran) ayrılmış
	return Vector2(s.x - 350.0, s.y - 116.0)


func _joy_rest() -> Vector2:
	return Vector2(190.0, _screen().y - 190.0)


# --- Girdi -------------------------------------------------------------------

## Dokunma test modu (?dokunma): telefonda hangi olayların geldiğini ekranda gösterir.
var touch_debug := false
var dbg := {"down": 0, "up": 0, "drag": 0, "mouse": 0, "last": Vector2.ZERO, "btn": ""}


func _input(event: InputEvent) -> void:
	if touch_debug:
		if event is InputEventScreenTouch:
			dbg["down" if event.pressed else "up"] += 1
			dbg["last"] = event.position
		elif event is InputEventScreenDrag:
			dbg["drag"] += 1
			dbg["last"] = event.position
		elif event is InputEventMouseButton or event is InputEventMouseMotion:
			dbg["mouse"] += 1
	if event is InputEventScreenTouch and popup == "shop" and tab != "levels":
		var st := event as InputEventScreenTouch
		if st.pressed:
			_swipe_from = st.position
		elif _swipe_from.x > -1.0:
			var dx := st.position.x - _swipe_from.x
			if absf(dx) > 90.0 and absf(dx) > absf(st.position.y - _swipe_from.y) * 1.5:
				_on_button("page_prev" if dx > 0 else "page_next")
			_swipe_from = Vector2(-9999, -9999)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			for b in buttons:
				if (b["rect"] as Rect2).has_point(touch.position):
					if touch_debug:
						dbg["btn"] = String(b["id"])
					if b["enabled"]:
						joy_index = -1
						throw_index = -1
						_on_button(b["id"])
					get_viewport().set_input_as_handled()
					return
			if main.state != "playing":
				return
			if touch.position.distance_to(_throw_center()) < THROW_RADIUS + 34.0:
				throw_index = 0
				throw_pos = touch.position
				main.player_throw()
			elif touch.position.distance_to(_dash_center()) < DASH_RADIUS + 26.0:
				main.player_dash()
			elif touch.position.x < _screen().x * 0.6:
				# Ekranın sol tarafında nereye dokunulursa joystick orada açılır; yeni dokunuş her zaman devralır
				# (önceki parmağın kalkışı kaybolmuş olsa bile joystick kilitli kalmaz).
				joy_index = 0
				joy_origin = touch.position
				joy_pos = touch.position
		else:
			# Hangi kontrolün parmağı kalktı? iPhone Safari'de parmak numarası (index) bozuk geldiği için
			# (Godot hatası #95941) numaraya değil, kalkan parmağın konumuna bakılır: en yakın kontrol bırakılır.
			var p := touch.position
			match _nearest_control(p):
				"joy":
					joy_index = -1
				"throw":
					throw_index = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		# Sürükleme de konumuna göre en yakın etkin kontrole verilir (numara kullanılmaz)
		match _nearest_control(drag.position):
			"joy":
				joy_pos = drag.position
				var off := joy_pos - joy_origin
				if off.length() > JOY_RADIUS:
					joy_origin = joy_pos - off.normalized() * JOY_RADIUS
			"throw":
				throw_pos = drag.position


## Bir dokunuşun hangi etkin kontrole ait olduğu: joystick'in ya da FIRLAT parmağının son konumuna
## hangisi daha yakınsa o. Joystick ekranın solunda, FIRLAT sağında olduğu için karışmaz.
func _nearest_control(p: Vector2) -> String:
	var dj := p.distance_to(joy_pos) if joy_index >= 0 else INF
	var dt := p.distance_to(throw_pos) if throw_index >= 0 else INF
	# Başka bir parmak (ör. ATIL'a dokunup kalkan) yanlışlıkla joystick'i / FIRLAT'ı bırakmasın
	if dj != INF and p.x > _screen().x * 0.6 and dj > JOY_RADIUS * 1.6:
		dj = INF
	if dt != INF and dt > THROW_RADIUS * 1.6:
		dt = INF
	if dj == INF and dt == INF:
		return ""
	return "joy" if dj <= dt else "throw"

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
		"shop_characters", "shop_knives", "shop_levels":
			open_shop(id.trim_prefix("shop_"))
			main.sfx.play("select", 0.0, 0.0)
		"shop_close", "shop_outside", "settings_close":
			popup = ""
			main.sfx.play("click", -4.0, 0.0)
		"settings":
			popup = "settings"
			main.sfx.play("click", 0.0, 0.0)
		"shop_use":
			main.equip_or_buy(shop_preview)
		"noop":
			pass
		"skin_prev", "skin_next":
			main.cycle_skin(-1 if id == "skin_prev" else 1)
		"scoreboard":
			scoreboard_open = not scoreboard_open
		"bigmap":
			bigmap_open = not bigmap_open
		"atab_arena", "atab_reg", "atab_conn":
			admin_tab = id.trim_prefix("atab_")
			admin_page = 0
		"apage_prev":
			admin_page = maxi(0, admin_page - 1)
		"apage_next":
			admin_page += 1
		"adm_say":
			main.admin_say(say_edit.text)
			say_edit.text = ""
			say_edit.release_focus()
		_ when id.begins_with("emo_"):
			var e: String = CHAT_EMOJIS[id.trim_prefix("emo_").to_int()]
			if chat_edit.editable and (chat_edit.text + e).length() <= chat_edit.max_length:
				chat_edit.text += e
				main.sfx.play("select", -8.0, 0.0)
			elif not chat_edit.editable:
				flash_banner(Loc.t("chat_need_name"), Color(1, 0.6, 0.3), 2.5)
		"chat_send":
			main.send_chat(chat_edit.text)
			chat_edit.text = ""
			chat_edit.release_focus()
		"lbm_sp", "lbm_mp":
			lb_mode = id.trim_prefix("lbm_")
			lb_tab = LB_TABS[lb_mode][0][0]
			main.sfx.play("select", 0.0, 0.0)
		_ when id.begins_with("lb_"):
			lb_tab = id.trim_prefix("lb_")
			main.sfx.play("select", 0.0, 0.0)
		"admin_open":
			popup = ""
			main.on_button(id)
		_ when id.begins_with("pick_"):
			shop_preview = id.trim_prefix("pick_")
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
	_panel(Rect2(0, 0, s.x, 56), Color(0.06, 0.09, 0.13), Color(0, 0, 0, 0), 0, 0, 6)
	_text(Vector2(20, 37), "KNIFE ARENA  •  YÖNETİM PANELİ", 24, GOLD)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0)
	var online := not d.is_empty()
	var right_x := s.x - (170.0 if remote else 20.0)
	var status := ("Sunucu çalışıyor  •  " + _fmt_duration(int(d.get("uptime", 0)))) if online else "Veriler bekleniyor..."
	var sw := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	GameData.disc(cv, Vector2(right_x - sw - 16, 29), 7.0, Color(0.3, 1, 0.4, pulse) if online else Color(1, 0.6, 0.3, pulse))
	_text(Vector2(right_x - sw, 35), status, 17, Color(0.6, 1, 0.7))
	if remote:
		_button(Rect2(s.x - 150, 8, 130, 40), "menu", Loc.t("logout"), Color(0.55, 0.25, 0.25), true, 16)

	var gap := 14.0
	var lw := 330.0
	var rw := 360.0
	var mw := s.x - lw - rw - gap * 4
	var top := 68.0
	var lx := gap
	var mx := lx + lw + gap
	var rx := mx + mw + gap

	# --- Sol: durum ---
	var players: Array = d.get("players", [])
	var st := Rect2(lx, top, lw, 150)
	_panel(st, PANEL_BG, Color(1, 1, 1, 0.08), 14, 1)
	var cloud_on: bool = d.get("cloud", false)
	var stats := [
		["Arenadaki oyuncu", str(players.size()), GOLD],
		["Menüde bekleyen", str(d.get("menu_count", 0)), GOLD],
		["Bot (canlı / hedef)", "%d / %d" % [int(d.get("bots", 0)), int(d.get("bot_target", 0))], GOLD],
		["Skor tablosundaki oyuncu", str(d.get("lb_count", 0)), GOLD],
		["Kalıcı kayıt (bulut)", "Açık" if cloud_on else "Kapalı", Color(0.5, 1, 0.6) if cloud_on else Color(1, 0.6, 0.4)],
	]
	if not remote:
		var urls: Array = d.get("urls", [])
		stats.push_front(["Telefondan (aynı Wi-Fi)", urls[0] if not urls.is_empty() else "-", Color.WHITE])
	for i in stats.size():
		var y := st.position.y + 24 + i * 24
		_text(Vector2(st.position.x + 14, y), stats[i][0], 14, Color(1, 1, 1, 0.65))
		_text(Vector2(st.position.x, y), stats[i][1], _fit_size(stats[i][1], 15, 150.0), stats[i][2], HORIZONTAL_ALIGNMENT_RIGHT, st.size.x - 14)

	# --- Sol: kontroller ---
	var ct := Rect2(lx, st.end.y + gap, lw, 296)
	_panel(ct, PANEL_BG, Color(1, 1, 1, 0.08), 14, 1)
	_text(Vector2(ct.position.x + 14, ct.position.y + 26), "ARENA KONTROLLERİ", 15, GOLD)
	_text(Vector2(ct.position.x + 14, ct.position.y + 58), "En çok bot", 15, Color.WHITE)
	_text(Vector2(ct.position.x + 14, ct.position.y + 74), "(oyuncu girdikçe azalır)", 10, Color(1, 1, 1, 0.45))
	_button(Rect2(ct.end.x - 150, ct.position.y + 36, 44, 36), "adm_bot_minus", "-", Color(0.55, 0.25, 0.25), true, 22)
	_text(Vector2(ct.end.x - 104, ct.position.y + 62), str(d.get("bot_target", 0)), 20, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 50.0)
	_button(Rect2(ct.end.x - 56, ct.position.y + 36, 44, 36), "adm_bot_plus", "+", Color(0.22, 0.6, 0.33), true, 22)
	var zone_on: bool = d.get("zone", false)
	var chat_locked: bool = d.get("chat_locked", false)
	var grid := [
		["adm_reset", "ARENAYI SIFIRLA", Color(0.6, 0.32, 0.22)],
		["adm_event", "OLAY BAŞLAT", Color(0.7, 0.52, 0.14)],
		["adm_boss", "DEV ÇAĞIR", Color(0.65, 0.2, 0.2)],
		["adm_zone", "ALAN: AÇIK" if zone_on else "ALAN: KAPALI", Color(0.75, 0.2, 0.25) if zone_on else Color(0.3, 0.36, 0.45)],
		["adm_chatlock", "SOHBETİ AÇ" if chat_locked else "SOHBETİ KAPAT", Color(0.22, 0.55, 0.33) if chat_locked else Color(0.4, 0.3, 0.55)],
		["adm_chatclear", "SOHBETİ TEMİZLE", Color(0.4, 0.3, 0.55)],
		["adm_lbreset", "SKOR TABLOSUNU SIFIRLA", Color(0.7, 0.22, 0.22)],
	]
	var bw := (lw - 14 * 2 - 10) / 2.0
	for i in grid.size():
		var full := i == grid.size() - 1 # son buton tam genişlik (tehlikeli işlem)
		var bx := ct.position.x + 14 + (0.0 if full else (i % 2) * (bw + 10))
		var by := ct.position.y + 84 + (i / 2) * 50
		_button(Rect2(bx, by, lw - 28 if full else bw, 42), grid[i][0], grid[i][1], grid[i][2], true, 13)

	# --- Sol: sunucu günlüğü ---
	var lg := Rect2(lx, ct.end.y + gap, lw, s.y - ct.end.y - gap * 2)
	_panel(lg, PANEL_BG, Color(1, 1, 1, 0.08), 14, 1)
	_text(Vector2(lg.position.x + 14, lg.position.y + 24), "SUNUCU GÜNLÜĞÜ", 15, GOLD)
	var log: Array = d.get("log", [])
	var rows := int((lg.size.y - 40) / 19)
	for i in mini(rows, log.size()):
		var e: Dictionary = log[i]
		var y := lg.position.y + 46 + i * 19
		_text(Vector2(lg.position.x + 12, y), e["time"], 11, Color(1, 1, 1, 0.4))
		var txt: String = e["text"]
		_text(Vector2(lg.position.x + 74, y), txt, _fit_size(txt, 13, lw - 86.0), e["col"])

	# --- Orta: sekmeler (arenadakiler / tüm oyuncular / giriş-çıkış kayıtları) ---
	var reg: Array = d.get("reg", [])
	var tabs := [["arena", "ARENA (%d)" % players.size()], ["reg", "TÜM OYUNCULAR (%d)" % reg.size()], ["conn", "GİRİŞ KAYITLARI"]]
	var tw := (mw - 8.0 * 2) / 3.0
	for i in tabs.size():
		var tr := Rect2(mx + i * (tw + 8.0), top, tw, 38)
		var on: bool = admin_tab == tabs[i][0]
		_panel(tr, Color(GOLD, 0.2) if on else Color(1, 1, 1, 0.05), GOLD if on else Color(1, 1, 1, 0.1), 10, 2 if on else 1)
		_text_fit(Vector2(tr.position.x, tr.position.y + 25), tabs[i][1], 14, GOLD if on else Color(1, 1, 1, 0.6), tr.size.x)
		buttons.append({"rect": tr, "id": "atab_" + tabs[i][0], "enabled": true})
	var body := Rect2(mx, top + 46, mw, s.y - top - 46 - gap)
	match admin_tab:
		"reg":
			_draw_registry(body, reg)
		"conn":
			_draw_conn_log(body, d.get("conn", []))
		_:
			_draw_server_players(body, players)

	# --- Sağ: duyuru ve sohbet yönetimi ---
	var an := Rect2(rx, top, rw, 112)
	_panel(an, PANEL_BG, GOLD, 14, 2)
	_text(Vector2(an.position.x + 14, an.position.y + 26), "DUYURU GÖNDER", 15, GOLD)
	_text(Vector2(an.position.x + 14, an.position.y + 46), "Oyundaki ve menüdeki herkes görür", 11, Color(1, 1, 1, 0.5))
	_button(Rect2(an.end.x - 84, an.position.y + 58, 70, 40), "adm_say", "GÖNDER", Color(0.75, 0.55, 0.12), true, 13)
	_draw_chat_mod(Rect2(rx, an.end.y + gap, rw, s.y - an.end.y - gap * 2), d)


## Yönetim paneli: oyuncular (cihaz, konum, seviye, leş) ve oyuncu başına işlemler.
func _draw_server_players(r: Rect2, players: Array) -> void:
	_panel(r, PANEL_BG, Color(1, 1, 1, 0.08), 14, 1)
	_text(Vector2(r.position.x + 14, r.position.y + 24), "ARENADAKİ OYUNCULAR (%d)" % players.size(), 15, GOLD)
	if players.is_empty():
		_text(Vector2(r.position.x, r.position.y + r.size.y / 2.0 + 10), "Şu an arenada oyuncu yok", 16, Color(1, 1, 1, 0.45),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var acts := [["coins", "+100", Color(0.75, 0.55, 0.12)], ["level", "+1 Sv", Color(0.3, 0.45, 0.85)],
		["heal", "Can", Color(0.22, 0.6, 0.33)], ["kick", "At", Color(0.7, 0.25, 0.22)]]
	var row_h := 52.0
	for i in players.size():
		var y := r.position.y + 36 + i * row_h
		if y + row_h > r.end.y:
			break
		var pl: Dictionary = players[i]
		var peer := int(pl["peer"])
		var row := Rect2(r.position.x + 8, y, r.size.x - 16, row_h - 6)
		_panel(row, Color(1, 1, 1, 0.04) if i % 2 == 0 else Color(1, 1, 1, 0.02), Color(0, 0, 0, 0), 10)
		var mid := row.position.y + row.size.y / 2.0
		if String(pl["skin"]) != "":
			_draw_skin(pl["skin"], Vector2(row.position.x + 22, mid - 2), 42.0)
		var alive: bool = pl["alive"]
		GameData.disc(cv, Vector2(row.position.x + 40, mid + 12), 4.0, Color(0.4, 1, 0.5) if alive else Color(1, 0.4, 0.35))
		var info_w := row.size.x - acts.size() * 52.0 - 60.0
		var pname := "%s  •  Sv %d  •  %d leş" % [String(pl["name"]), int(pl["level"]), int(pl["kills"])]
		_text(Vector2(row.position.x + 50, mid - 2), pname, _fit_size(pname, 14, info_w), Color.WHITE)
		var where := String(pl.get("dev", "?"))
		if String(pl.get("loc", "")) != "":
			where += "  •  " + String(pl["loc"])
		where += "  •  " + _fmt_duration(int(pl["since"]))
		_text(Vector2(row.position.x + 50, mid + 15), where, _fit_size(where, 11, info_w), Color(0.6, 0.85, 1, 0.8))
		var bx := row.end.x - acts.size() * 52.0
		for a in acts:
			_button(Rect2(bx, row.position.y + 6, 48, 34), "adm_%s_%d" % [a[0], peer], a[1], a[2], true, 12)
			bx += 52.0


## Yönetim paneli: şimdiye kadar giren tüm oyuncular; seviye / altın düzenleme ve hesap sıfırlama.
## Değişiklik oyuncu çevrimiçiyse hemen, değilse bir sonraki girişinde uygulanır ("bekliyor").
func _draw_registry(r: Rect2, reg: Array) -> void:
	_panel(r, PANEL_BG, Color(1, 1, 1, 0.08), 14, 1)
	_text(Vector2(r.position.x + 14, r.position.y + 24), "KAYITLI OYUNCULAR (ilk başlama sırasıyla)", 15, GOLD)
	_text(Vector2(r.position.x, r.position.y + 24), "yeşil nokta: şu an bağlı", 11, Color(1, 1, 1, 0.45),
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14.0)
	if reg.is_empty():
		_text(Vector2(r.position.x, r.position.y + r.size.y / 2.0), "Henüz kayıtlı oyuncu yok", 15, Color(1, 1, 1, 0.45),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var row_h := 48.0
	var per_page := maxi(1, int((r.size.y - 80.0) / row_h))
	var pages := ceili(reg.size() / float(per_page))
	admin_page = clampi(admin_page, 0, pages - 1)
	var acts := [["lvdn", "Sv-", Color(0.3, 0.36, 0.5)], ["lvup", "Sv+", Color(0.3, 0.45, 0.85)],
		["cdn", "-100", Color(0.5, 0.4, 0.2)], ["cup", "+100", Color(0.75, 0.55, 0.12)], ["reset", "Sıfırla", Color(0.7, 0.25, 0.22)],
		["free", "Bırak", Color(0.35, 0.45, 0.55)]]
	var bw := 40.0
	for i in per_page:
		var idx := admin_page * per_page + i
		if idx >= reg.size():
			break
		var p: Dictionary = reg[idx]
		var row := Rect2(r.position.x + 8, r.position.y + 36 + i * row_h, r.size.x - 16, row_h - 6)
		_panel(row, Color(1, 1, 1, 0.04) if i % 2 == 0 else Color(1, 1, 1, 0.02), Color(0, 0, 0, 0), 10)
		var mid := row.position.y + row.size.y / 2.0
		GameData.disc(cv, Vector2(row.position.x + 12, mid - 6), 5.0, Color(0.4, 1, 0.5) if p.get("on", false) else Color(1, 1, 1, 0.2))
		var info_w := row.size.x - acts.size() * (bw + 4) - 30.0
		var line1 := "%d. %s  •  Sv %d  •  %d altın  •  %d leş" % [idx + 1, String(p.get("n", "?")), int(p.get("l", 1)), int(p.get("c", 0)), int(p.get("kills", 0))]
		_text(Vector2(row.position.x + 24, mid - 2), line1, _fit_size(line1, 14, info_w), Color.WHITE)
		var line2 := "Başladı: %s  •  Son: %s  •  %s" % [String(p.get("first", "-")), String(p.get("seen", "-")), String(p.get("dev", ""))]
		if p.get("pend", false):
			line2 += "  •  değişiklik bekliyor"
		if p.get("owned", false):
			line2 = "🔒 " + line2
		_text(Vector2(row.position.x + 24, mid + 14), line2, _fit_size(line2, 11, info_w), Color(0.6, 0.85, 1, 0.8))
		var bx := row.end.x - acts.size() * (bw + 4)
		for a in acts:
			_button(Rect2(bx, row.position.y + 5, bw, 32), "adm_pl_%s_%s" % [a[0], p["k"]], a[1], a[2], true, 11)
			bx += bw + 4
	if pages > 1:
		var py := r.end.y - 38.0
		var cx := r.position.x + r.size.x / 2.0
		_button(Rect2(cx - 110, py, 60, 30), "apage_prev", "<", Color(0.25, 0.3, 0.42), admin_page > 0, 16)
		_text(Vector2(cx - 50, py + 21), "%d / %d" % [admin_page + 1, pages], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 100.0)
		_button(Rect2(cx + 50, py, 60, 30), "apage_next", ">", Color(0.25, 0.3, 0.42), admin_page < pages - 1, 16)


## Yönetim paneli: giriş / çıkış kayıtları (sunucu yeniden başlasa da saklanır).
func _draw_conn_log(r: Rect2, conn: Array) -> void:
	_panel(r, PANEL_BG, Color(1, 1, 1, 0.08), 14, 1)
	_text(Vector2(r.position.x + 14, r.position.y + 24), "GİRİŞ / ÇIKIŞ KAYITLARI", 15, GOLD)
	if conn.is_empty():
		_text(Vector2(r.position.x, r.position.y + r.size.y / 2.0), "Henüz kayıt yok", 15, Color(1, 1, 1, 0.45),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var evs := {"giris_menu": ["menüye girdi", Color(0.5, 1, 0.6)], "giris_arena": ["arenaya girdi", Color(0.6, 0.85, 1)],
		"cikis": ["çıktı", Color(1, 0.55, 0.45)]}
	var rows := int((r.size.y - 40) / 20)
	var shown := 0
	for i in range(conn.size() - 1, -1, -1): # en yeni üstte
		if shown >= rows:
			break
		var c: Dictionary = conn[i]
		var y := r.position.y + 46 + shown * 20
		shown += 1
		var ev: Array = evs.get(String(c.get("ev", "")), [String(c.get("ev", "")), Color.WHITE])
		_text(Vector2(r.position.x + 12, y), String(c.get("t", "")), 11, Color(1, 1, 1, 0.4))
		var nm := String(c.get("n", "?"))
		_text(Vector2(r.position.x + 92, y), nm, _fit_size(nm, 13, 100.0), Color.WHITE)
		var evt: String = ev[0]
		if int(c.get("dur", -1)) >= 0:
			evt += " (" + _fmt_duration(int(c["dur"])) + ")"
		_text(Vector2(r.position.x + 196, y), evt, _fit_size(evt, 12, 130.0), ev[1])
		var where := String(c.get("dev", ""))
		if String(c.get("loc", "")) != "":
			where += "  •  " + String(c["loc"])
		_text(Vector2(r.position.x + 330, y), where, _fit_size(where, 12, r.size.x - 342.0), Color(1, 1, 1, 0.6))


## Yönetim paneli: sohbet mesajları (sil / sustur) ve susturulanlar.
func _draw_chat_mod(r: Rect2, d: Dictionary) -> void:
	_panel(r, PANEL_BG, Color(0.45, 0.75, 1, 0.3), 14, 1)
	var locked: bool = d.get("chat_locked", false)
	_text(Vector2(r.position.x + 14, r.position.y + 24), "GENEL SOHBET" + ("  (KAPALI)" if locked else ""), 15,
		Color(1, 0.6, 0.45) if locked else Color(0.6, 0.85, 1))
	var muted: Array = d.get("muted", [])
	var mute_h := 0.0 if muted.is_empty() else 30.0 + ceili(muted.size() / 2.0) * 34.0
	var msgs: Array = d.get("chat", [])
	var list_bottom := r.end.y - mute_h - 8.0
	if msgs.is_empty():
		_text(Vector2(r.position.x, r.position.y + (list_bottom - r.position.y) / 2.0 + 20), "Sohbette mesaj yok", 14,
			Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var row_h := 40.0
	var y := r.position.y + 36
	for i in range(msgs.size() - 1, -1, -1): # en yeni üstte
		if y + row_h > list_bottom:
			break
		var m: Dictionary = msgs[i]
		var row := Rect2(r.position.x + 8, y, r.size.x - 16, row_h - 4)
		var is_admin: bool = m.get("a", false)
		_panel(row, Color(GOLD, 0.1) if is_admin else Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 8)
		var nm := String(m.get("n", "?")) + ": "
		var line := nm + String(m.get("m", ""))
		var tw := row.size.x - (20.0 if is_admin else 128.0)
		_text(Vector2(row.position.x + 10, row.position.y + 23), line, _fit_size(line, 13, tw), GOLD if is_admin else Color.WHITE)
		if not is_admin:
			var mid := int(m.get("id", -1))
			_button(Rect2(row.end.x - 112, row.position.y + 5, 50, 26), "adm_chatdel_%d" % mid, "Sil", Color(0.6, 0.3, 0.25), true, 12)
			_button(Rect2(row.end.x - 58, row.position.y + 5, 52, 26), "adm_chatmute_%d" % mid, "Sustur", Color(0.45, 0.3, 0.55), true, 11)
		y += row_h
	if not muted.is_empty():
		var my := r.end.y - mute_h
		_text(Vector2(r.position.x + 14, my + 18), "Susturulanlar (dokun: kaldır)", 12, Color(1, 0.6, 0.45))
		var cw := (r.size.x - 28 - 8) / 2.0
		for i in muted.size():
			var bx := r.position.x + 14 + (i % 2) * (cw + 8)
			var by := my + 26 + (i / 2) * 34
			_button(Rect2(bx, by, cw, 30), "adm_unmute_%d" % i, String(muted[i]) + "  x", Color(0.35, 0.3, 0.4), true, 12)

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
# Düzen: üstte logo, altın, seviye ve ayarlar; ortada seçili karakter vitrini, isim kutusu ve
# iki büyük mod butonu (tek / çok oyunculu); solda koleksiyon butonları; sağda istatistikler.
# Koleksiyon (karakter/bıçak/seviye) ve ayarlar açılır kapanır pencerelerde.

func _menu_center(s: Vector2) -> Vector2:
	return Vector2(s.x / 2.0, s.y * 0.43)


func _draw_menu(s: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# Arka plan: arena hafifçe görünür, kenarlara doğru koyulaşır
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.06, 0.05, 0.62))
	for i in 8:
		var w := 40.0 + i * 22.0
		cv.draw_rect(Rect2(0, 0, w, s.y), Color(0, 0, 0, 0.05))
		cv.draw_rect(Rect2(s.x - w, 0, w, s.y), Color(0, 0, 0, 0.05))
	_draw_menu_header(s)
	_draw_showcase(s, t)
	_draw_menu_side(s)
	_draw_mode_buttons(s, t)
	if popup != "":
		buttons.clear() # alttaki menü butonları pencere açıkken basılamasın
		if popup == "shop":
			_draw_shop(s, t)
		else:
			_draw_settings(s)


func _draw_menu_header(s: Vector2) -> void:
	_text(Vector2(28, 62), "KNIFE ARENA", 44, GOLD)
	_text(Vector2(30, 88), Loc.t("tagline"), 14, Color(1, 1, 1, 0.65))
	# Sağ üst: ayarlar, seviye, altın (sağdan sola)
	var x := s.x - 24.0 - 52.0
	var gear := Rect2(x, 22, 52, 52)
	_button(gear, "settings", "", Color(0.25, 0.3, 0.42), true, 16)
	var gc := gear.get_center() + Vector2(0, 1)
	for k in 8:
		GameData.disc(cv, gc + Vector2.from_angle(TAU * k / 8.0) * 13.0, 4.5, Color.WHITE)
	GameData.disc(cv, gc, 12.0, Color.WHITE)
	GameData.disc(cv, gc, 5.5, Color(0.25, 0.3, 0.42))
	x -= 12.0
	var lvl := int(main.save["level"])
	var need := GameData.xp_needed(lvl)
	var lw := 210.0
	x -= lw
	_panel(Rect2(x, 22, lw, 52), PANEL_BG, Color(0.45, 0.75, 1, 0.6), 26, 2)
	_level_badge(Vector2(x + 26, 48), 18.0, lvl)
	var bar := Rect2(x + 52, 41, lw - 66, 14)
	_progress_bar(bar, 1.0 if lvl >= GameData.MAX_LEVEL else float(main.save["xp"]) / need, Color(0.45, 0.75, 1))
	_text(Vector2(bar.position.x, bar.end.y - 2), "%d / %d XP" % [int(main.save["xp"]), need], 11, Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER, bar.size.x)
	x -= 12.0
	var coins := int(main.save["coins"])
	var cw := _coin_width(coins, 24) + 34.0
	x -= cw
	_panel(Rect2(x, 22, cw, 52), PANEL_BG, GOLD, 26, 2)
	_coin_amount(Vector2(x + 17, 57), coins, 24)


## Seçili karakter: kaide, parlama ve etrafında dönen seçili bıçaklar.
func _draw_showcase(s: Vector2, t: float) -> void:
	var skin: Dictionary = main.playable_skin()
	var sel_id: String = skin["id"]
	var skin_col: Color = skin["color"]
	var c := _menu_center(s)
	for i in 5:
		GameData.disc(cv, c + Vector2(0, 20), 220.0 - i * 24.0, Color(0.02, 0.04, 0.04, 0.12))
	for i in 6:
		GameData.disc(cv, c + Vector2(0, 10), 145.0 - i * 18.0, Color(skin_col, 0.05))
	cv.draw_set_transform(c + Vector2(0, 88), 0.0, Vector2(1.0, 0.3))
	GameData.disc(cv, Vector2.ZERO, 118.0, Color(0, 0, 0, 0.4))
	GameData.disc(cv, Vector2.ZERO, 102.0, skin_col)
	GameData.disc(cv, Vector2.ZERO, 95.0, skin_col.darkened(0.6))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var kind: int = main.selected_knife()
	var kc := c + Vector2(0, 24)
	var pos: Array[Vector2] = []
	var rot: Array[float] = []
	for i in 8:
		var a := t * 1.5 + TAU * i / 8.0
		pos.append(kc + Vector2(cos(a) * 150.0, sin(a) * 46.0))
		rot.append(Vector2(cos(a), sin(a) * 0.3).angle() + PI / 2.0)
	for i in 8:
		if pos[i].y < kc.y:
			KnifeArt.draw(cv, pos[i], rot[i], 1.05, kind)
	var acc: int = main.selected_acc()
	if acc > 0:
		GameData.draw_accessory(cv, acc, sel_id, c + Vector2(0, -12), 200.0, 1.0, t, true)
	_draw_skin(sel_id, c + Vector2(0, -12), 200.0, Color.WHITE, 1 + int(t * 10.0) % 8)
	if acc > 0:
		GameData.draw_accessory(cv, acc, sel_id, c + Vector2(0, -12), 200.0, 1.0, t, false)
	for i in 8:
		if pos[i].y >= kc.y:
			KnifeArt.draw(cv, pos[i], rot[i], 1.05, kind)
	for side in [-1, 1]:
		var ac := c + Vector2(side * 225.0, -10.0)
		var ar := Rect2(ac - Vector2(40, 40), Vector2(80, 80))
		GameData.disc(cv, ac + Vector2(0, 4), 36.0, Color(0, 0, 0, 0.3))
		GameData.disc(cv, ac, 36.0, Color(0.12, 0.16, 0.22, 0.85))
		cv.draw_arc(ac, 36.0, 0.0, TAU, 32, Color(GOLD, 0.7), 2.5)
		var tip := ac + Vector2(side * 11.0, 0)
		cv.draw_polyline(PackedVector2Array([tip - Vector2(side * 16.0, -16.0), tip, tip - Vector2(side * 16.0, 16.0)]), Color.WHITE, 6.0)
		buttons.append({"rect": ar, "id": "skin_prev" if side < 0 else "skin_next", "enabled": true})
	_text_fit(Vector2(c.x - 250, c.y + 140), Loc.t(sel_id + ".name"), 30, Color.WHITE, 500.0)
	var kinfo: Dictionary = GameData.KNIVES[kind]
	_text_fit(Vector2(c.x - 250, c.y + 164), Loc.t("knife_label") % Loc.t(kinfo["id"] + ".name"), 15,
		(kinfo["color"] as Color).lightened(0.25), 500.0)
	# (İsim kutusu bunun altında LineEdit olarak çizilir: bkz. _process)


## Sol: koleksiyon butonları. Sağ: istatistikler.
func _draw_menu_side(s: Vector2) -> void:
	var owned_skins := 0
	for sk in GameData.available_skins():
		if main.skin_unlocked(sk):
			owned_skins += 1
	var owned_knives := 0
	for kn in GameData.KNIVES:
		if main.skin_unlocked(kn):
			owned_knives += 1
	var items := [
		["shop_characters", Loc.t("tab_characters"), "%d / %d" % [owned_skins, GameData.available_skins().size()], Color(0.55, 0.3, 0.25)],
		["shop_knives", Loc.t("tab_knives"), "%d / %d" % [owned_knives, GameData.KNIVES.size()], Color(0.3, 0.42, 0.6)],
		["shop_levels", Loc.t("tab_levels"), Loc.t("level_short") % int(main.save["level"]), Color(0.32, 0.3, 0.55)],
	]
	var y := 120.0
	var claimable: int = main.quest_claimable_count()
	for it in items:
		var r := Rect2(24, y, 230, 64)
		_button(r, it[0], "", it[3], true, 16)
		_text(Vector2(r.position.x + 18, r.position.y + 30), it[1], _fit_size(it[1], 19, 150.0), Color.WHITE)
		_text(Vector2(r.position.x + 18, r.position.y + 52), it[2], 13, Color(1, 1, 1, 0.7))
		_text(Vector2(r.end.x - 34, r.position.y + 42), ">", 24, Color(1, 1, 1, 0.8))
		# Alınmayı bekleyen görev ödülü varsa seviye butonunda kırmızı rozet
		if it[0] == "shop_levels" and claimable > 0:
			var bc := Vector2(r.end.x - 6, r.position.y + 6)
			GameData.disc(cv, bc, 13.0, Color(0.9, 0.2, 0.2))
			_text(bc + Vector2(-13, 6), str(claimable), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 26.0)
		y += 78.0
	# Sol alt: genel sohbet
	_draw_chat(_chat_rect(s))
	_draw_leaderboard(Rect2(s.x - 24 - 260, 92, 260, s.y - 92 - 24))


func _chat_rect(s: Vector2) -> Rect2:
	return Rect2(24, 356, 260, s.y - 356 - 24)


## Ana menü genel sohbeti: son mesajlar (alttan yukarı, satır kaydırmalı) ve yazma kutusu.
func _draw_chat(r: Rect2) -> void:
	_panel(r, PANEL_BG, Color(0.45, 0.75, 1, 0.35), 16, 1)
	var online: bool = main.lobby_online
	var st := _server_status()
	GameData.disc(cv, r.position + Vector2(18, 21), 5.0, Color(0.3, 1, 0.4) if online else st[1])
	_text(Vector2(r.position.x + 30, r.position.y + 27), Loc.t("chat_title"), 16, Color(0.6, 0.85, 1))
	var note := ""
	if not online:
		note = st[0] if main.lobby_state != "" else Loc.t("chat_connecting")
	elif main.save["top"] is Dictionary and main.save["top"].get("chat_locked", false) and (main.chat as Array).is_empty():
		note = Loc.t("chat_locked")
	# Yazma kutusu ve gönder butonu (kutu LineEdit olarak _process'te konumlanır)
	_button(Rect2(r.end.x - 50, r.end.y - 46, 42, 38), "chat_send", ">", Color(0.28, 0.42, 0.88), true, 20)
	# Hızlı emoji satırı: dokununca yazı kutusuna eklenir
	var ew := (r.size.x - 16.0) / CHAT_EMOJIS.size()
	for i in CHAT_EMOJIS.size():
		var er := Rect2(r.position.x + 8 + i * ew, r.end.y - 86, ew - 3, 34)
		_panel(er, Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.08), 8, 1)
		# Genişlik verilmez (taşan metni kırpmasın); ortalama elle yapılır
		var efs := 17
		var eww := font.get_string_size(CHAT_EMOJIS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, efs).x
		cv.draw_string(font, Vector2(er.get_center().x - eww / 2.0, er.position.y + 24), CHAT_EMOJIS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, efs, Color(1, 0.9, 0.55))
		buttons.append({"rect": er, "id": "emo_%d" % i, "enabled": true})
	# Mesajlar: en yenisi altta
	var fs := 14
	var lh := 18.0
	var width := r.size.x - 24.0
	var y := r.end.y - 98.0
	var top := r.position.y + 40.0
	var msgs: Array = main.chat
	if msgs.is_empty() or note != "":
		# Boş ya da bağlantı yok: ortada açıklama (sunucu durumu ya da ilk mesaj daveti)
		var info := note if note != "" else Loc.t("chat_empty")
		var lines := _wrap(info, 13, width - 10.0)
		var cy := r.get_center().y - lines.size() * 9.0
		for k in lines.size():
			_text(Vector2(r.position.x + 12, cy + k * 18.0), lines[k], 13, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, width)
		if note != "" or msgs.is_empty():
			return
	var me := String(main.save["player_name"]).strip_edges().to_lower()
	for i in range(msgs.size() - 1, -1, -1):
		var m: Dictionary = msgs[i]
		var nm := String(m["n"]) + ": "
		var lines := _wrap(nm + String(m["m"]), fs, width)
		if y - (lines.size() - 1) * lh < top:
			break
		var ly := y - (lines.size() - 1) * lh
		var name_col := Color(1, 0.45, 0.35) if m.get("a", false) else (GOLD if String(m["n"]).to_lower() == me else Color(0.6, 0.85, 1))
		for k in lines.size():
			var line: String = lines[k]
			var lx := r.position.x + 12
			if k == 0:
				# İlk satırda isim renkli, mesaj beyaz
				_text(Vector2(lx, ly), nm, fs, name_col)
				var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				_text(Vector2(lx + nw, ly), line.substr(nm.length()), fs, Color.WHITE)
			else:
				_text(Vector2(lx, ly + k * lh), line, fs, Color.WHITE)
		y -= lines.size() * lh + 4.0


## Basit kelime kaydırma: metni verilen genişliğe sığan satırlara böler.
func _wrap(text: String, size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var test := word if line == "" else line + " " + word
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width or line == "":
			line = test
		else:
			out.append(line)
			line = word
	if line != "":
		out.append(line)
	return out


## Skor tablosu kategorileri: mod → [istatistik anahtarı, başlık, kayıttaki karşılığı, renk]
const LB_TABS := {
	"sp": [["l", "lb_level", "level"], ["sk", "lb_kills", "sp_kills"], ["sc", "lb_coins", "sp_coins"]],
	"mp": [["l", "lb_level", "level"], ["mk", "lb_kills", "mp_kills"], ["mc", "lb_coins", "mp_coins"]],
}
const MEDALS := [Color(1, 0.82, 0.25), Color(0.82, 0.85, 0.92), Color(0.86, 0.55, 0.3)]


## Ana menü skor tablosu: çevrimiçi sunucudan çekilen liste + oyuncunun kendisi.
## Üstte mod seçimi (tek / çok oyunculu), altında kategori; ilk üçe taç ve madalyalar.
func _draw_leaderboard(r: Rect2) -> void:
	_panel(r, PANEL_BG, Color(GOLD, 0.35), 18, 2)
	_draw_crown_icon(Vector2(r.position.x + 30, r.position.y + 24), 0.8)
	_text(Vector2(r.position.x + 22, r.position.y + 31), Loc.t("lb_title"), 19, GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 22.0)
	# Mod seçimi
	var mw := (r.size.x - 28.0) / 2.0
	for i in 2:
		var mode: String = ["sp", "mp"][i]
		var mr := Rect2(r.position.x + 12 + i * (mw + 4.0), r.position.y + 42, mw, 40)
		var on := lb_mode == mode
		var mcol := Color(0.22, 0.66, 0.33) if mode == "sp" else Color(0.28, 0.42, 0.88)
		_panel(mr, mcol if on else Color(1, 1, 1, 0.05), mcol.lightened(0.3) if on else Color(1, 1, 1, 0.1), 10, 2 if on else 1)
		_text_fit(Vector2(mr.position.x, mr.position.y + 26), Loc.t("lb_" + mode), 14, Color.WHITE if on else Color(1, 1, 1, 0.55), mr.size.x)
		buttons.append({"rect": mr.grow(3.0), "id": "lbm_" + mode, "enabled": true})
	# Kategori
	var tabs: Array = LB_TABS[lb_mode]
	if not tabs.any(func(x: Array) -> bool: return x[0] == lb_tab):
		lb_tab = tabs[0][0]
	var tw := (r.size.x - 24.0 - 8.0) / 3.0
	var cur: Array = tabs[0]
	for i in tabs.size():
		var tr := Rect2(r.position.x + 12 + i * (tw + 4.0), r.position.y + 88, tw, 38)
		var active: bool = lb_tab == tabs[i][0]
		if active:
			cur = tabs[i]
		_panel(tr, Color(GOLD, 0.22) if active else Color(1, 1, 1, 0.04), GOLD if active else Color(1, 1, 1, 0.08), 9, 2 if active else 1)
		_text_fit(Vector2(tr.position.x, tr.position.y + 25), Loc.t(tabs[i][1]), 13, GOLD if active else Color(1, 1, 1, 0.55), tr.size.x)
		buttons.append({"rect": tr.grow(3.0), "id": "lb_" + tabs[i][0], "enabled": true})
	# Satırlar: sunucu listesi + oyuncunun güncel değeri
	var me := String(main.save["player_name"]).strip_edges()
	var my_val := int(main.save[cur[2]])
	var top: Dictionary = main.save["top"] if main.save["top"] is Dictionary else {}
	var rows := []
	var found := false
	for row in top.get(lb_tab, []):
		var n := String(row[0])
		var v := int(row[1])
		var mine := me != "" and n.to_lower() == me.to_lower()
		if mine:
			found = true
			v = maxi(v, my_val)
		rows.append([n, v, mine])
	if not found:
		rows.append([me if me != "" else Loc.t("lb_you"), my_val, true])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var y0 := r.position.y + 134.0
	var foot := 30.0 # alttaki "ilk 3" hedef yazısı
	var rh := clampf((r.end.y - y0 - foot) / 8.0, 30.0, 44.0)
	var max_rows := int((r.end.y - y0 - foot) / rh)
	var my_rank := 0
	for i in rows.size():
		if rows[i][2]:
			my_rank = i
	var vcol := Color(0.6, 0.85, 1) if lb_tab == "l" else GOLD
	for i in mini(rows.size(), max_rows):
		var idx := i
		# Son satır: oyuncu listenin dışında kalıyorsa onu göster
		if i == max_rows - 1 and my_rank >= max_rows:
			idx = my_rank
		var row: Array = rows[idx]
		var rr := Rect2(r.position.x + 8, y0 + i * rh, r.size.x - 16, rh - 4.0)
		var mine: bool = row[2]
		# Sunucudan liste gelmeden (yalnızca kendin) taç / madalya gösterilmez
		var podium: bool = idx < 3 and not top.get(lb_tab, []).is_empty()
		var bg := Color(MEDALS[idx], 0.16) if podium else Color(1, 1, 1, 0.04 if i % 2 == 0 else 0.02)
		var border := Color(MEDALS[idx], 0.55) if podium else Color(0, 0, 0, 0)
		if mine:
			bg = Color(GOLD, 0.24)
			border = GOLD
		_panel(rr, bg, border, 10, 2 if mine else (1 if podium else 0))
		var rc := rr.position + Vector2(20, rr.size.y / 2.0)
		var fs := int(minf(17.0 if podium else 15.0, rh * 0.48))
		if idx == 0 and podium:
			_draw_crown_icon(rc + Vector2(0, 1), 0.85)
		elif podium:
			_draw_medal(rc, minf(11.0, rh * 0.3), MEDALS[idx], idx + 1)
		else:
			_text(Vector2(rc.x - 14, rc.y + fs * 0.36), str(idx + 1), fs, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 28.0)
		var val := str(row[1])
		var vw := font.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var name_col: Color = GOLD if mine else (MEDALS[idx].lightened(0.25) if podium else Color.WHITE)
		_text(Vector2(rr.position.x + 42, rc.y + fs * 0.36), String(row[0]), _fit_size(String(row[0]), fs, rr.size.x - 60.0 - vw), name_col)
		_text(Vector2(rr.position.x, rc.y + fs * 0.36), val, fs, vcol, HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x - 10.0)
	# Hedef: ilk üçe girmek için gereken fark
	var goal := ""
	if top.get(lb_tab, []).is_empty():
		goal = Loc.t("lb_empty")
	elif rows.size() > 3 and my_rank >= 3:
		goal = Loc.t("lb_goal") % (int(rows[2][1]) - my_val + 1)
	elif my_rank < 3 and my_val > 0:
		goal = Loc.t("lb_podium")
	if goal != "":
		_text(Vector2(r.position.x + 10, r.end.y - 12), goal, _fit_size(goal, 13, r.size.x - 20.0), Color(1, 1, 1, 0.6),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20.0)


## Küçük taç ikonu (skor tablosunda birinci).
func _draw_crown_icon(c: Vector2, sc: float) -> void:
	var pts := PackedVector2Array([Vector2(-13, 8), Vector2(-15, -7), Vector2(-7, 0), Vector2(0, -11),
		Vector2(7, 0), Vector2(15, -7), Vector2(13, 8)])
	for i in pts.size():
		pts[i] = c + pts[i] * sc
	cv.draw_colored_polygon(pts, Color(1, 0.8, 0.2))
	pts.append(pts[0])
	cv.draw_polyline(pts, Color(0.45, 0.28, 0.02), 2.0)
	GameData.disc(cv, c + Vector2(0, 3) * sc, 2.6 * sc, Color(1, 0.2, 0.3))


## Madalya: kurdele + sıra numaralı disk.
func _draw_medal(c: Vector2, r: float, col: Color, rank: int) -> void:
	var rib := Color(0.8, 0.15, 0.2) if rank == 2 else Color(0.2, 0.4, 0.85)
	cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.9, -r * 1.6), c + Vector2(-r * 0.2, -r * 1.6), c + Vector2(r * 0.2, -r * 0.4), c + Vector2(-r * 0.4, -r * 0.4)]), rib)
	cv.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.9, -r * 1.6), c + Vector2(r * 0.2, -r * 1.6), c + Vector2(-r * 0.2, -r * 0.4), c + Vector2(r * 0.4, -r * 0.4)]), rib.darkened(0.2))
	GameData.disc(cv, c + Vector2(0, r * 0.25), r, col.darkened(0.35))
	GameData.disc(cv, c + Vector2(0, r * 0.15), r * 0.85, col)
	var fs := int(r * 1.15)
	_text(Vector2(c.x - r, c.y + r * 0.15 + fs * 0.36), str(rank), fs, Color(0.15, 0.12, 0.1), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)

## Çok oyunculu sunucusunun durumu: [yazı, renk].
func _server_status() -> Array:
	match String(main.lobby_state):
		"ready":
			return [Loc.t("srv_online") % int(main.online_count), Color(0.55, 1, 0.6)]
		"offline":
			return [Loc.t("srv_offline"), Color(1, 0.55, 0.45)]
		"outdated":
			return [Loc.t("srv_outdated"), Color(1, 0.75, 0.35)]
		"connecting":
			return [Loc.t("srv_waking"), Color(1, 0.85, 0.4)]
	return [Loc.t("mode_multi_sub"), Color(1, 1, 1, 0.8)]


## Alt orta: iki büyük mod butonu (başlık + açıklama).
func _draw_mode_buttons(s: Vector2, t: float) -> void:
	var w := minf(330.0, (s.x - 80.0) / 2.0)
	var h := 92.0
	var y := s.y - h - 22.0
	var glow := 0.5 + 0.5 * sin(t * 4.0)
	var modes := [
		["play", Loc.t("mode_single"), Loc.t("mode_single_sub"), Color(0.22, 0.66, 0.33), Rect2(s.x / 2.0 - w - 10.0, y, w, h)],
		["mp", Loc.t("mode_multi"), Loc.t("mode_multi_sub"), Color(0.28, 0.42, 0.88), Rect2(s.x / 2.0 + 10.0, y, w, h)],
	]
	for m in modes:
		var r: Rect2 = m[4]
		var col: Color = m[3]
		_panel(r.grow(3.0 + glow * 4.0), Color(col, 0.12 + glow * 0.12), Color(0, 0, 0, 0), 20)
		_button(r, m[0], "", col, true, 16)
		_text(Vector2(r.position.x, r.position.y + 46), m[1], _fit_size(m[1], 30, r.size.x - 24.0), Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var sub: String = m[2]
		var sub_col := Color(1, 1, 1, 0.8)
		var sub_fs := _fit_size(sub, 14, r.size.x - 40.0)
		if m[0] == "mp":
			# Çok oyunculu: sunucunun anlık durumu (açık / uyanıyor / kapalı / güncelleniyor), başında renkli nokta
			var st := _server_status()
			sub = st[0]
			sub_col = st[1]
			sub_fs = _fit_size(sub, 14, r.size.x - 40.0)
			var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs).x
			GameData.disc(cv, Vector2(r.get_center().x - sw / 2.0 - 12.0, r.position.y + 67), 5.0, sub_col)
		_text(Vector2(r.position.x, r.position.y + 72), sub, sub_fs, sub_col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


# --- Koleksiyon penceresi (karakterler / bıçaklar / seviyeler) -------------------

func _shop_items() -> Array:
	return GameData.available_skins() if tab == "characters" else GameData.KNIVES


func _shop_item(id: String) -> Dictionary:
	for it in GameData.SKINS + GameData.KNIVES:
		if it["id"] == id:
			return it
	return {}


func _equipped_id() -> String:
	return String(main.playable_skin()["id"]) if tab == "characters" else String(GameData.KNIVES[main.selected_knife()]["id"])


func open_shop(which: String) -> void:
	popup = "shop"
	tab = which
	page = -1
	shop_preview = _equipped_id() if which != "levels" else ""


func _draw_shop(s: Vector2, t: float) -> void:
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
	var w := minf(s.x - 60.0, 1180.0)
	var r := Rect2((s.x - w) / 2.0, 26, w, s.y - 52)
	_panel(r, Color(0.05, 0.08, 0.11, 0.97), Color(1, 1, 1, 0.12), 22, 2, 16)
	# Sekmeler ve kapatma
	var tabs := ["characters", "knives", "levels"]
	var tab_w := 200.0
	for k in tabs.size():
		var id: String = tabs[k]
		var active := tab == id
		var tr := Rect2(r.position.x + 22.0 + k * (tab_w + 8.0), r.position.y + 14.0, tab_w, 58.0)
		_panel(tr, Color(GOLD, 0.2) if active else Color(1, 1, 1, 0.05), GOLD if active else Color(1, 1, 1, 0.1), 12, 2 if active else 1)
		_text_fit(Vector2(tr.position.x, tr.position.y + 37), Loc.t("tab_" + id), 21, GOLD if active else Color(1, 1, 1, 0.6), tr.size.x)
		buttons.append({"rect": tr, "id": "shop_" + id, "enabled": true})
	var coins := int(main.save["coins"])
	var cw := _coin_width(coins, 20) + 30.0
	_panel(Rect2(r.end.x - 90 - cw, r.position.y + 16, cw, 44), PANEL_BG, GOLD, 22, 2)
	_coin_amount(Vector2(r.end.x - 90 - cw + 15, r.position.y + 46), coins, 20)
	_button(Rect2(r.end.x - 80, r.position.y + 12, 64, 60), "shop_close", "X", Color(0.55, 0.25, 0.25), true, 26)

	var body := Rect2(r.position.x + 22, r.position.y + 86, r.size.x - 44, r.size.y - 104)
	if tab == "levels":
		var lw := minf(440.0, body.size.x * 0.42)
		_draw_quests_and_items(Rect2(body.position, Vector2(lw, body.size.y)), t)
		_draw_level_table(Rect2(body.position.x + lw + 16.0, body.position.y, body.size.x - lw - 16.0, body.size.y))
	else:
		var pane := Rect2(body.position, Vector2(300, body.size.y))
		_draw_shop_preview(pane, t)
		var grid := Rect2(body.position.x + 320, body.position.y, body.size.x - 320, body.size.y)
		_draw_shop_grid(grid, t)
	# Pencere dışına dokununca kapanır (en sona eklenir: pencere butonları önceliklidir)
	buttons.append({"rect": Rect2(Vector2.ZERO, s), "id": "shop_outside", "enabled": true})


## Sol bölme: seçili kartın büyük önizlemesi, açıklaması ve SEÇ / SATIN AL butonu.
func _draw_shop_preview(r: Rect2, t: float) -> void:
	_panel(r, Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.08), 16, 1)
	var item := _shop_item(shop_preview)
	if item.is_empty():
		return
	var id: String = item["id"]
	var col: Color = item["color"]
	var c := r.position + Vector2(r.size.x / 2.0, r.size.y * 0.33)
	for i in 4:
		GameData.disc(cv, c, 110.0 - i * 20.0, Color(col, 0.06))
	if tab == "characters":
		cv.draw_set_transform(c + Vector2(0, 74), 0.0, Vector2(1.0, 0.3))
		GameData.disc(cv, Vector2.ZERO, 80.0, Color(col, 0.5))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_skin(id, c, 170.0, Color.WHITE, 1 + int(t * 10.0) % 8)
	else:
		var k := GameData.knife_index(id)
		var glow: Color = item["glow"]
		if glow.a > 0.0:
			cv.draw_texture_rect(GameData.glow_tex(), Rect2(c - Vector2(90, 90), Vector2(180, 180)), false, glow)
		KnifeArt.draw(cv, c, PI / 4.0 + sin(t * 2.0) * 0.2, 3.2, k, false)
	var ny := r.position.y + r.size.y * 0.33 + 128
	_text_fit(Vector2(r.position.x, ny), Loc.t(id + ".name"), 26, Color.WHITE, r.size.x)
	if tab == "characters":
		_text_fit(Vector2(r.position.x, ny + 26), Loc.t(id + ".desc"), 14, col.lightened(0.4), r.size.x)
		var fx := String(item.get("fx", ""))
		if fx != "":
			var ac: Color = item.get("aura", GOLD)
			_text_fit(Vector2(r.position.x, ny + 48), "✦ " + Loc.t("fx_label") % Loc.t("fx_" + fx), 13, ac.lightened(0.3), r.size.x)
	elif item.get("female", false):
		_text_fit(Vector2(r.position.x, ny + 26), Loc.t("female_only"), 14, Color(1, 0.55, 0.8), r.size.x)
	# Durum ve işlem butonu
	var owned: bool = main.skin_unlocked(item)
	var equipped := id == _equipped_id()
	var br := Rect2(r.position.x + 16, r.end.y - 84, r.size.x - 32, 66)
	var wrong_skin: bool = tab == "knives" and not main.knife_allowed(GameData.knife_index(id), main.playable_skin()["id"])
	if equipped:
		_button(br, "noop", Loc.t("equipped"), Color(0.3, 0.34, 0.4), false, 22)
	elif owned and wrong_skin:
		_button(br, "noop", Loc.t("female_need"), Color(0.45, 0.3, 0.42), false, 18)
	elif owned:
		_button(br, "shop_use", Loc.t("equip"), Color(0.22, 0.66, 0.33), true, 26)
	elif not main.level_ok(item):
		_button(br, "noop", Loc.t("level_req") % int(item["level"]), Color(0.3, 0.3, 0.36), false, 18)
	else:
		var price := int(item["price"])
		var afford := int(main.save["coins"]) >= price
		_button(br, "shop_use" if afford else "noop", Loc.t("buy") + "        ", Color(0.85, 0.6, 0.12) if afford else Color(0.3, 0.3, 0.36),
			afford, 24)
		var pw := _coin_width(price, 24)
		_coin_amount(Vector2(br.end.x - pw - 22, br.position.y + br.size.y / 2.0 + 9), price, 24, Color.WHITE if afford else Color(1, 0.6, 0.55))


func _grid_rect(content: Rect2, k: int) -> Rect2:
	var gap := 12.0
	var cw := (content.size.x - gap * (CARD_COLS - 1)) / CARD_COLS
	var ch := minf(190.0, (content.size.y - 70.0 - gap) / 2.0)
	return Rect2(content.position.x + (k % CARD_COLS) * (cw + gap), content.position.y + (k / CARD_COLS) * (ch + gap), cw, ch)


func _draw_shop_grid(content: Rect2, t: float) -> void:
	var list := _shop_items()
	var pages := ceili(list.size() / float(CARDS_PER_PAGE))
	if page < 0:
		page = 0
		for i in list.size():
			if list[i]["id"] == shop_preview:
				page = i / CARDS_PER_PAGE
	page = clampi(page, 0, pages - 1)
	var equipped := _equipped_id()
	for k in CARDS_PER_PAGE:
		var i := page * CARDS_PER_PAGE + k
		if i >= list.size():
			break
		_shop_card(_grid_rect(content, k), list[i], list[i]["id"] == shop_preview, list[i]["id"] == equipped, t)
	if pages > 1:
		var row_y := _grid_rect(content, CARD_COLS).end.y + 8.0
		var cx := content.position.x + content.size.x / 2.0
		_button(Rect2(cx - 190, row_y, 110, 54), "page_prev", "<", Color(0.25, 0.3, 0.42), page > 0, 30)
		_button(Rect2(cx + 80, row_y, 110, 54), "page_next", ">", Color(0.25, 0.3, 0.42), page < pages - 1, 30)
		for i in pages:
			GameData.disc(cv, Vector2(cx + (i - (pages - 1) / 2.0) * 22.0, row_y + 27.0), 7.0, GOLD if i == page else Color(1, 1, 1, 0.25))


func _shop_card(r: Rect2, item: Dictionary, selected: bool, equipped: bool, t: float) -> void:
	var id: String = item["id"]
	var col: Color = item["color"]
	var owned: bool = main.skin_unlocked(item)
	if selected:
		_panel(r.grow(3.0), Color(GOLD, 0.3), Color(0, 0, 0, 0), 17)
	_panel(r, col.darkened(0.65) if selected else Color(0.11, 0.15, 0.2), GOLD if selected else Color(1, 1, 1, 0.07), 14,
		3 if selected else 1)
	var c := r.position + Vector2(r.size.x / 2.0, r.size.y * 0.4)
	if tab == "characters":
		cv.draw_set_transform(c + Vector2(0, r.size.y * 0.22), 0.0, Vector2(1.0, 0.3))
		GameData.disc(cv, Vector2.ZERO, 32.0, Color(0, 0, 0, 0.3) if not selected else Color(col, 0.45))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_skin(id, c, minf(r.size.x * 0.72, r.size.y * 0.58), Color.WHITE if owned or selected else Color(0.6, 0.6, 0.65),
			(1 + int(t * 10.0) % 8) if selected else 0)
	else:
		var glow: Color = item["glow"]
		if glow.a > 0.0:
			cv.draw_texture_rect(GameData.glow_tex(), Rect2(c - Vector2(44, 44), Vector2(88, 88)), false, Color(glow, glow.a * (1.0 if owned else 0.5)))
		KnifeArt.draw(cv, c, PI / 4.0, minf(2.0, r.size.y / 90.0), GameData.knife_index(id), false)
	if equipped:
		_panel(Rect2(r.position.x + 8, r.position.y + 8, 64, 22), Color(0.22, 0.66, 0.33), Color(0, 0, 0, 0), 11)
		_text(Vector2(r.position.x + 8, r.position.y + 25), Loc.t("in_use"), 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 64.0)
	if item.get("female", false):
		var fy := r.position.y + (34.0 if equipped else 8.0)
		_panel(Rect2(r.position.x + 8, fy, 64, 22), Color(0.85, 0.3, 0.6), Color(0, 0, 0, 0), 11)
		_text(Vector2(r.position.x + 8, fy + 16), Loc.t("female_tag"), 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 64.0)
	_card_footer(r, item, owned, selected)
	buttons.append({"rect": r, "id": "pick_" + id, "enabled": true})


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


## Seviye sekmesinin sol sütunu: günlük görevler (üstte) ve seviyeyle açılan eşyalar (altta).
func _draw_quests_and_items(r: Rect2, t: float) -> void:
	_text(Vector2(r.position.x + 4, r.position.y + 22), Loc.t("daily_quests"), 20, GOLD)
	_text(Vector2(r.position.x, r.position.y + 20), Loc.t("quests_renew"), 12, Color(1, 1, 1, 0.5),
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4.0)
	var ids: Array = main.save["quest_ids"]
	var y := r.position.y + 34.0
	var qh := 74.0
	for i in ids.size():
		var q := GameData.quest_info(ids[i])
		var goal := int(q["goal"])
		var prog := mini(goal, int(main.save["quest_prog"][i]))
		var claimed: bool = main.save["quest_claimed"][i]
		var done := prog >= goal
		var qr := Rect2(r.position.x, y, r.size.x, qh - 8.0)
		_panel(qr, Color(0.22, 0.6, 0.33, 0.18) if done and not claimed else Color(1, 1, 1, 0.04),
			Color(0.5, 1, 0.6, 0.7) if done and not claimed else Color(1, 1, 1, 0.08), 12, 2 if done and not claimed else 1)
		var title: String = Loc.t(q["id"])
		if title.contains("%d"):
			title = title % goal
		var bw := 92.0
		var tw := qr.size.x - bw - 30.0
		_text(Vector2(qr.position.x + 14, qr.position.y + 25), title, _fit_size(title, 17, tw),
			Color(1, 1, 1, 0.5) if claimed else Color.WHITE)
		# Ödül: altın + XP
		var cw := _coin_amount(Vector2(qr.position.x + 14, qr.position.y + 50), int(q["coins"]), 15)
		_text(Vector2(qr.position.x + 26 + cw, qr.position.y + 50), "+%d XP" % int(q["xp"]), 14, Color(0.6, 0.85, 1))
		var bar := Rect2(qr.position.x + tw - 80.0, qr.position.y + 38, 90.0, 14)
		_progress_bar(bar, float(prog) / goal, Color(0.5, 1, 0.6) if done else Color(0.45, 0.75, 1))
		_text(Vector2(bar.position.x, bar.end.y - 2), "%d/%d" % [prog, goal], 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x)
		var br := Rect2(qr.end.x - bw - 10.0, qr.position.y + 11, bw, qr.size.y - 22.0)
		if claimed:
			_button(br, "noop", Loc.t("claimed"), Color(0.3, 0.34, 0.4), false, 15)
		else:
			_button(br, "quest_%d" % i, Loc.t("claim"), Color(0.22, 0.66, 0.33) if done else Color(0.3, 0.34, 0.4), done, 18)
		y += qh
	# Seviye eşyaları: dokununca takılır (seviyesi yetmeyenler kilitli)
	y += 10.0
	_text(Vector2(r.position.x + 4, y + 18), Loc.t("level_items"), 20, GOLD)
	y += 30.0
	var n := GameData.ACCESSORIES.size()
	var gap := 8.0
	var cw2 := (r.size.x - gap * (n - 1)) / n
	var ch := clampf(r.end.y - y, 60.0, cw2 * 1.9)
	var cur: int = main.selected_acc()
	var lvl := int(main.save["level"])
	for i in n:
		var it: Dictionary = GameData.ACCESSORIES[i]
		var cr := Rect2(r.position.x + i * (cw2 + gap), y, cw2, ch)
		var unlocked := lvl >= int(it["level"])
		var sel := i == cur
		_panel(cr, Color(GOLD, 0.18) if sel else Color(0.11, 0.15, 0.2), GOLD if sel else Color(1, 1, 1, 0.07), 12, 3 if sel else 1)
		var c := cr.position + Vector2(cr.size.x / 2.0, cr.size.y * 0.5)
		var sc := minf(cw2 / 100.0, ch / 150.0)
		if i == 0:
			cv.draw_arc(c + Vector2(0, -4), 16.0, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 3.0)
			cv.draw_line(c + Vector2(-11, 7), c + Vector2(11, -15), Color(1, 1, 1, 0.35), 3.0)
		else:
			var sid := String(main.playable_skin()["id"])
			var sc_center := c + Vector2(0, 8.0 * sc)
			GameData.draw_accessory(cv, i, sid, sc_center, 84.0 * sc, 1.0, t, true)
			_draw_skin(sid, sc_center, 84.0 * sc, Color.WHITE if unlocked else Color(0.35, 0.35, 0.4))
			GameData.draw_accessory(cv, i, sid, sc_center, 84.0 * sc, 1.0, t, false)
		var label: String = Loc.t(it["id"] + ".name")
		if unlocked:
			_text_fit(Vector2(cr.position.x, cr.end.y - 8), label, 13, Color.WHITE if sel else Color(1, 1, 1, 0.8), cr.size.x)
		else:
			cv.draw_rect(cr.grow(-2.0), Color(0, 0, 0, 0.35))
			_draw_lock(c + Vector2(0, -8), 0.6)
			_text_fit(Vector2(cr.position.x, cr.end.y - 8), Loc.t("level_short") % int(it["level"]), 13, Color(0.7, 0.85, 1), cr.size.x)
		buttons.append({"rect": cr, "id": it["id"], "enabled": true})


## Seviye tablosu: mevcut seviyenin çevresindeki seviyeler, ödülleri ve açtıkları.
func _draw_level_table(content: Rect2) -> void:
	var lvl := int(main.save["level"])
	var rows := 8
	var row_h := minf(60.0, (content.size.y - 8.0) / rows)
	var first := clampi(lvl - 1, 1, maxi(1, GameData.MAX_LEVEL - rows + 1))
	for i in rows:
		var L := first + i
		if L > GameData.MAX_LEVEL:
			break
		var r := Rect2(content.position.x, content.position.y + i * row_h, content.size.x, row_h - 6.0)
		var is_cur := L == lvl
		var done := L < lvl
		_panel(r, Color(GOLD, 0.16) if is_cur else Color(1, 1, 1, 0.04), GOLD if is_cur else Color(1, 1, 1, 0.06), 12, 2 if is_cur else 1)
		_level_badge(r.position + Vector2(28, r.size.y / 2.0), 17.0, L)
		var unlocks := PackedStringArray()
		for item in GameData.SKINS + GameData.KNIVES:
			if int(item["level"]) == L and int(item["price"]) > 0:
				unlocks.append(Loc.t(item["id"] + ".name"))
		for item in GameData.ACCESSORIES:
			if int(item["level"]) == L and L > 1:
				unlocks.append(Loc.t(item["id"] + ".name"))
		var mid := r.position.y + r.size.y / 2.0
		var reward_w := _coin_width(GameData.level_reward(L), 18) + 20.0
		var status_w := 110.0
		var text_w := r.size.x - 60.0 - reward_w - status_w - 40.0
		if not unlocks.is_empty():
			var txt := Loc.t("level_unlocks") % ", ".join(unlocks)
			_text(Vector2(r.position.x + 58, mid + 6), txt, _fit_size(txt, 16, text_w), Color(1, 1, 1, 0.85))
		if is_cur:
			var need := GameData.xp_needed(lvl)
			var xb := Rect2(r.end.x - status_w - reward_w - 60.0, mid - 9, reward_w + 50.0, 18)
			_progress_bar(xb, float(main.save["xp"]) / need, Color(0.45, 0.75, 1))
			_text(Vector2(xb.position.x, xb.end.y - 3), "%d/%d XP" % [int(main.save["xp"]), need], 12, Color.WHITE,
				HORIZONTAL_ALIGNMENT_CENTER, xb.size.x)
		else:
			_coin_amount(Vector2(r.end.x - status_w - reward_w, mid + 7), GameData.level_reward(L), 18,
				GOLD if not done else Color(1, 1, 1, 0.4))
		var status := Loc.t("current") if is_cur else (Loc.t("done") if done else "")
		if status != "":
			_text(Vector2(r.end.x - status_w, mid + 6), status, 15, GOLD if is_cur else Color(0.5, 1, 0.6),
				HORIZONTAL_ALIGNMENT_CENTER, status_w - 8.0)
		elif L > lvl:
			_draw_lock(Vector2(r.end.x - status_w / 2.0, mid), 0.6)


# --- Ayarlar penceresi ------------------------------------------------------------

func _draw_settings(s: Vector2) -> void:
	cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
	var r := Rect2(s.x / 2.0 - 260, s.y / 2.0 - 230, 520, 460)
	_panel(r, Color(0.05, 0.08, 0.11, 0.97), Color(1, 1, 1, 0.12), 22, 2, 16)
	_text(Vector2(r.position.x, r.position.y + 50), Loc.t("settings"), 28, GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_button(Rect2(r.end.x - 66, r.position.y + 14, 48, 46), "settings_close", "X", Color(0.55, 0.25, 0.25), true, 20)
	var on_col := Color(0.22, 0.6, 0.33)
	var off_col := Color(0.3, 0.34, 0.42)
	var rows := [
		["sound", Loc.t("sound_on") if main.save["sound"] else Loc.t("sound_off"), on_col if main.save["sound"] else off_col],
		["aim", Loc.t("auto_aim_on") if main.save["auto_aim"] else Loc.t("auto_aim_off"), on_col if main.save["auto_aim"] else off_col],
		["lang", Loc.t("language"), Color(0.3, 0.42, 0.7)],
		["fullscreen", Loc.t("fullscreen"), Color(0.3, 0.42, 0.7)],
		["admin_open", Loc.t("admin"), Color(0.4, 0.3, 0.55)],
	]
	var y := r.position.y + 78
	for row in rows:
		_button(Rect2(r.position.x + 40, y, r.size.x - 80, 60), row[0], row[1], row[2], true, 20)
		y += 72
	buttons.append({"rect": Rect2(Vector2.ZERO, s), "id": "settings_close", "enabled": true})

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
	var mm := Rect2(16, 14, 168, 168)
	_draw_minimap(mm)
	buttons.append({"rect": mm, "id": "bigmap", "enabled": true})
	main.perf_mark("hud_minimap", _t)
	_t = Time.get_ticks_usec()

	# Aktif güçlendirme süreleri: ekranın alt ortasında yatay sıra (simge, dolan halka, kalan saniye)
	var active := []
	for entry in [["infinity", p.inf_t], ["speed", p.speed_t], ["shield", p.shield_t], ["magnet", p.magnet_t], ["rage", p.rage_t], ["slow", p.slow_t]]:
		if float(entry[1]) > 0.0:
			active.append(entry)
	var slot := 78.0
	var x0 := s.x / 2.0 - (active.size() - 1) * slot / 2.0
	for ai in active.size():
		var entry: Array = active[ai]
		var left: float = entry[1]
		var c := Vector2(x0 + ai * slot, s.y - 150.0)
		_panel(Rect2(c.x - 34, c.y - 32, 68, 82), Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.12), 14, 1)
		GameData.disc(cv, c, 24.0, Color(0, 0, 0, 0.5))
		var info: Dictionary = GameData.POWERUPS.get(entry[0], {})
		var icon: Texture2D = GameData.tex(info["icon"]) if not info.is_empty() else null
		var ring_col: Color = info["color"] if not info.is_empty() else (Color(1, 0.3, 0.2) if entry[0] == "rage" else Color(0.5, 0.75, 1))
		var dur: float = info["duration"] if not info.is_empty() else (7.0 if entry[0] == "rage" else 4.0)
		if icon != null:
			cv.draw_texture_rect(icon, Rect2(c - Vector2(17, 17), Vector2(34, 34)), false)
		elif entry[0] == "infinity":
			GameData.draw_infinity(cv, c, 0.8, info["color"])
		else:
			GameData.disc(cv, c, 12.0, ring_col)
		cv.draw_arc(c, 24.0, -PI / 2, -PI / 2 + TAU * clampf(left / dur, 0.0, 1.0), 32, ring_col, 4.0)
		_text(Vector2(c.x - 30, c.y + 44), "%d sn" % ceili(left), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 60.0)

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
	# Sağ üst: liderler (sıra, seviye, isim, leş, bıçak). Dokununca tam skor tablosu açılır.
	var board: Array[Fighter] = main.leaderboard(5)
	var pw := 270.0
	var lx := s.x - 16.0 - pw
	var ly := 14.0
	var lb := Rect2(lx, ly, pw, 40 + board.size() * 27)
	_panel(lb, PANEL_BG, Color(1, 1, 1, 0.08), 14, 1)
	_text(Vector2(lx + 14, ly + 25), Loc.t("leaders") + "  >", 17, GOLD)
	_skull(Vector2(lx + pw - 84, ly + 18), 6.0, Color(1, 0.6, 0.55))
	KnifeArt.draw(cv, Vector2(lx + pw - 30, ly + 17), PI / 4.0, 0.55, 0, false)
	for i in board.size():
		var f := board[i]
		var col := f.color.lightened(0.35)
		var ry := ly + 52.0 + i * 27.0
		if f.is_player:
			_panel(Rect2(lx + 4, ry - 19, pw - 8, 25), Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 8)
		_text(Vector2(lx + 10, ry), "%d" % (i + 1), 15, Color(1, 1, 1, 0.6))
		_level_badge(Vector2(lx + 40, ry - 6), 11.0, f.level)
		_text(Vector2(lx + 58, ry), f.display_name, _fit_size(f.display_name, 16, 130.0), col)
		_text(Vector2(lx + pw - 104, ry), str(f.kills), 16, Color(1, 0.6, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
		_text(Vector2(lx + pw - 50, ry), str(f.knives), 16, col, HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	buttons.append({"rect": Rect2(lx, ly, pw, 36), "id": "scoreboard", "enabled": true})
	if main.state == "playing" and main.net_mode == "":
		_button(Rect2(mm.end.x + 12, 14, 58, 52), "pause", "II", Color(0.25, 0.3, 0.42), true, 22)
	if scoreboard_open:
		_draw_scoreboard(s)
	if bigmap_open:
		cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.45))
		var side := minf(s.y - 90.0, 560.0)
		var br := Rect2(s.x / 2.0 - side / 2.0, (s.y - side) / 2.0, side, side)
		_draw_minimap(br, true)
		buttons.append({"rect": Rect2(Vector2.ZERO, s), "id": "bigmap", "enabled": true})


## Tam skor tablosu: arenadaki herkes; seviye, leş ve bıçak sayısıyla.
func _draw_scoreboard(s: Vector2) -> void:
	var list: Array[Fighter] = main.leaderboard(30)
	var w := minf(640.0, s.x - 80.0)
	var row_h := 30.0
	var h := minf(s.y - 120.0, 96.0 + list.size() * row_h)
	var r := Rect2((s.x - w) / 2.0, 70, w, h)
	_panel(r, Color(0.04, 0.06, 0.09, 0.94), Color(1, 1, 1, 0.12), 18, 2, 12)
	_text(Vector2(r.position.x, r.position.y + 38), Loc.t("scoreboard"), 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var hy := r.position.y + 64
	_text(Vector2(r.position.x + 20, hy), "#", 13, Color(1, 1, 1, 0.5))
	_text(Vector2(r.position.x + 92, hy), Loc.t("sb_player"), 13, Color(1, 1, 1, 0.5))
	_text(Vector2(r.end.x - 180, hy), Loc.t("sb_kills"), 13, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 70.0)
	_text(Vector2(r.end.x - 100, hy), Loc.t("sb_knives"), 13, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	for i in list.size():
		var y := hy + 12 + i * row_h
		if y + row_h > r.end.y - 6:
			break
		var f := list[i]
		var human := f.is_player or f.peer_id != 0
		if f.is_player:
			_panel(Rect2(r.position.x + 10, y, r.size.x - 20, row_h - 2), Color(GOLD, 0.15), Color(0, 0, 0, 0), 8)
		var ty := y + 21
		_text(Vector2(r.position.x + 20, ty), str(i + 1), 15, Color(1, 1, 1, 0.7))
		_level_badge(Vector2(r.position.x + 66, ty - 6), 11.0, f.level)
		GameData.disc(cv, Vector2(r.position.x + 92, ty - 6), 5.0, f.color)
		var nm := f.display_name + ("  •" if human and main.net_mode == "client" else "")
		_text(Vector2(r.position.x + 104, ty), nm, _fit_size(nm, 16, r.size.x - 320.0), Color(1, 0.92, 0.3) if f.is_player else Color.WHITE)
		_text(Vector2(r.end.x - 180, ty), str(f.kills), 16, Color(1, 0.6, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 70.0)
		_text(Vector2(r.end.x - 100, ty), str(f.knives), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	_text(Vector2(r.position.x, r.end.y + 22), Loc.t("sb_hint"), 13, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	buttons.append({"rect": r, "id": "scoreboard", "enabled": true})


## Sol üst oyuncu kartı: portre + seviye, isim, can barı, bıçak/leş/altın sayaçları.
## Sol üst: ince sayaç şeridi (bıçak, bomba, leş, altın). Can karakterin üstünde gösterildiği için
## büyük oyuncu kartı yok; arena daha geniş görünür.
func _draw_player_card(p: Fighter) -> void:
	var w := 230.0 + (54.0 if p.bombs > 0 else 0.0)
	var s := _screen()
	var bx := s.x / 2.0 - w / 2.0
	var by := s.y - 58.0
	_panel(Rect2(bx, by, w, 42), PANEL_BG, Color(1, 1, 1, 0.14), 21, 1)
	var x := bx + 14.0
	var row := by + 28.0
	KnifeArt.draw(cv, Vector2(x + 8, row - 7), PI / 4.0, 0.7, p.knife_kind, false)
	_text(Vector2(x + 22, row), str(p.knives), 18, Color.WHITE)
	x += 66.0
	if p.bombs > 0:
		main._draw_bomb(cv, Vector2(x + 8, row - 5), 0.45, Time.get_ticks_msec() / 1000.0)
		_text(Vector2(x + 22, row), "x%d" % p.bombs, 18, Color(1, 0.6, 0.3))
		x += 54.0
	_skull(Vector2(x + 8, row - 8), 7.0, Color(1, 0.6, 0.55))
	_text(Vector2(x + 20, row), str(p.kills), 18, Color(1, 0.6, 0.55))
	x += 56.0
	_coin_amount(Vector2(x, row), main.match_coins, 18)


## Mini harita: köşeleri yuvarlak kare içinde arena, daralan alan, kutular, güçlendirmeler,
## rakipler (bıçak sayısına göre büyüklük), lider (taç) ve oyuncu (yön oku).
func _draw_minimap(rect: Rect2, big := false) -> void:
	_panel(rect, Color(0.03, 0.06, 0.08, 0.88 if big else 0.82), Color(1, 1, 1, 0.18), 18 if big else 14, 1, 6)
	var c := rect.get_center()
	var r := rect.size.x * 0.5 - (16.0 if big else 8.0)
	var k: float = r / main.ARENA_RADIUS
	var u := r / 80.0 # işaret ölçeği (büyük haritada büyür)
	GameData.disc(cv, c, r, Color(0.18, 0.38, 0.24, 0.95))
	for i in range(1, 4):
		cv.draw_arc(c, r * i / 4.0, 0.0, TAU, 40, Color(1, 1, 1, 0.07), 1.0)
	# Daralan alan: dışarısı kırmızı, sınır çizgisi
	var zr: float = main.zone_radius * k
	if zr < r - 0.5:
		cv.draw_arc(c, (zr + r) / 2.0, 0.0, TAU, 48, Color(0.85, 0.1, 0.15, 0.45), r - zr)
		cv.draw_arc(c, zr, 0.0, TAU, 48, Color(1, 0.5, 0.5), 2.0)
	cv.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	# Ekranda görünen alan (kamera çerçevesi)
	var vr: Rect2 = main.view_rect
	var vtl := c + vr.position * k
	cv.draw_rect(Rect2(vtl, vr.size * k), Color(1, 1, 1, 0.35), false, 1.0)
	# Kutular (kahverengi kare) ve güçlendirmeler (kendi renginde)
	for cr in main.crates:
		var cp: Vector2 = c + (cr["pos"] as Vector2) * k
		cv.draw_rect(Rect2(cp - Vector2(1.6, 1.6) * u, Vector2(3.2, 3.2) * u), Color(0.9, 0.62, 0.3))
	for pu in main.powerups:
		var info: Dictionary = GameData.POWERUPS[pu["type"]]
		var pp: Vector2 = c + (pu["pos"] as Vector2) * k
		GameData.disc(cv, pp, 2.6 * u, Color(0, 0, 0, 0.5))
		GameData.disc(cv, pp, 2.0 * u, info["color"])
	# Rakipler: bıçak sayısına göre büyüklük; renk = sana göre tehlike (kırmızı güçlü, sarı denk, yeşil zayıf)
	var p: Fighter = main.player
	var my_k: int = p.knives if p != null else 0
	var leader: Fighter = main._leader()
	for f in main.fighters:
		if not f.alive or f == p or f.concealed:
			continue
		var fp: Vector2 = c + f.position * k
		if f.boss:
			GameData.disc(cv, fp, 6.5 * u, Color(0, 0, 0, 0.7))
			GameData.disc(cv, fp, 5.0 * u, Color(0.75, 0.3, 1))
			cv.draw_arc(fp, 7.5 * u, 0.0, TAU, 20, Color(0.85, 0.5, 1, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)), 1.5 * u)
			continue
		var fr := (2.4 + minf(f.knives, 40) * 0.07) * u
		var col := Color(1, 0.85, 0.3)
		if f.knives > my_k + 4:
			col = Color(1, 0.3, 0.25)
		elif f.knives < my_k - 3:
			col = Color(0.45, 1, 0.5)
		GameData.disc(cv, fp, fr + 1.2 * u, Color(0, 0, 0, 0.7))
		GameData.disc(cv, fp, fr, col)
		if f == leader:
			var cw := 4.0 * u
			cv.draw_colored_polygon(PackedVector2Array([fp + Vector2(-cw, -fr - 1.0), fp + Vector2(-cw, -fr - cw * 1.3),
				fp + Vector2(-cw * 0.4, -fr - cw * 0.8), fp + Vector2(0, -fr - cw * 1.5), fp + Vector2(cw * 0.4, -fr - cw * 0.8),
				fp + Vector2(cw, -fr - cw * 1.3), fp + Vector2(cw, -fr - 1.0)]), GOLD)
	# Oyuncu: parlayan altın ok
	if p != null and p.alive:
		var pp := c + p.position * k
		var dir := p.facing
		var side := dir.orthogonal()
		var a := 6.0 * u
		GameData.disc(cv, pp, a * 1.4, Color(GOLD, 0.3 + 0.15 * sin(Time.get_ticks_msec() / 200.0)))
		cv.draw_colored_polygon(PackedVector2Array([pp + dir * a * 1.2, pp - dir * a * 0.7 + side * a * 0.8, pp - dir * a * 0.3,
			pp - dir * a * 0.7 - side * a * 0.8]), GOLD)
		cv.draw_polyline(PackedVector2Array([pp + dir * a * 1.2, pp - dir * a * 0.7 + side * a * 0.8, pp - dir * a * 0.3,
			pp - dir * a * 0.7 - side * a * 0.8, pp + dir * a * 1.2]), Color(0, 0, 0, 0.7), 1.0)
	if big:
		# Büyük harita açıklaması
		var ly := rect.end.y - 14.0
		var items := [[Color(1, 0.3, 0.25), Loc.t("map_strong")], [Color(1, 0.85, 0.3), Loc.t("map_equal")],
			[Color(0.45, 1, 0.5), Loc.t("map_weak")], [Color(0.75, 0.3, 1), Loc.t("map_boss")]]
		var x := rect.position.x + 22.0
		for it in items:
			GameData.disc(cv, Vector2(x, ly - 5), 6.0, it[0])
			_text(Vector2(x + 10, ly), it[1], 13, Color(1, 1, 1, 0.8))
			x += 26.0 + font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	else:
		# Dokunulabilir olduğunu belirten küçük büyüteç işareti
		var mc := rect.end - Vector2(14, 14)
		cv.draw_arc(mc + Vector2(-2, -2), 5.0, 0.0, TAU, 12, Color(1, 1, 1, 0.6), 2.0)
		cv.draw_line(mc + Vector2(2, 2), mc + Vector2(6, 6), Color(1, 1, 1, 0.6), 2.0)

## Leş bildirimleri: sağda liderler tablosunun altında, sağa yaslı. Öldüren ve ölen kendi renginde;
## seni ilgilendirenler (sen öldürdün / seni öldürdüler) renkli çerçeveyle öne çıkar. Yeni gelen kayarak girer.
func _draw_kill_feed(s: Vector2) -> void:
	var y := 14.0 + 40.0 + 5 * 27.0 + 12.0
	var right := s.x - 16.0
	var now: float = main.round_time
	var shown := 0
	for e in main.kill_feed:
		var age := now - float(e["time"])
		if age > 5.0 or shown >= 4:
			continue
		shown += 1
		var a := clampf((5.0 - age) * 2.0, 0.0, 1.0)
		var slide := maxf(0.0, 0.18 - age) / 0.18 * 60.0
		var killer: String = e["killer"]
		var victim: String = e["victim"]
		var kw := font.get_string_size(killer, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var vw := font.get_string_size(victim, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var w := kw + vw + 70.0
		var x := right - w + slide
		var mine: bool = e["mine"]
		var kc: Color = e["killer_col"]
		var vc: Color = e["victim_col"]
		_panel(Rect2(x, y, w, 30), Color(0.04, 0.06, 0.09, 0.78 * a), Color(GOLD, 0.8 * a) if mine else Color(1, 1, 1, 0.08 * a), 15, 2 if mine else 1)
		GameData.disc(cv, Vector2(x + 12, y + 15), 4.0, Color(kc, a))
		_text(Vector2(x + 22, y + 21), killer, 16, Color(kc.lightened(0.35), a))
		KnifeArt.draw(cv, Vector2(x + 22 + kw + 16, y + 15), PI / 2.0, 0.75, 0, false)
		_skull(Vector2(x + 22 + kw + 32, y + 13), 5.0, Color(1, 1, 1, 0.8 * a))
		_text(Vector2(x + kw + 64, y + 21), victim, 16, Color(vc.lightened(0.35), a * 0.85))
		y += 35.0


## Bekleme süresi göstergesi: kalan oran kadar kararan pasta dilimi (saat yönünde açılır).
func _pie(c: Vector2, r: float, ratio: float, col: Color) -> void:
	var pts := PackedVector2Array([c])
	var steps := maxi(3, int(32 * ratio))
	var start := -PI / 2 + TAU * (1.0 - ratio)
	for i in steps + 1:
		pts.append(c + Vector2.from_angle(start + TAU * ratio * i / steps) * r)
	cv.draw_colored_polygon(pts, col)


## Düğme yeniden hazır olduğunda kısa bir parlama halkası.
func _ready_flash(c: Vector2, r: float, age: float) -> void:
	if age < 0.0 or age > 0.35:
		return
	var a := 1.0 - age / 0.35
	cv.draw_arc(c, r + age * 60.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8 * a), 4.0)


## ATIL düğmesine basıldı (basılma efekti için).
func on_dash_pressed() -> void:
	_dash_pressed_at = Time.get_ticks_msec() / 1000.0


func _draw_controls(s: Vector2) -> void:
	var base := joy_origin if joy_index >= 0 else _joy_rest()
	var alpha := 1.0 if joy_index >= 0 else 0.55
	GameData.disc(cv, base, JOY_RADIUS + 6.0, Color(0, 0, 0, 0.15 * alpha))
	GameData.disc(cv, base, JOY_RADIUS, Color(1, 1, 1, 0.1 * alpha))
	cv.draw_arc(base, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35 * alpha), 3.0)
	# Tutamak parmağın olduğu yerde (halkanın içinde) durur; yön oku hareket yönünü gösterir
	var knob := base + ((joy_pos - joy_origin).limit_length(JOY_RADIUS) if joy_index >= 0 else Vector2.ZERO)
	var v := joy_vector()
	if v != Vector2.ZERO:
		var tip := base + v.normalized() * (JOY_RADIUS + 14.0)
		var side := v.normalized().orthogonal() * 12.0
		cv.draw_colored_polygon(PackedVector2Array([tip, tip - v.normalized() * 18.0 + side, tip - v.normalized() * 18.0 - side]),
			Color(1, 1, 1, 0.75))
	GameData.disc(cv, knob + Vector2(0, 4), JOY_KNOB, Color(0, 0, 0, 0.2 * alpha))
	GameData.disc(cv, knob, JOY_KNOB, Color(1, 1, 1, 0.55 * alpha))
	cv.draw_arc(knob, JOY_KNOB, 0.0, TAU, 32, Color(1, 1, 1, 0.8 * alpha), 2.0)

	var p: Fighter = main.player
	var now := Time.get_ticks_msec() / 1000.0
	# --- FIRLAT: basılınca küçülür; bekleme süresinde üstüne kararan dilim gelir, bitince parlar ---
	var c := _throw_center()
	var ready: bool = p.knives > 0 or p.bombs > 0 or p.inf_t > 0.0
	var cd_ratio := clampf(p.throw_cooldown / (main.THROW_COOLDOWN * (2.0 if p.bombs > 0 else 1.0)), 0.0, 1.0)
	if cd_ratio <= 0.0 and _throw_was_cooling:
		_throw_ready_at = now
	_throw_was_cooling = cd_ratio > 0.0
	var held := throw_held()
	var tr := THROW_RADIUS * (0.92 if held else 1.0)
	var col := Color(0.95, 0.3, 0.25, 0.9 if held else 0.7) if ready else Color(0.5, 0.5, 0.5, 0.45)
	GameData.disc(cv, c + Vector2(0, 6), tr, Color(0, 0, 0, 0.25))
	GameData.disc(cv, c, tr, col)
	if held:
		GameData.disc(cv, c, tr * 0.8, Color(1, 1, 1, 0.12))
	cv.draw_arc(c, tr, 0.0, TAU, 48, Color(1, 1, 1, 0.65), 3.0)
	# Hedef kilitliyse buton nabız gibi atar
	if main.player_target != null and ready and cd_ratio <= 0.0:
		var pulse := fmod(now / 0.7, 1.0)
		cv.draw_arc(c, tr + pulse * 22.0, 0.0, TAU, 48, Color(1, 0.3, 0.25, 1.0 - pulse), 4.0)
	if p.bombs > 0:
		# Elde bomba varsa bir sonraki atış bomba: butonda bomba ve sayısı
		main._draw_bomb(cv, c + Vector2(0, -6), 1.3, now)
		_text(Vector2(c.x + 18, c.y - 30), "x%d" % p.bombs, 20, Color(1, 0.85, 0.4))
	else:
		KnifeArt.draw(cv, c + Vector2(0, -8), PI / 4.0, 2.0, p.knife_kind)
	_text(Vector2(c.x - 60, c.y + 50), Loc.t("throw"), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	if cd_ratio > 0.0:
		_pie(c, tr, cd_ratio, Color(0, 0, 0, 0.45))
		cv.draw_arc(c, tr - 5.0, -PI / 2, -PI / 2 + TAU * (1.0 - cd_ratio), 40, Color(1, 1, 1, 0.9), 5.0)
	_ready_flash(c, tr, now - _throw_ready_at)
	# Kalan bıçak sayısı rozeti (bıçak bitince kırmızı)
	var kb := c + Vector2(tr * 0.68, -tr * 0.68)
	GameData.disc(cv, kb, 20.0, Color(0.1, 0.12, 0.16, 0.95))
	cv.draw_arc(kb, 20.0, 0.0, TAU, 24, Color(1, 0.4, 0.35) if p.knives <= 0 else GOLD, 2.0)
	if p.inf_t > 0.0:
		GameData.draw_infinity(cv, kb, 0.75, Color(0.4, 0.95, 1))
	else:
		_text(Vector2(kb.x - 20, kb.y + 7), str(p.knives), 18, Color(1, 0.45, 0.4) if p.knives <= 0 else Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, 40.0)

	# --- ATIL: bekleme süresinde kararan dilim ve kalan saniye; hazır olunca parlar ---
	var d := _dash_center()
	var dash_ratio := clampf(p.dash_cd / Fighter.DASH_COOLDOWN, 0.0, 1.0)
	if dash_ratio <= 0.0 and _dash_was_cooling:
		_dash_ready_at = now
	_dash_was_cooling = dash_ratio > 0.0
	var dr := DASH_RADIUS * (0.9 if now - _dash_pressed_at < 0.12 else 1.0)
	GameData.disc(cv, d + Vector2(0, 5), dr, Color(0, 0, 0, 0.25))
	GameData.disc(cv, d, dr, Color(0.25, 0.55, 0.95, 0.8) if dash_ratio <= 0.0 else Color(0.25, 0.3, 0.4, 0.6))
	cv.draw_arc(d, dr, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 2.5)
	for k in 3:
		var off := Vector2(-12 + k * 10, -6)
		cv.draw_polyline(PackedVector2Array([d + off + Vector2(-5, -7), d + off + Vector2(3, 0), d + off + Vector2(-5, 7)]),
			Color(1, 1, 1, (0.5 + k * 0.25) * (1.0 if dash_ratio <= 0.0 else 0.4)), 3.5)
	if dash_ratio > 0.0:
		_pie(d, dr, dash_ratio, Color(0, 0, 0, 0.4))
		cv.draw_arc(d, dr - 4.0, -PI / 2, -PI / 2 + TAU * (1.0 - dash_ratio), 32, Color(1, 1, 1, 0.9), 4.0)
		_text(Vector2(d.x - 40, d.y + 8), "%.1f" % p.dash_cd, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	else:
		_text(Vector2(d.x - 50, d.y + 24), Loc.t("dash"), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 100.0)
	_ready_flash(d, dr, now - _dash_ready_at)

