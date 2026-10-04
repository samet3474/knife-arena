param([string]$ServerUrl = "")
# Knife Arena'yı internete yayınlar:
#  1) Web sürümünü docs/ klasörüne çıkarır (GitHub Pages buradan yayınlar)
#  2) Sunucu paketini server/ klasörüne çıkarır (Render.com bundan Docker sunucusu kurar)
#  3) Değişiklikleri GitHub'a gönderir; Pages ve Render birkaç dakika içinde güncellenir.
# Kullanım:  powershell -ExecutionPolicy Bypass -File yayinla.ps1 [-ServerUrl wss://...onrender.com]
$ErrorActionPreference = "Stop"
$proj = $PSScriptRoot
$godot = "C:\Users\TRHN\Downloads\Godot_v4.7.2-stable_win64_console.exe"

if ($ServerUrl -ne "") { Set-Content -Path "$proj\server_url.txt" -Value $ServerUrl -NoNewline -Encoding ascii }
"Sunucu adresi: " + (Get-Content "$proj\server_url.txt" -ErrorAction SilentlyContinue)

Write-Host "Web sürümü dışa aktarılıyor..."
New-Item -ItemType Directory -Force "$proj\build\web" | Out-Null
& $godot --headless --path $proj --export-release "Web" "$proj\build\web\index.html" 2>&1 | Out-Null
if (Test-Path "$proj\docs") { Remove-Item "$proj\docs" -Recurse -Force }
Copy-Item "$proj\build\web" "$proj\docs" -Recurse
New-Item -ItemType File "$proj\docs\.nojekyll" -Force | Out-Null
New-Item -ItemType File "$proj\docs\.gdignore" -Force | Out-Null # Godot bu klasörü proje dosyası sanmasın

# Telefon ayarları: ana ekrana ekleyince tam ekran, ekran yoğunluğu sınırı (iPhone'da akıcılık)
$head = @"
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Knife Arena">
<link rel="apple-touch-icon" href="index.apple-touch-icon.png">
<style>html, body { overscroll-behavior: none; touch-action: none; background: #0b0f0d; }
* { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; -webkit-tap-highlight-color: transparent; }
canvas { touch-action: none; -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; outline: none; }</style>
<script>
(function () {
	var touch = ('ontouchstart' in window) || (navigator.maxTouchPoints || 0) > 0;
	var cap = Math.min(window.devicePixelRatio || 1, touch ? 2.0 : 2.0);
	try { Object.defineProperty(window, 'devicePixelRatio', { get: function () { return cap; } }); } catch (e) {}
})();
</script>
</head>
"@
$html = [IO.File]::ReadAllText("$proj\docs\index.html")
$html = $html.Replace("</head>", $head)
[IO.File]::WriteAllText("$proj\docs\index.html", $html, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Sunucu paketi dışa aktarılıyor..."
New-Item -ItemType Directory -Force "$proj\server" | Out-Null
& $godot --headless --path $proj --export-pack "Linux Server" "$proj\server\knife_arena.pck" 2>&1 | Out-Null

Write-Host "GitHub'a gönderiliyor..."
$git = "C:\Program Files\Git\cmd\git.exe"
& $git -C $proj add -A
& $git -C $proj commit -q -m ("Yayın " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
& $git -C $proj push -u origin main
Write-Host "Tamam. GitHub Pages ve Render birkaç dakika içinde güncellenir."
