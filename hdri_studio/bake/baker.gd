class_name HdriBaker
extends RefCounted
## Esegue il compute shader di bake e tiene la texture RGBA32F risultante.
## Con il RenderingDevice principale la texture è condivisibile con il preview via Texture2DRD;
## con un device locale (spike, test) serve submit()/sync() prima di leggere i dati.

const SHADER_PATH := "res://bake/bake.glsl"
const MAX_LIGHTS := 64
const PUSH_CONSTANT_FLOATS := 20
## Texture array delle luci Texture: ogni immagine viene ricampionata a questa dimensione.
const TEX_LAYER_SIZE := Vector2i(2048, 1024)
const TEX_LAYERS := 12
## Griglia della misura fotometrica (nel frame locale della luce).
const MEASURE_RES := Vector2i(256, 256)

var rd: RenderingDevice
var width := 4096
var height := 2048
var supersample := 2
var texture := RID()

var _local := false
var _shader := RID()
var _pipeline := RID()
var _lights_buf := RID()
var _grads_buf := RID()
var _base_tex := RID()
var _sampler := RID()
var _uniform_set := RID()
var _base_is_placeholder := true
var _tex_array := RID()
var _tex_layers := {}   # percorso → strato
var _tex_lru: Array[String] = []
var _measure_tex := RID()
var _measure_set := RID()
var _k_cache := {}      # shape_key → K


func _init(local_device := false) -> void:
	_local = local_device
	rd = RenderingServer.create_local_rendering_device() if local_device else RenderingServer.get_rendering_device()
	assert(rd != null, "RenderingDevice non disponibile (headless?)")
	_compile()
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = rd.sampler_create(ss)
	var zero := PackedByteArray()
	zero.resize(MAX_LIGHTS * RigLight.STRIDE * 16)
	_lights_buf = rd.storage_buffer_create(zero.size(), zero)
	var zero_g := PackedByteArray()
	zero_g.resize(MAX_LIGHTS * RigLight.GRAD_STOPS * 16)
	_grads_buf = rd.storage_buffer_create(zero_g.size(), zero_g)
	_set_base_placeholder()
	_create_texture_array()
	set_resolution(width, height)


func _compile() -> void:
	# Tre strade, in ordine: sorgente su disco (editor: errori leggibili), risorsa importata
	# (RDShaderFile, già SPIR-V), sorgente incorporato in BakeGlslSource (app esportata, sempre
	# disponibile). Ogni fallimento finisce nel log: in un build release gli assert non esistono.
	var spirv: RDShaderSPIRV = null
	var how := ""
	if OS.has_feature("editor") and FileAccess.file_exists(SHADER_PATH):
		var src := FileAccess.get_file_as_string(SHADER_PATH).replace("#[compute]", "")
		spirv = _compile_source(src)
		how = "sorgente"
	if spirv == null:
		var sf := load(SHADER_PATH) as RDShaderFile
		if sf != null:
			spirv = sf.get_spirv()
			how = "risorsa importata"
			if spirv != null and (spirv.compile_error_compute != "" or spirv.bytecode_compute.is_empty()):
				push_warning("bake.glsl (risorsa importata): %s" % spirv.compile_error_compute)
				spirv = null
	if spirv == null:
		spirv = _compile_source(BakeGlslSource.SOURCE)
		how = "sorgente incorporato"
	if spirv == null or spirv.compile_error_compute != "":
		push_error("bake.glsl non compilabile (%s): %s" % [how, spirv.compile_error_compute if spirv else "null"])
		return
	_shader = rd.shader_create_from_spirv(spirv)
	_pipeline = rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		push_error("bake.glsl: pipeline non creata (%s)" % how)
	print("Baker: shader da %s" % how)


func _compile_source(src: String) -> RDShaderSPIRV:
	var shader_src := RDShaderSource.new()
	shader_src.source_compute = src
	var spirv := rd.shader_compile_spirv_from_source(shader_src)
	if spirv.compile_error_compute != "":
		push_error("bake.glsl: " + spirv.compile_error_compute)
		return null
	return spirv


func is_ready() -> bool:
	return _pipeline.is_valid()


