@tool
class_name TraitEffect
extends Resource
## Одна строка черты: «параметр ИИ × множитель». Неизменяемый шаблон (один .tres делят многие враги).

## Параметр из реестра AIParams (в инспекторе — выпадающий список).
@export var param: StringName = &""
## 1.0 = без изменений, 0.8 = на 20% меньше, 1.4 = на 40% больше.
@export_range(0.1, 3.0, 0.05) var multiplier: float = 1.0


func _validate_property(property: Dictionary) -> void:
	if property.name == "param":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(AIParams.all_keys())


static func make(p: StringName, m: float) -> TraitEffect:
	var e := TraitEffect.new()
	e.param = p
	e.multiplier = m
	return e
