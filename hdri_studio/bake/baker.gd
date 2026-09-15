class_name HdriBaker
extends RefCounted
## Esegue il compute shader di bake e tiene la texture RGBA32F risultante.
## Con il RenderingDevice principale la texture è condivisibile con il preview via Texture2DRD;
## con un device locale (spike, test) serve submit()/sync() prima di leggere i dati.

const SHADER_PATH := "res://bake/bake.glsl"
const MAX_LIGHTS := 64
const PUSH_CONSTANT_FLOATS := 20

var rd: RenderingDevice
var width := 4096
var height := 2048
var supersample := 2
var texture := RID()

var _local := false
var _shader := RID()
var _pipeline := RID()
var _lights_buf := RID()
var _base_tex := RID()
var _sampler := RID()
var _uniform_set := RID()
var _base_is_placeholder := true


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
	_set_base_placeholder()
	set_resolution(width, height)


func _compile() -> void:
	var src := FileAccess.get_file_as_string(SHADER_PATH)
	assert(not src.is_empty(), "Shader non trovato: " + SHADER_PATH)
	src = src.replace("#[compute]", "")
	var shader_src := RDShaderSource.new()
	shader_src.source_compute = src
	var spirv := rd.shader_compile_spirv_from_source(shader_src)
	if spirv.compile_error_compute != "":
		push_error("bake.glsl: " + spirv.compile_error_compute)
		assert(false)
	_shader = rd.shader_create_from_spirv(spirv)
	_pipeline = rd.compute_pipeline_create(_shader)


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
	var img := Image.new()
	var err: Error
	if path.get_extension().to_lower() == "exr":
		err = img.load_exr_from_buffer(FileAccess.get_file_as_bytes(path))
	else:
		err = img.load(path)
	if err != OK or img.is_empty():
		push_warning("Impossibile caricare l'HDRI di base: %s (%s)" % [path, error_string(err)])
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
	var fmt := RDTextureFormat.new()
	fmt.width = img.get_width()
	fmt.height = img.get_height()
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_base_tex = rd.texture_create(fmt, RDTextureView.new(), [img.get_data()])
	_uniform_set = RID()


func has_base_image() -> bool:
	return not _base_is_placeholder


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
	_uniform_set = rd.uniform_set_create([u0, u1, u2], _shader, 0)


## Esegue il bake del rig nella texture. Con calibration = true ignora le luci e disegna i marker degli assi.
func bake(rig: LightRig, calibration := false) -> void:
	_ensure_uniform_set()

	var data := PackedFloat32Array()
	var count := 0
	for l in rig.active_lights():
		if count >= MAX_LIGHTS:
			push_warning("Più di %d luci: le altre vengono ignorate" % MAX_LIGHTS)
			break
		l.pack(data)
		count += 1
	if count > 0:
		var bytes := data.to_byte_array()
		rd.buffer_update(_lights_buf, 0, bytes.size(), bytes)

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
	for rid in [_uniform_set, texture, _base_tex, _lights_buf, _sampler, _pipeline, _shader]:
		if rid.is_valid():
			rd.free_rid(rid)
	_uniform_set = RID()
	texture = RID()
	if _local:
		rd.free()