func set_resolution(w: int, h: int) -> void:
	if texture.is_valid() and w == width and h == height:
		return
	width = w
	height = h
	if texture.is_valid():
		rd.free_rid(texture)
	var fmt := RDTextureFormat.new()
	fmt.width = width
	fmt.height = height
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)
	texture = rd.texture_create(fmt, RDTextureView.new())
	_uniform_set = RID()


func _set_base_placeholder() -> void:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBAF)
	img.fill(Color.BLACK)
	_upload_base(img)
	_base_is_placeholder = true


## Carica l'HDRI di base (EXR o .hdr). Restituisce false se il file non si legge.
func set_base_image_from_file(path: String) -> bool:
	var img := load_linear_image(path)
	if img == null:
		push_warning("Impossibile caricare l'HDRI di base: " + path)
		return false
	set_base_image(img)
	return true


func set_base_image(img: Image) -> void:
	var copy := img.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_RGBAF)
	_upload_base(copy)
	_base_is_placeholder = false


func _upload_base(img: Image) -> void:
	if _base_tex.is_valid():
		rd.free_rid(_base_tex)
	_measure_set = RID()
	var fmt := RDTextureFormat.new()
	fmt.width = img.get_width()
	fmt.height = img.get_height()
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_base_tex = rd.texture_create(fmt, RDTextureView.new(), [img.get_data()])
	_uniform_set = RID()


func has_base_image() -> bool:
	return not _base_is_placeholder


# --- texture delle luci --------------------------------------------------------------------------

func _create_texture_array() -> void:
	var fmt := RDTextureFormat.new()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	fmt.width = TEX_LAYER_SIZE.x
	fmt.height = TEX_LAYER_SIZE.y
	fmt.array_layers = TEX_LAYERS
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var zero := PackedByteArray()
	zero.resize(TEX_LAYER_SIZE.x * TEX_LAYER_SIZE.y * 8)
	var layers: Array[PackedByteArray] = []
	for i in TEX_LAYERS:
		layers.append(zero)
	_tex_array = rd.texture_create(fmt, RDTextureView.new(), layers)


## Carica un'immagine lineare (EXR o .hdr) dal disco; null se non leggibile. Gli EXR con codec che
## TinyEXR non decodifica (DWAA/DWAB, B44, PXR24) passano da una conversione in PIZ via Blender.
static func load_linear_image(path: String) -> Image:
	var img := Image.new()
	var err: Error
	if path.get_extension().to_lower() == "exr":
		var src := path
		if not ExrConvert.tinyexr_can_read(path):
			src = ExrConvert.to_piz_cached(path)
			if src == "":
				push_warning("EXR con codec non leggibile e Blender non disponibile per convertirlo: " + path)
				return null
		err = img.load_exr_from_buffer(FileAccess.get_file_as_bytes(src))
	else:
		err = img.load(path)
	if err != OK or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	return img


## Strato del texture array per il file (caricandolo se serve), -1 se non leggibile.
func texture_layer(path: String) -> int:
	if path == "":
		return -1
	if _tex_layers.has(path):
		_tex_lru.erase(path)
		_tex_lru.append(path)
		return _tex_layers[path]
	var img := load_linear_image(path)
	if img == null:
		push_warning("Immagine della luce non leggibile: " + path)
		return -1
	img.resize(TEX_LAYER_SIZE.x, TEX_LAYER_SIZE.y, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBAH)
	var layer: int
	if _tex_layers.size() < TEX_LAYERS:
		layer = _tex_layers.size()
	else:
		var evict: String = _tex_lru.pop_front()
		layer = _tex_layers[evict]
		_tex_layers.erase(evict)
	rd.texture_update(_tex_array, layer, img.get_data())
	_tex_layers[path] = layer
	_tex_lru.append(path)
	return layer


## Dimenticare un file (per esempio se è stato modificato su disco).
func forget_texture(path: String) -> void:
	if _tex_layers.has(path):
		_tex_layers.erase(path)
		_tex_lru.erase(path)


