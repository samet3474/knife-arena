extends Node
## Sunucu verisini (skor tablosu, sohbet, giriş/çıkış kayıtları) GitHub Gist'te saklar.
## Ücretsiz Render sunucusunun diski her yeniden başlatmada sıfırlanır; veri burada kalıcıdır.
## Gerekli ortam değişkeni (Render > Environment): GIST_TOKEN ("gist" izinli GitHub anahtarı).
## GIST_ID verilmezse sunucu, hesaptaki "knife_arena_state.json" dosyalı gizli Gist'i kendisi bulur,
## yoksa oluşturur. Anahtar yoksa hiçbir şey yapmaz (yalnızca yerel dosya kullanılır).

const FILE_NAME := "knife_arena_state.json"
const API := "https://api.github.com/gists"
const SAVE_INTERVAL := 15.0 # en fazla 15 saniyede bir yazılır (GitHub sınırlarına takılmamak için)

var gist_id := ""
var token := ""
var enabled := false
var ready_to_save := false # Gist bulunup okunduktan sonra yazılır (boş veriyle üstüne yazmamak için)
var _pending = null # yazılmayı bekleyen son veri
var _timer := 0.0
var _busy := false
var _http: HTTPRequest
var _log: Callable = func(_t: String) -> void: pass


func _ready() -> void:
	gist_id = OS.get_environment("GIST_ID").strip_edges()
	token = OS.get_environment("GIST_TOKEN").strip_edges()
	enabled = token != ""
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)


func _headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer " + token,
		"Accept: application/vnd.github+json",
		"User-Agent: knife-arena-server",
		"Content-Type: application/json",
	])


## Tek istek gönderir; bitince done(code, body_text) çağrılır.
func _call(url: String, method: int, body: String, done: Callable) -> void:
	_busy = true
	var cb := func(_r: int, code: int, _h: PackedStringArray, b: PackedByteArray) -> void:
		_busy = false
		done.call(code, b.get_string_from_utf8())
	_http.request_completed.connect(cb, CONNECT_ONE_SHOT)
	if _http.request(url, _headers(), method, body) != OK:
		_http.request_completed.disconnect(cb)
		_busy = false
		done.call(0, "")


## Kayıtlı veriyi okur; bitince on_loaded(Dictionary) çağrılır. log(text): sunucu günlüğüne yazar.
func load_state(on_loaded: Callable, log_func: Callable) -> void:
	if not enabled:
		return
	_log = log_func
	if gist_id != "":
		_read(on_loaded)
		return
	# GIST_ID yok: hesaptaki Gist'ler arasında bizim dosyamızı ara
	_call(API + "?per_page=100", HTTPClient.METHOD_GET, "", func(code: int, text: String) -> void:
		if code != 200:
			_log.call("Bulut: Gist listesi alınamadı (HTTP %d). Anahtarın 'gist' izni var mı?" % code)
			return
		var list = JSON.parse_string(text)
		if list is Array:
			for g in list:
				if g is Dictionary and g.get("files") is Dictionary and g["files"].has(FILE_NAME):
					gist_id = String(g["id"])
					break
		if gist_id != "":
			_read(on_loaded)
		else:
			_create())


func _create() -> void:
	var body := JSON.stringify({"description": "Knife Arena sunucu kayitlari", "public": false,
		"files": {FILE_NAME: {"content": "{}"}}})
	_call(API, HTTPClient.METHOD_POST, body, func(code: int, text: String) -> void:
		var d = JSON.parse_string(text)
		if code == 201 and d is Dictionary:
			gist_id = String(d["id"])
			ready_to_save = true
			_log.call("Bulut: yeni kayıt dosyası oluşturuldu")
		else:
			_log.call("Bulut: kayıt dosyası oluşturulamadı (HTTP %d)" % code))


func _read(on_loaded: Callable) -> void:
	_call(API + "/" + gist_id, HTTPClient.METHOD_GET, "", func(code: int, text: String) -> void:
		if code != 200:
			_log.call("Bulut: kayıt okunamadı (HTTP %d)" % code)
			return
		ready_to_save = true
		var d = JSON.parse_string(text)
		if not d is Dictionary or not d.get("files") is Dictionary or not d["files"].has(FILE_NAME):
			return
		var content = JSON.parse_string(String(d["files"][FILE_NAME].get("content", "")))
		if content is Dictionary and not content.is_empty():
			on_loaded.call(content))


## Yazma isteği: veri bekletilir, en fazla SAVE_INTERVAL saniyede bir gönderilir.
func request_save(data: Dictionary) -> void:
	if enabled:
		_pending = data.duplicate(true)


func _process(delta: float) -> void:
	if not enabled or not ready_to_save:
		return
	_timer -= delta
	if _pending == null or _busy or _timer > 0.0:
		return
	_timer = SAVE_INTERVAL
	var body := JSON.stringify({"files": {FILE_NAME: {"content": JSON.stringify(_pending)}}})
	_pending = null
	_call(API + "/" + gist_id, HTTPClient.METHOD_PATCH, body, func(code: int, _text: String) -> void:
		if code != 200:
			_log.call("Bulut: kayıt yazılamadı (HTTP %d)" % code))
