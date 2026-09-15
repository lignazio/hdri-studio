class_name ParamRow
extends HBoxContainer
## Etichetta + slider + spinbox sincronizzati. value_changed durante il drag, committed a fine drag
## (o subito se si scrive nello spinbox): il committed è il momento in cui salvare lo snapshot di undo.

signal value_changed(value: float)
signal committed()

var slider: HSlider
var spin: SpinBox
var _syncing := false


func _init(label_text: String, min_v: float, max_v: float, step: float, exp_edit := false) -> void:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 96
	label.clip_text = true
	add_child(label)
	slider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.exp_edit = exp_edit
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(slider)
	spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.custom_minimum_size.x = 84
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(spin)
	slider.value_changed.connect(_on_slider)
	slider.drag_ended.connect(func(changed: bool) -> void: if changed: committed.emit())
	spin.value_changed.connect(_on_spin)


func set_value_silent(v: float) -> void:
	_syncing = true
	slider.set_value_no_signal(v)
	spin.set_value_no_signal(v)
	_syncing = false


func get_value() -> float:
	return spin.value


func _on_slider(v: float) -> void:
	if _syncing:
		return
	spin.set_value_no_signal(v)
	value_changed.emit(v)


func _on_spin(v: float) -> void:
	if _syncing:
		return
	slider.set_value_no_signal(v)
	value_changed.emit(v)
	committed.emit()