func _ensure_uniform_set() -> void:
	if _uniform_set.is_valid():
		return
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(texture)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(_lights_buf)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u2.binding = 2
	u2.add_id(_sampler)
	u2.add_id(_base_tex)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u3.binding = 3
	u3.add_id(_sampler)
	u3.add_id(_tex_array)
	var u4 := RDUniform.new()
	u4.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u4.binding = 4
	u4.add_id(_grads_buf)
	_uniform_set = rd.uniform_set_create([u0, u1, u2, u3, u4], _shader, 0)


## K = ∫ w(d)·cosθ dω della luce (sr, pesato dal profilo e dall'immagine): misurato sul GPU nel
## frame locale della luce, con cache sui parametri di forma.
func measure_k(l: RigLight) -> float:
	var key := l.shape_key()
	if _k_cache.has(key):
		return _k_cache[key]
	_ensure_measure_set()
	var probe := l.duplicate_light()
	probe.photometric = false
	probe.intensity = 1.0
	probe.ev = 0.0
	probe.kelvin = 6500.0
	probe.tint = Color.WHITE
	probe.enabled = true
	var layer := -1
	if probe.shape == RigLight.Shape.TEXTURE:
		layer = texture_layer(probe.texture_path)
	var data := PackedFloat32Array()
	probe.pack(data, layer)
	var bytes := data.to_byte_array()
	rd.buffer_update(_lights_buf, 0, bytes.size(), bytes)
	_upload_gradient_slot0(probe)
	var pc := PackedFloat32Array([
		float(MEASURE_RES.x), float(MEASURE_RES.y), 1.0, 1.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 1.0,
		0.0, 1.0, 0.0, 0.0,
	])
	var pc_bytes := pc.to_byte_array()
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	rd.compute_list_bind_uniform_set(cl, _measure_set, 0)
	rd.compute_list_set_push_constant(cl, pc_bytes, pc_bytes.size())
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(cl, (MEASURE_RES.x + 7) / 8, (MEASURE_RES.y + 7) / 8, 1)
	rd.compute_list_end()
	if _local:
		rd.submit()
		rd.sync()
	var f := rd.texture_get_data(_measure_tex, 0).to_float32_array()
	var k := 0.0
	var i := 0
	while i < f.size():
		k += f[i]
		i += 4
	_k_cache[key] = k
	return k


func _ensure_measure_set() -> void:
	if _measure_set.is_valid():
		return
	var fmt := RDTextureFormat.new()
	fmt.width = MEASURE_RES.x
	fmt.height = MEASURE_RES.y
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_measure_tex = rd.texture_create(fmt, RDTextureView.new())
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(_measure_tex)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(_lights_buf)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u2.binding = 2
	u2.add_id(_sampler)
	u2.add_id(_base_tex)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u3.binding = 3
	u3.add_id(_sampler)
	u3.add_id(_tex_array)
	var u4 := RDUniform.new()
	u4.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u4.binding = 4
	u4.add_id(_grads_buf)
	_measure_set = rd.uniform_set_create([u0, u1, u2, u3, u4], _shader, 0)


## Texture planare di una luce (per l'area light nel software 3D): immagine RGBAF di long_side px sul
## lato lungo, aspetto = tan(w/2) / tan(h/2), radianza già applicata, supersampling 2×2.
func bake_planar(l: RigLight, long_side := 1024) -> Image:
	if l.photometric:
		l.measured_k = measure_k(l)
	var thw := tan(deg_to_rad(minf(l.width, 178.0)) * 0.5)
	var thh := tan(deg_to_rad(minf(l.height, 178.0)) * 0.5)
	var w := long_side
	var h := long_side
	if thw >= thh:
		h = maxi(int(round(long_side * thh / thw)), 4)
	else:
		w = maxi(int(round(long_side * thw / thh)), 4)
	# texture e uniform set temporanei
	var fmt := RDTextureFormat.new()
	fmt.width = w
	fmt.height = h
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var tex := rd.texture_create(fmt, RDTextureView.new())
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(tex)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(_lights_buf)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u2.binding = 2
	u2.add_id(_sampler)
	u2.add_id(_base_tex)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u3.binding = 3
	u3.add_id(_sampler)
	u3.add_id(_tex_array)
	var u4 := RDUniform.new()
	u4.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u4.binding = 4
	u4.add_id(_grads_buf)
	var uset := rd.uniform_set_create([u0, u1, u2, u3, u4], _shader, 0)

	var layer := -1
	if l.shape == RigLight.Shape.TEXTURE:
		layer = texture_layer(l.texture_path)
	var data := PackedFloat32Array()
	var probe := l.duplicate_light()
	probe.measured_k = l.measured_k
	probe.enabled = true
	probe.pack(data, layer)
	var bytes := data.to_byte_array()
	rd.buffer_update(_lights_buf, 0, bytes.size(), bytes)
	_upload_gradient_slot0(probe)
	var pc := PackedFloat32Array([
		float(w), float(h), 1.0, 2.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 2.0,
		0.0, 1.0, 0.0, 0.0,
	])
	var pc_bytes := pc.to_byte_array()
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	rd.compute_list_set_push_constant(cl, pc_bytes, pc_bytes.size())
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(cl, (w + 7) / 8, (h + 7) / 8, 1)
	rd.compute_list_end()
	if _local:
		rd.submit()
		rd.sync()
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBAF, rd.texture_get_data(tex, 0))
	rd.free_rid(uset)
	rd.free_rid(tex)
	return img


