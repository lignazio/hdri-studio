class_name ThumbnailCache
extends RefCounted
## Miniature delle HDRI del catalogo: generate in un thread, salvate come PNG in user://thumbs/
## (chiave = percorso + data di modifica), consegnate sul thread principale con poll().

signal ready(path: String, texture: ImageTexture, size: Vector2i)

const SIZE := Vector2i(384, 192)
const DIR := "user://thumbs_384"
## Offset in EV aggiunto all'esposizione automatica delle miniature (fa parte della chiave di cache).
static var exposure_ev := 0.0

var _queue: Array[String] = []
var _queued := {}
var _results: Array = []
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _thread: Thread
var _running := true


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_thread = Thread.new()
	_thread.start(_worker)


func shutdown() -> void:
	_running = false
	_sem.post()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


## Restituisce subito la miniatura se è in cache su disco, altrimenti la mette in coda e
## restituisce null: arriverà tramite il segnale ready.
func request(path: String) -> ImageTexture:
	var key := _key(path)
	var png := DIR + "/" + key + ".png"
	if FileAccess.file_exists(png):
		var img := Image.load_from_file(ProjectSettings.globalize_path(png))
		if img != null:
			var meta := _read_meta(key)
			var tex := ImageTexture.create_from_image(img)
			ready.emit.call_deferred(path, tex, meta)
			return tex
	_mutex.lock()
	if not _queued.has(path):
		_queued[path] = true
		_queue.append(path)
		_sem.post()
	_mutex.unlock()
	return null


## Da chiamare ogni frame sul thread principale.
func poll() -> void:
	_mutex.lock()
	var results := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for r in results:
		var path: String = r[0]
		var img: Image = r[1]
		var size: Vector2i = r[2]
		_mutex.lock()
		_queued.erase(path)
		_mutex.unlock()
		if img == null:
			continue
		var key := _key(path)
		img.save_png(ProjectSettings.globalize_path(DIR + "/" + key + ".png"))
		var f := FileAccess.open(DIR + "/" + key + ".json", FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"w": size.x, "h": size.y}))
		ready.emit(path, ImageTexture.create_from_image(img), size)


## Dimensioni dell'immagine originale, se la miniatura è già stata generata.
func image_size(path: String) -> Vector2i:
	return _read_meta(_key(path))


static func _key(path: String) -> String:
	var mtime := FileAccess.get_modified_time(path)
	return (path + ":" + str(mtime) + ":" + ("%.2f" % exposure_ev)).md5_text()


static func _read_meta(key: String) -> Vector2i:
	var txt := FileAccess.get_file_as_string(DIR + "/" + key + ".json")
	if txt.is_empty():
		return Vector2i.ZERO
	var d = JSON.parse_string(txt)
	if d is Dictionary:
		return Vector2i(int(d.get("w", 0)), int(d.get("h", 0)))
	return Vector2i.ZERO


func _worker() -> void:
	while true:
		_sem.wait()
		if not _running:
			return
		_mutex.lock()
		var path: String = _queue.pop_front() if not _queue.is_empty() else ""
		_mutex.unlock()
		if path == "":
			continue
		var img := HdriBaker.load_linear_image(path)
		var size := Vector2i.ZERO
		var thumb: Image = null
		if img != null:
			size = Vector2i(img.get_width(), img.get_height())
			thumb = _make_thumb(img)
		_mutex.lock()
		_results.append([path, thumb, size])
		_mutex.unlock()


## Ridimensiona mantenendo l'aspetto dentro SIZE, esposizione automatica, sRGB.
static func _make_thumb(img: Image) -> Image:
	img.convert(Image.FORMAT_RGBAF)
	var aspect := float(img.get_width()) / float(img.get_height())
	var w := SIZE.x
	var h := int(round(SIZE.x / aspect))
	if h > SIZE.y:
		h = SIZE.y
		w = int(round(SIZE.y * aspect))
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var f := img.get_data().to_float32_array()
	var sum := 0.0
	var n := 0
	var i := 0
	while i < f.size():
		sum += 0.2126 * f[i] + 0.7152 * f[i + 1] + 0.0722 * f[i + 2]
		n += 1
		i += 4
	var mean := sum / maxf(n, 1)
	var k := clampf(0.35 / maxf(mean, 1e-6), 0.02, 50.0) * pow(2.0, exposure_ev)
	i = 0
	while i < f.size():
		f[i] *= k
		f[i + 1] *= k
		f[i + 2] *= k
		f[i + 3] = 1.0
		i += 4
	var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBAF, f.to_byte_array())
	out.convert(Image.FORMAT_RGB8)
	out.linear_to_srgb()
	# letterbox su SIZE
	var canvas := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	canvas.fill(Color(0.1, 0.1, 0.1))
	canvas.blit_rect(out, Rect2i(0, 0, w, h), Vector2i((SIZE.x - w) / 2, (SIZE.y - h) / 2))
	return canvas
