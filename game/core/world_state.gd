class_name WorldState
extends RefCounted
## Persistent world facts keyed by stable ids ("alder_lane.road", "house_mendes.roof").
## Only deviations from authored defaults are stored, never scene copies.

signal changed(key: String, value: Variant)

var _values: Dictionary = {}


func get_value(key: String, default: Variant = null) -> Variant:
	return _values.get(key, default)


func set_value(key: String, value: Variant) -> bool:
	if _values.has(key) and _values[key] == value:
		return false
	_values[key] = value
	changed.emit(key, value)
	return true


func has(key: String) -> bool:
	return _values.has(key)


func to_dict() -> Dictionary:
	return _values.duplicate(true)


func from_dict(d: Dictionary) -> void:
	_values = d.duplicate(true)
