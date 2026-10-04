extends Node
## Çok basit statik dosya sunucusu (HTTP/1.0). Oyunun web sürümünü aynı Wi-Fi'deki
## telefonlara sunar: http://<bilgisayar-ip>:8080 . Python vb. gerekmez.
## Dosyalar gzip ile sıkıştırılıp bellekte tutulur (38 MB'lık motor ≈ 9 MB'a iner);
## motor dosyası (wasm) telefonda önbelleğe alınır, sonraki açılışlarda yeniden inmez.

const PORT := 8080
const CHUNK := 256 * 1024
const MIME := {
	"html": "text/html; charset=utf-8", "js": "application/javascript", "wasm": "application/wasm",
	"pck": "application/octet-stream", "png": "image/png", "svg": "image/svg+xml", "ico": "image/x-icon",
	"json": "application/json", "css": "text/css",
}

## Telefonlar için sayfaya eklenen etiketler:
##  - "Ana Ekrana Ekle" ile açılınca adres çubuğu olmadan tam ekran çalışma (iPhone ve Android),
##  - ekran yoğunluğunu sınırlama (dokunmatik cihazda 1.25, diğerlerinde 1.5; iPhone'un 3x ekranı çok ağır),
##  - sayfanın kaydırılmasını/yakınlaştırılmasını engelleme.
const HEAD_INJECT := """
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Knife Arena">
<link rel="apple-touch-icon" href="index.apple-touch-icon.png">
<style>html, body { overscroll-behavior: none; touch-action: none; background: #0b0f0d; }</style>
<script>
(function () {
	var touch = ('ontouchstart' in window) || (navigator.maxTouchPoints || 0) > 0;
	var cap = Math.min(window.devicePixelRatio || 1, touch ? 1.25 : 1.5);
	try { Object.defineProperty(window, 'devicePixelRatio', { get: function () { return cap; } }); } catch (e) {}
})();
</script>
</head>"""

var root_dir := ""
var server := TCPServer.new()
var clients: Array[Dictionary] = []
var cache := {} # dosya yolu → {"mtime", "raw", "gz", "mime"}


func start(dir: String) -> Error:
	root_dir = dir
	return server.listen(PORT)


func _process(_delta: float) -> void:
	while server.is_connection_available():
		var conn := server.take_connection()
		clients.append({"conn": conn, "req": "", "data": PackedByteArray(), "sent": 0, "header_done": false})
	for i in range(clients.size() - 1, -1, -1):
		if not _serve(clients[i]):
			clients[i]["conn"].disconnect_from_host()
			clients.remove_at(i)


## Bir bağlantıyı ilerletir; bağlantı kapanacaksa false döner.
func _serve(c: Dictionary) -> bool:
	var conn: StreamPeerTCP = c["conn"]
	conn.poll()
	if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	if not c["header_done"]:
		var avail := conn.get_available_bytes()
		if avail > 0:
			c["req"] = String(c["req"]) + conn.get_utf8_string(avail)
		if not String(c["req"]).contains("\r\n\r\n"):
			return String(c["req"]).length() < 8192
		c["header_done"] = true
		c["data"] = _build_response(String(c["req"]))
	# Büyük dosyaları parça parça gönder
	var data: PackedByteArray = c["data"]
	var sent: int = c["sent"]
	if sent >= data.size():
		return false
	var part := data.slice(sent, mini(sent + CHUNK, data.size()))
	var res := conn.put_partial_data(part)
	if res[0] != OK:
		return false
	c["sent"] = sent + int(res[1])
	return true


func _build_response(request: String) -> PackedByteArray:
	var request_line := request.get_slice("\r\n", 0)
	var path := request_line.get_slice(" ", 1).get_slice("?", 0).uri_decode()
	if path == "/" or path == "":
		path = "/index.html"
	# Klasör dışına çıkmaya izin verme
	if path.contains(".."):
		return _status(403, "Forbidden")
	var file_path := root_dir.path_join(path.trim_prefix("/"))
	if not FileAccess.file_exists(file_path):
		return _status(404, "Not Found")
	var entry := _load(file_path)
	var gzip_ok := request.to_lower().contains("accept-encoding:") and request.to_lower().contains("gzip")
	var body: PackedByteArray = entry["gz"] if gzip_ok else entry["raw"]
	# Motor (wasm) sürümle değişmez: bir gün önbellekte kalsın. Diğerleri güncellemeyle değişebilir.
	var cache_ctl := "public, max-age=86400" if file_path.ends_with(".wasm") else "no-cache"
	var header := "HTTP/1.0 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: %s\r\n" % [
		entry["mime"], body.size(), cache_ctl]
	if gzip_ok:
		header += "Content-Encoding: gzip\r\n"
	header += "Connection: close\r\n\r\n"
	var out := header.to_utf8_buffer()
	out.append_array(body)
	return out


## Dosyayı okur, gerekirse yamalar ve sıkıştırır; değişmediyse bellekteki kopyayı kullanır.
func _load(file_path: String) -> Dictionary:
	var mtime := FileAccess.get_modified_time(file_path)
	if cache.has(file_path) and int(cache[file_path]["mtime"]) == mtime:
		return cache[file_path]
	var raw := _patch_for_http(file_path.get_file(), FileAccess.get_file_as_bytes(file_path))
	var entry := {
		"mtime": mtime,
		"raw": raw,
		"gz": raw.compress(FileAccess.COMPRESSION_GZIP),
		"mime": MIME.get(file_path.get_extension().to_lower(), "application/octet-stream"),
	}
	cache[file_path] = entry
	return entry


## Godot'nun web sürümü normalde HTTPS ister. Yerel ağda düz HTTP ile çalışabilmesi için:
##  - sayfadaki ön kontrolden "Secure Context" maddesi çıkarılır,
##  - HTTPS yokken tarayıcıda bulunmayan audioWorklet'e erişim çökmesin diye korunur
##    (ses, project.godot'daki ayar sayesinde ScriptProcessor ile akış olarak çalınır).
func _patch_for_http(file_name: String, body: PackedByteArray) -> PackedByteArray:
	if file_name == "index.html":
		var html := body.get_string_from_utf8()
		html = html.replace("if (missing.length !== 0) {",
			"if (missing.filter((m) => !m.startsWith('Secure Context')).length !== 0) {")
		html = html.replace("</head>", HEAD_INJECT)
		return html.to_utf8_buffer()
	if file_name == "index.js":
		var js := body.get_string_from_utf8()
		js = js.replace("GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path)",
			"GodotAudio.audioPositionWorkletPromise=(ctx.audioWorklet?ctx.audioWorklet.addModule(path):new Promise(function(){}))")
		return js.to_utf8_buffer()
	return body


func _status(code: int, text: String) -> PackedByteArray:
	return ("HTTP/1.0 %d %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [code, text, text.length(), text]).to_utf8_buffer()
