class_name UndoStack
extends RefCounted
## Undo a snapshot: ogni commit salva il rig intero come Dictionary. Semplice e robusto per un rig
## di poche decine di luci.

const MAX_DEPTH := 200

var _stack: Array[Dictionary] = []
var _index := -1


func reset(snapshot: Dictionary) -> void:
	_stack = [snapshot]
	_index = 0


func push(snapshot: Dictionary) -> void:
	if _index >= 0 and _stack[_index] == snapshot:
		return
	_stack.resize(_index + 1)
	_stack.append(snapshot)
	if _stack.size() > MAX_DEPTH:
		_stack.pop_front()
	_index = _stack.size() - 1


func can_undo() -> bool:
	return _index > 0


func can_redo() -> bool:
	return _index < _stack.size() - 1


func undo() -> Dictionary:
	if not can_undo():
		return {}
	_index -= 1
	return _stack[_index]


func redo() -> Dictionary:
	if not can_redo():
		return {}
	_index += 1
	return _stack[_index]
