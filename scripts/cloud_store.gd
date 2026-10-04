extends Node
## Sunucu verisini (skor tablosu, giriş/çıkış kayıtları) GitHub Gist'te saklar.
## Ücretsiz Render sunucusunun diski her yeniden başlatmada sıfırlanır; veri burada kalıcıdır.
## Gerekli ortam değişkenleri (Render > Environment): GIST_ID ve GIST_TOKEN ("gist" izinli GitHub anahtarı).
## İkisi de yoksa hiçbir şey yapmaz (yalnızca yerel dosya kullanılır).

const FILE_NAME := "knife_arena_state.json"
const SAVE_INTERVAL := 30.0 # en fazla 30 saniyede bir yazılır (GitHub sınırlarına takılmamak için)

var gist_id := ""
var token := ""
var enabled := false
var _pending = null # yazılmayı bekleyen son veri
var _timer := 0.0
var _busy := false
var _http: HTTPRequest


func _ready() -> void:
	gist_id = OS.get_environment("GIST_ID").strip_edges()
	token = OS.get_environment("GIST_TOKEN").strip_edges()
	enabled = gist_id != "" and token != ""
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


## Kayıtlı veriyi okur; bitince on_loaded(Dictionary) çağrılır (yoksa/hatada çağrılmaz).
func load_state(on_loaded: Callable) -> void:
	if not enabled:
		return
	_busy = true
	var done := func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		_busy = false
		if code != 200:
			print("Bulut kaydı okunamadı (HTTP %d)" % code)
			return
		var d = JSON.parse_string(body.get_string_from_utf8())
		if not d is Dictionary or not d.get("files") is Dictionary or not d["files"].has(FILE_NAME):
			return
		var content = JSON.parse_string(String(d["files"][FILE_NAME].get("content", "")))
		if content is Dictionary:
			on_loaded.call(content)
	_http.request_completed.connect(done, CONNECT_ONE_SHOT)
	if _http.request("https://api.github.com/gists/" + gist_id, _headers(), HTTPClient.METHOD_GET) != OK:
		_busy = false


## Yazma isteği: veri bekletilir, en fazla SAVE_INTERVAL saniyede bir gönderilir.
func request_save(data: Dictionary) -> void:
	if enabled:
		_pending = data.duplicate(true)


func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _pending == null or _busy or _timer > 0.0:
		return
	_timer = SAVE_INTERVAL
	var body := JSON.stringify({"files": {FILE_NAME: {"content": JSON.stringify(_pending)}}})
	_pending = null
	_busy = true
	var done := func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		_busy = false
		if code != 200:
			print("Bulut kaydı yazılamadı (HTTP %d)" % code)
	_http.request_completed.connect(done, CONNECT_ONE_SHOT)
	if _http.request("https://api.github.com/gists/" + gist_id, _headers(), HTTPClient.METHOD_PATCH, body) != OK:
		_busy = false