func _upload_gradient_slot0(l: RigLight) -> void:
	var g := PackedFloat32Array()
	l.pack_gradient(g)
	var gb := g.to_byte_array()
	rd.buffer_update(_grads_buf, 0, gb.size(), gb)


## Esegue il bake del rig nella texture. Con calibration = true ignora le luci e disegna i marker degli
## assi. include_separate: le luci separate entrano nel preview ma non nell'HDRI esportata.
func bake(rig: LightRig, calibration := false, include_separate := true) -> void:
	# le luci fotometriche hanno bisogno del loro K prima del pack (la misura usa lo stesso buffer)
	for l in rig.active_lights(include_separate):
		if l.photometric:
			l.measured_k = measure_k(l)
	_ensure_uniform_set()

	var data := PackedFloat32Array()
	var gdata := PackedFloat32Array()
	var count := 0
	for l in rig.active_lights(include_separate):
		if count >= MAX_LIGHTS:
			push_warning("Più di %d luci: le altre vengono ignorate" % MAX_LIGHTS)
			break
		var layer := -1
		if l.shape == RigLight.Shape.TEXTURE:
			layer = texture_layer(l.texture_path)
		l.pack(data, layer)
		l.pack_gradient(gdata)
		count += 1
	if count > 0:
		var bytes := data.to_byte_array()
		rd.buffer_update(_lights_buf, 0, bytes.size(), bytes)
		var gbytes := gdata.to_byte_array()
		rd.buffer_update(_grads_buf, 0, gbytes.size(), gbytes)

	var base_on := rig.base_enabled and has_base_image()
	var pc := PackedFloat32Array([
		float(width), float(height), float(count), float(supersample),
		rig.bg_zenith.r, rig.bg_zenith.g, rig.bg_zenith.b, float(rig.background),
		rig.bg_horizon.r, rig.bg_horizon.g, rig.bg_horizon.b, 1.0 if calibration else 0.0,
		rig.bg_nadir.r, rig.bg_nadir.g, rig.bg_nadir.b, 0.0,
		deg_to_rad(rig.base_rotation), rig.base_exposure(), 1.0 if base_on else 0.0, 1.0 if rig.base_flip else 0.0,
	])
	assert(pc.size() == PUSH_CONSTANT_FLOATS)
	var pc_bytes := pc.to_byte_array()

	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	rd.compute_list_set_push_constant(cl, pc_bytes, pc_bytes.size())
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(cl, (width + 7) / 8, (height + 7) / 8, 1)
	rd.compute_list_end()
	if _local:
		rd.submit()
		rd.sync()


## Copia la texture dalla GPU in un Image RGBAF (float32).
func get_image() -> Image:
	var bytes := rd.texture_get_data(texture, 0)
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, bytes)


func free_resources() -> void:
	for rid in [_uniform_set, _measure_set, texture, _measure_tex, _base_tex, _tex_array, _lights_buf, _grads_buf, _sampler, _pipeline, _shader]:
		if rid.is_valid():
			rd.free_rid(rid)
	_uniform_set = RID()
	texture = RID()
	if _local:
		rd.free()
