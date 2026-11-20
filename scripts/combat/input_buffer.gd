class_name InputBuffer
extends RefCounted
## Буфер ввода: нажатие, сделанное чуть раньше, чем действие стало возможным, живёт `window` секунд.
## Время передаётся снаружи (тесты не зависят от часов).

var window: float = 0.2
var _stamps: Dictionary = {}


func push(action: StringName, now: float) -> void:
	_stamps[action] = now


## true и сброс, если нажатие моложе окна.
func consume(action: StringName, now: float) -> bool:
	if not _stamps.has(action):
		return false
	var fresh: bool = now - float(_stamps[action]) <= window
	_stamps.erase(action)
	return fresh


func has(action: StringName, now: float) -> bool:
	return _stamps.has(action) and now - float(_stamps[action]) <= window


func clear() -> void:
	_stamps.clear()
